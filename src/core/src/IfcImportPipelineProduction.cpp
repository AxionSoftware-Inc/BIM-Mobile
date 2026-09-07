// Production IFC fidelity wrapper.
//
// V2 remains a self-contained, proven recovery implementation.  This
// translation unit compiles it as an internal stage and then performs a
// monotonic fidelity pass for schema details that used to be lost in the
// lightweight STEP recovery path: parameterized profile attribute positions,
// tessellated PnIndex indirection and missing building-storey levels.
#define import_ifc import_ifc_v2_internal
#include "IfcImportPipelineV2.cpp"
#undef import_ifc

#include <iomanip>

namespace tbe::core {
namespace {

std::string number_text(double value) {
    std::ostringstream stream;
    stream << std::setprecision(17) << value;
    return stream.str();
}

std::string integer_tuple_text(const std::vector<int>& values) {
    std::string result{"("};
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index != 0) result += ',';
        result += std::to_string(values[index]);
    }
    result += ')';
    return result;
}

std::string nested_integer_tuple_text(const std::vector<std::vector<int>>& values) {
    std::string result{"("};
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index != 0) result += ',';
        result += integer_tuple_text(values[index]);
    }
    result += ')';
    return result;
}

std::string reference_list_text(const std::vector<int>& values) {
    std::string result{"("};
    for (std::size_t index = 0; index < values.size(); ++index) {
        if (index != 0) result += ',';
        result += '#' + std::to_string(values[index]);
    }
    result += ')';
    return result;
}

void remap_indices(std::vector<std::vector<int>>& faces, const std::vector<int>& pn_index) {
    if (pn_index.empty()) return;
    for (auto& face : faces) {
        for (auto& index : face) {
            if (index < 1 || static_cast<std::size_t>(index) > pn_index.size()) {
                index = 0;
                continue;
            }
            index = pn_index[static_cast<std::size_t>(index - 1)];
        }
    }
}

std::vector<int> remap_indices(std::vector<int> face, const std::vector<int>& pn_index) {
    if (pn_index.empty()) return face;
    for (auto& index : face) {
        if (index < 1 || static_cast<std::size_t>(index) > pn_index.size()) {
            index = 0;
            continue;
        }
        index = pn_index[static_cast<std::size_t>(index - 1)];
    }
    return face;
}

struct FidelityEntitySet {
    EntityIndex entities{};
    std::unordered_set<int> approximate_profile_ids{};
};

