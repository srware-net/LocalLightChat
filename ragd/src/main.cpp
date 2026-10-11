#include "app.hpp"
#include "config.hpp"
#include "http.hpp"
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

void print_help() {
    std::cout << R"TXT(ragd 0.3.1 - lightweight local RAG retrieval daemon

Usage:
  ragd [--config ragd.conf] [options]

Options:
  --listen HOST             Listen address (default 0.0.0.0)
  --port N                  Listen port (default 8787)
  --db PATH                 SQLite database path
  --llama-url URL           llama-server base URL (http://)
  --embedding-model NAME    Model id/alias routed by llama-server
  --llama-api-key KEY       Optional bearer token (otherwise RAGD_LLAMA_API_KEY)
  --chunk-chars N           Target chunk size in UTF-8 bytes
  --chunk-max-chars N       Maximum chunk size
  --chunk-overlap N         Approximate textual overlap
  --embedding-batch N       Chunks per /v1/embeddings request
  --default-top-k N         Default retrieval count
  --max-top-k N             Maximum final retrieval count
  --help                    Show this help

Config file uses key=value with the same names using underscores.
Lines beginning with # or ; are comments.
If --config is omitted, ./ragd.conf is required and loaded automatically.
If llama_api_key is empty/not set, RAGD_LLAMA_API_KEY is used as a fallback.
Hybrid and reranker settings are configured in ragd.conf. Reranker connection data has no CLI flags.
)TXT";
}

bool has_arg(int argc, char** argv, const std::string& needle) {
    for (int i = 1; i < argc; ++i) if (argv[i] == needle) return true;
    return false;
}

std::string require_value(int& i, int argc, char** argv) {
    if (i + 1 >= argc) throw std::runtime_error(std::string("Missing value for ") + argv[i]);
    return argv[++i];
}

} // namespace

int main(int argc, char** argv) {
    try {
        if (has_arg(argc, argv, "--help")) { print_help(); return 0; }
        ragd::http::SocketRuntime sockets;
        ragd::Config cfg;

        // Config file first, environment fallback second, CLI overrides last.
        // If no explicit --config is supplied, ./ragd.conf is required.
        bool explicit_config = false;
        for (int i = 1; i < argc; ++i) {
            if (std::string(argv[i]) == "--config") {
                std::string path = require_value(i, argc, argv);
                ragd::load_config_file(cfg, path);
                explicit_config = true;
            }
        }
        if (!explicit_config) {
            std::ifstream default_cfg("ragd.conf");
            if (!default_cfg.good()) {
                throw std::runtime_error(
                    "No config specified and default ragd.conf was not found. "
                    "Create ./ragd.conf or use --config PATH");
            }
            default_cfg.close();
            ragd::load_config_file(cfg, "ragd.conf");
        }

        // Secrets can stay out of the config file. File values win over the
        // environment; command-line options below win over both.
        ragd::apply_environment_fallbacks(cfg);

        for (int i = 1; i < argc; ++i) {
            std::string a = argv[i];
            if (a == "--config") { ++i; continue; }
            if (a == "--listen") ragd::apply_config_kv(cfg, "listen", require_value(i, argc, argv));
            else if (a == "--port") ragd::apply_config_kv(cfg, "port", require_value(i, argc, argv));
            else if (a == "--db") ragd::apply_config_kv(cfg, "db", require_value(i, argc, argv));
            else if (a == "--llama-url") ragd::apply_config_kv(cfg, "llama_url", require_value(i, argc, argv));
            else if (a == "--embedding-model") ragd::apply_config_kv(cfg, "embedding_model", require_value(i, argc, argv));
            else if (a == "--llama-api-key") ragd::apply_config_kv(cfg, "llama_api_key", require_value(i, argc, argv));
            else if (a == "--chunk-chars") ragd::apply_config_kv(cfg, "chunk_chars", require_value(i, argc, argv));
            else if (a == "--chunk-max-chars") ragd::apply_config_kv(cfg, "chunk_max_chars", require_value(i, argc, argv));
            else if (a == "--chunk-overlap") ragd::apply_config_kv(cfg, "chunk_overlap", require_value(i, argc, argv));
            else if (a == "--embedding-batch") ragd::apply_config_kv(cfg, "embedding_batch", require_value(i, argc, argv));
            else if (a == "--default-top-k") ragd::apply_config_kv(cfg, "default_top_k", require_value(i, argc, argv));
            else if (a == "--max-top-k") ragd::apply_config_kv(cfg, "max_top_k", require_value(i, argc, argv));
            else if (a == "--help") {}
            else throw std::runtime_error("Unknown argument: " + a);
        }

        ragd::App app(cfg);
        ragd::http::Server server(cfg.listen, cfg.port, [&app](const ragd::http::Request& req) { return app.handle(req); }, cfg.max_request_bytes);
        server.run();
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "ragd fatal: " << e.what() << "\n";
        return 1;
    }
}
