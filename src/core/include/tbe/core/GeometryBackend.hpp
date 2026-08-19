#pragma once

#include "tbe/core/Element.hpp"

#include <string>

#ifndef TBE_HAS_OCCT
#define TBE_HAS_OCCT 0
#endif

namespace tbe::core {

// Geometry backends own the conversion from semantic wall data to renderable
// geometry. The model layer only sees these value types and never exposes
// backend-specific handles such as OCCT TopoDS_Shape objects.
class IGeometryBackend {
public:
    virtual ~IGeometryBackend() = default;

    [[nodiscard]] virtual std::string name() const = 0;
    [[nodiscard]] virtual bool supports_exact_solids() const noexcept = 0;
    [[nodiscard]] virtual WallProfile2D build_wall_profile(const WallData& wall) const = 0;
    [[nodiscard]] virtual GeneratedGeometry build_wall_geometry(const WallData& wall, Revision source_revision) const = 0;
};

class FallbackGeometryBackend final : public IGeometryBackend {
public:
    [[nodiscard]] std::string name() const override;
    [[nodiscard]] bool supports_exact_solids() const noexcept override;
    [[nodiscard]] WallProfile2D build_wall_profile(const WallData& wall) const override;
    [[nodiscard]] GeneratedGeometry build_wall_geometry(const WallData& wall, Revision source_revision) const override;
};

#if TBE_HAS_OCCT
class OpenCascadeGeometryBackend final : public IGeometryBackend {
public:
    [[nodiscard]] std::string name() const override;
    [[nodiscard]] bool supports_exact_solids() const noexcept override;
    [[nodiscard]] WallProfile2D build_wall_profile(const WallData& wall) const override;
    [[nodiscard]] GeneratedGeometry build_wall_geometry(const WallData& wall, Revision source_revision) const override;
};
#endif

} // namespace tbe::core
