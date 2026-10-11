#pragma once
#include "types.hpp"
#include <cstddef>
#include <string>
#include <vector>

namespace ragd {

enum class RetrievalMode { Dense, Hybrid, Precise };

RetrievalMode parse_retrieval_mode(const std::string& value);
const char* retrieval_mode_name(RetrievalMode mode);
std::vector<SearchHit> union_candidates(const std::vector<SearchHit>& dense, const std::vector<SearchHit>& sparse);
std::vector<SearchHit> reciprocal_rank_fusion(const std::vector<SearchHit>& dense,
                                              const std::vector<SearchHit>& sparse,
                                              std::size_t rrf_k,
                                              std::size_t top_k);

} // namespace ragd
