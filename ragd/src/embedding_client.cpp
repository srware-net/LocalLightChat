#include "embedding_client.hpp"
#include "mini_json.hpp"
#include "vector_index.hpp"
#include <algorithm>
#include <stdexcept>

namespace ragd {

EmbeddingClient::EmbeddingClient(std::string llama_url, std::string model, std::string api_key, PostJsonFn post_json)
    : model_(std::move(model)), api_key_(std::move(api_key)), post_json_(std::move(post_json)) {
    if (llama_url.empty()) throw std::runtime_error("llama_url must be configured (for example http://192.168.1.50:8080)");
    url_ = http::parse_http_url(llama_url);
    if (model_.empty()) throw std::runtime_error("embedding_model must not be empty");
    if (!post_json_) {
        post_json_ = [](const http::Url& u, const std::string& path, const std::string& body, const Headers& headers) {
            return http::post_json(u, path, body, headers);
        };
    }
}

std::vector<std::vector<float>> EmbeddingClient::embed(const std::vector<std::string>& inputs) const {
    if (inputs.empty()) return {};
    json::Value body = json::Value::object();
    body["model"] = model_;
    body["encoding_format"] = "float";
    body["input"] = json::Value::array();
    for (const auto& x : inputs) body["input"].push_back(x);

    std::vector<std::pair<std::string, std::string>> headers;
    if (!api_key_.empty()) headers.emplace_back("Authorization", "Bearer " + api_key_);
    auto r = post_json_(url_, "/v1/embeddings", json::dump(body), headers);
    if (r.status < 200 || r.status >= 300) {
        std::string detail = r.body.substr(0, 1024);
        throw std::runtime_error("llama-server /v1/embeddings returned HTTP " + std::to_string(r.status) + ": " + detail);
    }

    json::Value root = json::parse(r.body);
    const auto& data = root.at("data").as_array();
    if (data.size() != inputs.size()) throw std::runtime_error("llama-server returned unexpected embedding count");

    std::vector<std::vector<float>> out(inputs.size());
    std::size_t dim = 0;
    for (const auto& item : data) {
        int index = item.at("index").as_int();
        if (index < 0 || static_cast<std::size_t>(index) >= out.size()) throw std::runtime_error("llama-server returned invalid embedding index");
        const auto& arr = item.at("embedding").as_array();
        if (arr.empty()) throw std::runtime_error("llama-server returned empty embedding");
        std::vector<float> v;
        v.reserve(arr.size());
        for (const auto& n : arr) {
            if (!n.is_number()) throw std::runtime_error("Non-numeric embedding value from llama-server");
            v.push_back(static_cast<float>(n.as_number()));
        }
        if (dim == 0) dim = v.size();
        if (v.size() != dim) throw std::runtime_error("llama-server returned mixed embedding dimensions");
        normalize_vector(v);
        out[static_cast<std::size_t>(index)] = std::move(v);
    }
    for (const auto& v : out) if (v.empty()) throw std::runtime_error("llama-server embedding response has missing index");
    return out;
}

std::vector<float> EmbeddingClient::embed_one(const std::string& input) const {
    auto all = embed(std::vector<std::string>{input});
    return std::move(all.front());
}

} // namespace ragd
