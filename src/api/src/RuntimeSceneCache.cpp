#include "RuntimeSceneCache.hpp"
#include "tbe/core/Project.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <limits>
#include <map>
#include <stdexcept>
#include <tuple>
#include <type_traits>
#include <unordered_map>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace tbe::api::runtime_cache {

namespace {

namespace fs = std::filesystem;

constexpr std::array<char, 8> kMagic{'T', 'B', 'E', 'B', 'I', 'M', 'C', '2'};
constexpr std::uint32_t kEndianMarker = 0x01020304u;
constexpr std::uint64_t kMaxStringBytes = 16ull * 1024ull * 1024ull;
constexpr std::uint64_t kMaxCollectionEntries = 32ull * 1024ull * 1024ull;
constexpr std::size_t kLeafChunkCount = 8;

std::uint64_t source_fingerprint(const fs::path& source) {
    std::ifstream input(source, std::ios::binary);
    if (!input) throw std::runtime_error("failed to read IFC source for cache fingerprint");
    constexpr std::uint64_t offset_basis = 14695981039346656037ull;
    constexpr std::uint64_t prime = 1099511628211ull;
    std::uint64_t hash = offset_basis;
    std::array<char, 64 * 1024> buffer{};
    while (input) {
        input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        const auto count = input.gcount();
        for (std::streamsize index = 0; index < count; ++index) {
            hash ^= static_cast<std::uint8_t>(buffer[static_cast<std::size_t>(index)]);
            hash *= prime;
        }
    }
    if (!input.eof()) throw std::runtime_error("failed while fingerprinting IFC source");
    return hash;
}

template <typename T>
void write_scalar(std::ostream& out, T value) {
    static_assert(std::is_trivially_copyable_v<T>);
    out.write(reinterpret_cast<const char*>(&value), sizeof(T));
    if (!out) throw std::runtime_error("failed while writing BIM cache");
}

template <typename T>
T read_scalar(std::istream& in) {
    static_assert(std::is_trivially_copyable_v<T>);
    T value{};
    in.read(reinterpret_cast<char*>(&value), sizeof(T));
    if (!in) throw std::runtime_error("BIM cache is truncated or corrupt");
    return value;
}

std::size_t checked_size(std::uint64_t value, const char* label) {
    if (value > kMaxCollectionEntries || value > std::numeric_limits<std::size_t>::max()) {
        throw std::runtime_error(std::string("BIM cache has an invalid ") + label + " count");
    }
    return static_cast<std::size_t>(value);
}

void write_string(std::ostream& out, const std::string& value) {
    write_scalar<std::uint64_t>(out, value.size());
    out.write(value.data(), static_cast<std::streamsize>(value.size()));
    if (!out) throw std::runtime_error("failed while writing BIM cache string");
}

std::string read_string(std::istream& in) {
    const auto size = read_scalar<std::uint64_t>(in);
    if (size > kMaxStringBytes || size > std::numeric_limits<std::size_t>::max()) {
        throw std::runtime_error("BIM cache string is too large");
    }
    std::string value(static_cast<std::size_t>(size), '\0');
    in.read(value.data(), static_cast<std::streamsize>(value.size()));
    if (!in) throw std::runtime_error("BIM cache is truncated while reading a string");
    return value;
}

template <typename T>
void write_scalar_vector(std::ostream& out, const std::vector<T>& values) {
    static_assert(std::is_trivially_copyable_v<T>);
    write_scalar<std::uint64_t>(out, values.size());
    if (values.empty()) return;
    out.write(
        reinterpret_cast<const char*>(values.data()),
        static_cast<std::streamsize>(values.size() * sizeof(T))
    );
    if (!out) throw std::runtime_error("failed while writing BIM cache buffer");
}

template <typename T>
std::vector<T> read_scalar_vector(std::istream& in, const char* label) {
    static_assert(std::is_trivially_copyable_v<T>);
    const auto count = checked_size(read_scalar<std::uint64_t>(in), label);
    if (count > std::numeric_limits<std::size_t>::max() / sizeof(T)) {
        throw std::runtime_error(std::string("BIM cache ") + label + " buffer is too large");
    }
    std::vector<T> values(count);
    if (values.empty()) return values;
    in.read(
        reinterpret_cast<char*>(values.data()),
        static_cast<std::streamsize>(values.size() * sizeof(T))
    );
    if (!in) throw std::runtime_error(std::string("BIM cache is truncated while reading ") + label);
    return values;
}

void write_vec3(std::ostream& out, const Vec3& value) {
    write_scalar<double>(out, value.x);
    write_scalar<double>(out, value.y);
    write_scalar<double>(out, value.z);
}

Vec3 read_vec3(std::istream& in) {
    return Vec3{
        .x = read_scalar<double>(in),
        .y = read_scalar<double>(in),
        .z = read_scalar<double>(in),
    };
}

void write_bounds(std::ostream& out, const AABB3D& value) {
    write_vec3(out, value.min);
    write_vec3(out, value.max);
}

AABB3D read_bounds(std::istream& in) {
    return AABB3D{.min = read_vec3(in), .max = read_vec3(in)};
}

bool is_finite_bounds(const AABB3D& bounds) {
    return std::isfinite(bounds.min.x) && std::isfinite(bounds.min.y) && std::isfinite(bounds.min.z) &&
        std::isfinite(bounds.max.x) && std::isfinite(bounds.max.y) && std::isfinite(bounds.max.z) &&
        bounds.min.x <= bounds.max.x && bounds.min.y <= bounds.max.y && bounds.min.z <= bounds.max.z;
}

AABB3D union_bounds(const AABB3D& first, const AABB3D& second) {
    return AABB3D{
        .min = {
            .x = std::min(first.min.x, second.min.x),
            .y = std::min(first.min.y, second.min.y),
            .z = std::min(first.min.z, second.min.z),
        },
        .max = {
            .x = std::max(first.max.x, second.max.x),
            .y = std::max(first.max.y, second.max.y),
            .z = std::max(first.max.z, second.max.z),
        },
    };
}

constexpr std::size_t kMinCompoundProxyTriangles = 4;
constexpr std::size_t kMaxCompoundProxyParts = 4096;
constexpr double kCompoundProxyWeldScale = 100000.0;
constexpr std::uint64_t kVirtualIfcPartTag = std::uint64_t{1} << 62;
constexpr std::uint64_t kVirtualIfcPartSourceMask = (std::uint64_t{1} << 46) - 1;
constexpr std::uint64_t kVirtualIfcPartOrdinalMask = (std::uint64_t{1} << 16) - 1;

struct WeldedPositionKey {
    std::int64_t x{};
    std::int64_t y{};
    std::int64_t z{};

