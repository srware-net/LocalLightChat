#pragma once
#include "chunker.hpp"
#include "config.hpp"
#include "embedding_client.hpp"
#include "http.hpp"
#include "reranker_client.hpp"
#include "retrieval.hpp"
#include "store.hpp"
#include "vector_index.hpp"
#include <atomic>
#include <condition_variable>
#include <deque>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <shared_mutex>
#include <thread>

namespace ragd {

class App {
public:
    explicit App(Config cfg,
                 EmbeddingClient::PostJsonFn embedding_transport = {},
                 RerankerClient::PostJsonFn reranker_transport = {});
    ~App();
    App(const App&) = delete;
    App& operator=(const App&) = delete;

    http::Response handle(const http::Request& req);
    const Config& config() const { return cfg_; }

private:
    struct Job {
        std::string id;
        std::string document_id;
        std::string state = "queued";
        std::size_t done = 0;
        std::size_t total = 0;
        std::size_t chunks = 0;
        std::string error;
    };
    struct IngestTask {
        std::string job_id;
        DocumentRecord doc;
        std::string text;
    };

    Config cfg_;
    Store store_;
    Chunker chunker_;
    EmbeddingClient embeddings_;
    std::unique_ptr<RerankerClient> reranker_;
    std::unique_ptr<IVectorIndex> index_;
    mutable std::shared_mutex index_mutex_;
    std::mutex ingest_mutex_;

    std::mutex jobs_mutex_;
    std::condition_variable jobs_cv_;
    std::map<std::string, Job> jobs_;
    std::deque<IngestTask> job_queue_;
    std::thread worker_;
    std::atomic<bool> stop_worker_{false};
    std::atomic<std::uint64_t> job_counter_{0};

    void rebuild_index();
    http::Response health();
    http::Response status();
    http::Response ingest(const http::Request& req);
    http::Response search(const http::Request& req);
    http::Response remove_document(const std::string& id);
    http::Response job_status(const std::string& id);

    IngestTask parse_ingest(const http::Request& req, std::string job_id = {});
    std::size_t process_ingest(const DocumentRecord& doc, const std::string& text,
                               const std::function<void(const std::string&, std::size_t, std::size_t)>& progress);
    std::string new_job_id();
    void worker_loop();
    void update_job(const std::string& id, const std::string& state, std::size_t done, std::size_t total,
                    std::size_t chunks = 0, const std::string& error = {});
};

} // namespace ragd
