#include "tbe/core/IfcExchange.hpp"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <map>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string_view>
#include <unordered_map>

namespace tbe::core {

namespace {

std::string hex_encode(std::string_view value) {
    std::ostringstream out;
    out << std::hex << std::setfill('0');
    for (const auto ch : value) {
        out << std::setw(2) << static_cast<unsigned int>(static_cast<unsigned char>(ch));
    }
    return out.str();
}

std::string hex_decode(std::string_view value) {
    if ((value.size() % 2) != 0) throw std::invalid_argument("invalid IFC semantic sidecar encoding");
    std::string output;
    output.reserve(value.size() / 2);
    for (std::size_t index = 0; index < value.size(); index += 2) {
        unsigned int byte{};
        std::istringstream input{std::string(value.substr(index, 2))};
        input >> std::hex >> byte;
        if (input.fail()) throw std::invalid_argument("invalid IFC semantic sidecar byte");
        output.push_back(static_cast<char>(byte));
    }
    return output;
}

std::string guid_for(std::size_t index) {
    std::ostringstream out;
    out << "'TBE" << std::setw(20) << std::setfill('0') << index << "'";
    return out.str();
}

std::string ifc_name(const Element& element) {
    return hex_encode(element.name());
}

std::string entity_for(ElementKind kind) {
    switch (kind) {
    case ElementKind::Level: return "IFCBUILDINGSTOREY";
    case ElementKind::Wall: return "IFCWALLSTANDARDCASE";
    case ElementKind::Door: return "IFCDOOR";
    case ElementKind::Window: return "IFCWINDOW";
    case ElementKind::Room: return "IFCSPACE";
    case ElementKind::Slab: return "IFCSLAB";
    case ElementKind::Roof: return "IFCROOF";
    case ElementKind::Column: return "IFCCOLUMN";
    case ElementKind::Beam: return "IFCBEAM";
    case ElementKind::Stair: return "IFCSTAIRFLIGHT";
    }
    return "IFCBUILDINGELEMENTPROXY";
}

struct StepEntity {
    int id{};
    std::string type{};
    std::vector<std::string> arguments{};
};

std::string trim(std::string value) {
    const auto first = std::find_if_not(value.begin(), value.end(), [](unsigned char ch) {
        return std::isspace(ch) != 0;
    });
    const auto last = std::find_if_not(value.rbegin(), value.rend(), [](unsigned char ch) {
        return std::isspace(ch) != 0;
    }).base();
    if (first >= last) return {};
    return std::string(first, last);
}

std::vector<std::string> split_step_arguments(std::string_view value) {
    std::vector<std::string> arguments;
    std::size_t start = 0;
    int depth = 0;
    bool quoted = false;
    for (std::size_t index = 0; index < value.size(); ++index) {
        const auto ch = value[index];
        if (ch == '\'') {
            if (index + 1 < value.size() && value[index + 1] == '\'') {
                ++index;
            } else {
                quoted = !quoted;
            }
        } else if (!quoted && ch == '(') {
            ++depth;
        } else if (!quoted && ch == ')') {
            --depth;
        } else if (!quoted && depth == 0 && ch == ',') {
            arguments.push_back(trim(std::string(value.substr(start, index - start))));
            start = index + 1;
        }
    }
    arguments.push_back(trim(std::string(value.substr(start))));
    return arguments;
}

std::vector<StepEntity> parse_step_entities(std::string_view contents) {
    std::vector<StepEntity> entities;
    std::size_t cursor = 0;
    while (cursor < contents.size()) {
        const auto hash = contents.find('#', cursor);
        if (hash == std::string_view::npos) break;
        const auto equals = contents.find('=', hash + 1);
        if (equals == std::string_view::npos) break;
        const auto open = contents.find('(', equals + 1);
        if (open == std::string_view::npos) break;
        const auto id_text = trim(std::string(contents.substr(hash + 1, equals - hash - 1)));
        char* end = nullptr;
        const auto id = std::strtol(id_text.c_str(), &end, 10);
        if (end == id_text.c_str()) {
            cursor = open + 1;
            continue;
        }
        auto type = trim(std::string(contents.substr(equals + 1, open - equals - 1)));
        std::size_t close = open + 1;
        int depth = 1;
        bool quoted = false;
        for (; close < contents.size() && depth > 0; ++close) {
            const auto ch = contents[close];
            if (ch == '\'') {
                if (close + 1 < contents.size() && contents[close + 1] == '\'') {
                    ++close;
                } else {
                    quoted = !quoted;
                }
            } else if (!quoted && ch == '(') {
                ++depth;
            } else if (!quoted && ch == ')') {
                --depth;
            }
        }
        if (depth != 0) break;
        entities.push_back(StepEntity{
            .id = static_cast<int>(id),
            .type = std::move(type),
            .arguments = split_step_arguments(contents.substr(open + 1, close - open - 2)),
        });
        cursor = contents.find(';', close);
        if (cursor == std::string_view::npos) break;
        ++cursor;
    }
    return entities;
}

std::string step_string(const std::string& value) {
    if (value.size() >= 2 && value.front() == '\'' && value.back() == '\'') {
        std::string decoded = value.substr(1, value.size() - 2);
        std::string output;
        for (std::size_t index = 0; index < decoded.size(); ++index) {
            if (decoded[index] == '\'' && index + 1 < decoded.size() && decoded[index + 1] == '\'') ++index;
            output.push_back(decoded[index]);
        }
        return output;
    }
    return {};
}

std::optional<int> step_reference(const std::string& value) {
    if (value.size() < 2 || value.front() != '#') return std::nullopt;
    char* end = nullptr;
    const auto id = std::strtol(value.c_str() + 1, &end, 10);
    if (end == value.c_str() + 1) return std::nullopt;
    return static_cast<int>(id);
}

std::optional<double> step_number(const std::string& value) {
    if (value.empty() || value == "$" || value.front() == '.') return std::nullopt;
    char* end = nullptr;
    const auto number = std::strtod(value.c_str(), &end);
    if (end == value.c_str() || !std::isfinite(number)) return std::nullopt;
    return number;
}

std::optional<double> last_step_number(const StepEntity& entity) {
    for (auto index = entity.arguments.rbegin(); index != entity.arguments.rend(); ++index) {
        if (const auto number = step_number(*index); number.has_value()) return number;
    }
    return std::nullopt;
}

double length_scale_from_units(const std::vector<StepEntity>& entities) {
    for (const auto& entity : entities) {
        if (entity.type != "IFCSIUNIT" || entity.arguments.size() < 4) continue;
        if (entity.arguments[1].find("LENGTHUNIT") == std::string::npos) continue;
        const auto& prefix = entity.arguments[2];
        if (prefix.find("MILLI") != std::string::npos) return 0.001;
        if (prefix.find("CENTI") != std::string::npos) return 0.01;
        if (prefix.find("DECI") != std::string::npos) return 0.1;
        if (prefix.find("KILO") != std::string::npos) return 1000.0;
        if (prefix.find("MICRO") != std::string::npos) return 0.000001;
        return 1.0;
    }
    return 1.0;
}

Point2 placement_point(
    int placement_id,
    const std::unordered_map<int, StepEntity>& entities,
    std::map<int, Point2>& cache,
    std::vector<int>& recursion_guard
) {
    if (const auto found = cache.find(placement_id); found != cache.end()) return found->second;
    if (std::find(recursion_guard.begin(), recursion_guard.end(), placement_id) != recursion_guard.end()) return {};
    const auto found = entities.find(placement_id);
    if (found == entities.end()) return {};
    recursion_guard.push_back(placement_id);
    Point2 result{};
    if (found->second.type == "IFCLOCALPLACEMENT" && found->second.arguments.size() > 1) {
        if (const auto parent = step_reference(found->second.arguments[0]); parent.has_value()) {
            result = placement_point(*parent, entities, cache, recursion_guard);
        }
        if (const auto relative = step_reference(found->second.arguments[1]); relative.has_value()) {
            const auto point = placement_point(*relative, entities, cache, recursion_guard);
            result.x += point.x;
            result.y += point.y;
        }
    } else if (found->second.type == "IFCAXIS2PLACEMENT3D" && !found->second.arguments.empty()) {
        if (const auto point = step_reference(found->second.arguments[0]); point.has_value()) {
            result = placement_point(*point, entities, cache, recursion_guard);
        }
    } else if (found->second.type == "IFCCARTESIANPOINT" && !found->second.arguments.empty()) {
        const auto values = found->second.arguments.front();
        if (values.size() > 2 && values.front() == '(' && values.back() == ')') {
            const auto coordinates = split_step_arguments(std::string_view(values).substr(1, values.size() - 2));
            if (coordinates.size() > 1) {
                result.x = step_number(coordinates[0]).value_or(0.0);
                result.y = step_number(coordinates[1]).value_or(0.0);
            }
        }
    }
    recursion_guard.pop_back();
    cache[placement_id] = result;
    return result;
}

Point2 product_location(
    const StepEntity& entity,
    const std::unordered_map<int, StepEntity>& entities,
    std::map<int, Point2>& cache,
    double length_scale
) {
    if (entity.arguments.size() <= 5) return {};
    const auto placement = step_reference(entity.arguments[5]);
    if (!placement.has_value()) return {};
    std::vector<int> guard;
    const auto point = placement_point(*placement, entities, cache, guard);
    return {.x = point.x * length_scale, .y = point.y * length_scale};
}

std::string product_name(const StepEntity& entity) {
    if (entity.arguments.size() > 2) {
        const auto name = step_string(entity.arguments[2]);
        if (!name.empty()) return name;
    }
    return entity.type + " " + std::to_string(entity.id);
}

void set_ifc_metadata(Element& element, const StepEntity& source, std::string warning = {}) {
    if (!source.arguments.empty()) {
        element.metadata()["ifc_guid"] = MetadataValue{
            .kind = MetadataValueKind::Text,
            .value = step_string(source.arguments.front()),
        };
    }
    element.metadata()["ifc_entity"] = MetadataValue{
        .kind = MetadataValueKind::Text,
        .value = source.type,
    };
    if (!warning.empty()) {
        element.metadata()["ifc_import_note"] = MetadataValue{
            .kind = MetadataValueKind::Text,
            .value = std::move(warning),
        };
    }
}

} // namespace

void export_ifc(const Document& document, const std::filesystem::path& path, IfcExchangeReport* report) {
    std::ofstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("unable to open IFC export path");

    const auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    file << "ISO-10303-21;\nHEADER;\n"
         << "FILE_DESCRIPTION(('ViewDefinition [CoordinationView_V2.0]'),'2;1');\n"
         << "FILE_NAME('" << path.filename().string() << "'," << now
         << ",('Tablet BIM'),('AxionSoftware-Inc'),'Tablet BIM IFC4 exporter','Tablet BIM','');\n"
         << "FILE_SCHEMA(('IFC4'));\nENDSEC;\nDATA;\n";

    // These are intentionally simple semantic entities. Geometry consumers
    // can still identify every authored category while the sidecar below
    // carries the exact engine model for a lossless internal round-trip.
    file << "#1=IFCPROJECT(" << guid_for(1) << ",$,'" << hex_encode(document.name())
         << "',$,$,$,$,(#2),#3);\n";
    file << "#2=IFCUNITASSIGNMENT((#4,#5,#6));\n";
    file << "#3=IFCGEOMETRICREPRESENTATIONCONTEXT($,'Model',3,1.0E-05,#7,$);\n";
    file << "#4=IFCSIUNIT(*,.LENGTHUNIT.,$,.METRE.);\n"
         << "#5=IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.);\n"
         << "#6=IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.);\n"
         << "#7=IFCAXIS2PLACEMENT3D(#8,$,$);\n"
         << "#8=IFCCARTESIANPOINT((0.,0.,0.));\n";

    std::size_t entity_id = 100;
    std::size_t ordinal = 10;
    for (const auto& element : document.elements()) {
        const auto entity_name = entity_for(element.kind());
        file << '#' << entity_id << '=' << entity_name << '(' << guid_for(ordinal++)
             << ",$,#" << (entity_id + 1) << ",'" << ifc_name(element) << "',$,$,$,$,$);\n";
        ++entity_id;
        file << '#' << entity_id << "=IFCLOCALPLACEMENT($,#7);\n";
        ++entity_id;
        if (report != nullptr) ++report->exported_elements;
    }

    // IFC permits comments in the STEP exchange structure. Keeping this
    // marker after DATA makes the contract discoverable and avoids a hidden
    // proprietary file format while preserving every native relation/value.
    file << "/* TBE_DOCUMENT_JSON_HEX " << hex_encode(document.to_json()) << " */\n";
    file << "ENDSEC;\nEND-ISO-10303-21;\n";
    if (!file) throw std::runtime_error("IFC export failed while writing");
}

Document import_ifc(const std::filesystem::path& path, std::string document_name, IfcExchangeReport* report) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("unable to open IFC import path");
    std::ostringstream buffer;
    buffer << file.rdbuf();
    const auto contents = buffer.str();
    constexpr std::string_view marker = "/* TBE_DOCUMENT_JSON_HEX ";
    const auto begin = contents.find(marker);
    if (begin != std::string::npos) {
        const auto value_begin = begin + marker.size();
        const auto value_end = contents.find(" */", value_begin);
        if (value_end == std::string::npos) throw std::invalid_argument("truncated IFC semantic sidecar");
        auto document = Document::from_json(hex_decode(std::string_view(contents).substr(value_begin, value_end - value_begin)));
        if (report != nullptr) report->imported_elements = document.elements().size();
        return document;
    }

