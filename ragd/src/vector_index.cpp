#include "vector_index.hpp"
#include <algorithm>
#include <cmath>
#include <queue>
#include <stdexcept>

namespace ragd {

void normalize_vector(std::vector<float>& v) {
    double n2 = 0.0;
    for (float x : v) n2 += static_cast<double>(x) * x;
    if (n2 <= 0.0) throw std::runtime_error("Embedding vector has zero norm");
    const float inv = static_cast<float>(1.0 / std::sqrt(n2));
    for (float& x : v) x *= inv;
}

void FlatIndex::replace(std::vector<IndexEntry> entries) {
    std::size_t dim = 0;
    for (auto& e : entries) {
        if (e.embedding.empty()) throw std::runtime_error("Empty embedding in index");
        if (dim == 0) dim = e.embedding.size();
        if (e.embedding.size() != dim) throw std::runtime_error("Mixed embedding dimensions in index");
        normalize_vector(e.embedding);
    }
    entries_ = std::move(entries);
    dim_ = dim;
}

std::vector<SearchHit> FlatIndex::search(const std::vector<float>& query_in, std::size_t top_k, const SearchFilter& filter) const {
    if (top_k == 0 || entries_.empty()) return {};
    if (query_in.size() != dim_) throw std::runtime_error("Query embedding dimension does not match index");
    std::vector<float> query = query_in;
    normalize_vector(query);

    struct Node { float score; std::size_t idx; };
    struct MinCmp { bool operator()(const Node& a, const Node& b) const { return a.score > b.score; } };
    std::priority_queue<Node, std::vector<Node>, MinCmp> heap;

    for (std::size_t i = 0; i < entries_.size(); ++i) {
        const auto& e = entries_[i];
        if (!filter.owner.empty() && e.owner != filter.owner) continue;
        if (!filter.document_ids.empty() && filter.document_ids.find(e.document_id) == filter.document_ids.end()) continue;
        float dot = 0.0f;
        for (std::size_t d = 0; d < dim_; ++d) dot += query[d] * e.embedding[d];
        if (heap.size() < top_k) heap.push(Node{dot, i});
        else if (dot > heap.top().score) { heap.pop(); heap.push(Node{dot, i}); }
    }

    std::vector<SearchHit> out;
    out.reserve(heap.size());
    while (!heap.empty()) {
        const auto n = heap.top(); heap.pop();
        const auto& e = entries_[n.idx];
        out.push_back(SearchHit{e.chunk_id, e.document_id, e.ordinal, n.score});
    }
    std::sort(out.begin(), out.end(), [](const SearchHit& a, const SearchHit& b){ return a.score > b.score; });
    return out;
}

} // namespace ragd
