#pragma once

#include "tbe/core/GeometryBackend.hpp"

#include <memory>
#include <string>

namespace tbe::core {

class GeometryService {
public:
    enum class Backend {
        Fallback,
        OpenCascade,
    };

    explicit GeometryService(Backend backend = Backend::Fallback);
    ~GeometryService();

    GeometryService(const GeometryService&) = delete;
    GeometryService& operator=(const GeometryService&) = delete;
    GeometryService(GeometryService&&) noexcept;
    GeometryService& operator=(GeometryService&&) noexcept;

    [[nodiscard]] std::string backend_name() const;
    [[nodiscard]] bool supports_exact_solids() const noexcept;
    [[nodiscard]] double polygon_area(const std::vector<Point2>& polygon) const;
    [[nodiscard]] double roof_surface_area(const RoofData& roof) const;
    [[nodiscard]] double layered_assembly_thickness(const LayeredAssemblyData& assembly) const;
    [[nodiscard]] MeshBuffer build_extruded_polygon_mesh(
        const std::vector<Point2>& polygon,
        double thickness,
        double elevation_offset
    ) const;
    [[nodiscard]] MeshBuffer build_column_mesh(Point2 center, double width, double depth, double height) const;
    [[nodiscard]] MeshBuffer build_beam_mesh(Point2 start, Point2 end, double width, double height) const;
    [[nodiscard]] MeshBuffer build_stair_mesh(const StairData& stair) const;
    [[nodiscard]] WallProfile2D build_wall_profile(const WallData& wall) const;
    [[nodiscard]] GeneratedGeometry build_wall_geometry(const WallData& wall, Revision source_revision) const;

private:
    std::unique_ptr<IGeometryBackend> backend_;
};

} // namespace tbe::core
