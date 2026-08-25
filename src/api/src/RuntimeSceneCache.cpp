#include "RuntimeSceneCache.hpp"

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

constexpr std::array<char, 8> kMagic{'T', 'B', 'E', 'B', 'I', 'M', 'C', '1'};
constexpr std::uint32_t kEndianMarker = 0x01020304u;
constexpr std::uint64_t kMaxStringBytes = 16ull * 1024ull * 1024ull;
constexpr std::uint64_t kMaxCollectionEntries = 32ull * 1024ull * 1024ull;
constexpr std::size_t kLeafChunkCount = 8;
constexpr double kTileSizeMeters = 24.0;

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

struct ChunkKey {
    std::uint64_t level_id{};
    std::string material_category{};
    std::int32_t tile_x{};
    std::int32_t tile_y{};

    [[nodiscard]] auto as_tuple() const {
        return std::tie(level_id, material_category, tile_x, tile_y);
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
    };
}

BimCacheSceneDTO compile(const RenderSceneDTO& scene, BimCacheSourceDTO source) {
    BimCacheSceneDTO compiled;
    compiled.format_version = kBimCacheFormatVersion;
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
            .material_category = object.material_category.empty() ? "generic" : object.material_category,
            .tile_x = static_cast<std::int32_t>(std::floor(center.x / kTileSizeMeters)),
            .tile_y = static_cast<std::int32_t>(std::floor(center.y / kTileSizeMeters)),
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
        for (const auto index : object.mesh.indices) {
            if (index >= object.mesh.positions.size() || vertex_offset + index > std::numeric_limits<std::uint32_t>::max()) {
                throw std::runtime_error("BIM cache compiler received an invalid mesh index");
            }
            chunk.indices.push_back(static_cast<std::uint32_t>(vertex_offset + index));
        }
        chunk.primitives.push_back(BimCachePrimitiveDTO{
            .element_id = object.element_id,
            .kind = object.kind,
            .revision = object.revision,
            .first_index = static_cast<std::uint32_t>(first_index),
            .index_count = static_cast<std::uint32_t>(object.mesh.indices.size()),
            .bounds = object.bounds,
        });
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

void write_file(const std::string& cache_path, const BimCacheSceneDTO& scene) {
    if (scene.format_version != kBimCacheFormatVersion) {
        throw std::runtime_error("unsupported BIM cache format for writing");
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
        write_string(out, scene.source.source_path);
        write_scalar<std::uint64_t>(out, scene.source.source_size_bytes);
        write_scalar<std::int64_t>(out, scene.source.source_modified_ticks);
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
    scene.source.source_path = read_string(in);
    scene.source.source_size_bytes = read_scalar<std::uint64_t>(in);
    scene.source.source_modified_ticks = read_scalar<std::int64_t>(in);
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
        if (current.source_size_bytes != scene.source.source_size_bytes ||
            current.source_modified_ticks != scene.source.source_modified_ticks) {
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
