#include "tbe/core/Project.hpp"

#include <stdexcept>
#include <utility>

namespace tbe::core {

Project::Project(std::string name)
    : name_(std::move(name)),
      document_(name_ + " Model") {
    if (name_.empty()) {
        throw std::invalid_argument("project name must not be empty");
    }
}

std::string_view Project::name() const noexcept {
    return name_;
}

Document& Project::active_document() noexcept {
    return document_;
}

const Document& Project::active_document() const noexcept {
    return document_;
}

} // namespace tbe::core
