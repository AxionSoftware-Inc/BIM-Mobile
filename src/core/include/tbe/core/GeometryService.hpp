#pragma once

#include "tbe/core/Element.hpp"

#include <string>
#include <vector>

namespace tbe::core {

class GeometryService {
public:
    [[nodiscard]] std::string backend_name() const;
    [[nodiscard]] WallProfile2D build_wall_profile(const WallData& wall) const;
    // Returns the final horizontal wall footprint after endpoint joins have
    // been resolved.  Both straight and curved walls use this same boundary
    // for plan rendering, snapping and native edge metadata.
    [[nodiscard]] std::vector<Point2> build_wall_footprint(const WallData& wall) const;
    [[nodiscard]] GeneratedGeometry build_wall_geometry(
        const WallData& wall,
        Revision source_revision,
        const std::vector<WallAssemblyLayer>& layers = {}
    ) const;
};

} // namespace tbe::core
