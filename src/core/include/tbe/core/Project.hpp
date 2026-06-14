#pragma once

#include "tbe/core/Document.hpp"

#include <string>
#include <string_view>

namespace tbe::core {

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