FidelityEntitySet prepare_fidelity_entities(const std::vector<StepEntity>& parsed) {
    FidelityEntitySet prepared;
    prepared.entities.reserve(parsed.size() + parsed.size() / 16 + 64);
    int next_id = 1;
    for (const auto& source : parsed) {
        prepared.entities.emplace(source.id, source);
        next_id = std::max(next_id, source.id + 1);
    }

    std::vector<StepEntity> additions;

    // IfcParameterizedProfileDef inherits Position before its dimensions.  V2
    // originally consumed ProfileName as Position and Position as X/radius.
    // Rewrite only the internal recovery view so the source document and its
    // semantic identity remain untouched.
    for (const auto& source : parsed) {
        auto corrected = source;
        if ((source.type == "IFCRECTANGLEPROFILEDEF" ||
             source.type == "IFCRECTANGLEHOLLOWPROFILEDEF") &&
            source.arguments.size() > 4) {
            corrected.type = "IFCRECTANGLEPROFILEDEF";
            corrected.arguments[1] = source.arguments[2]; // Position
            corrected.arguments[2] = source.arguments[3]; // XDim
            corrected.arguments[3] = source.arguments[4]; // YDim
            if (source.type == "IFCRECTANGLEHOLLOWPROFILEDEF") {
                prepared.approximate_profile_ids.insert(source.id);
            }
            prepared.entities[source.id] = std::move(corrected);
        } else if ((source.type == "IFCCIRCLEPROFILEDEF" ||
                    source.type == "IFCCIRCLEHOLLOWPROFILEDEF") &&
                   source.arguments.size() > 3) {
            corrected.type = "IFCCIRCLEPROFILEDEF";
            corrected.arguments[1] = source.arguments[2]; // Position
            corrected.arguments[2] = source.arguments[3]; // Radius
            if (source.type == "IFCCIRCLEHOLLOWPROFILEDEF") {
                prepared.approximate_profile_ids.insert(source.id);
            }
            prepared.entities[source.id] = std::move(corrected);
        } else if (source.type == "IFCELLIPSEPROFILEDEF" &&
                   source.arguments.size() > 4) {
            const auto semi_axis_1 = step_number(source.arguments[3]).value_or(0.0);
            const auto semi_axis_2 = step_number(source.arguments[4]).value_or(0.0);
            if (semi_axis_1 <= 1.0e-12 || semi_axis_2 <= 1.0e-12) continue;

            Transform3 position;
            PlacementCache cache;
            if (const auto position_id = step_reference(source.arguments[2]); position_id.has_value()) {
                std::unordered_set<int> guard;
                position = placement_transform(*position_id, prepared.entities, cache, guard);
            }

            constexpr int segments = 48;
            std::vector<int> point_ids;
            point_ids.reserve(segments + 1);
            for (int index = 0; index <= segments; ++index) {
                const auto angle = 2.0 * 3.14159265358979323846 *
                    static_cast<double>(index % segments) / static_cast<double>(segments);
                const auto point = transform_point(
                    position,
                    {semi_axis_1 * std::cos(angle), semi_axis_2 * std::sin(angle), 0.0});
                const auto point_id = next_id++;
                point_ids.push_back(point_id);
                additions.push_back(StepEntity{
                    .id = point_id,
                    .type = "IFCCARTESIANPOINT",
                    .arguments = {"(" + number_text(point.x) + "," + number_text(point.y) + "," + number_text(point.z) + ")"},
                });
            }
            const auto curve_id = next_id++;
            additions.push_back(StepEntity{
                .id = curve_id,
                .type = "IFCPOLYLINE",
                .arguments = {reference_list_text(point_ids)},
            });
            corrected.type = "IFCARBITRARYCLOSEDPROFILEDEF";
            corrected.arguments = {
                source.arguments[0],
                source.arguments[1],
                '#' + std::to_string(curve_id),
            };
            prepared.approximate_profile_ids.insert(source.id);
            prepared.entities[source.id] = std::move(corrected);
        }
    }

    for (auto& addition : additions) {
        prepared.entities.emplace(addition.id, std::move(addition));
    }
    additions.clear();

    // IFC4 tessellated face sets may index Coordinates indirectly through
    // PnIndex. Treating CoordIndex as a direct point-list index scrambles the
    // mesh while still producing superficially valid triangles.
    for (const auto& source : parsed) {
        if (source.type == "IFCTRIANGULATEDFACESET" && source.arguments.size() > 4) {
            const auto pn_index = integer_list(source.arguments[4]);
            if (pn_index.empty()) continue;
            auto corrected = prepared.entities[source.id];
            auto faces = nested_integer_tuples(source.arguments[3]);
            remap_indices(faces, pn_index);
            corrected.arguments[3] = nested_integer_tuple_text(faces);
            corrected.arguments[4] = "$";
            prepared.entities[source.id] = std::move(corrected);
        } else if (source.type == "IFCPOLYGONALFACESET" && source.arguments.size() > 3) {
            const auto pn_index = integer_list(source.arguments[3]);
            if (pn_index.empty()) continue;
            auto corrected_set = prepared.entities[source.id];
            std::vector<int> cloned_face_ids;
            for (const auto face_id : references_in(source.arguments[2])) {
                const auto face = prepared.entities.find(face_id);
                if (face == prepared.entities.end() || face->second.arguments.empty()) continue;
                if (face->second.type != "IFCINDEXEDPOLYGONALFACE" &&
                    face->second.type != "IFCINDEXEDPOLYGONALFACEWITHVOIDS") {
                    continue;
                }
                auto cloned = face->second;
                cloned.id = next_id++;
                cloned.arguments[0] = integer_tuple_text(
                    remap_indices(integer_list(face->second.arguments[0]), pn_index));
                cloned_face_ids.push_back(cloned.id);
                additions.push_back(std::move(cloned));
            }
            if (!cloned_face_ids.empty()) {
                corrected_set.arguments[2] = reference_list_text(cloned_face_ids);
                corrected_set.arguments[3] = "$";
                prepared.entities[source.id] = std::move(corrected_set);
            }
        }
    }
    for (auto& addition : additions) {
        prepared.entities.emplace(addition.id, std::move(addition));
    }

    return prepared;
}

