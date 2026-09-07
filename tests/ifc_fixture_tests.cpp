#include "tbe/core/Element.hpp"
#include "tbe/core/IfcExchange.hpp"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

const tbe::core::MeshBuffer* mesh_for(const tbe::core::Element& element) {
    switch (element.kind()) {
    case tbe::core::ElementKind::Wall:
        return &element.wall()->geometry.mesh;
    case tbe::core::ElementKind::Door:
        return &element.door()->mesh;
    case tbe::core::ElementKind::Window:
        return &element.window()->mesh;
    case tbe::core::ElementKind::Slab:
        return &element.slab()->mesh;
    case tbe::core::ElementKind::Roof:
        return &element.roof()->mesh;
    case tbe::core::ElementKind::Column:
        return &element.column()->mesh;
    case tbe::core::ElementKind::Beam:
        return &element.beam()->mesh;
    case tbe::core::ElementKind::Stair:
        return &element.stair()->mesh;
    case tbe::core::ElementKind::Proxy:
        return &element.proxy()->mesh;
    case tbe::core::ElementKind::Level:
    case tbe::core::ElementKind::Room:
        return nullptr;
    }
    return nullptr;
}

const tbe::core::Element* element_by_ifc_guid(
    const tbe::core::Document& document,
    const std::string& guid
) {
    for (const auto& element : document.elements()) {
        const auto found = element.metadata().find("ifc_guid");
        if (found != element.metadata().end() && found->second.value == guid) return &element;
    }
    return nullptr;
}

struct Bounds {
    double min_x{1.0e100};
    double min_y{1.0e100};
    double min_z{1.0e100};
    double max_x{-1.0e100};
    double max_y{-1.0e100};
    double max_z{-1.0e100};
};

Bounds bounds_for(const tbe::core::MeshBuffer& mesh) {
    Bounds bounds;
    for (const auto& point : mesh.vertices) {
        bounds.min_x = std::min(bounds.min_x, point.x);
        bounds.min_y = std::min(bounds.min_y, point.y);
        bounds.min_z = std::min(bounds.min_z, point.z);
        bounds.max_x = std::max(bounds.max_x, point.x);
        bounds.max_y = std::max(bounds.max_y, point.y);
        bounds.max_z = std::max(bounds.max_z, point.z);
    }
    return bounds;
}

void validate_fixture(const std::filesystem::path& path, bool require_mesh) {
    assert(std::filesystem::exists(path));

    tbe::core::IfcExchangeReport report;
    const auto document = tbe::core::import_ifc(path, path.stem().string(), &report);
    assert(report.imported_elements > 0);
    assert(document.elements().size() == report.imported_elements);

    // Every source physical product is accounted for. Failed geometry remains
    // an explicit diagnostic issue; it must never disappear silently.
    assert(report.silent_dropped_products == 0);
    assert(report.source_physical_products ==
           report.native_semantic_products +
           report.recovered_proxy_products +
           report.failed_geometry_products);
    assert(report.issues.size() >= report.failed_geometry_products);

    std::size_t meshed_elements{};
    std::size_t mesh_vertices{};
    std::size_t mesh_triangles{};
    for (const auto& element : document.elements()) {
        const auto* mesh = mesh_for(element);
        if (mesh == nullptr) continue;
        if (mesh->vertices.empty() && mesh->indices.empty()) continue;
        assert(!mesh->vertices.empty());
        assert(!mesh->indices.empty());
        assert(mesh->indices.size() % 3 == 0);
        for (const auto& vertex : mesh->vertices) {
            assert(std::isfinite(vertex.x));
            assert(std::isfinite(vertex.y));
            assert(std::isfinite(vertex.z));
        }
        for (const auto index : mesh->indices) assert(index < mesh->vertices.size());
        ++meshed_elements;
        mesh_vertices += mesh->vertices.size();
        mesh_triangles += mesh->indices.size() / 3;
    }

    std::cout << path.filename().string() << ": "
              << report.imported_elements << " elements, "
              << meshed_elements << " meshed, "
              << mesh_vertices << " vertices, "
              << mesh_triangles << " triangles, source="
              << report.source_physical_products << ", native="
              << report.native_semantic_products << ", proxy="
              << report.recovered_proxy_products << ", failed="
              << report.failed_geometry_products << ", properties="
              << report.imported_property_values << ", "
              << report.warnings.size() << " warnings\n";
    for (const auto& warning : report.warnings) std::cout << "  warning: " << warning << "\n";
    for (const auto& issue : report.issues) {
        std::cout << "  issue: #" << issue.step_id << " " << issue.entity_type
                  << " [" << issue.stage << "] " << issue.message << "\n";
    }
    if (require_mesh) {
        assert(meshed_elements > 0);
        assert(mesh_vertices > 0);
        assert(mesh_triangles > 0);
    }
}