    bool operator==(const WeldedPositionKey&) const = default;
};

struct WeldedPositionKeyHash {
    std::size_t operator()(const WeldedPositionKey& key) const {
        const auto mix = [](std::uint64_t value) {
            value ^= value >> 30;
            value *= 0xbf58476d1ce4e5b9ULL;
            value ^= value >> 27;
            value *= 0x94d049bb133111ebULL;
            return value ^ (value >> 31);
        };
        return static_cast<std::size_t>(mix(static_cast<std::uint64_t>(key.x)) ^
            mix(static_cast<std::uint64_t>(key.y)) ^
            mix(static_cast<std::uint64_t>(key.z)));
    }
};

class TriangleDisjointSet {
public:
    explicit TriangleDisjointSet(std::size_t size)
        : parent_(size), rank_(size, 0) {
        for (std::size_t index = 0; index < size; ++index) parent_[index] = index;
    }

    std::size_t find(std::size_t value) {
        while (parent_[value] != value) {
            parent_[value] = parent_[parent_[value]];
            value = parent_[value];
        }
        return value;
    }

    void merge(std::size_t first, std::size_t second) {
        first = find(first);
        second = find(second);
        if (first == second) return;
        if (rank_[first] < rank_[second]) std::swap(first, second);
        parent_[second] = first;
        if (rank_[first] == rank_[second]) ++rank_[first];
    }

private:
    std::vector<std::size_t> parent_;
    std::vector<std::uint8_t> rank_;
};

struct CompoundProxyPart {
    std::vector<std::uint32_t> triangle_indices{};
    AABB3D bounds{
        .min = {
            .x = std::numeric_limits<double>::max(),
            .y = std::numeric_limits<double>::max(),
            .z = std::numeric_limits<double>::max(),
        },
        .max = {
            .x = std::numeric_limits<double>::lowest(),
            .y = std::numeric_limits<double>::lowest(),
            .z = std::numeric_limits<double>::lowest(),
        },
    };
};

bool is_compound_ifc_proxy(const RenderSceneObjectDTO& object) {
    if (object.kind != ApiElementKind::Proxy) return false;
    const auto entity = object.metadata.find("ifc_entity");
    return entity != object.metadata.end() && entity->second == "IFCBUILDINGELEMENTPROXY";
}

std::optional<WeldedPositionKey> welded_position_key(const Vec3& point) {
    if (!std::isfinite(point.x) || !std::isfinite(point.y) || !std::isfinite(point.z)) {
        return std::nullopt;
    }
    const auto maximum = static_cast<double>(std::numeric_limits<std::int64_t>::max()) / kCompoundProxyWeldScale;
    if (std::abs(point.x) > maximum || std::abs(point.y) > maximum || std::abs(point.z) > maximum) {
        return std::nullopt;
    }
    return WeldedPositionKey{
        .x = static_cast<std::int64_t>(std::llround(point.x * kCompoundProxyWeldScale)),
        .y = static_cast<std::int64_t>(std::llround(point.y * kCompoundProxyWeldScale)),
        .z = static_cast<std::int64_t>(std::llround(point.z * kCompoundProxyWeldScale)),
    };
}

void extend_bounds(AABB3D& bounds, const Vec3& point) {
    bounds.min.x = std::min(bounds.min.x, point.x);
    bounds.min.y = std::min(bounds.min.y, point.y);
    bounds.min.z = std::min(bounds.min.z, point.z);
    bounds.max.x = std::max(bounds.max.x, point.x);
    bounds.max.y = std::max(bounds.max.y, point.y);
    bounds.max.z = std::max(bounds.max.z, point.z);
}

std::vector<CompoundProxyPart> split_compound_ifc_proxy(const RenderSceneObjectDTO& object) {
    const auto& mesh = object.mesh;
    const auto triangle_count = mesh.indices.size() / 3;
    if (!is_compound_ifc_proxy(object) || triangle_count < kMinCompoundProxyTriangles ||
        mesh.indices.size() % 3 != 0) {
        return {};
    }

    TriangleDisjointSet components(triangle_count);
    std::unordered_map<WeldedPositionKey, std::size_t, WeldedPositionKeyHash> first_triangle_by_position;
    first_triangle_by_position.reserve(mesh.indices.size());
    for (std::size_t triangle_index = 0; triangle_index < triangle_count; ++triangle_index) {
        const auto first_index = triangle_index * 3;
        for (std::size_t corner = 0; corner < 3; ++corner) {
            const auto vertex_index = mesh.indices[first_index + corner];
            if (vertex_index >= mesh.positions.size()) return {};
            const auto key = welded_position_key(mesh.positions[vertex_index]);
            if (!key.has_value()) return {};
            const auto [found, inserted] = first_triangle_by_position.emplace(*key, triangle_index);
            if (!inserted) components.merge(triangle_index, found->second);
        }
    }

    std::unordered_map<std::size_t, std::size_t> part_by_root;
    part_by_root.reserve(triangle_count);
    std::vector<CompoundProxyPart> parts;
    for (std::size_t triangle_index = 0; triangle_index < triangle_count; ++triangle_index) {
        const auto root = components.find(triangle_index);
        const auto [found, inserted] = part_by_root.emplace(root, parts.size());
        if (inserted) parts.emplace_back();
        auto& part = parts[found->second];
        part.triangle_indices.push_back(static_cast<std::uint32_t>(triangle_index));
        const auto first_index = triangle_index * 3;
        for (std::size_t corner = 0; corner < 3; ++corner) {
            extend_bounds(part.bounds, mesh.positions[mesh.indices[first_index + corner]]);
        }
    }

    if (parts.size() <= 1 || parts.size() > kMaxCompoundProxyParts) return {};
    return parts;
}

ElementIdDTO virtual_ifc_part_id(ElementIdDTO source_element_id, std::size_t ordinal) {
    // Some CAD/Revit exports store an entire building as one
    // IFCBUILDINGELEMENTPROXY.  The cache owns these transient part IDs only;
    // the source IFC and editable document remain untouched.
    const auto source = source_element_id.value & kVirtualIfcPartSourceMask;
    const auto part = (static_cast<std::uint64_t>(ordinal) + 1) & kVirtualIfcPartOrdinalMask;
    return {.value = kVirtualIfcPartTag | (source << 16) | part};
}

Vec3 bounds_center(const AABB3D& bounds) {
    return Vec3{
        .x = (bounds.min.x + bounds.max.x) * 0.5,
        .y = (bounds.min.y + bounds.max.y) * 0.5,
        .z = (bounds.min.z + bounds.max.z) * 0.5,
    };
}

int longest_axis(const AABB3D& bounds) {
    const auto x = bounds.max.x - bounds.min.x;
    const auto y = bounds.max.y - bounds.min.y;
    const auto z = bounds.max.z - bounds.min.z;
    if (x >= y && x >= z) return 0;
    return y >= z ? 1 : 2;
}

double axis_value(const Vec3& point, int axis) {
    return axis == 0 ? point.x : (axis == 1 ? point.y : point.z);
}

AABB3D bounds_for_chunks(const BimCacheSceneDTO& scene, const std::vector<std::uint32_t>& indices, std::size_t begin, std::size_t end) {
    if (begin >= end || end > indices.size()) {
        throw std::runtime_error("cannot build BIM cache BVH for an empty range");
    }
    AABB3D bounds = scene.chunks[indices[begin]].bounds;
    for (auto index = begin + 1; index < end; ++index) {
        bounds = union_bounds(bounds, scene.chunks[indices[index]].bounds);
    }
    return bounds;
}

std::int32_t build_bvh(
    BimCacheSceneDTO& scene,
    std::vector<std::uint32_t>& pending_indices,
    std::size_t begin,
    std::size_t end
) {
    const auto bounds = bounds_for_chunks(scene, pending_indices, begin, end);
    const auto node_index = static_cast<std::int32_t>(scene.bvh_nodes.size());
    scene.bvh_nodes.push_back(BimCacheBvhNodeDTO{.bounds = bounds});
    const auto count = end - begin;
    if (count <= kLeafChunkCount) {
        auto& node = scene.bvh_nodes[static_cast<std::size_t>(node_index)];
        node.first_chunk = static_cast<std::uint32_t>(scene.bvh_chunk_indices.size());
        node.chunk_count = static_cast<std::uint32_t>(count);
        for (auto index = begin; index < end; ++index) {
            scene.bvh_chunk_indices.push_back(pending_indices[index]);
        }
        return node_index;
    }

    const auto axis = longest_axis(bounds);
    const auto middle = begin + count / 2;
    std::nth_element(
        pending_indices.begin() + static_cast<std::ptrdiff_t>(begin),
        pending_indices.begin() + static_cast<std::ptrdiff_t>(middle),
        pending_indices.begin() + static_cast<std::ptrdiff_t>(end),
        [&](std::uint32_t first, std::uint32_t second) {
            return axis_value(bounds_center(scene.chunks[first].bounds), axis) <
                axis_value(bounds_center(scene.chunks[second].bounds), axis);
        }
    );
    const auto left = build_bvh(scene, pending_indices, begin, middle);
    const auto right = build_bvh(scene, pending_indices, middle, end);
    auto& node = scene.bvh_nodes[static_cast<std::size_t>(node_index)];
    node.left_child = left;
    node.right_child = right;
    return node_index;
}

Vec3 subtract(const Vec3& first, const Vec3& second) {
    return Vec3{
        .x = first.x - second.x,
        .y = first.y - second.y,
        .z = first.z - second.z,
    };
}

Vec3 cross(const Vec3& first, const Vec3& second) {
    return Vec3{
        .x = first.y * second.z - first.z * second.y,
        .y = first.z * second.x - first.x * second.z,
        .z = first.x * second.y - first.y * second.x,
    };
}

double dot(const Vec3& first, const Vec3& second) {
    return first.x * second.x + first.y * second.y + first.z * second.z;
}

bool ray_bounds_distance(
    const Vec3& origin,
    const Vec3& direction,
    const AABB3D& bounds,
    double maximum_distance,
    double& out_distance
) {
    constexpr double kParallelEpsilon = 1.0e-12;
    double near_distance = 0.0;
    double far_distance = maximum_distance;
    const std::array<double, 3> origins{origin.x, origin.y, origin.z};
    const std::array<double, 3> directions{direction.x, direction.y, direction.z};
    const std::array<double, 3> minimums{bounds.min.x, bounds.min.y, bounds.min.z};
    const std::array<double, 3> maximums{bounds.max.x, bounds.max.y, bounds.max.z};
    for (std::size_t axis = 0; axis < origins.size(); ++axis) {
        if (std::abs(directions[axis]) < kParallelEpsilon) {
            if (origins[axis] < minimums[axis] || origins[axis] > maximums[axis]) return false;
            continue;
        }
        auto first = (minimums[axis] - origins[axis]) / directions[axis];
        auto second = (maximums[axis] - origins[axis]) / directions[axis];
        if (first > second) std::swap(first, second);
        near_distance = std::max(near_distance, first);
        far_distance = std::min(far_distance, second);
        if (near_distance > far_distance) return false;
    }
    out_distance = near_distance;
    return true;
}

std::optional<double> ray_triangle_distance(
    const Vec3& origin,
    const Vec3& direction,
    const Vec3& first,
    const Vec3& second,
    const Vec3& third
) {
    constexpr double kEpsilon = 1.0e-9;
    const auto first_edge = subtract(second, first);
    const auto second_edge = subtract(third, first);
    const auto cross_direction = cross(direction, second_edge);
    const auto determinant = dot(first_edge, cross_direction);
    if (std::abs(determinant) < kEpsilon) return std::nullopt;
    const auto inverse_determinant = 1.0 / determinant;
    const auto origin_offset = subtract(origin, first);
    const auto u = dot(origin_offset, cross_direction) * inverse_determinant;
    if (u < -kEpsilon || u > 1.0 + kEpsilon) return std::nullopt;
    const auto cross_origin = cross(origin_offset, first_edge);
    const auto v = dot(direction, cross_origin) * inverse_determinant;
    if (v < -kEpsilon || u + v > 1.0 + kEpsilon) return std::nullopt;
    const auto distance = dot(second_edge, cross_origin) * inverse_determinant;
    if (distance <= kEpsilon) return std::nullopt;
    return distance;
}

bool kind_visible(ApiElementKind kind, std::uint64_t visible_kind_mask) {
    const auto kind_index = static_cast<std::uint32_t>(kind);
    return kind_index < 64 && (visible_kind_mask & (std::uint64_t{1} << kind_index)) != 0;
}

bool opening_kind(ApiElementKind kind) {
    return kind == ApiElementKind::Door || kind == ApiElementKind::Window;
}

std::optional<Vec3> point_at(
    const BimCacheChunkDTO& chunk,
    std::uint32_t index
) {
    const auto vertex_index = static_cast<std::size_t>(index);
    if (vertex_index >= chunk.positions.size() / 3) return std::nullopt;
    const auto offset = vertex_index * 3;
    return Vec3{
        .x = static_cast<double>(chunk.positions[offset]),
        .y = static_cast<double>(chunk.positions[offset + 1]),
        .z = static_cast<double>(chunk.positions[offset + 2]),
    };
}

void pick_chunk(
    const BimCacheChunkDTO& chunk,
    const Vec3& origin,
    const Vec3& direction,
    std::uint64_t visible_kind_mask,
    double& nearest_surface_distance,
    std::optional<ElementIdDTO>& nearest_surface,
    double& nearest_opening_distance,
    std::optional<ElementIdDTO>& nearest_opening
) {
    for (const auto& primitive : chunk.primitives) {
        if (!kind_visible(primitive.kind, visible_kind_mask) || primitive.index_count < 3) continue;
        double primitive_entry{};
        const auto maximum_distance = opening_kind(primitive.kind)
            ? nearest_opening_distance
            : nearest_surface_distance;
        if (!ray_bounds_distance(origin, direction, primitive.bounds, maximum_distance, primitive_entry)) continue;
        const auto first_index = static_cast<std::size_t>(primitive.first_index);
        if (first_index >= chunk.indices.size()) continue;
        const auto available_indices = chunk.indices.size() - first_index;
        const auto index_count = std::min<std::size_t>(primitive.index_count, available_indices);
        for (std::size_t offset = 0; offset + 2 < index_count; offset += 3) {
            const auto first = point_at(chunk, chunk.indices[first_index + offset]);
            const auto second = point_at(chunk, chunk.indices[first_index + offset + 1]);
            const auto third = point_at(chunk, chunk.indices[first_index + offset + 2]);
            if (!first.has_value() || !second.has_value() || !third.has_value()) continue;
            const auto distance = ray_triangle_distance(origin, direction, *first, *second, *third);
            if (!distance.has_value()) continue;
            if (opening_kind(primitive.kind)) {
                if (*distance < nearest_opening_distance) {
                    nearest_opening_distance = *distance;
                    nearest_opening = primitive.element_id;
                }
            } else if (*distance < nearest_surface_distance) {
                nearest_surface_distance = *distance;
                nearest_surface = primitive.element_id;
            }
        }
    }
}

struct ChunkKey {
    std::uint64_t level_id{};
    ApiElementKind kind{ApiElementKind::Unknown};
    std::string material_category{};
    std::int32_t tile_x{};
    std::int32_t tile_y{};

