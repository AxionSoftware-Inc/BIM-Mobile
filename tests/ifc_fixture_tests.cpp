#include "tbe/core/Element.hpp"
#include "tbe/core/IfcExchange.hpp"

#include <cassert>
#include <cmath>
#include <filesystem>
#include <iostream>
#include <string>

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

void validate_fixture(const std::filesystem::path& path) {
    assert(std::filesystem::exists(path));

    tbe::core::IfcExchangeReport report;
    const auto document = tbe::core::import_ifc(path, path.stem().string(), &report);
    assert(report.imported_elements > 0);
    assert(!document.elements().empty());

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

    // A real building fixture must produce renderable geometry, not only
    // semantic envelopes or metadata records.
    assert(meshed_elements > 0);
    assert(mesh_vertices > 0);
    assert(mesh_triangles > 0);
    std::cout << path.filename().string() << ": "
              << report.imported_elements << " elements, "
              << meshed_elements << " meshed, "
              << mesh_vertices << " vertices, "
              << mesh_triangles << " triangles\n";
}

} // namespace

int main(int argc, char** argv) {
    assert(argc > 1);
    for (int index = 1; index < argc; ++index) validate_fixture(argv[index]);
    return 0;
}