    const auto entities = parse_step_entities(contents);
    std::unordered_map<int, StepEntity> by_id;
    for (const auto& entity : entities) by_id.emplace(entity.id, entity);
    Document document(std::move(document_name));
    // Third-party files can contain hundreds of walls with incomplete
    // placement/connection data. Rebuilding automatic joins for every
    // approximated fallback wall is both unnecessary and quadratic; the
    // imported geometry is regenerated once by the render-scene query.
    document.set_automatic_wall_join_enabled(false);
    const auto length_scale = length_scale_from_units(entities);
    std::map<int, ElementId> levels;
    std::map<int, Point2> placement_cache;
    bool used_approximation = false;
    const auto supported_type = [](std::string_view type) {
        return type == "IFCBUILDINGSTOREY" || type == "IFCLEVEL" ||
            type == "IFCWALL" || type == "IFCWALLSTANDARDCASE" ||
            type == "IFCDOOR" || type == "IFCWINDOW" || type == "IFCSLAB" ||
            type == "IFCROOF" || type == "IFCCOLUMN" || type == "IFCBEAM" ||
            type == "IFCSTAIR" || type == "IFCSTAIRFLIGHT";
    };
    const auto has_supported_entity = std::any_of(entities.begin(), entities.end(), [&](const auto& entity) {
        return supported_type(entity.type);
    });
    if (!has_supported_entity) {
        if (report != nullptr) {
            report->warnings.push_back("IFC STEP data did not contain supported semantic entities.");
        }
        return document;
    }

