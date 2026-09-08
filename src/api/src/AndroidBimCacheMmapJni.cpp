#include "RuntimeSceneCache.hpp"
#include "tbe/core/Project.hpp"

#include <jni.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <limits>
#include <memory>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <string>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <utility>
#include <vector>

namespace {

using tbe::api::AABB3D;
using tbe::api::ApiElementKind;
using tbe::api::BimCacheSourceDTO;
using tbe::api::RenderSceneFeatureEdgeRole;
using tbe::api::Vec3;

constexpr std::array<char, 8> kMagic{'T', 'B', 'E', 'B', 'I', 'M', 'C', '2'};
constexpr std::uint32_t kEndianMarker = 0x01020304u;
constexpr std::uint64_t kMaxStringBytes = 16ull * 1024ull * 1024ull;
constexpr std::uint64_t kMaxCollectionEntries = 32ull * 1024ull * 1024ull;
constexpr std::array<const char*, 8> kWallMetadataKeys{
    "start_x", "start_y", "end_x", "end_y", "thickness_meters",
    "height_meters", "profile_corners", "layer_profile",
};

struct MappedFeatureEdge {
    Vec3 start{};
    Vec3 end{};
    RenderSceneFeatureEdgeRole role{RenderSceneFeatureEdgeRole::Silhouette};
};

struct MappedPrimitive {
    std::uint64_t element_id{};
    ApiElementKind kind{ApiElementKind::Unknown};
    std::uint64_t revision{};
    std::uint32_t first_index{};
    std::uint32_t index_count{};
    AABB3D bounds{};
    std::vector<MappedFeatureEdge> feature_edges{};
    std::array<std::string, kWallMetadataKeys.size()> wall_metadata{};
};

struct MappedChunk {
    std::uint64_t level_id{};
    std::string material_category{};
    std::int32_t tile_x{};
    std::int32_t tile_y{};
    AABB3D bounds{};
    std::size_t positions_offset{};
    std::size_t positions_count{};
    std::size_t indices_offset{};
    std::size_t indices_count{};
    std::uint64_t kind_mask{};
    std::vector<MappedPrimitive> primitives{};
};

struct MappedBvhNode {
    AABB3D bounds{};
    std::int32_t left_child{-1};
    std::int32_t right_child{-1};
    std::uint32_t first_chunk{};
    std::uint32_t chunk_count{};
};

struct NativeBimCacheHandle {
    int fd{-1};
    const std::byte* mapping{nullptr};
    std::size_t mapping_size{};
    std::vector<MappedChunk> chunks{};
    std::vector<MappedBvhNode> bvh_nodes{};
    std::vector<std::uint32_t> bvh_chunk_indices{};

    ~NativeBimCacheHandle() {
        if (mapping != nullptr && mapping_size != 0) {
            munmap(const_cast<std::byte*>(mapping), mapping_size);
        }
        if (fd >= 0) close(fd);
    }

    NativeBimCacheHandle() = default;
    NativeBimCacheHandle(const NativeBimCacheHandle&) = delete;
    NativeBimCacheHandle& operator=(const NativeBimCacheHandle&) = delete;
};

std::mutex error_mutex;
std::string last_error;

void set_error(std::string value) {
    std::scoped_lock lock(error_mutex);
    last_error = std::move(value);
}

void clear_error() {
    std::scoped_lock lock(error_mutex);
    last_error.clear();
}

std::string error_snapshot() {
    std::scoped_lock lock(error_mutex);
    return last_error;
}

std::string to_string(JNIEnv* environment, jstring value) {
    if (value == nullptr) return {};
    const char* utf8 = environment->GetStringUTFChars(value, nullptr);
    if (utf8 == nullptr) return {};
    std::string result(utf8);
    environment->ReleaseStringUTFChars(value, utf8);
    return result;
}

NativeBimCacheHandle* to_handle(jlong value) {
    return reinterpret_cast<NativeBimCacheHandle*>(static_cast<std::uintptr_t>(value));
}

jlong to_jlong(NativeBimCacheHandle* value) {
    return static_cast<jlong>(reinterpret_cast<std::uintptr_t>(value));
}

class Cursor {
public:
    Cursor(const std::byte* data, std::size_t size) : data_(data), size_(size) {}

