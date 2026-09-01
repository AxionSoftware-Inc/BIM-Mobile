#pragma once

#include "tbe/core/Document.hpp"

#include <string>
#include <string_view>

namespace tbe::core {

// v0.1 is the first supported product line. Persistence schema and render
// contracts have independent versions so a visual-contract upgrade never
// silently mutates a project document.
inline constexpr std::string_view TBE_PRODUCT_VERSION = "0.1.0";
inline constexpr int TBE_SCHEMA_VERSION = 1;
inline constexpr std::string_view TBE_ENGINE_VERSION = TBE_PRODUCT_VERSION;

class Project {
public:
    explicit Project(std::string name);

    [[nodiscard]] std::string_view name() const noexcept;
    [[nodiscard]] Document& active_document() noexcept;
    [[nodiscard]] const Document& active_document() const noexcept;
    [[nodiscard]] std::string to_json() const;
    [[nodiscard]] static Project from_json(std::string_view json);

private:
    std::string name_;
    Document document_;
};

} // namespace tbe::core