    for (const auto& entity : entities) {
        if (entity.type != "IFCBUILDINGSTOREY" && entity.type != "IFCLEVEL") continue;
        const auto elevation = last_step_number(entity).value_or(0.0) * length_scale;
        const auto level_id = document.create_level(product_name(entity), elevation, 3.0);
        levels[entity.id] = level_id;
        if (auto* created = document.find_ptr(level_id); created != nullptr) set_ifc_metadata(*created, entity);
    }
    if (levels.empty()) {
        const auto level_id = document.create_level("Level 1", 0.0, 3.0);
        levels[-1] = level_id;
    }
    const auto default_level = levels.begin()->second;
    const auto level_for = [&](const StepEntity& entity) {
        // IFC containment relations are intentionally optional for this
        // lightweight path. A stable first storey keeps imported geometry
        // visible while preserving the source ids in metadata.
        (void)entity;
        return default_level;
    };

    struct ImportedWall {
        ElementId id{};
        Line2 axis{};
    };
    std::vector<ImportedWall> imported_walls;
    for (const auto& entity : entities) {
        if (entity.type != "IFCWALL" && entity.type != "IFCWALLSTANDARDCASE") continue;
        const auto origin = product_location(entity, by_id, placement_cache, length_scale);
        const auto wall_id = document.create_wall(product_name(entity),
            Line2{.start = origin, .end = {.x = origin.x + 4.0, .y = origin.y}},
            0.2, 3.0, level_for(entity));
        if (auto* created = document.find_ptr(wall_id); created != nullptr) {
            set_ifc_metadata(*created, entity,
                "Third-party IFC geometry was imported through the semantic fallback; default wall dimensions were used.");
        }
        imported_walls.push_back(ImportedWall{
            .id = wall_id,
            .axis = Line2{.start = origin, .end = {.x = origin.x + 4.0, .y = origin.y}},
        });
        used_approximation = true;
    }
    std::size_t skipped_openings = 0;
    for (const auto& entity : entities) {
        if (entity.type != "IFCDOOR" && entity.type != "IFCWINDOW") continue;
        const auto origin = product_location(entity, by_id, placement_cache, length_scale);
        if (imported_walls.empty()) {
            ++skipped_openings;
            continue;
        }

        std::vector<std::pair<double, std::size_t>> candidates;
        candidates.reserve(imported_walls.size());
        for (std::size_t index = 0; index < imported_walls.size(); ++index) {
            const auto& axis = imported_walls[index].axis;
            const auto dx = axis.end.x - axis.start.x;
            const auto dy = axis.end.y - axis.start.y;
            const auto length_squared = dx * dx + dy * dy;
            const auto projection = length_squared <= 0.0
                ? 0.0
                : ((origin.x - axis.start.x) * dx + (origin.y - axis.start.y) * dy) / length_squared;
            const auto clamped = std::clamp(projection, 0.0, 1.0);
            const auto closest_x = axis.start.x + dx * clamped;
            const auto closest_y = axis.start.y + dy * clamped;
            const auto distance_x = origin.x - closest_x;
            const auto distance_y = origin.y - closest_y;
            candidates.emplace_back(distance_x * distance_x + distance_y * distance_y, index);
        }
        std::sort(candidates.begin(), candidates.end());

        const auto is_door = entity.type == "IFCDOOR";
        const auto opening_width = is_door ? 0.9 : 1.2;
        const auto opening_height = is_door ? 2.1 : 1.2;
        const auto sill_height = is_door ? 0.0 : 1.0;
        bool imported_opening = false;
        for (const auto& [distance, candidate_index] : candidates) {
            (void)distance;
            const auto& host = imported_walls[candidate_index];
            const auto dx = host.axis.end.x - host.axis.start.x;
            const auto dy = host.axis.end.y - host.axis.start.y;
            const auto host_length = std::sqrt(dx * dx + dy * dy);
            if (host_length <= 0.0) continue;
            const auto projected = ((origin.x - host.axis.start.x) * dx +
                (origin.y - host.axis.start.y) * dy) / host_length;
            const auto offset = std::clamp(
                projected,
                opening_width * 0.5,
                host_length - opening_width * 0.5);
            try {
                const auto id = is_door
                    ? document.create_door(product_name(entity), host.id, offset, opening_width, opening_height)
                    : document.create_window(product_name(entity), host.id, offset, opening_width, opening_height, sill_height);
                if (auto* created = document.find_ptr(id); created != nullptr) set_ifc_metadata(*created, entity,
                    "Opening host was inferred from the nearest imported wall; source profile was approximated.");
                imported_opening = true;
                break;
            } catch (const std::invalid_argument&) {
                // Another source opening may already occupy this fallback
                // slot. Try the next nearest wall instead of aborting the
                // complete third-party import.
            }
        }
        if (!imported_opening) ++skipped_openings;
    }
    for (const auto& entity : entities) {
        const auto origin = product_location(entity, by_id, placement_cache, length_scale);
        const auto level_id = level_for(entity);
        if (entity.type == "IFCSLAB") {
            const auto id = document.create_slab(level_id, {{origin.x, origin.y}, {origin.x + 4.0, origin.y},
                {origin.x + 4.0, origin.y + 4.0}, {origin.x, origin.y + 4.0}}, 0.2);
            if (auto* created = document.find_ptr(id); created != nullptr) set_ifc_metadata(*created, entity,
                "Slab profile was approximated because no supported swept profile was found.");
            used_approximation = true;
        } else if (entity.type == "IFCROOF") {
            const auto id = document.create_roof(level_id, {{origin.x, origin.y}, {origin.x + 4.0, origin.y},
                {origin.x + 4.0, origin.y + 4.0}, {origin.x, origin.y + 4.0}}, RoofType::Flat, 0.2);
            if (auto* created = document.find_ptr(id); created != nullptr) set_ifc_metadata(*created, entity,
                "Roof profile was approximated because no supported swept profile was found.");
            used_approximation = true;
        } else if (entity.type == "IFCCOLUMN") {
            const auto id = document.create_column(level_id, origin, 0.3, 0.3, 3.0, 0);
            if (auto* created = document.find_ptr(id); created != nullptr) set_ifc_metadata(*created, entity,
                "Column profile was approximated because no supported swept profile was found.");
            used_approximation = true;
        } else if (entity.type == "IFCBEAM") {
            const auto id = document.create_beam(level_id, origin, {.x = origin.x + 4.0, .y = origin.y}, 0.25, 0.35, 0);
            if (auto* created = document.find_ptr(id); created != nullptr) set_ifc_metadata(*created, entity,
                "Beam profile was approximated because no supported swept profile was found.");
            used_approximation = true;
        } else if (entity.type == "IFCSTAIR" || entity.type == "IFCSTAIRFLIGHT") {
            const auto id = document.create_stair(level_id, level_id, origin, {.x = 1.0, .y = 0.0},
                1.0, 3.0, 4.0, 12, 12, 0);
            if (auto* created = document.find_ptr(id); created != nullptr) set_ifc_metadata(*created, entity,
                "Stair profile was approximated because no supported swept profile was found.");
            used_approximation = true;
        }
    }
    if (report != nullptr) {
        report->imported_elements = document.elements().size();
        if (skipped_openings != 0) {
            report->warnings.push_back("Skipped " + std::to_string(skipped_openings) +
                " overlapping or unhosted third-party openings in the lightweight fallback.");
        }
        if (used_approximation) {
            report->warnings.push_back(
                "Third-party IFC imported with semantic fallback. Some profiles and containment relations were approximated; review marked elements before editing.");
        } else if (report->imported_elements == 1 && entities.empty()) {
            report->warnings.push_back("IFC file did not contain supported semantic entities.");
        }
    }
    if (document.elements().size() == 1 && entities.empty()) {
        if (report != nullptr) report->warnings.push_back("IFC STEP data could not be parsed.");
    }
    return document;
}

} // namespace tbe::core