    [[nodiscard]] auto as_tuple() const {
        return std::tie(level_id, kind, material_category, tile_x, tile_y);
    }

    bool operator<(const ChunkKey& other) const {
        return as_tuple() < other.as_tuple();
    }
};

void write_level(std::ostream& out, const RenderSceneLevelDTO& level) {
    write_scalar<std::uint64_t>(out, level.level_id.value);
    write_string(out, level.name);
    write_scalar<double>(out, level.elevation_meters);
    write_scalar<double>(out, level.default_wall_height_meters);
}

RenderSceneLevelDTO read_level(std::istream& in) {
    return RenderSceneLevelDTO{
        .level_id = {.value = read_scalar<std::uint64_t>(in)},
        .name = read_string(in),
        .elevation_meters = read_scalar<double>(in),
        .default_wall_height_meters = read_scalar<double>(in),
    };
}

void write_primitive(std::ostream& out, const BimCachePrimitiveDTO& primitive) {
    write_scalar<std::uint64_t>(out, primitive.element_id.value);
    write_scalar<std::int32_t>(out, static_cast<std::int32_t>(primitive.kind));
    write_scalar<std::uint64_t>(out, primitive.revision);
    write_scalar<std::uint32_t>(out, primitive.first_index);
    write_scalar<std::uint32_t>(out, primitive.index_count);
    write_bounds(out, primitive.bounds);
}

BimCachePrimitiveDTO read_primitive(std::istream& in) {
    return BimCachePrimitiveDTO{
        .element_id = {.value = read_scalar<std::uint64_t>(in)},
        .kind = static_cast<ApiElementKind>(read_scalar<std::int32_t>(in)),
        .revision = read_scalar<std::uint64_t>(in),
        .first_index = read_scalar<std::uint32_t>(in),
        .index_count = read_scalar<std::uint32_t>(in),
        .bounds = read_bounds(in),
    };
}

void write_chunk(std::ostream& out, const BimCacheChunkDTO& chunk) {
    write_scalar<std::uint64_t>(out, chunk.level_id.value);
    write_string(out, chunk.material_category);
    write_scalar<std::int32_t>(out, chunk.tile_x);
    write_scalar<std::int32_t>(out, chunk.tile_y);
    write_bounds(out, chunk.bounds);
    write_scalar_vector(out, chunk.positions);
    write_scalar_vector(out, chunk.indices);
    write_scalar<std::uint64_t>(out, chunk.primitives.size());
    for (const auto& primitive : chunk.primitives) write_primitive(out, primitive);
}

BimCacheChunkDTO read_chunk(std::istream& in) {
    BimCacheChunkDTO chunk;
    chunk.level_id = {.value = read_scalar<std::uint64_t>(in)};
    chunk.material_category = read_string(in);
    chunk.tile_x = read_scalar<std::int32_t>(in);
    chunk.tile_y = read_scalar<std::int32_t>(in);
    chunk.bounds = read_bounds(in);
    chunk.positions = read_scalar_vector<float>(in, "position");
    chunk.indices = read_scalar_vector<std::uint32_t>(in, "index");
    const auto primitive_count = checked_size(read_scalar<std::uint64_t>(in), "primitive");
    chunk.primitives.reserve(primitive_count);
    for (std::size_t index = 0; index < primitive_count; ++index) {
        chunk.primitives.push_back(read_primitive(in));
    }
    return chunk;
}

void write_bvh_node(std::ostream& out, const BimCacheBvhNodeDTO& node) {
    write_bounds(out, node.bounds);
    write_scalar<std::int32_t>(out, node.left_child);
    write_scalar<std::int32_t>(out, node.right_child);
    write_scalar<std::uint32_t>(out, node.first_chunk);
    write_scalar<std::uint32_t>(out, node.chunk_count);
}

BimCacheBvhNodeDTO read_bvh_node(std::istream& in) {
    return BimCacheBvhNodeDTO{
        .bounds = read_bounds(in),
        .left_child = read_scalar<std::int32_t>(in),
        .right_child = read_scalar<std::int32_t>(in),
        .first_chunk = read_scalar<std::uint32_t>(in),
        .chunk_count = read_scalar<std::uint32_t>(in),
    };
}

std::string cache_material_category(const RenderSceneObjectDTO& object) {
    // The interactive scene keeps wall type data in metadata because it is
    // authoring semantics, not a physical material. Native cache chunks need
    // the same small semantic hint so the renderer can choose the correct
    // Solid/Shaded surface without sending the full scene back through JSON.
    if (object.kind == ApiElementKind::Wall) {
        const auto category = object.metadata.find("wall_type_category");
        const auto name = object.metadata.find("wall_type_name");
        const std::string category_value = category == object.metadata.end() ? "Generic" : category->second;
        const std::string name_value = name == object.metadata.end() ? "Generic Wall" : name->second;
        return "wall:" + category_value + "|" + name_value;
    }
    return object.material_category.empty() ? "generic" : object.material_category;
}

} // namespace

