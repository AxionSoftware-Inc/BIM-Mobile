#pragma once

#include "tbe/core/Element.hpp"

#include <string>

namespace tbe::core {

class GeometryService {
public:
    [[nodiscard]] std::string backend_name() const;
    [[nodiscard]] WallProfile2D build_wall_profile(const WallData& wall) const;
    [[nodiscard]] GeneratedGeometry build_wall_geometry(const WallData& wall, Revision source_revision) const;
};

} // namespace tbe::core
