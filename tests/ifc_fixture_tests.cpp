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

void validate_fixture(const std::filesystem::path& path, bool require_mesh) {
    assert(std::filesystem::exists(path));

    tbe::core::IfcExchangeReport report;
    const auto document = tbe::core::import_ifc(path, path.stem().string(), &report);
    assert(report.imported_elements > 0);
    assert(document.elements().size() == report.imported_elements);

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
              << mesh_triangles << " triangles, "
              << report.warnings.size() << " warnings\n";
    for (const auto& warning : report.warnings) std::cout << "  warning: " << warning << "\n";
    if (require_mesh) {
        // Known-good fixtures must produce renderable geometry, not only
        // semantic envelopes or metadata records.
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
        if (std::filesystem::path(argv[index]).stem() == "multi-storey-containment") {
            validate_multi_storey_containment(argv[index]);
        }
    }
    return 0;
}