    template <typename T>
    T read() {
        static_assert(std::is_trivially_copyable_v<T>);
        require(sizeof(T));
        T value{};
        std::memcpy(&value, data_ + offset_, sizeof(T));
        offset_ += sizeof(T);
        return value;
    }

    std::string read_string() {
        const auto bytes = read<std::uint64_t>();
        if (bytes > kMaxStringBytes || bytes > std::numeric_limits<std::size_t>::max()) {
            throw std::runtime_error("BIM cache string is too large");
        }
        const auto count = static_cast<std::size_t>(bytes);
        require(count);
        std::string value(reinterpret_cast<const char*>(data_ + offset_), count);
        offset_ += count;
        return value;
    }

    std::size_t read_count(const char* label) {
        const auto value = read<std::uint64_t>();
        if (value > kMaxCollectionEntries || value > std::numeric_limits<std::size_t>::max()) {
            throw std::runtime_error(std::string("BIM cache has an invalid ") + label + " count");
        }
        return static_cast<std::size_t>(value);
    }

    std::size_t skip_array(std::size_t count, std::size_t element_size, const char* label) {
        if (element_size != 0 && count > std::numeric_limits<std::size_t>::max() / element_size) {
            throw std::runtime_error(std::string("BIM cache ") + label + " buffer is too large");
        }
        const auto bytes = count * element_size;
        require(bytes);
        const auto start = offset_;
        offset_ += bytes;
        return start;
    }

    std::size_t offset() const { return offset_; }
    std::size_t remaining() const { return size_ - offset_; }

private:
    void require(std::size_t bytes) const {
        if (bytes > size_ - offset_) {
            throw std::runtime_error("BIM cache is truncated or corrupt");
        }
    }