bool graph_contains_any(
    int id,
    const EntityIndex& entities,
    const std::unordered_set<int>& targets,
    std::unordered_set<int>& visited
) {
    if (targets.find(id) != targets.end()) return true;
    if (!visited.insert(id).second) return false;
    const auto found = entities.find(id);
    if (found == entities.end()) return false;
    for (const auto& argument : found->second.arguments) {
        for (const auto child : references_in(argument)) {
            if (graph_contains_any(child, entities, targets, visited)) return true;
        }
    }
    return false;
}

bool graph_uses_fidelity_fix(const StepEntity& product, const EntityIndex& original) {
    if (product.arguments.size() <= 6) return false;
    const auto shape = step_reference(product.arguments[6]);
    if (!shape.has_value()) return false;
    std::unordered_set<int> visited;
    std::vector<int> stack{*shape};
    while (!stack.empty()) {
        const auto id = stack.back();
        stack.pop_back();
        if (!visited.insert(id).second) continue;
        const auto found = original.find(id);
        if (found == original.end()) continue;
        const auto& entity = found->second;
        if (entity.type == "IFCRECTANGLEPROFILEDEF" ||
            entity.type == "IFCCIRCLEPROFILEDEF" ||
            entity.type == "IFCRECTANGLEHOLLOWPROFILEDEF" ||
            entity.type == "IFCCIRCLEHOLLOWPROFILEDEF" ||
            entity.type == "IFCELLIPSEPROFILEDEF") {
            return true;
        }
        if (entity.type == "IFCTRIANGULATEDFACESET" && entity.arguments.size() > 4 &&
            !integer_list(entity.arguments[4]).empty()) {
            return true;
        }
        if (entity.type == "IFCPOLYGONALFACESET" && entity.arguments.size() > 3 &&
            !integer_list(entity.arguments[3]).empty()) {
            return true;
        }
        for (const auto& argument : entity.arguments) {
            for (const auto child : references_in(argument)) stack.push_back(child);
        }
    }
    return false;
}

struct StoreyInfo {
    int step_id{};
    double elevation{};
    std::string name{};
};

std::vector<StoreyInfo> collect_storeys(
    const std::vector<StepEntity>& parsed,
    const EntityIndex& entities,
    PlacementCache& placement_cache,
    double unit_scale
) {
    std::vector<StoreyInfo> storeys;
    for (const auto& entity : parsed) {
        if (entity.type != "IFCBUILDINGSTOREY" && entity.type != "IFCLEVEL") continue;
        double elevation = 0.0;
        bool placement_known = false;
        if (entity.arguments.size() > 5) {
            if (const auto placement_id = step_reference(entity.arguments[5]); placement_id.has_value()) {
                std::unordered_set<int> guard;
                const auto placement = placement_transform(*placement_id, entities, placement_cache, guard);
                elevation = placement.origin.z * unit_scale;
                placement_known = true;
            }
        }
        if (!placement_known) {
            for (auto it = entity.arguments.rbegin(); it != entity.arguments.rend(); ++it) {
                if (const auto value = step_number(*it); value.has_value()) {
                    elevation = *value * unit_scale;
                    break;
                }
            }
        }
        auto name = entity.arguments.size() > 2 ? step_string(entity.arguments[2]) : std::string{};
        if (name.empty()) name = "Storey " + std::to_string(entity.id);
        storeys.push_back(StoreyInfo{entity.id, elevation, std::move(name)});
    }
    std::sort(storeys.begin(), storeys.end(), [](const auto& left, const auto& right) {
        if (left.elevation != right.elevation) return left.elevation < right.elevation;
        return left.step_id < right.step_id;
    });
    return storeys;
}

