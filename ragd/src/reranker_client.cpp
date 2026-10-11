#include "reranker_client.hpp"
#include "mini_json.hpp"
#include <algorithm>
#include <stdexcept>
#include <unordered_set>

namespace ragd {
namespace {

std::string cap_utf8_bytes(const std::string& text, std::size_t max_bytes) {
    if (max_bytes == 0 || text.size() <= max_bytes) return text;

    std::size_t end = max_bytes;
    while (end > 0 && (static_cast<unsigned char>(text[end]) & 0xC0u) == 0x80u) --end;
    return text.substr(0, end);
}

} // namespace

std::vector<std::pair<std::size_t, float>> parse_reranker_results(const std::string& body, std::size_t document_count) {
    json::Value root = json::parse(body);
    const auto& results = root.at("results").as_array();
    std::vector<std::pair<std::size_t, float>> out;
    out.reserve(results.size());
    std::unordered_set<std::size_t> seen;
    for (const auto& item : results) {
        if (!item.is_object()) throw std::runtime_error("Reranker result entry must be an object");
        const auto& index_v = item.at("index");
        const auto& score_v = item.at("relevance_score");
        if (!index_v.is_number() || !score_v.is_number()) throw std::runtime_error("Reranker result has invalid index or relevance_score");
        const int index = index_v.as_int();
        if (index < 0 || static_cast<std::size_t>(index) >= document_count) throw std::runtime_error("Reranker returned out-of-range document index");
        const auto idx = static_cast<std::size_t>(index);
        if (!seen.insert(idx).second) throw std::runtime_error("Reranker returned duplicate document index");
        out.emplace_back(idx, static_cast<float>(score_v.as_number()));
    }
    std::sort(out.begin(), out.end(), [](const auto& a, const auto& b) {
        if (a.second != b.second) return a.second > b.second;
        return a.first < b.first;
    });
    return out;
}

RerankerClient::RerankerClient(std::string url, std::string model, std::string api_key, PostJsonFn post_json, std::size_t max_document_bytes)
    : model_(std::move(model)), api_key_(std::move(api_key)), post_json_(std::move(post_json)), max_document_bytes_(max_document_bytes) {
    if (url.empty()) throw std::runtime_error("reranker_url must not be empty when reranker is enabled");
    if (model_.empty()) throw std::runtime_error("reranker_model must not be empty when reranker is enabled");
    url_ = http::parse_http_url(url);
    if (!post_json_) {
        post_json_ = [](const http::Url& u, const std::string& path, const std::string& body, const Headers& headers) {
            return http::post_json(u, path, body, headers);
        };
    }
}

std::vector<SearchHit> RerankerClient::rerank(const std::string& query,
                                               const std::vector<SearchHit>& candidates,
                                               const std::vector<StoredChunk>& chunks,
                                               std::size_t top_k) const {
    if (candidates.size() != chunks.size()) throw std::runtime_error("Reranker candidate/chunk count mismatch");
    if (top_k == 0 || candidates.empty()) return {};

    json::Value body = json::Value::object();
    body["model"] = model_;
    body["query"] = query;
    body["top_n"] = static_cast<int>(std::min(top_k, candidates.size()));
    body["documents"] = json::Value::array();
    for (const auto& chunk : chunks) body["documents"].push_back(cap_utf8_bytes(chunk.text, max_document_bytes_));

    Headers headers;
    if (!api_key_.empty()) headers.emplace_back("Authorization", "Bearer " + api_key_);
    const auto response = post_json_(url_, "/v1/rerank", json::dump(body), headers);
    if (response.status < 200 || response.status >= 300) {
        throw std::runtime_error("reranker /v1/rerank returned HTTP " + std::to_string(response.status) + ": " + response.body.substr(0, 1024));
    }

    auto ranked = parse_reranker_results(response.body, candidates.size());
    if (ranked.size() > top_k) ranked.resize(top_k);
    std::vector<SearchHit> out;
    out.reserve(ranked.size());
    for (const auto& item : ranked) {
        SearchHit hit = candidates[item.first];
        hit.score = item.second;
        out.push_back(std::move(hit));
    }
    return out;
}

} // namespace ragd