    const std::byte* data_{};
    std::size_t size_{};
    std::size_t offset_{};
};

Vec3 read_vec3(Cursor& cursor) {
    return Vec3{
        .x = cursor.read<double>(),
        .y = cursor.read<double>(),
        .z = cursor.read<double>(),
    };
}

AABB3D read_bounds(Cursor& cursor) {
    return AABB3D{.min = read_vec3(cursor), .max = read_vec3(cursor)};
}

bool finite_bounds(const AABB3D& bounds) {
    return std::isfinite(bounds.min.x) && std::isfinite(bounds.min.y) && std::isfinite(bounds.min.z) &&
        std::isfinite(bounds.max.x) && std::isfinite(bounds.max.y) && std::isfinite(bounds.max.z) &&
        bounds.min.x <= bounds.max.x && bounds.min.y <= bounds.max.y && bounds.min.z <= bounds.max.z;
}

MappedPrimitive read_primitive(Cursor& cursor) {
    MappedPrimitive primitive;
    primitive.element_id = cursor.read<std::uint64_t>();
    primitive.kind = static_cast<ApiElementKind>(cursor.read<std::int32_t>());
    primitive.revision = cursor.read<std::uint64_t>();
    primitive.first_index = cursor.read<std::uint32_t>();
    primitive.index_count = cursor.read<std::uint32_t>();
    primitive.bounds = read_bounds(cursor);
    if (!finite_bounds(primitive.bounds)) {
        throw std::runtime_error("BIM cache primitive has invalid bounds");
    }

    const auto edge_count = cursor.read_count("primitive feature edge");
    primitive.feature_edges.reserve(edge_count);
    for (std::size_t index = 0; index < edge_count; ++index) {
        primitive.feature_edges.push_back(MappedFeatureEdge{
            .start = read_vec3(cursor),
            .end = read_vec3(cursor),
            .role = static_cast<RenderSceneFeatureEdgeRole>(cursor.read<std::uint8_t>()),
        });
    }

    const auto metadata_count = cursor.read_count("primitive metadata");
    for (std::size_t index = 0; index < metadata_count; ++index) {
        const auto key = cursor.read_string();
        auto value = cursor.read_string();
        for (std::size_t key_index = 0; key_index < kWallMetadataKeys.size(); ++key_index) {
            if (key == kWallMetadataKeys[key_index]) {
                primitive.wall_metadata[key_index] = std::move(value);
                break;
            }
        }
    }
    return primitive;
}

std::unique_ptr<NativeBimCacheHandle> open_mapped_cache(
    const std::string& cache_path,
    const std::string& source_ifc_path
) {
    auto handle = std::make_unique<NativeBimCacheHandle>();
    handle->fd = open(cache_path.c_str(), O_RDONLY | O_CLOEXEC);
    if (handle->fd < 0) {
        throw std::runtime_error("BIM cache does not exist: " + cache_path);
    }

    struct stat file_stats {};
    if (fstat(handle->fd, &file_stats) != 0 || file_stats.st_size <= 0) {
        throw std::runtime_error("BIM cache has an invalid file size");
    }
    if (static_cast<std::uint64_t>(file_stats.st_size) > std::numeric_limits<std::size_t>::max()) {
        throw std::runtime_error("BIM cache is too large for this Android process");
    }
    handle->mapping_size = static_cast<std::size_t>(file_stats.st_size);
    void* mapped = mmap(nullptr, handle->mapping_size, PROT_READ, MAP_PRIVATE, handle->fd, 0);
    if (mapped == MAP_FAILED) {
        handle->mapping_size = 0;
        throw std::runtime_error("failed to memory-map BIM cache");
    }
    handle->mapping = static_cast<const std::byte*>(mapped);
#ifdef MADV_RANDOM
    (void)madvise(const_cast<std::byte*>(handle->mapping), handle->mapping_size, MADV_RANDOM);
#endif

    Cursor cursor(handle->mapping, handle->mapping_size);
    for (const auto expected : kMagic) {
        if (cursor.read<char>() != expected) {
            throw std::runtime_error("BIM cache has an invalid magic header");
        }
    }
    if (cursor.read<std::uint32_t>() != tbe::api::runtime_cache::kBimCacheFormatVersion) {
        throw std::runtime_error("BIM cache format version is unsupported");
    }
    if (cursor.read<std::uint32_t>() != kEndianMarker) {
        throw std::runtime_error("BIM cache byte order is unsupported");
    }
    if (cursor.read<std::uint32_t>() != tbe::api::runtime_cache::kBimCacheSceneCompilerVersion) {
        throw std::runtime_error("BIM cache scene compiler version is unsupported");
    }
    if (cursor.read<std::uint32_t>() != tbe::api::runtime_cache::kBimCacheObjectMappingVersion) {
        throw std::runtime_error("BIM cache object mapping version is unsupported");
    }
    if (cursor.read<std::uint32_t>() != tbe::api::runtime_cache::kBimCacheFormatFlags) {
        throw std::runtime_error("BIM cache format flags are unsupported");
    }
    const auto tile_size = cursor.read<double>();
    if (!std::isfinite(tile_size) || tile_size <= 0.0) {
        throw std::runtime_error("BIM cache chunk seed size is invalid");
    }
    if (cursor.read_string() != tbe::core::TBE_ENGINE_VERSION) {
        throw std::runtime_error("BIM cache engine version is unsupported");
    }

    BimCacheSourceDTO stored_source;
    stored_source.source_path = cursor.read_string();
    stored_source.source_size_bytes = cursor.read<std::uint64_t>();
    stored_source.source_modified_ticks = cursor.read<std::int64_t>();
    stored_source.source_fingerprint = cursor.read<std::uint64_t>();
    (void)cursor.read_count("source object");
    (void)cursor.read_count("source triangle");

    if (!source_ifc_path.empty()) {
        const auto current = tbe::api::runtime_cache::source_signature(source_ifc_path);
        if (current.source_path != stored_source.source_path ||
            current.source_size_bytes != stored_source.source_size_bytes ||
            current.source_modified_ticks != stored_source.source_modified_ticks ||
            current.source_fingerprint != stored_source.source_fingerprint) {
            throw std::runtime_error("BIM cache is stale for the current IFC source");
        }
    }

    const auto level_count = cursor.read_count("level");
    for (std::size_t index = 0; index < level_count; ++index) {
        (void)cursor.read<std::uint64_t>();
        (void)cursor.read_string();
        (void)cursor.read<double>();
        (void)cursor.read<double>();
    }

    const auto chunk_count = cursor.read_count("chunk");
    handle->chunks.reserve(chunk_count);
    for (std::size_t chunk_index = 0; chunk_index < chunk_count; ++chunk_index) {
        MappedChunk chunk;
        chunk.level_id = cursor.read<std::uint64_t>();
        chunk.material_category = cursor.read_string();
        chunk.tile_x = cursor.read<std::int32_t>();
        chunk.tile_y = cursor.read<std::int32_t>();
        chunk.bounds = read_bounds(cursor);
        if (!finite_bounds(chunk.bounds)) {
            throw std::runtime_error("BIM cache chunk has invalid bounds");
        }

        chunk.positions_count = cursor.read_count("position");
        chunk.positions_offset = cursor.skip_array(chunk.positions_count, sizeof(float), "position");
        chunk.indices_count = cursor.read_count("index");
        chunk.indices_offset = cursor.skip_array(chunk.indices_count, sizeof(std::uint32_t), "index");

        const auto primitive_count = cursor.read_count("primitive");
        chunk.primitives.reserve(primitive_count);
        for (std::size_t primitive_index = 0; primitive_index < primitive_count; ++primitive_index) {
            auto primitive = read_primitive(cursor);
            const auto ordinal = static_cast<std::uint32_t>(primitive.kind);
            if (ordinal < 64) chunk.kind_mask |= std::uint64_t{1} << ordinal;
            const auto first = static_cast<std::size_t>(primitive.first_index);
            const auto count = static_cast<std::size_t>(primitive.index_count);
            if (first > chunk.indices_count || count > chunk.indices_count - first) {
                throw std::runtime_error("BIM cache primitive index range exceeds its chunk");
            }
            chunk.primitives.push_back(std::move(primitive));
        }
        handle->chunks.push_back(std::move(chunk));
    }

    const auto node_count = cursor.read_count("BVH node");
    handle->bvh_nodes.reserve(node_count);
    for (std::size_t index = 0; index < node_count; ++index) {
        MappedBvhNode node{
            .bounds = read_bounds(cursor),
            .left_child = cursor.read<std::int32_t>(),
            .right_child = cursor.read<std::int32_t>(),
            .first_chunk = cursor.read<std::uint32_t>(),
            .chunk_count = cursor.read<std::uint32_t>(),
        };
        if (!finite_bounds(node.bounds)) {
            throw std::runtime_error("BIM cache BVH node has invalid bounds");
        }
        handle->bvh_nodes.push_back(node);
    }

    const auto bvh_index_count = cursor.read_count("BVH chunk index");
    handle->bvh_chunk_indices.reserve(bvh_index_count);
    for (std::size_t index = 0; index < bvh_index_count; ++index) {
        const auto chunk_index = cursor.read<std::uint32_t>();
        if (chunk_index >= handle->chunks.size()) {
            throw std::runtime_error("BIM cache BVH references an invalid chunk");
        }
        handle->bvh_chunk_indices.push_back(chunk_index);
    }
    if (cursor.remaining() != 0) {
        throw std::runtime_error("BIM cache has unexpected trailing bytes");
    }

    return handle;
}

jlongArray make_long_array(JNIEnv* environment, const std::vector<std::int64_t>& values) {
    if (values.size() > static_cast<std::size_t>(std::numeric_limits<jsize>::max())) return nullptr;
    auto* result = environment->NewLongArray(static_cast<jsize>(values.size()));
    if (result != nullptr && !values.empty()) {
        environment->SetLongArrayRegion(
            result,
            0,
            static_cast<jsize>(values.size()),
            reinterpret_cast<const jlong*>(values.data())
        );
    }
    return result;
}

jdoubleArray make_double_array(JNIEnv* environment, const std::vector<double>& values) {
    if (values.size() > static_cast<std::size_t>(std::numeric_limits<jsize>::max())) return nullptr;
    auto* result = environment->NewDoubleArray(static_cast<jsize>(values.size()));
    if (result != nullptr && !values.empty()) {
        environment->SetDoubleArrayRegion(result, 0, static_cast<jsize>(values.size()), values.data());
    }
    return result;
}

jdoubleArray make_bounds_array(JNIEnv* environment, const AABB3D& bounds) {
    const std::vector<double> values{
        bounds.min.x, bounds.min.y, bounds.min.z,
        bounds.max.x, bounds.max.y, bounds.max.z,
    };
    return make_double_array(environment, values);
}

bool kind_visible(ApiElementKind kind, std::uint64_t visible_kind_mask) {
    const auto ordinal = static_cast<std::uint32_t>(kind);
    return ordinal < 64 && (visible_kind_mask & (std::uint64_t{1} << ordinal)) != 0;
}

bool opening_kind(ApiElementKind kind) {
    return kind == ApiElementKind::Door || kind == ApiElementKind::Window;
}

Vec3 subtract(const Vec3& first, const Vec3& second) {
    return {.x = first.x - second.x, .y = first.y - second.y, .z = first.z - second.z};
}

Vec3 cross(const Vec3& first, const Vec3& second) {
    return {
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
    constexpr double epsilon = 1.0e-12;
    double near_distance = 0.0;
    double far_distance = maximum_distance;
    const std::array<double, 3> origins{origin.x, origin.y, origin.z};
    const std::array<double, 3> directions{direction.x, direction.y, direction.z};
    const std::array<double, 3> minimums{bounds.min.x, bounds.min.y, bounds.min.z};
    const std::array<double, 3> maximums{bounds.max.x, bounds.max.y, bounds.max.z};
    for (std::size_t axis = 0; axis < 3; ++axis) {
        if (std::abs(directions[axis]) < epsilon) {
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
    constexpr double epsilon = 1.0e-9;
    const auto first_edge = subtract(second, first);
    const auto second_edge = subtract(third, first);
    const auto cross_direction = cross(direction, second_edge);
    const auto determinant = dot(first_edge, cross_direction);
    if (std::abs(determinant) < epsilon) return std::nullopt;
    const auto inverse = 1.0 / determinant;
    const auto origin_offset = subtract(origin, first);
    const auto u = dot(origin_offset, cross_direction) * inverse;
    if (u < -epsilon || u > 1.0 + epsilon) return std::nullopt;
    const auto cross_origin = cross(origin_offset, first_edge);
    const auto v = dot(direction, cross_origin) * inverse;
    if (v < -epsilon || u + v > 1.0 + epsilon) return std::nullopt;
    const auto distance = dot(second_edge, cross_origin) * inverse;
    return distance > epsilon ? std::optional<double>(distance) : std::nullopt;
}

std::uint32_t mapped_index(const NativeBimCacheHandle& cache, const MappedChunk& chunk, std::size_t index) {
    if (index >= chunk.indices_count) throw std::runtime_error("BIM cache index read is out of range");
    std::uint32_t value{};
    const auto offset = chunk.indices_offset + index * sizeof(std::uint32_t);
    std::memcpy(&value, cache.mapping + offset, sizeof(value));
    return value;
}

Vec3 mapped_position(const NativeBimCacheHandle& cache, const MappedChunk& chunk, std::uint32_t index) {
    const auto vertex_count = chunk.positions_count / 3;
    if (index >= vertex_count) throw std::runtime_error("BIM cache vertex read is out of range");
    std::array<float, 3> values{};
    const auto offset = chunk.positions_offset + static_cast<std::size_t>(index) * 3 * sizeof(float);
    std::memcpy(values.data(), cache.mapping + offset, sizeof(values));
    return {.x = values[0], .y = values[1], .z = values[2]};
}

void pick_chunk(
    const NativeBimCacheHandle& cache,
    const MappedChunk& chunk,
    const Vec3& origin,
    const Vec3& direction,
    std::uint64_t visible_kind_mask,
    double& nearest_surface_distance,
    std::optional<std::uint64_t>& nearest_surface,
    double& nearest_opening_distance,
    std::optional<std::uint64_t>& nearest_opening
) {
    for (const auto& primitive : chunk.primitives) {
        if (!kind_visible(primitive.kind, visible_kind_mask) || primitive.index_count < 3) continue;
        double primitive_entry{};
        const auto maximum_distance = opening_kind(primitive.kind)
            ? nearest_opening_distance
            : nearest_surface_distance;
        if (!ray_bounds_distance(origin, direction, primitive.bounds, maximum_distance, primitive_entry)) continue;
        for (std::size_t offset = 0; offset + 2 < primitive.index_count; offset += 3) {
            const auto first = mapped_position(
                cache,
                chunk,
                mapped_index(cache, chunk, static_cast<std::size_t>(primitive.first_index) + offset)
            );
            const auto second = mapped_position(
                cache,
                chunk,
                mapped_index(cache, chunk, static_cast<std::size_t>(primitive.first_index) + offset + 1)
            );
            const auto third = mapped_position(
                cache,
                chunk,
                mapped_index(cache, chunk, static_cast<std::size_t>(primitive.first_index) + offset + 2)
            );
            const auto distance = ray_triangle_distance(origin, direction, first, second, third);
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

std::optional<std::uint64_t> pick(
    const NativeBimCacheHandle& cache,
    const Vec3& origin,
    const Vec3& direction,
    std::uint64_t visible_kind_mask
) {
    if (!std::isfinite(origin.x) || !std::isfinite(origin.y) || !std::isfinite(origin.z) ||
        !std::isfinite(direction.x) || !std::isfinite(direction.y) || !std::isfinite(direction.z) ||
        dot(direction, direction) < 1.0e-18) {
        return std::nullopt;
    }

    auto nearest_surface_distance = std::numeric_limits<double>::infinity();
    auto nearest_opening_distance = std::numeric_limits<double>::infinity();
    std::optional<std::uint64_t> nearest_surface;
    std::optional<std::uint64_t> nearest_opening;

    const auto visit_chunk = [&](std::uint32_t chunk_index) {
        if (chunk_index >= cache.chunks.size()) return;
        const auto& chunk = cache.chunks[chunk_index];
        double entry{};
        if (!ray_bounds_distance(
                origin,
                direction,
                chunk.bounds,
                std::max(nearest_surface_distance, nearest_opening_distance),
                entry
            )) return;
        pick_chunk(
            cache,
            chunk,
            origin,
            direction,
            visible_kind_mask,
            nearest_surface_distance,
            nearest_surface,
            nearest_opening_distance,
            nearest_opening
        );
    };

    if (cache.bvh_nodes.empty()) {
        for (std::size_t index = 0; index < cache.chunks.size(); ++index) {
            visit_chunk(static_cast<std::uint32_t>(index));
        }
    } else {
        std::vector<std::int32_t> pending{0};
        while (!pending.empty()) {
            const auto node_index = pending.back();
            pending.pop_back();
            if (node_index < 0 || static_cast<std::size_t>(node_index) >= cache.bvh_nodes.size()) continue;
            const auto& node = cache.bvh_nodes[static_cast<std::size_t>(node_index)];
            double entry{};
            if (!ray_bounds_distance(
                    origin,
                    direction,
                    node.bounds,
                    std::max(nearest_surface_distance, nearest_opening_distance),
                    entry
                )) continue;
            if (node.chunk_count > 0) {
                const auto first = static_cast<std::size_t>(node.first_chunk);
                const auto available = first <= cache.bvh_chunk_indices.size()
                    ? cache.bvh_chunk_indices.size() - first
                    : 0;
                const auto count = std::min<std::size_t>(node.chunk_count, available);
                for (std::size_t offset = 0; offset < count; ++offset) {
                    visit_chunk(cache.bvh_chunk_indices[first + offset]);
                }
            } else {
                if (node.left_child >= 0) pending.push_back(node.left_child);
                if (node.right_child >= 0) pending.push_back(node.right_child);
            }
        }
    }

    if (nearest_opening.has_value() &&
        (!nearest_surface.has_value() || nearest_opening_distance <= nearest_surface_distance + 0.35)) {
        return nearest_opening;
    }
    return nearest_surface;
}

} // namespace

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeOpen(
    JNIEnv* environment,
    jclass,
    jstring cache_path,
    jstring source_ifc_path
) {
    try {
        const auto cache = to_string(environment, cache_path);
        const auto source = to_string(environment, source_ifc_path);
        if (cache.empty() || source.empty()) {
            set_error("BIM cache and IFC source paths are required");
            return 0;
        }
        auto handle = open_mapped_cache(cache, source);
        clear_error();
        return to_jlong(handle.release());
    } catch (const std::exception& error) {
        set_error(error.what());
        return 0;
    }
}

JNIEXPORT void JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeClose(
    JNIEnv*,
    jclass,
    jlong handle
) {
    delete to_handle(handle);
}

JNIEXPORT jstring JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeLastError(JNIEnv* environment, jclass) {
    const auto value = error_snapshot();
    return environment->NewStringUTF(value.c_str());
}

JNIEXPORT jint JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkCount(JNIEnv*, jclass, jlong handle) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || cache->chunks.size() > static_cast<std::size_t>(std::numeric_limits<jint>::max())) return 0;
    return static_cast<jint>(cache->chunks.size());
}

JNIEXPORT jlong JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkLevelId(
    JNIEnv*, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) return 0;
    return static_cast<jlong>(cache->chunks[static_cast<std::size_t>(chunk_index)].level_id);
}

JNIEXPORT jstring JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkMaterial(
    JNIEnv* environment, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) {
        return environment->NewStringUTF("generic");
    }
    return environment->NewStringUTF(cache->chunks[static_cast<std::size_t>(chunk_index)].material_category.c_str());
}

JNIEXPORT jlong JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkKindMask(
    JNIEnv*, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) return 0;
    return static_cast<jlong>(cache->chunks[static_cast<std::size_t>(chunk_index)].kind_mask);
}

JNIEXPORT jlongArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkPrimitiveRanges(
    JNIEnv* environment, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) return nullptr;
    const auto& primitives = cache->chunks[static_cast<std::size_t>(chunk_index)].primitives;
    std::vector<std::int64_t> values;
    values.reserve(primitives.size() * 3);
    for (const auto& primitive : primitives) {
        values.push_back(primitive.first_index);
        values.push_back(primitive.index_count);
        values.push_back(static_cast<std::int64_t>(primitive.kind));
    }
    return make_long_array(environment, values);
}