ElementId level_near(const LevelIndex& levels, double elevation, double tolerance = 0.001) {
    for (const auto& [id, existing] : levels) {
        if (std::abs(existing - elevation) <= tolerance) return id;
    }
    return 0;
}

std::unordered_map<int, ElementId> ensure_storey_levels(
    const std::vector<StoreyInfo>& storeys,
    Document& document
) {
    std::unordered_map<int, ElementId> result;
    auto levels = build_level_index(document);
    for (std::size_t index = 0; index < storeys.size(); ++index) {
        const auto& storey = storeys[index];
        auto level_id = level_near(levels, storey.elevation);
        if (level_id == 0) {
            auto height = 3.0;
            if (index + 1 < storeys.size()) {
                const auto delta = storeys[index + 1].elevation - storey.elevation;
                if (delta > 0.10 && std::isfinite(delta)) height = delta;
            }
            level_id = document.create_level(storey.name, storey.elevation, height);
            levels.emplace_back(level_id, storey.elevation);
        }
        result[storey.step_id] = level_id;
        if (auto* level = document.find_ptr(level_id); level != nullptr) {
            set_metadata(*level, "ifc_storey_step_id", std::to_string(storey.step_id), MetadataValueKind::Number);
        }
    }
    return result;
}

MeshBuffer* mutable_element_mesh(Element& element) {
    switch (element.kind()) {
    case ElementKind::Wall: return &element.wall()->geometry.mesh;
    case ElementKind::Door: return &element.door()->mesh;
    case ElementKind::Window: return &element.window()->mesh;
    case ElementKind::Slab: return &element.slab()->mesh;
    case ElementKind::Roof: return &element.roof()->mesh;
    case ElementKind::Column: return &element.column()->mesh;
    case ElementKind::Beam: return &element.beam()->mesh;
    case ElementKind::Stair: return &element.stair()->mesh;
    case ElementKind::Proxy: return &element.proxy()->mesh;
    case ElementKind::Level:
    case ElementKind::Room: return nullptr;
    }
    return nullptr;
}

void set_element_level_id(Element& element, ElementId level_id) {
    switch (element.kind()) {
    case ElementKind::Wall: element.wall()->level_id = level_id; break;
    case ElementKind::Door: element.door()->level_id = level_id; break;
    case ElementKind::Window: element.window()->level_id = level_id; break;
    case ElementKind::Slab: element.slab()->level_id = level_id; break;
    case ElementKind::Roof: element.roof()->level_id = level_id; break;
    case ElementKind::Column: element.column()->level_id = level_id; break;
    case ElementKind::Beam: element.beam()->level_id = level_id; break;
    case ElementKind::Stair: element.stair()->base_level_id = level_id; break;
    case ElementKind::Proxy: element.proxy()->level_id = level_id; break;
    case ElementKind::Level:
    case ElementKind::Room: break;
    }
}

void relevel_preserve_world(Document& document, Element& element, ElementId level_id) {
    if (level_id == 0) return;
    const auto old_level_id = element_level_id(element);
    if (old_level_id == level_id) return;
    const auto old_elevation = level_elevation(document, old_level_id);
    const auto new_elevation = level_elevation(document, level_id);
    if (auto* mesh = mutable_element_mesh(element); mesh != nullptr) {
        const auto delta = old_elevation - new_elevation;
        for (auto& point : mesh->vertices) point.z += delta;
    }
    set_element_level_id(element, level_id);
}