BimCacheSourceDTO source_signature(const std::string& source_ifc_path) {
    const fs::path source(source_ifc_path);
    if (source.empty() || !fs::exists(source) || !fs::is_regular_file(source)) {
        throw std::runtime_error("IFC source does not exist: " + source_ifc_path);
    }
    const auto modified = fs::last_write_time(source).time_since_epoch().count();
    return BimCacheSourceDTO{
        .source_path = fs::absolute(source).lexically_normal().string(),
        .source_size_bytes = fs::file_size(source),
        .source_modified_ticks = static_cast<std::int64_t>(modified),
        .source_fingerprint = source_fingerprint(source),
    };
}

BimCacheSceneDTO compile(
    const RenderSceneDTO& scene,
    BimCacheSourceDTO source,
    const BimCacheChunkingPolicy& policy
) {
    if (!std::isfinite(policy.seed_tile_size_meters) || policy.seed_tile_size_meters <= 0.0) {
        throw std::runtime_error("BIM cache chunk seed size must be finite and positive");
    }
    BimCacheSceneDTO compiled;
    compiled.format_version = kBimCacheFormatVersion;
    compiled.scene_compiler_version = kBimCacheSceneCompilerVersion;
    compiled.object_mapping_version = kBimCacheObjectMappingVersion;
    compiled.format_flags = kBimCacheFormatFlags;
    compiled.chunk_seed_tile_size_meters = policy.seed_tile_size_meters;
    compiled.engine_version = std::string(tbe::core::TBE_ENGINE_VERSION);
    compiled.source = std::move(source);
    compiled.levels = scene.levels;
    compiled.source_object_count = scene.objects.size();
    compiled.source_triangle_count = scene.index_count / 3;

    std::map<ChunkKey, std::size_t> chunk_by_key;
    for (const auto& object : scene.objects) {
        if (object.mesh.positions.empty() || object.mesh.indices.size() < 3 || !is_finite_bounds(object.bounds)) {
            continue;
        }
        const auto center = bounds_center(object.bounds);
        const ChunkKey key{
            .level_id = object.level_id.value,
            .kind = object.kind,
            .material_category = cache_material_category(object),
            .tile_x = static_cast<std::int32_t>(std::floor(center.x / policy.seed_tile_size_meters)),
            .tile_y = static_cast<std::int32_t>(std::floor(center.y / policy.seed_tile_size_meters)),
        };
        auto [found, inserted] = chunk_by_key.emplace(key, compiled.chunks.size());
        if (inserted) {
            compiled.chunks.push_back(BimCacheChunkDTO{
                .level_id = object.level_id,
                .material_category = key.material_category,
                .tile_x = key.tile_x,
                .tile_y = key.tile_y,
                .bounds = object.bounds,
            });
        }
        auto& chunk = compiled.chunks[found->second];
        const auto vertex_offset = chunk.positions.size() / 3;
        const auto first_index = chunk.indices.size();
        if (vertex_offset > std::numeric_limits<std::uint32_t>::max() ||
            first_index > std::numeric_limits<std::uint32_t>::max() ||
            object.mesh.indices.size() > std::numeric_limits<std::uint32_t>::max()) {
            throw std::runtime_error("BIM cache chunk exceeds 32-bit GPU buffer limits");
        }
        for (const auto& point : object.mesh.positions) {
            if (!std::isfinite(point.x) || !std::isfinite(point.y) || !std::isfinite(point.z)) {
                throw std::runtime_error("BIM cache compiler received non-finite geometry");
            }
            chunk.positions.push_back(static_cast<float>(point.x));
            chunk.positions.push_back(static_cast<float>(point.y));
            chunk.positions.push_back(static_cast<float>(point.z));
        }
        const auto append_index = [&](std::uint32_t index) {
            if (index >= object.mesh.positions.size() ||
                vertex_offset + index > std::numeric_limits<std::uint32_t>::max()) {
                throw std::runtime_error("BIM cache compiler received an invalid mesh index");
            }
            chunk.indices.push_back(static_cast<std::uint32_t>(vertex_offset + index));
        };
        const auto parts = split_compound_ifc_proxy(object);
        if (parts.empty()) {
            for (const auto index : object.mesh.indices) append_index(index);
            chunk.primitives.push_back(BimCachePrimitiveDTO{
                .element_id = object.element_id,
                .kind = object.kind,
                .revision = object.revision,
                .first_index = static_cast<std::uint32_t>(first_index),
                .index_count = static_cast<std::uint32_t>(object.mesh.indices.size()),
                .bounds = object.bounds,
            });
        } else {
            for (std::size_t part_index = 0; part_index < parts.size(); ++part_index) {
                const auto& part = parts[part_index];
                const auto part_first_index = chunk.indices.size();
                for (const auto triangle_index : part.triangle_indices) {
                    const auto source_index = static_cast<std::size_t>(triangle_index) * 3;
                    append_index(object.mesh.indices[source_index]);
                    append_index(object.mesh.indices[source_index + 1]);
                    append_index(object.mesh.indices[source_index + 2]);
                }
                chunk.primitives.push_back(BimCachePrimitiveDTO{
                    .element_id = virtual_ifc_part_id(object.element_id, part_index),
                    .kind = object.kind,
                    .revision = object.revision,
                    .first_index = static_cast<std::uint32_t>(part_first_index),
                    .index_count = static_cast<std::uint32_t>(part.triangle_indices.size() * 3),
                    .bounds = part.bounds,
                });
            }
        }
        chunk.bounds = union_bounds(chunk.bounds, object.bounds);
    }

    if (!compiled.chunks.empty()) {
        std::vector<std::uint32_t> chunk_indices(compiled.chunks.size());
        for (std::size_t index = 0; index < chunk_indices.size(); ++index) {
            chunk_indices[index] = static_cast<std::uint32_t>(index);
        }
        (void)build_bvh(compiled, chunk_indices, 0, chunk_indices.size());
    }
    return compiled;
}

