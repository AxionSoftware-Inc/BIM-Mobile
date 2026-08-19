#pragma once

#include "tbe/core/Element.hpp"

namespace tbe::core {

class Document;

// Builds and caches relationship indexes without owning semantic model data.
// Document remains the mutation facade, while this service owns the derived
// dependency graph cache and its versioning.
class DependencyGraphService {
public:
    [[nodiscard]] DependencyGraph build(const Document& document) const;
    [[nodiscard]] const DependencyGraph& get(const Document& document) const;
    void invalidate() noexcept;
    [[nodiscard]] Revision version() const noexcept;

private:
    mutable DependencyGraph cache_{};
    mutable bool dirty_{true};
    mutable Revision version_{};
};

} // namespace tbe::core