std::unordered_map<int, ElementId> build_step_index(const Document& document) {
    std::unordered_map<int, ElementId> result;
    for (const auto& element : document.elements()) {
        const auto found = element.metadata().find("ifc_step_id");
        if (found == element.metadata().end()) continue;
        char* end = nullptr;
        const auto value = std::strtol(found->second.value.c_str(), &end, 10);
        if (end != found->second.value.c_str() && value > 0 && value <= std::numeric_limits<int>::max()) {
            result.emplace(static_cast<int>(value), element.id());
        }
    }
    return result;
}

bool mesh_has_geometry(const Element& element) {
    switch (element.kind()) {
    case ElementKind::Wall: return !element.wall()->geometry.mesh.vertices.empty() && !element.wall()->geometry.mesh.indices.empty();
    case ElementKind::Door: return !element.door()->mesh.vertices.empty() && !element.door()->mesh.indices.empty();
    case ElementKind::Window: return !element.window()->mesh.vertices.empty() && !element.window()->mesh.indices.empty();
    case ElementKind::Slab: return !element.slab()->mesh.vertices.empty() && !element.slab()->mesh.indices.empty();
    case ElementKind::Roof: return !element.roof()->mesh.vertices.empty() && !element.roof()->mesh.indices.empty();
    case ElementKind::Column: return !element.column()->mesh.vertices.empty() && !element.column()->mesh.indices.empty();
    case ElementKind::Beam: return !element.beam()->mesh.vertices.empty() && !element.beam()->mesh.indices.empty();
    case ElementKind::Stair: return !element.stair()->mesh.vertices.empty() && !element.stair()->mesh.indices.empty();
    case ElementKind::Proxy: return !element.proxy()->mesh.vertices.empty() && !element.proxy()->mesh.indices.empty();
    case ElementKind::Level:
    case ElementKind::Room: return false;
    }
    return false;
}

} // namespace

