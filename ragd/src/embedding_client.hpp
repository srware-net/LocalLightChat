#pragma once
#include "http.hpp"
#include <cstddef>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace ragd {

class EmbeddingClient {
public:
    using Headers = std::vector<std::pair<std::string, std::string>>;
    using PostJsonFn = std::function<http::ClientResponse(const http::Url&, const std::string&, const std::string&, const Headers&)>;

    EmbeddingClient(std::string llama_url, std::string model, std::string api_key = {}, PostJsonFn post_json = {});
    std::vector<std::vector<float>> embed(const std::vector<std::string>& inputs) const;
    std::vector<float> embed_one(const std::string& input) const;
    const std::string& model() const { return model_; }

private:
    http::Url url_;
    std::string model_;
    std::string api_key_;
    PostJsonFn post_json_;
};

} // namespace ragd
