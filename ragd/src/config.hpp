#pragma once
#include <cstddef>
#include <string>

namespace ragd {

struct Config {
    std::string listen = "0.0.0.0";
    int port = 8787;
    std::string db_path = "ragd.sqlite3";
    std::string llama_url;
    std::string embedding_model = "embed";
    std::string llama_api_key;
    std::size_t chunk_chars = 1800;
    std::size_t chunk_max_chars = 2800;
    std::size_t chunk_overlap = 200;
    std::size_t embedding_batch = 32;
    std::size_t default_top_k = 8;
    std::size_t max_top_k = 64;
    std::size_t hybrid_dense_k = 96;
    std::size_t hybrid_bm25_k = 32;
    std::size_t hybrid_rrf_k = 60;
    bool reranker_enabled = false;
    std::string reranker_url;
    std::string reranker_model;
    std::string reranker_api_key;
    std::size_t reranker_max_bytes = 0;
    std::size_t max_request_bytes = 128 * 1024 * 1024;
};

void load_config_file(Config& cfg, const std::string& path);
void apply_config_kv(Config& cfg, const std::string& key, const std::string& value);
void apply_environment_fallbacks(Config& cfg);

} // namespace ragd
