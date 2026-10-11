#include "app.hpp"
#include "mini_json.hpp"
#include <algorithm>
#include <chrono>
#include <cstdint>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace ragd {
namespace {

struct HttpError : std::runtime_error {
    int status;
    HttpError(int s, const std::string& msg) : std::runtime_error(msg), status(s) {}
};

http::Response json_response(int status, json::Value body) {
    http::Response r; r.status = status; r.body = json::dump(body); return r;
}
http::Response error_response(int status, const std::string& code, const std::string& detail) {
    json::Value j = json::Value::object(); j["error"] = code; j["detail"] = detail; return json_response(status, std::move(j));
}
std::string fnv1a64_hex(const std::string& s) {
    std::uint64_t h = 14695981039346656037ull;
    for (unsigned char c : s) { h ^= c; h *= 1099511628211ull; }
    std::ostringstream os; os << std::hex << std::setw(16) << std::setfill('0') << h; return os.str();
}
std::string url_decode(const std::string& s) {
    auto hex = [](char c)->int { if (c >= '0' && c <= '9') return c-'0'; if (c >= 'a' && c <= 'f') return c-'a'+10; if (c >= 'A' && c <= 'F') return c-'A'+10; return -1; };
    std::string out;
    for (std::size_t i=0;i<s.size();++i) {
        if (s[i]=='%' && i+2<s.size()) { int a=hex(s[i+1]), b=hex(s[i+2]); if(a>=0&&b>=0){out.push_back(static_cast<char>((a<<4)|b));i+=2;continue;} }
        out.push_back(s[i]);
    }
    return out;
}
std::string strip_query(const std::string& target) { auto q=target.find('?'); return q==std::string::npos?target:target.substr(0,q); }

} // namespace

App::App(Config cfg, EmbeddingClient::PostJsonFn embedding_transport, RerankerClient::PostJsonFn reranker_transport)
    : cfg_(std::move(cfg)), store_(cfg_.db_path),
      chunker_(ChunkerConfig{cfg_.chunk_chars, cfg_.chunk_max_chars, cfg_.chunk_overlap}),
      embeddings_(cfg_.llama_url, cfg_.embedding_model, cfg_.llama_api_key, std::move(embedding_transport)),
      index_(std::make_unique<FlatIndex>()) {
    if (cfg_.port <= 0 || cfg_.port > 65535) throw std::runtime_error("Invalid listen port");
    if (cfg_.embedding_batch == 0) throw std::runtime_error("embedding_batch must be > 0");
    if (cfg_.default_top_k == 0 || cfg_.max_top_k == 0 || cfg_.default_top_k > cfg_.max_top_k) throw std::runtime_error("Invalid top_k configuration");
    if (cfg_.hybrid_dense_k == 0 || cfg_.hybrid_bm25_k == 0 || cfg_.hybrid_rrf_k == 0) throw std::runtime_error("Invalid hybrid retrieval configuration");
    if (cfg_.reranker_enabled) {
        reranker_ = std::make_unique<RerankerClient>(cfg_.reranker_url, cfg_.reranker_model, cfg_.reranker_api_key, std::move(reranker_transport), cfg_.reranker_max_bytes);
    }
    rebuild_index();
    worker_ = std::thread([this]{ worker_loop(); });
}

App::~App() {
    stop_worker_ = true;
    jobs_cv_.notify_all();
    if (worker_.joinable()) worker_.join();
}

void App::rebuild_index() {
    auto entries = store_.load_index(cfg_.embedding_model);
    std::unique_lock<std::shared_mutex> lock(index_mutex_); index_->replace(std::move(entries));
}

http::Response App::handle(const http::Request& req) {
    try {
        const std::string path = strip_query(req.target);
        if (req.method=="GET" && path=="/health") return health();
        if (req.method=="GET" && path=="/v1/status") return status();
        if (req.method=="POST" && path=="/v1/documents") return ingest(req);
        if (req.method=="POST" && path=="/v1/search") return search(req);
        const std::string jobs_prefix="/v1/jobs/";
        if (req.method=="GET" && path.rfind(jobs_prefix,0)==0 && path.size()>jobs_prefix.size()) return job_status(url_decode(path.substr(jobs_prefix.size())));
        const std::string docs_prefix="/v1/documents/";
        if (req.method=="DELETE" && path.rfind(docs_prefix,0)==0 && path.size()>docs_prefix.size()) return remove_document(url_decode(path.substr(docs_prefix.size())));
        return error_response(404,"not_found","Unknown endpoint");
    } catch (const HttpError& e) { return error_response(e.status,"request_error",e.what()); }
      catch (const std::exception& e) { return error_response(500,"internal_error",e.what()); }
}

