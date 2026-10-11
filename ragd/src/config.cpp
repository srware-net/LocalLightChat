#include "config.hpp"
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <fstream>
#include <stdexcept>

namespace ragd {
namespace {
std::string trim(const std::string& s) {
    std::size_t a = 0, b = s.size();
    while (a < b && std::isspace(static_cast<unsigned char>(s[a]))) ++a;
    while (b > a && std::isspace(static_cast<unsigned char>(s[b - 1]))) --b;
    return s.substr(a, b - a);
}
std::size_t parse_size(const std::string& v, const char* key) {
    try {
        std::size_t p = 0;
        unsigned long long n = std::stoull(v, &p);
        if (p != v.size()) throw std::runtime_error("bad");
        return static_cast<std::size_t>(n);
    } catch (...) { throw std::runtime_error(std::string("Invalid numeric config value for ") + key); }
}
int parse_int(const std::string& v, const char* key) {
    try {
        std::size_t p = 0;
        long n = std::stol(v, &p);
        if (p != v.size()) throw std::runtime_error("bad");
        return static_cast<int>(n);
    } catch (...) { throw std::runtime_error(std::string("Invalid numeric config value for ") + key); }
}

bool parse_bool(const std::string& v, const char* key) {
    std::string x;
    x.reserve(v.size());
    for (unsigned char c : v) x.push_back(static_cast<char>(std::tolower(c)));
    if (x == "true" || x == "1" || x == "yes" || x == "on") return true;
    if (x == "false" || x == "0" || x == "no" || x == "off") return false;
    throw std::runtime_error(std::string("Invalid boolean config value for ") + key);
}
std::string get_environment_variable(const char* name) {
#ifdef _MSC_VER
    char* value = nullptr;
    std::size_t size = 0;
    if (_dupenv_s(&value, &size, name) != 0 || value == nullptr) return {};
    std::string result(value);
    std::free(value);
    return result;
#else
    const char* value = std::getenv(name);
    return value ? std::string(value) : std::string{};
#endif
}
}

void apply_config_kv(Config& cfg, const std::string& key, const std::string& value) {
    if (key == "listen") cfg.listen = value;
    else if (key == "port") cfg.port = parse_int(value, "port");
    else if (key == "db" || key == "db_path") cfg.db_path = value;
    else if (key == "llama_url") cfg.llama_url = value;
    else if (key == "embedding_model") cfg.embedding_model = value;
    else if (key == "llama_api_key") cfg.llama_api_key = value;
    else if (key == "chunk_chars") cfg.chunk_chars = parse_size(value, "chunk_chars");
    else if (key == "chunk_max_chars") cfg.chunk_max_chars = parse_size(value, "chunk_max_chars");
    else if (key == "chunk_overlap") cfg.chunk_overlap = parse_size(value, "chunk_overlap");
    else if (key == "embedding_batch") cfg.embedding_batch = parse_size(value, "embedding_batch");
    else if (key == "default_top_k") cfg.default_top_k = parse_size(value, "default_top_k");
    else if (key == "max_top_k") cfg.max_top_k = parse_size(value, "max_top_k");
    else if (key == "hybrid_dense_k") cfg.hybrid_dense_k = parse_size(value, "hybrid_dense_k");
    else if (key == "hybrid_bm25_k") cfg.hybrid_bm25_k = parse_size(value, "hybrid_bm25_k");
    else if (key == "hybrid_rrf_k") cfg.hybrid_rrf_k = parse_size(value, "hybrid_rrf_k");
    else if (key == "reranker_enabled") cfg.reranker_enabled = parse_bool(value, "reranker_enabled");
    else if (key == "reranker_url") cfg.reranker_url = value;
    else if (key == "reranker_model") cfg.reranker_model = value;
    else if (key == "reranker_api_key") cfg.reranker_api_key = value;
    else if (key == "reranker_max_bytes") cfg.reranker_max_bytes = parse_size(value, "reranker_max_bytes");
    else if (key == "max_request_bytes") cfg.max_request_bytes = parse_size(value, "max_request_bytes");
    else throw std::runtime_error("Unknown config key: " + key);
}

void apply_environment_fallbacks(Config& cfg) {
    if (cfg.llama_api_key.empty()) {
        const std::string value = get_environment_variable("RAGD_LLAMA_API_KEY");
        if (!value.empty()) cfg.llama_api_key = value;
    }
}

void load_config_file(Config& cfg, const std::string& path) {
    std::ifstream f(path);
    if (!f) throw std::runtime_error("Cannot open config file: " + path);
    std::string line;
    int line_no = 0;
    while (std::getline(f, line)) {
        ++line_no;
        line = trim(line);
        if (line.empty() || line[0] == '#' || line[0] == ';') continue;
        auto eq = line.find('=');
        if (eq == std::string::npos) throw std::runtime_error("Invalid config line " + std::to_string(line_no));
        std::string key = trim(line.substr(0, eq));
        std::string value = trim(line.substr(eq + 1));
        apply_config_kv(cfg, key, value);
    }
}

} // namespace ragd
