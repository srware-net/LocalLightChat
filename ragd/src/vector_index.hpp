#pragma once
#include "types.hpp"
#include <memory>
#include <string>
#include <unordered_set>
#include <vector>

namespace ragd {

struct SearchFilter {
    std::string owner;
    std::unordered_set<std::string> document_ids;
};

class IVectorIndex {
public:
    virtual ~IVectorIndex() = default;
    virtual void replace(std::vector<IndexEntry> entries) = 0;
    virtual std::vector<SearchHit> search(const std::vector<float>& query, std::size_t top_k, const SearchFilter& filter) const = 0;
    virtual std::size_t size() const = 0;
    virtual std::size_t dimension() const = 0;
};

class FlatIndex final : public IVectorIndex {
public:
    void replace(std::vector<IndexEntry> entries) override;
    std::vector<SearchHit> search(const std::vector<float>& query, std::size_t top_k, const SearchFilter& filter) const override;
    std::size_t size() const override { return entries_.size(); }
    std::size_t dimension() const override { return dim_; }

private:
    std::vector<IndexEntry> entries_;
    std::size_t dim_ = 0;
};

void normalize_vector(std::vector<float>& v);

} // namespace ragd