JNIEXPORT jobjectArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkPrimitiveMetadata(
    JNIEnv* environment, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) return nullptr;
    const auto& primitives = cache->chunks[static_cast<std::size_t>(chunk_index)].primitives;
    const auto item_count = primitives.size() * kWallMetadataKeys.size();
    if (item_count > static_cast<std::size_t>(std::numeric_limits<jsize>::max())) return nullptr;
    const auto string_class = environment->FindClass("java/lang/String");
    if (string_class == nullptr) return nullptr;
    auto* result = environment->NewObjectArray(static_cast<jsize>(item_count), string_class, nullptr);
    if (result == nullptr) return nullptr;
    for (std::size_t primitive_index = 0; primitive_index < primitives.size(); ++primitive_index) {
        for (std::size_t key_index = 0; key_index < kWallMetadataKeys.size(); ++key_index) {
            auto* value = environment->NewStringUTF(primitives[primitive_index].wall_metadata[key_index].c_str());
            if (value == nullptr) return nullptr;
            environment->SetObjectArrayElement(
                result,
                static_cast<jsize>(primitive_index * kWallMetadataKeys.size() + key_index),
                value
            );
            environment->DeleteLocalRef(value);
        }
    }
    return result;
}

JNIEXPORT jdoubleArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkBounds(
    JNIEnv* environment, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) return nullptr;
    return make_bounds_array(environment, cache->chunks[static_cast<std::size_t>(chunk_index)].bounds);
}