http::Response App::health() {
    json::Value j=json::Value::object(); j["ok"]=true; j["service"]="ragd"; j["version"]="0.3.1"; return json_response(200,std::move(j));
}

http::Response App::status() {
    json::Value j=json::Value::object(); j["ok"]=true; j["embedding_model"]=cfg_.embedding_model; j["llama_url"]=cfg_.llama_url;
    const bool precise_available = cfg_.reranker_enabled && static_cast<bool>(reranker_);
    j["retrieval_modes"] = precise_available ? "dense,hybrid,precise" : "dense,hybrid";
    json::Value retrieval_capabilities = json::Value::object();
    retrieval_capabilities["dense"] = true;
    retrieval_capabilities["hybrid"] = true;
    retrieval_capabilities["precise"] = precise_available;
    j["retrieval_capabilities"] = std::move(retrieval_capabilities);
    j["reranker_enabled"] = cfg_.reranker_enabled;
    j["precise_available"] = precise_available;
    j["documents"]=static_cast<double>(store_.document_count()); j["stored_chunks_for_model"]=static_cast<double>(store_.chunk_count(cfg_.embedding_model));
    {
        std::shared_lock<std::shared_mutex> lock(index_mutex_); j["index"]="flat-exact"; j["indexed_chunks"]=static_cast<double>(index_->size()); j["dimension"]=static_cast<double>(index_->dimension());
    }
    {
        std::lock_guard<std::mutex> lock(jobs_mutex_);
        std::size_t active=0; for (const auto& kv:jobs_) if(kv.second.state!="ready"&&kv.second.state!="failed") ++active;
        j["active_jobs"]=static_cast<double>(active); j["queued_jobs"]=static_cast<double>(job_queue_.size());
    }
    return json_response(200,std::move(j));
}

App::IngestTask App::parse_ingest(const http::Request& req, std::string job_id) {
    json::Value body; try { body=json::parse(req.body); } catch(const std::exception& e){throw HttpError(400,e.what());}
    if(!body.is_object()) throw HttpError(400,"Body must be a JSON object");
    const std::string id=body.string_or("id"), text=body.string_or("text");
    if (id.empty()) throw HttpError(422,"id is required");
    if (text.empty()) throw HttpError(422,"text is required");
    DocumentRecord doc; doc.id=id; doc.owner=body.string_or("owner"); doc.name=body.string_or("name",id); doc.source=body.string_or("source",doc.name); doc.content_hash=fnv1a64_hex(text);
    if(body.contains("metadata")){if(!body.at("metadata").is_object()) throw HttpError(422,"metadata must be an object"); doc.metadata_json=json::dump(body.at("metadata"));} else doc.metadata_json="{}";
    return IngestTask{std::move(job_id),std::move(doc),text};
}

std::size_t App::process_ingest(const DocumentRecord& doc, const std::string& text,
                                const std::function<void(const std::string&, std::size_t, std::size_t)>& progress) {
    progress("chunking",0,0);
    auto chunks=chunker_.split(text); if(chunks.empty()) throw HttpError(422,"Document produced no chunks");
    progress("embedding",0,chunks.size());
    std::lock_guard<std::mutex> ingest_lock(ingest_mutex_);
    std::vector<PersistChunk> persist; persist.reserve(chunks.size());
    for(std::size_t start=0;start<chunks.size();start+=cfg_.embedding_batch){
        const std::size_t end=std::min(chunks.size(),start+cfg_.embedding_batch);
        std::vector<std::string> texts; texts.reserve(end-start); for(std::size_t i=start;i<end;++i) texts.push_back(chunks[i].text);
        std::vector<std::vector<float>> vectors;
        try { vectors=embeddings_.embed(texts); } catch(const std::exception& e){throw HttpError(502,e.what());}
        if(vectors.size()!=texts.size()) throw HttpError(502,"Embedding server returned unexpected vector count");
        for(std::size_t i=0;i<vectors.size();++i){
            PersistChunk p; p.ordinal=chunks[start+i].ordinal; p.text=std::move(chunks[start+i].text); p.page=chunks[start+i].page; p.section=std::move(chunks[start+i].section);
            p.embedding=std::move(vectors[i]); p.embedding_model=cfg_.embedding_model; persist.push_back(std::move(p));
        }
        progress("embedding",end,chunks.size());
    }
    progress("storing",chunks.size(),chunks.size());
    store_.replace_document(doc,persist); rebuild_index();
    return persist.size();
}