void validate_multi_storey_containment(const std::filesystem::path& path) {
    tbe::core::IfcExchangeReport report;
    const auto document = tbe::core::import_ifc(path, "Multi-storey", &report);
    std::vector<std::pair<tbe::core::ElementId, double>> levels;
    for (const auto& element : document.elements()) {
        if (const auto* level = element.level(); level != nullptr) {
            levels.emplace_back(element.id(), level->elevation_meters);
        }
    }
    assert(levels.size() == 2);
    std::sort(levels.begin(), levels.end(), [](const auto& left, const auto& right) {
        return left.second < right.second;
    });
    assert(std::abs(levels[0].second - 0.0) < 1.0e-6);
    assert(std::abs(levels[1].second - 3.2) < 1.0e-6);

    for (const auto& element : document.elements()) {
        const auto* wall = element.wall();
        if (wall == nullptr) continue;
        const auto guid = element.metadata().at("ifc_guid").value;
        if (guid == "W1") assert(wall->level_id == levels[0].first);
        if (guid == "W2") assert(wall->level_id == levels[1].first);
    }
}

void validate_mapped_nested_placement(const std::filesystem::path& path) {
    tbe::core::IfcExchangeReport report;
    const auto document = tbe::core::import_ifc(path, "Mapped nested placement", &report);
    assert(report.silent_dropped_products == 0);
    assert(report.source_physical_products == 2);

    const auto* first = element_by_ifc_guid(document, "F1");
    const auto* second = element_by_ifc_guid(document, "F2");
    assert(first != nullptr);
    assert(second != nullptr);
    const auto* first_mesh = mesh_for(*first);
    const auto* second_mesh = mesh_for(*second);
    assert(first_mesh != nullptr && !first_mesh->vertices.empty());
    assert(second_mesh != nullptr && !second_mesh->vertices.empty());

    const auto first_exact = first->metadata().find("ifc_exact_geometry");
    const auto second_exact = second->metadata().find("ifc_exact_geometry");
    assert(first_exact != first->metadata().end() && first_exact->second.value == "true");
    assert(second_exact != second->metadata().end() && second_exact->second.value == "true");
    assert(first->metadata().find("ifc_mapping_source_step_id") != first->metadata().end());
    assert(second->metadata().find("ifc_mapping_source_step_id") != second->metadata().end());

    // Storey elevation is represented by the engine level, therefore meshes
    // are level-relative in Z. Mapped target translation (2 m in local X),
    // product translation and a 90-degree product rotation must each be
    // applied exactly once.
    const auto a = bounds_for(*first_mesh);
    const auto b = bounds_for(*second_mesh);
    assert(std::abs(a.min_x - 0.5) < 1.0e-6);
    assert(std::abs(a.max_x - 1.0) < 1.0e-6);
    assert(std::abs(a.min_y - 4.0) < 1.0e-6);
    assert(std::abs(a.max_y - 5.0) < 1.0e-6);
    assert(std::abs(a.min_z) < 1.0e-6);
    assert(std::abs(a.max_z) < 1.0e-6);
    assert(std::abs(b.min_x - 4.5) < 1.0e-6);
    assert(std::abs(b.max_x - 5.0) < 1.0e-6);
    assert(std::abs(b.min_y - 4.0) < 1.0e-6);
    assert(std::abs(b.max_y - 5.0) < 1.0e-6);
    assert(std::abs(b.min_z) < 1.0e-6);
    assert(std::abs(b.max_z) < 1.0e-6);

    assert(first->proxy() != nullptr && second->proxy() != nullptr);
    assert(first->proxy()->level_id == second->proxy()->level_id);
    const auto* level = document.find_ptr(first->proxy()->level_id);
    assert(level != nullptr && level->level() != nullptr);
    assert(std::abs(level->level()->elevation_meters - 3.0) < 1.0e-6);
}