JNIEXPORT jobject JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkPositions(
    JNIEnv* environment, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) return nullptr;
    const auto& chunk = cache->chunks[static_cast<std::size_t>(chunk_index)];
    if (chunk.positions_count == 0) return nullptr;
    return environment->NewDirectByteBuffer(
        const_cast<std::byte*>(cache->mapping + chunk.positions_offset),
        static_cast<jlong>(chunk.positions_count * sizeof(float))
    );
}

JNIEXPORT jobject JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeChunkIndices(
    JNIEnv* environment, jclass, jlong handle, jint chunk_index
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr || chunk_index < 0 || static_cast<std::size_t>(chunk_index) >= cache->chunks.size()) return nullptr;
    const auto& chunk = cache->chunks[static_cast<std::size_t>(chunk_index)];
    if (chunk.indices_count == 0) return nullptr;
    return environment->NewDirectByteBuffer(
        const_cast<std::byte*>(cache->mapping + chunk.indices_offset),
        static_cast<jlong>(chunk.indices_count * sizeof(std::uint32_t))
    );
}

JNIEXPORT jlongArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativePrimitiveData(
    JNIEnv* environment, jclass, jlong handle
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr) return nullptr;
    std::size_t primitive_count = 0;
    for (const auto& chunk : cache->chunks) primitive_count += chunk.primitives.size();
    std::vector<std::int64_t> values;
    values.reserve(primitive_count * 4);
    for (const auto& chunk : cache->chunks) {
        for (const auto& primitive : chunk.primitives) {
            values.push_back(static_cast<std::int64_t>(primitive.element_id));
            values.push_back(static_cast<std::int64_t>(primitive.kind));
            values.push_back(static_cast<std::int64_t>(primitive.revision));
            values.push_back(static_cast<std::int64_t>(chunk.level_id));
        }
    }
    return make_long_array(environment, values);
}