Document import_ifc(
    const std::filesystem::path& path,
    std::string document_name,
    IfcExchangeReport* report
) {
    auto document = import_ifc_v2_internal(path, std::move(document_name), report);

    std::ifstream file(path, std::ios::binary);
    if (!file) return document;
    std::ostringstream buffer;
    buffer << file.rdbuf();
    const auto contents = buffer.str();
    if (contents.find("/* TBE_DOCUMENT_JSON_HEX ") != std::string::npos) return document;

    const auto parsed = parse_step_entities(contents);
    EntityIndex original;
    original.reserve(parsed.size());
    for (const auto& entity : parsed) original.emplace(entity.id, entity);
    auto prepared = prepare_fidelity_entities(parsed);

    const auto unit_scale = length_scale(parsed);
    PlacementCache placement_cache;
    placement_cache.reserve(parsed.size() / 8 + 16);
    MappingCache mapping_cache;
    mapping_cache.reserve(parsed.size() / 16 + 16);
    const auto spatial_parents = build_spatial_parent_index(parsed);
    const auto storeys = collect_storeys(parsed, original, placement_cache, unit_scale);
    const auto storey_levels = ensure_storey_levels(storeys, document);
    auto levels = build_level_index(document);
    auto guid_index = build_guid_index(document);
    auto step_index = build_step_index(document);

    std::size_t corrected_geometry = 0;
    std::size_t restored_products = 0;
    std::size_t created_levels = 0;
    for (const auto& storey : storeys) {
        const auto mapped = storey_levels.find(storey.step_id);
        if (mapped == storey_levels.end()) continue;
        const auto* level = document.find_ptr(mapped->second);
        if (level != nullptr && level->level() != nullptr &&
            std::abs(level->level()->elevation_meters - storey.elevation) <= 0.001) {
            ++created_levels;
        }
    }

    for (const auto& source : parsed) {
        if (!is_physical_product(source, original)) continue;
        const auto guid = source_guid(source);
        Element* existing = nullptr;
        if (!guid.empty()) {
            const auto found = guid_index.find(guid);
            if (found != guid_index.end()) existing = document.find_ptr(found->second);
        }
        if (existing == nullptr) {
            const auto found = step_index.find(source.id);
            if (found != step_index.end()) existing = document.find_ptr(found->second);
        }

        ElementId correct_level{};
        if (const auto storey = storey_for_product(source.id, original, spatial_parents); storey.has_value()) {
            const auto mapped = storey_levels.find(*storey);
            if (mapped != storey_levels.end()) correct_level = mapped->second;
        }
        if (existing != nullptr && correct_level != 0) {
            relevel_preserve_world(document, *existing, correct_level);
            set_metadata(*existing, "ifc_storey_level_id", std::to_string(correct_level), MetadataValueKind::Number);
        }

        const bool affected = graph_uses_fidelity_fix(source, original);
        const bool needs_geometry = existing == nullptr || !mesh_has_geometry(*existing) ||
            !metadata_true(*existing, "ifc_exact_geometry");
        if (!affected && !needs_geometry) continue;

        auto recovered = product_recovered_mesh(
            source, prepared.entities, unit_scale, placement_cache, mapping_cache);
        if (recovered.mesh.vertices.empty() || recovered.mesh.indices.empty()) continue;

        if (!prepared.approximate_profile_ids.empty()) {
            const auto shape = source.arguments.size() > 6 ? step_reference(source.arguments[6]) : std::nullopt;
            if (shape.has_value()) {
                std::unordered_set<int> visited;
                if (graph_contains_any(*shape, original, prepared.approximate_profile_ids, visited)) {
                    recovered.exact = false;
                    recovered.stage = "profile-outer-shell-tessellation";
                }
            }
        }

        if (existing != nullptr) {
            const bool current_exact = metadata_true(*existing, "ifc_exact_geometry");
            if (current_exact && !recovered.exact) continue;
            if (assign_mesh(document, *existing, source, std::move(recovered))) {
                ++corrected_geometry;
            }
            continue;
        }

        const auto bounds = mesh_bounds(recovered.mesh);
        if (!bounds.valid) continue;
        if (correct_level == 0) correct_level = nearest_level(levels, bounds.minimum.z);
        if (correct_level == 0) {
            correct_level = document.create_level("Level 1", 0.0, 3.0);
            levels = build_level_index(document);
        }
        const auto elevation = level_elevation(document, correct_level);
        const auto width = std::max(0.01, bounds.maximum.x - bounds.minimum.x);
        const auto depth = std::max(0.01, bounds.maximum.y - bounds.minimum.y);
        const auto height = std::max(0.01, bounds.maximum.z - bounds.minimum.z);
        const auto center = Point2{
            (bounds.minimum.x + bounds.maximum.x) * 0.5,
            (bounds.minimum.y + bounds.maximum.y) * 0.5,
        };
        const auto exact = recovered.exact;
        const auto stage = recovered.stage;
        const auto mapping_source = recovered.mapping_source_step_id;
        const auto id = document.create_proxy(
            product_name(source),
            correct_level,
            center,
            width,
            depth,
            height,
            relative_to_level(std::move(recovered.mesh), elevation));
        if (auto* created = document.find_ptr(id); created != nullptr) {
            mark_source_identity(*created, source, exact, stage, mapping_source);
            if (!guid.empty()) guid_index[guid] = id;
            step_index[source.id] = id;
            ++restored_products;
            if (report != nullptr) {
                ++report->recovered_proxy_products;
                if (exact) ++report->exact_mesh_products;
                else ++report->approximate_products;
                if (report->failed_geometry_products > 0) --report->failed_geometry_products;
            }
        }
    }

    if (report != nullptr) {
        report->imported_elements = document.elements().size();
        report->warnings.push_back(
            "IFC fidelity pass: corrected profile/PnIndex geometry=" +
            std::to_string(corrected_geometry) +
            ", restored products=" + std::to_string(restored_products) +
            ", storeys mapped=" + std::to_string(storey_levels.size()) + ".");
        report->warnings.push_back(
            "IFC fidelity cache generation 5: parameterized profiles use schema-correct Position/dimension attributes, tessellated PnIndex is resolved before triangulation, and every distinct source storey elevation is represented by a BIM level.");
    }
    return document;
}

} // namespace tbe::core