std::optional<ElementIdDTO> pick(
    const BimCacheSceneDTO& scene,
    const Vec3& ray_origin,
    const Vec3& ray_direction,
    std::uint64_t visible_kind_mask
) {
    if (!std::isfinite(ray_origin.x) || !std::isfinite(ray_origin.y) || !std::isfinite(ray_origin.z) ||
        !std::isfinite(ray_direction.x) || !std::isfinite(ray_direction.y) || !std::isfinite(ray_direction.z) ||
        dot(ray_direction, ray_direction) < 1.0e-18) {
        return std::nullopt;
    }

    auto nearest_surface_distance = std::numeric_limits<double>::infinity();
    auto nearest_opening_distance = std::numeric_limits<double>::infinity();
    std::optional<ElementIdDTO> nearest_surface;
    std::optional<ElementIdDTO> nearest_opening;
    const auto visit_chunk = [&](std::uint32_t chunk_index) {
        if (chunk_index >= scene.chunks.size()) return;
        const auto& chunk = scene.chunks[chunk_index];
        double entry_distance{};
        if (!ray_bounds_distance(
                ray_origin,
                ray_direction,
                chunk.bounds,
                std::max(nearest_surface_distance, nearest_opening_distance),
                entry_distance
            )) {
            return;
        }
        pick_chunk(
            chunk,
            ray_origin,
            ray_direction,
            visible_kind_mask,
            nearest_surface_distance,
            nearest_surface,
            nearest_opening_distance,
            nearest_opening
        );
    };

    if (scene.bvh_nodes.empty()) {
        for (std::size_t index = 0; index < scene.chunks.size(); ++index) {
            visit_chunk(static_cast<std::uint32_t>(index));
        }
    } else {
        std::vector<std::int32_t> pending_nodes{0};
        while (!pending_nodes.empty()) {
            const auto node_index = pending_nodes.back();
            pending_nodes.pop_back();
            if (node_index < 0 || static_cast<std::size_t>(node_index) >= scene.bvh_nodes.size()) continue;
            const auto& node = scene.bvh_nodes[static_cast<std::size_t>(node_index)];
            double entry_distance{};
            if (!ray_bounds_distance(
                    ray_origin,
                    ray_direction,
                    node.bounds,
                    std::max(nearest_surface_distance, nearest_opening_distance),
                    entry_distance
                )) {
                continue;
            }
            if (node.chunk_count > 0) {
                const auto first_chunk = static_cast<std::size_t>(node.first_chunk);
                const auto available_chunks = first_chunk <= scene.bvh_chunk_indices.size()
                    ? scene.bvh_chunk_indices.size() - first_chunk
                    : 0;
                const auto chunk_count = std::min<std::size_t>(node.chunk_count, available_chunks);
                for (std::size_t offset = 0; offset < chunk_count; ++offset) {
                    visit_chunk(scene.bvh_chunk_indices[first_chunk + offset]);
                }
            } else {
                if (node.left_child >= 0) pending_nodes.push_back(node.left_child);
                if (node.right_child >= 0) pending_nodes.push_back(node.right_child);
            }
        }
    }

    // Door/window panels are intentionally slightly inset in their hosts.
    // Matching the normal renderer's preference keeps a tap on an opening
    // from always resolving to its wall face.
    if (nearest_opening.has_value() &&
        (!nearest_surface.has_value() || nearest_opening_distance <= nearest_surface_distance + 0.35)) {
        return nearest_opening;
    }
    return nearest_surface;
}