JNIEXPORT jdoubleArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativePrimitiveBounds(
    JNIEnv* environment, jclass, jlong handle
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr) return nullptr;
    std::vector<double> values;
    for (const auto& chunk : cache->chunks) {
        for (const auto& primitive : chunk.primitives) {
            values.insert(values.end(), {
                primitive.bounds.min.x, primitive.bounds.min.y, primitive.bounds.min.z,
                primitive.bounds.max.x, primitive.bounds.max.y, primitive.bounds.max.z,
            });
        }
    }
    return make_double_array(environment, values);
}

JNIEXPORT jlongArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativePrimitiveFeatureEdgeCounts(
    JNIEnv* environment, jclass, jlong handle
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr) return nullptr;
    std::vector<std::int64_t> values;
    for (const auto& chunk : cache->chunks) {
        for (const auto& primitive : chunk.primitives) {
            values.push_back(static_cast<std::int64_t>(primitive.feature_edges.size()));
        }
    }
    return make_long_array(environment, values);
}

JNIEXPORT jdoubleArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativePrimitiveFeatureEdgeData(
    JNIEnv* environment, jclass, jlong handle
) {
    const auto* cache = to_handle(handle);
    if (cache == nullptr) return nullptr;
    std::vector<double> values;
    for (const auto& chunk : cache->chunks) {
        for (const auto& primitive : chunk.primitives) {
            for (const auto& edge : primitive.feature_edges) {
                values.insert(values.end(), {
                    static_cast<double>(edge.role),
                    edge.start.x, edge.start.y, edge.start.z,
                    edge.end.x, edge.end.y, edge.end.z,
                });
            }
        }
    }
    return make_double_array(environment, values);
}

