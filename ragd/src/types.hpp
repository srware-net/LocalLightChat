#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace ragd {

struct ChunkInput {
    int ordinal = 0;
    std::string text;
    int page = 0;               // 1-based PDF page if known, otherwise 0
    std::string section;        // detected heading/title if known
};

struct StoredChunk {
    std::int64_t id = 0;
    std::string document_id;
    std::string owner;
    int ordinal = 0;
    std::string text;
    std::string source;
    std::string document_name;
    int page = 0;
    std::string section;
    std::vector<float> embedding;
};

struct IndexEntry {
    std::int64_t chunk_id = 0;
    std::string document_id;
    std::string owner;
    int ordinal = 0;
    std::vector<float> embedding;
};

struct SearchHit {
    std::int64_t chunk_id = 0;
    std::string document_id;
    int ordinal = 0;
    float score = 0.0f;
};

} // namespace ragd
