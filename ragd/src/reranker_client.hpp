#pragma once
#include "http.hpp"
#include "types.hpp"
#include <cstddef>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace ragd {

class RerankerClient {
public:
    using Headers = std::vector<std::pair<std::string, std::string>>;
    using PostJsonFn = std::function<http::ClientResponse(const http::Url&, const std::string&, const std::string&, const Headers&)>;

    RerankerClient(std::string url, std::string model, std::string api_key = {}, PostJsonFn post_json = {}, std::size_t max_document_bytes = 0);
    std::vector<SearchHit> rerank(const std::string& query,
                                  const std::vector<SearchHit>& candidates,
                                  const std::vector<StoredChunk>& chunks,
                                  std::size_t top_k) const;

private:
    http::Url url_;
    std::string model_;
    std::string api_key_;
    PostJsonFn post_json_;
    std::size_t max_document_bytes_ = 0;
};

std::vector<std::pair<std::size_t, float>> parse_reranker_results(const std::string& body, std::size_t document_count);

} // namespace ragd