JNIEXPORT jlong JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativePick(
    JNIEnv*, jclass, jlong handle,
    jdouble origin_x, jdouble origin_y, jdouble origin_z,
    jdouble direction_x, jdouble direction_y, jdouble direction_z,
    jlong visible_kind_mask
) {
    try {
        const auto* cache = to_handle(handle);
        if (cache == nullptr) return 0;
        const auto result = pick(
            *cache,
            {.x = origin_x, .y = origin_y, .z = origin_z},
            {.x = direction_x, .y = direction_y, .z = direction_z},
            static_cast<std::uint64_t>(visible_kind_mask)
        );
        clear_error();
        return result.has_value() ? static_cast<jlong>(*result) : 0;
    } catch (const std::exception& error) {
        set_error(error.what());
        return 0;
    }
}

JNIEXPORT jlongArray JNICALL
Java_com_example_viewer_1flutter_NativeBimCacheBridge_nativeCompileFromIfc(
    JNIEnv* environment,
    jclass,
    jstring source_ifc_path,
    jstring cache_path
) {
    try {
        const auto source = to_string(environment, source_ifc_path);
        const auto cache = to_string(environment, cache_path);
        if (source.empty() || cache.empty()) {
            set_error("IFC source and BIM cache paths are required");
            return nullptr;
        }
        const auto started = std::chrono::steady_clock::now();
        auto session_result = tbe::api::create_session("Android BIM cache benchmark");
        if (!session_result.ok() || !session_result.value.has_value()) {
            set_error(session_result.message.empty()
                ? "failed to create cache compiler session"
                : session_result.message);
            return nullptr;
        }
        auto session = std::move(*session_result.value);
        const auto import_result = session->import_ifc(source);
        if (!import_result.ok()) {
            set_error(import_result.message.empty() ? "failed to import IFC for cache compilation" : import_result.message);
            return nullptr;
        }
        const auto compile_result = session->compile_bim_cache(source, cache);
        if (!compile_result.ok() || !compile_result.value.has_value()) {
            set_error(compile_result.message.empty() ? "failed to compile BIM cache" : compile_result.message);
            return nullptr;
        }
        const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - started
        ).count();
        const auto& stats = *compile_result.value;
        const std::vector<std::int64_t> values{
            static_cast<std::int64_t>(elapsed),
            static_cast<std::int64_t>(stats.byte_size),
            static_cast<std::int64_t>(stats.source_object_count),
            static_cast<std::int64_t>(stats.source_triangle_count),
            static_cast<std::int64_t>(stats.chunk_count),
            static_cast<std::int64_t>(stats.primitive_count),
            static_cast<std::int64_t>(stats.bvh_node_count),
        };
        clear_error();
        return make_long_array(environment, values);
    } catch (const std::exception& error) {
        set_error(error.what());
        return nullptr;
    }
}

} // extern "C"
