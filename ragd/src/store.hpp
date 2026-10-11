#pragma once
#include "types.hpp"
#include "vector_index.hpp"
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>

struct sqlite3;

namespace ragd {

struct DocumentRecord {
    std::string id;
    std::string owner;
    std::string name;
    std::string source;
    std::string content_hash;
    std::string metadata_json;
};

struct PersistChunk {
    int ordinal = 0;
    std::string text;
    int page = 0;
    std::string section;
    std::vector<float> embedding;
    std::string embedding_model;
};

class Store {
public:
    explicit Store(const std::string& path);
    ~Store();
    Store(const Store&) = delete;
    Store& operator=(const Store&) = delete;

    void replace_document(const DocumentRecord& doc, const std::vector<PersistChunk>& chunks);
    bool delete_document(const std::string& id);
    std::vector<IndexEntry> load_index(const std::string& embedding_model);
    std::vector<SearchHit> bm25_search(const std::string& query, std::size_t top_k, const SearchFilter& filter);
    StoredChunk get_chunk(std::int64_t id);
    std::int64_t document_count();
    std::int64_t chunk_count(const std::string& embedding_model);

private:
    sqlite3* db_ = nullptr;
    std::mutex mutex_;
    void init_schema();
    void exec(const char* sql);
};

std::string make_fts5_query(const std::string& query);

} // namespace ragd
