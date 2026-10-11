#pragma once
#include "types.hpp"
#include <cstddef>
#include <string>
#include <vector>

namespace ragd {

struct ChunkerConfig {
    std::size_t target_chars = 1400;
    std::size_t max_chars = 2000;
    std::size_t overlap_chars = 180;
};

class Chunker {
public:
    explicit Chunker(ChunkerConfig cfg) : cfg_(cfg) {}
    std::vector<ChunkInput> split(const std::string& text) const;

private:
    ChunkerConfig cfg_;
};

} // namespace ragd
