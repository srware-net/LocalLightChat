#include "retrieval.hpp"
#include <algorithm>
#include <stdexcept>
#include <unordered_map>
#include <unordered_set>

namespace ragd {

RetrievalMode parse_retrieval_mode(const std::string& value) {
    if (value.empty() || value == "dense") return RetrievalMode::Dense;
    if (value == "hybrid") return RetrievalMode::Hybrid;
    if (value == "precise") return RetrievalMode::Precise;
    throw std::invalid_argument("retrieval_mode must be one of: dense, hybrid, precise");
}

const char* retrieval_mode_name(RetrievalMode mode) {
    switch (mode) {
        case RetrievalMode::Dense: return "dense";
        case RetrievalMode::Hybrid: return "hybrid";
        case RetrievalMode::Precise: return "precise";
    }
    return "dense";
}

std::vector<SearchHit> union_candidates(const std::vector<SearchHit>& dense, const std::vector<SearchHit>& sparse) {
    std::vector<SearchHit> out;
    out.reserve(dense.size() + sparse.size());
    std::unordered_set<std::int64_t> seen;
    seen.reserve(dense.size() + sparse.size());
    for (const auto& h : dense) {
        if (seen.insert(h.chunk_id).second) out.push_back(h);
    }
    for (const auto& h : sparse) {
        if (seen.insert(h.chunk_id).second) out.push_back(h);
    }
    return out;
}

std::vector<SearchHit> reciprocal_rank_fusion(const std::vector<SearchHit>& dense,
                                              const std::vector<SearchHit>& sparse,
                                              std::size_t rrf_k,
                                              std::size_t top_k) {
    if (rrf_k == 0) throw std::invalid_argument("hybrid_rrf_k must be > 0");
    if (top_k == 0) return {};

    struct Fused {
        SearchHit hit;
        double score = 0.0;
    };
    std::unordered_map<std::int64_t, Fused> fused;
    fused.reserve(dense.size() + sparse.size());

    auto add = [&](const std::vector<SearchHit>& hits) {
        for (std::size_t i = 0; i < hits.size(); ++i) {
            auto& f = fused[hits[i].chunk_id];
            if (f.hit.chunk_id == 0) f.hit = hits[i];
            f.score += 1.0 / static_cast<double>(rrf_k + i + 1);
        }
    };
    add(dense);
    add(sparse);

    std::vector<SearchHit> out;
    out.reserve(fused.size());
    for (auto& kv : fused) {
        kv.second.hit.score = static_cast<float>(kv.second.score);
        out.push_back(std::move(kv.second.hit));
    }
    std::sort(out.begin(), out.end(), [](const SearchHit& a, const SearchHit& b) {
        if (a.score != b.score) return a.score > b.score;
        return a.chunk_id < b.chunk_id;
    });
    if (out.size() > top_k) out.resize(top_k);
    return out;
}

} // namespace ragd