void write_file(const std::string& cache_path, const BimCacheSceneDTO& scene) {
    if (scene.format_version != kBimCacheFormatVersion) {
        throw std::runtime_error("unsupported BIM cache format for writing");
    }
    if (scene.scene_compiler_version != kBimCacheSceneCompilerVersion ||
        scene.object_mapping_version != kBimCacheObjectMappingVersion ||
        scene.format_flags != kBimCacheFormatFlags ||
        scene.engine_version != tbe::core::TBE_ENGINE_VERSION ||
        !std::isfinite(scene.chunk_seed_tile_size_meters) || scene.chunk_seed_tile_size_meters <= 0.0) {
        throw std::runtime_error("BIM cache compiler metadata is invalid for writing");
    }
    const fs::path target(cache_path);
    if (target.empty()) throw std::runtime_error("BIM cache path is empty");
    if (!target.parent_path().empty()) fs::create_directories(target.parent_path());
    const auto partial = target.string() + ".partial";
    {
        std::ofstream out(partial, std::ios::binary | std::ios::trunc);
        if (!out) throw std::runtime_error("failed to open BIM cache for writing");
        out.write(kMagic.data(), static_cast<std::streamsize>(kMagic.size()));
        write_scalar<std::uint32_t>(out, scene.format_version);
        write_scalar<std::uint32_t>(out, kEndianMarker);
        write_scalar<std::uint32_t>(out, scene.scene_compiler_version);
        write_scalar<std::uint32_t>(out, scene.object_mapping_version);
        write_scalar<std::uint32_t>(out, scene.format_flags);
        write_scalar<double>(out, scene.chunk_seed_tile_size_meters);
        write_string(out, scene.engine_version);
        write_string(out, scene.source.source_path);
        write_scalar<std::uint64_t>(out, scene.source.source_size_bytes);
        write_scalar<std::int64_t>(out, scene.source.source_modified_ticks);
        write_scalar<std::uint64_t>(out, scene.source.source_fingerprint);
        write_scalar<std::uint64_t>(out, scene.source_object_count);
        write_scalar<std::uint64_t>(out, scene.source_triangle_count);
        write_scalar<std::uint64_t>(out, scene.levels.size());
        for (const auto& level : scene.levels) write_level(out, level);
        write_scalar<std::uint64_t>(out, scene.chunks.size());
        for (const auto& chunk : scene.chunks) write_chunk(out, chunk);
        write_scalar<std::uint64_t>(out, scene.bvh_nodes.size());
        for (const auto& node : scene.bvh_nodes) write_bvh_node(out, node);
        write_scalar_vector(out, scene.bvh_chunk_indices);
        out.flush();
        if (!out) throw std::runtime_error("failed to finalize BIM cache");
    }
#ifdef _WIN32
    // Replace atomically on the cache volume. Deleting the existing cache
    // first leaves a crash window where neither the old nor new artifact is
    // usable, which is unacceptable for a large IFC reopening on tablet.
    const fs::path partial_path(partial);
    if (MoveFileExW(
            partial_path.c_str(),
            target.c_str(),
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
        ) == 0) {
        const auto error_code = static_cast<unsigned long>(GetLastError());
        fs::remove(partial);
        throw std::runtime_error("failed to publish BIM cache (Win32 error " + std::to_string(error_code) + ")");
    }
#else
    std::error_code error;
    fs::rename(partial, target, error);
    if (error) {
        fs::remove(partial);
        throw std::runtime_error("failed to publish BIM cache: " + error.message());
    }
#endif
}