std::string App::new_job_id() {
    const auto ms=std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::system_clock::now().time_since_epoch()).count();
    const auto n=++job_counter_; std::ostringstream os; os<<"job_"<<std::hex<<ms<<'_'<<n; return os.str();
}

void App::update_job(const std::string& id,const std::string& state,std::size_t done,std::size_t total,std::size_t chunks,const std::string& error){
    std::lock_guard<std::mutex> lock(jobs_mutex_); auto it=jobs_.find(id); if(it==jobs_.end()) return;
    it->second.state=state; it->second.done=done; it->second.total=total; if(chunks) it->second.chunks=chunks; it->second.error=error;
}

void App::worker_loop() {
    while(!stop_worker_){
        IngestTask task;
        {
            std::unique_lock<std::mutex> lock(jobs_mutex_); jobs_cv_.wait(lock,[this]{return stop_worker_||!job_queue_.empty();});
            if (stop_worker_) break;
            task=std::move(job_queue_.front());
            job_queue_.pop_front();
        }
        try {
            const std::size_t count=process_ingest(task.doc,task.text,[this,&task](const std::string& state,std::size_t done,std::size_t total){ update_job(task.job_id,state,done,total); });
            update_job(task.job_id,"ready",count,count,count);
        } catch(const std::exception& e) { update_job(task.job_id,"failed",0,0,0,e.what()); }
    }
}

http::Response App::ingest(const http::Request& req) {
    // Parse once to inspect async flag while preserving the existing synchronous API.
    json::Value body; try { body=json::parse(req.body); } catch(const std::exception& e){throw HttpError(400,e.what());}
    if(!body.is_object()) throw HttpError(400,"Body must be a JSON object");
    const bool async = body.bool_or("async", false);
    if(async){
        const std::string job_id=new_job_id();
        IngestTask task=parse_ingest(req,job_id);
        const std::string document_id = task.doc.id;
        {
            std::lock_guard<std::mutex> lock(jobs_mutex_);
            Job job; job.id=job_id; job.document_id=document_id; jobs_[job_id]=job; job_queue_.push_back(std::move(task));
        }
        jobs_cv_.notify_one();
        json::Value out=json::Value::object(); out["accepted"]=true; out["job_id"]=job_id; out["document_id"]=document_id; out["state"]="queued"; out["embedding_model"]=cfg_.embedding_model;
        return json_response(202,std::move(out));
    }
    IngestTask task=parse_ingest(req);
    const std::size_t count=process_ingest(task.doc,task.text,[](const std::string&,std::size_t,std::size_t){});
    json::Value out=json::Value::object(); out["ok"]=true; out["document_id"]=task.doc.id; out["chunks"]=static_cast<double>(count); out["embedding_model"]=cfg_.embedding_model; out["content_hash"]=task.doc.content_hash;
    return json_response(201,std::move(out));
}

http::Response App::job_status(const std::string& id) {
    Job job;
    {
        std::lock_guard<std::mutex> lock(jobs_mutex_); auto it=jobs_.find(id); if(it==jobs_.end()) return error_response(404,"not_found","Job not found"); job=it->second;
    }
    json::Value out=json::Value::object(); out["job_id"]=job.id; out["document_id"]=job.document_id; out["state"]=job.state; out["done"]=static_cast<double>(job.done); out["total"]=static_cast<double>(job.total); out["chunks"]=static_cast<double>(job.chunks);
    double pct=0.0; if(job.state=="ready") pct=100.0; else if(job.total>0) pct=100.0*static_cast<double>(job.done)/static_cast<double>(job.total); out["percent"]=pct;
    if (!job.error.empty()) out["error"]=job.error;
    return json_response(200,std::move(out));
}