void validate_profile_pnindex_fidelity(const std::filesystem::path& path) {
    tbe::core::IfcExchangeReport report;
    const auto document = tbe::core::import_ifc(path, "Profile PnIndex fidelity", &report);
    assert(report.silent_dropped_products == 0);
    assert(report.source_physical_products == 2);

    const auto* column = element_by_ifc_guid(document, "C1");
    const auto* furniture = element_by_ifc_guid(document, "FPN");
    assert(column != nullptr);
    assert(furniture != nullptr);
    const auto* column_mesh = mesh_for(*column);
    const auto* furniture_mesh = mesh_for(*furniture);
    assert(column_mesh != nullptr && !column_mesh->vertices.empty());
    assert(furniture_mesh != nullptr && !furniture_mesh->vertices.empty());

    // IfcRectangleProfileDef is (ProfileType, ProfileName, Position, XDim,
    // YDim). The old recovery path shifted these attributes left and produced
    // a degenerate extrusion. Product placement (10,20), profile position
    // (2,3), XDim=2 and YDim=1 must produce these exact level-relative bounds.
    const auto column_bounds = bounds_for(*column_mesh);
    assert(std::abs(column_bounds.min_x - 11.0) < 1.0e-6);
    assert(std::abs(column_bounds.max_x - 13.0) < 1.0e-6);
    assert(std::abs(column_bounds.min_y - 22.5) < 1.0e-6);
    assert(std::abs(column_bounds.max_y - 23.5) < 1.0e-6);
    assert(std::abs(column_bounds.min_z - 0.0) < 1.0e-6);
    assert(std::abs(column_bounds.max_z - 4.0) < 1.0e-6);

    // PnIndex=(3,4,5,6) means CoordIndex addresses those four entries of the
    // coordinate list, not entries 1..4 directly. The two leading 100m junk
    // points are deliberate: ignoring PnIndex would make this assertion fail
    // dramatically while still yielding a syntactically valid mesh.
    const auto furniture_bounds = bounds_for(*furniture_mesh);
    assert(std::abs(furniture_bounds.min_x - 5.0) < 1.0e-6);
    assert(std::abs(furniture_bounds.max_x - 7.0) < 1.0e-6);
    assert(std::abs(furniture_bounds.min_y - 6.0) < 1.0e-6);
    assert(std::abs(furniture_bounds.max_y - 7.0) < 1.0e-6);
    assert(std::abs(furniture_bounds.min_z) < 1.0e-6);
    assert(std::abs(furniture_bounds.max_z) < 1.0e-6);

    const auto column_exact = column->metadata().find("ifc_exact_geometry");
    const auto furniture_exact = furniture->metadata().find("ifc_exact_geometry");
    assert(column_exact != column->metadata().end() && column_exact->second.value == "true");
    assert(furniture_exact != furniture->metadata().end() && furniture_exact->second.value == "true");
}

} // namespace

int main(int argc, char** argv) {
    assert(argc > 1);
    bool require_mesh = true;
    int first_path = 1;
    if (std::string(argv[1]) == "--allow-envelope") {
        require_mesh = false;
        first_path = 2;
    }
    assert(first_path < argc);
    for (int index = first_path; index < argc; ++index) validate_fixture(argv[index], require_mesh);
    for (int index = first_path; index < argc; ++index) {
        const auto stem = std::filesystem::path(argv[index]).stem().string();
        if (stem == "multi-storey-containment") validate_multi_storey_containment(argv[index]);
        if (stem == "mapped-nested-placement") validate_mapped_nested_placement(argv[index]);
        if (stem == "profile-pnindex-fidelity") validate_profile_pnindex_fidelity(argv[index]);
    }
    return 0;
}