BimCacheSceneDTO read_file(const std::string& cache_path, const std::string& expected_source_ifc_path) {
    const fs::path path(cache_path);
    std::ifstream in(path, std::ios::binary);
    if (!in) throw std::runtime_error("BIM cache does not exist: " + cache_path);
    std::array<char, kMagic.size()> magic{};
    in.read(magic.data(), static_cast<std::streamsize>(magic.size()));
    if (!in || magic != kMagic) throw std::runtime_error("BIM cache has an invalid magic header");
    const auto version = read_scalar<std::uint32_t>(in);
    if (version != kBimCacheFormatVersion) throw std::runtime_error("BIM cache format version is unsupported");
    if (read_scalar<std::uint32_t>(in) != kEndianMarker) {
        throw std::runtime_error("BIM cache byte order is unsupported");
    }
    BimCacheSceneDTO scene;
    scene.format_version = version;
    scene.scene_compiler_version = read_scalar<std::uint32_t>(in);
    if (scene.scene_compiler_version != kBimCacheSceneCompilerVersion) {
        throw std::runtime_error("BIM cache scene compiler version is unsupported");
    }
    scene.object_mapping_version = read_scalar<std::uint32_t>(in);
    if (scene.object_mapping_version != kBimCacheObjectMappingVersion) {
        throw std::runtime_error("BIM cache object mapping version is unsupported");
    }
    scene.format_flags = read_scalar<std::uint32_t>(in);
    if (scene.format_flags != kBimCacheFormatFlags) {
        throw std::runtime_error("BIM cache format flags are unsupported");
    }
    scene.chunk_seed_tile_size_meters = read_scalar<double>(in);
    if (!std::isfinite(scene.chunk_seed_tile_size_meters) || scene.chunk_seed_tile_size_meters <= 0.0) {
        throw std::runtime_error("BIM cache chunk seed size is invalid");
    }
    scene.engine_version = read_string(in);
    if (scene.engine_version != tbe::core::TBE_ENGINE_VERSION) {
        throw std::runtime_error("BIM cache engine version is unsupported");
    }
    scene.source.source_path = read_string(in);
    scene.source.source_size_bytes = read_scalar<std::uint64_t>(in);
    scene.source.source_modified_ticks = read_scalar<std::int64_t>(in);
    scene.source.source_fingerprint = read_scalar<std::uint64_t>(in);
    scene.source_object_count = checked_size(read_scalar<std::uint64_t>(in), "source object");
    scene.source_triangle_count = checked_size(read_scalar<std::uint64_t>(in), "source triangle");
    const auto level_count = checked_size(read_scalar<std::uint64_t>(in), "level");
    scene.levels.reserve(level_count);
    for (std::size_t index = 0; index < level_count; ++index) scene.levels.push_back(read_level(in));
    const auto chunk_count = checked_size(read_scalar<std::uint64_t>(in), "chunk");
    scene.chunks.reserve(chunk_count);
    for (std::size_t index = 0; index < chunk_count; ++index) scene.chunks.push_back(read_chunk(in));
    const auto node_count = checked_size(read_scalar<std::uint64_t>(in), "BVH node");
    scene.bvh_nodes.reserve(node_count);
    for (std::size_t index = 0; index < node_count; ++index) scene.bvh_nodes.push_back(read_bvh_node(in));
    scene.bvh_chunk_indices = read_scalar_vector<std::uint32_t>(in, "BVH chunk index");
    if (in.peek() != std::char_traits<char>::eof()) {
        throw std::runtime_error("BIM cache has unexpected trailing bytes");
    }
    if (!expected_source_ifc_path.empty()) {
        const auto current = source_signature(expected_source_ifc_path);
        if (current.source_path != scene.source.source_path ||
            current.source_size_bytes != scene.source.source_size_bytes ||
            current.source_modified_ticks != scene.source.source_modified_ticks ||
            current.source_fingerprint != scene.source.source_fingerprint) {
            throw std::runtime_error("BIM cache is stale for the current IFC source");
        }
    }
    return scene;
}

BimCacheStatsDTO stats_for(const BimCacheSceneDTO& scene, std::size_t byte_size, bool source_valid) {
    std::size_t primitive_count = 0;
    for (const auto& chunk : scene.chunks) primitive_count += chunk.primitives.size();
    return BimCacheStatsDTO{
        .format_version = scene.format_version,
        .source_valid = source_valid,
        .source_object_count = scene.source_object_count,
        .source_triangle_count = scene.source_triangle_count,
        .chunk_count = scene.chunks.size(),
        .primitive_count = primitive_count,
        .bvh_node_count = scene.bvh_nodes.size(),
        .byte_size = byte_size,
    };
}

} // namespace tbe::api::runtime_cache