http::Response App::search(const http::Request& req) {
    json::Value body; try{body=json::parse(req.body);}catch(const std::exception& e){throw HttpError(400,e.what());}
    if (!body.is_object()) throw HttpError(400,"Body must be a JSON object");
    const std::string query=body.string_or("query");
    if (query.empty()) throw HttpError(422,"query is required");

    if (body.contains("retrieval_mode") && !body.at("retrieval_mode").is_string())
        throw HttpError(400, "retrieval_mode must be a string");
    RetrievalMode mode;
    try { mode = parse_retrieval_mode(body.string_or("retrieval_mode")); }
    catch (const std::invalid_argument& e) { throw HttpError(400, e.what()); }
    if (mode == RetrievalMode::Precise && (!cfg_.reranker_enabled || !reranker_))
        throw HttpError(503, "precise retrieval requested but reranker is disabled");

    int requested=body.int_or("top_k",static_cast<int>(cfg_.default_top_k));
    if(requested<=0) throw HttpError(422,"top_k must be > 0");
    std::size_t top_k=std::min<std::size_t>(static_cast<std::size_t>(requested),cfg_.max_top_k);

    SearchFilter filter; filter.owner=body.string_or("owner");
    if(body.contains("documents")){
        if(!body.at("documents").is_array()) throw HttpError(422,"documents must be an array");
        for(const auto& d:body.at("documents").as_array()){
            if(!d.is_string())throw HttpError(422,"documents entries must be strings");
            filter.document_ids.insert(d.as_string());
        }
    }

    std::vector<float> qv;
    try{qv=embeddings_.embed_one(query);}catch(const std::exception& e){throw HttpError(502,e.what());}

    const std::size_t dense_k = mode == RetrievalMode::Dense ? top_k : cfg_.hybrid_dense_k;
    std::vector<SearchHit> dense;
    {
        std::shared_lock<std::shared_mutex> lock(index_mutex_);
        if(index_->size()>0) dense=index_->search(qv,dense_k,filter);
    }

    std::vector<SearchHit> hits;
    std::string retriever;
    if (mode == RetrievalMode::Dense) {
        hits = std::move(dense);
        retriever = "dense-flat-exact";
    } else {
        std::vector<SearchHit> sparse;
        try { sparse = store_.bm25_search(query, cfg_.hybrid_bm25_k, filter); }
        catch (const std::exception& e) { throw HttpError(500, std::string("BM25 search failed: ") + e.what()); }

        if (mode == RetrievalMode::Hybrid) {
            hits = reciprocal_rank_fusion(dense, sparse, cfg_.hybrid_rrf_k, top_k);
            retriever = "hybrid-dense-bm25-rrf";
        } else {
            auto candidates = union_candidates(dense, sparse);
            std::vector<StoredChunk> candidate_chunks;
            candidate_chunks.reserve(candidates.size());
            try {
                for (const auto& candidate : candidates) candidate_chunks.push_back(store_.get_chunk(candidate.chunk_id));
                hits = reranker_->rerank(query, candidates, candidate_chunks, top_k);
            } catch (const std::exception& e) {
                throw HttpError(502, std::string("precise reranker failed: ") + e.what());
            }
            retriever = "precise-dense-bm25-rerank";
        }
    }

    json::Value out=json::Value::object();
    out["query"]=query;
    out["embedding_model"]=cfg_.embedding_model;
    out["retrieval_mode"]=retrieval_mode_name(mode);
    out["retriever"]=retriever;
    out["hits"]=json::Value::array();
    for(const auto& h:hits){
        StoredChunk c=store_.get_chunk(h.chunk_id);
        json::Value item=json::Value::object();
        item["chunk_id"]=std::to_string(h.chunk_id);
        item["document_id"]=h.document_id;
        item["ordinal"]=h.ordinal;
        item["score"]=static_cast<double>(h.score);
        item["text"]=c.text;
        item["source"]=c.source;
        item["name"]=c.document_name;
        item["page"]=c.page;
        item["section"]=c.section;
        out["hits"].push_back(std::move(item));
    }
    out["count"]=static_cast<double>(hits.size());
    return json_response(200,std::move(out));
}

http::Response App::remove_document(const std::string& id) {
    if (id.empty()) throw HttpError(422,"document id is required");
    std::lock_guard<std::mutex> ingest_lock(ingest_mutex_);
    bool removed=store_.delete_document(id);
    if (!removed) return error_response(404,"not_found","Document not found");
    rebuild_index();
    json::Value out=json::Value::object(); out["ok"]=true; out["document_id"]=id; return json_response(200,std::move(out));
}

} // namespace ragd
