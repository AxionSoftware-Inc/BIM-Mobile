#include "RuntimeSceneCache.hpp"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <limits>
#include <numeric>
#include <stdexcept>
#include <unordered_map>
#include <utility>
#include <vector>

namespace tbe::api::runtime_cache {

namespace {

constexpr std::size_t kLeafChunkCount = 8;

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

void extend_bounds(AABB3D& bounds, const Vec3& point, bool& initialized) {
    if (!initialized) {
        bounds = {.min = point, .max = point};
        initialized = true;
        return;
    }
    bounds.min.x = std::min(bounds.min.x, point.x);
    bounds.min.y = std::min(bounds.min.y, point.y);
    bounds.min.z = std::min(bounds.min.z, point.z);
    bounds.max.x = std::max(bounds.max.x, point.x);
    bounds.max.y = std::max(bounds.max.y, point.y);
    bounds.max.z = std::max(bounds.max.z, point.z);
}

std::size_t gpu_buffer_bytes(const BimCacheChunkDTO& chunk) {
    const auto position_bytes = chunk.positions.size() * sizeof(float);
    const auto index_bytes = chunk.indices.size() * sizeof(std::uint32_t);
    if (position_bytes > std::numeric_limits<std::size_t>::max() - index_bytes) {
        return std::numeric_limits<std::size_t>::max();
    }
    return position_bytes + index_bytes;
}

bool within_limits(const BimCacheChunkDTO& chunk, const BimCacheChunkingPolicy& policy) {
    return chunk.primitives.size() <= policy.max_elements_per_chunk &&
        chunk.indices.size() / 3 <= policy.max_triangles_per_chunk &&
        gpu_buffer_bytes(chunk) <= policy.max_gpu_buffer_bytes;
}

void validate_policy(const BimCacheChunkingPolicy& policy) {
    if (!std::isfinite(policy.seed_tile_size_meters) || policy.seed_tile_size_meters <= 0.0) {
        throw std::runtime_error("BIM cache chunk seed size must be finite and positive");
    }
    if (policy.max_elements_per_chunk == 0) {
        throw std::runtime_error("BIM cache max elements per chunk must be positive");
    }
    if (policy.max_triangles_per_chunk == 0) {
        throw std::runtime_error("BIM cache max triangles per chunk must be positive");
    }
    // One triangle with three unique XYZ float vertices and three uint32 indices
    // needs 48 bytes. Reject impossible policies instead of silently creating an
    // over-budget chunk that defeats the renderer's residency accounting.
    constexpr std::size_t kMinimumTriangleBytes = 3 * 3 * sizeof(float) + 3 * sizeof(std::uint32_t);
    if (policy.max_gpu_buffer_bytes < kMinimumTriangleBytes) {
        throw std::runtime_error("BIM cache GPU buffer budget is too small for one triangle");
    }
}

std::int32_t tile_coordinate(double value, double tile_size) {
    const auto coordinate = std::floor(value / tile_size);
    if (!std::isfinite(coordinate) ||
        coordinate < static_cast<double>(std::numeric_limits<std::int32_t>::min()) ||
        coordinate > static_cast<double>(std::numeric_limits<std::int32_t>::max())) {
        throw std::runtime_error("BIM cache refined tile coordinate exceeds 32-bit range");
    }
    return static_cast<std::int32_t>(coordinate);
}

struct ChunkBuilder {
    explicit ChunkBuilder(const BimCacheChunkDTO& source)
        : chunk{
            .level_id = source.level_id,
            .material_category = source.material_category,
            .tile_x = source.tile_x,
            .tile_y = source.tile_y,
        } {}

    BimCacheChunkDTO chunk{};
    std::unordered_map<std::uint32_t, std::uint32_t> vertex_remap{};
    bool has_bounds{false};

    bool empty() const {
        return chunk.indices.empty() && chunk.primitives.empty();
    }

    std::size_t bytes() const {
        return gpu_buffer_bytes(chunk);
    }

    std::size_t new_vertex_count_for_triangle(
        std::uint32_t first,
        std::uint32_t second,
        std::uint32_t third
    ) const {
        std::size_t count = 0;
        if (!vertex_remap.contains(first)) ++count;
        if (second != first && !vertex_remap.contains(second)) ++count;
        if (third != first && third != second && !vertex_remap.contains(third)) ++count;
        return count;
    }

    bool can_append_triangle(
        std::uint32_t first,
        std::uint32_t second,
        std::uint32_t third,
        const BimCacheChunkingPolicy& policy
    ) const {
        if (chunk.indices.size() / 3 >= policy.max_triangles_per_chunk) return false;
        const auto new_vertices = new_vertex_count_for_triangle(first, second, third);
        const auto extra_position_bytes = new_vertices * 3 * sizeof(float);
        const auto extra_index_bytes = 3 * sizeof(std::uint32_t);
        if (bytes() > policy.max_gpu_buffer_bytes) return false;
        const auto available = policy.max_gpu_buffer_bytes - bytes();
        return extra_position_bytes <= available && extra_index_bytes <= available - extra_position_bytes;
    }

    std::uint32_t append_vertex(const BimCacheChunkDTO& source, std::uint32_t source_index) {
        if (const auto found = vertex_remap.find(source_index); found != vertex_remap.end()) {
            return found->second;
        }
        const auto source_offset = static_cast<std::size_t>(source_index) * 3;
        if (source_offset + 2 >= source.positions.size()) {
            throw std::runtime_error("BIM cache primitive references an invalid source vertex");
        }
        const auto target_index = chunk.positions.size() / 3;
        if (target_index > std::numeric_limits<std::uint32_t>::max()) {
            throw std::runtime_error("BIM cache refined chunk exceeds 32-bit vertex range");
        }
        chunk.positions.push_back(source.positions[source_offset]);
        chunk.positions.push_back(source.positions[source_offset + 1]);
        chunk.positions.push_back(source.positions[source_offset + 2]);
        vertex_remap.emplace(source_index, static_cast<std::uint32_t>(target_index));
        return static_cast<std::uint32_t>(target_index);
    }

    void append_triangle(
        const BimCacheChunkDTO& source,
        std::uint32_t first,
        std::uint32_t second,
        std::uint32_t third,
        AABB3D& fragment_bounds,
        bool& fragment_has_bounds
    ) {
        for (const auto source_index : {first, second, third}) {
            const auto source_offset = static_cast<std::size_t>(source_index) * 3;
            if (source_offset + 2 >= source.positions.size()) {
                throw std::runtime_error("BIM cache primitive references an invalid source vertex");
            }
            const Vec3 point{
                .x = static_cast<double>(source.positions[source_offset]),
                .y = static_cast<double>(source.positions[source_offset + 1]),
                .z = static_cast<double>(source.positions[source_offset + 2]),
            };
            extend_bounds(fragment_bounds, point, fragment_has_bounds);
            extend_bounds(chunk.bounds, point, has_bounds);
            chunk.indices.push_back(append_vertex(source, source_index));
        }
    }

    BimCacheChunkDTO finish(double seed_tile_size_meters) {
        if (!has_bounds || chunk.indices.empty()) {
            throw std::runtime_error("cannot finalize an empty refined BIM cache chunk");
        }
        const auto center = bounds_center(chunk.bounds);
        chunk.tile_x = tile_coordinate(center.x, seed_tile_size_meters);
        chunk.tile_y = tile_coordinate(center.y, seed_tile_size_meters);
        return std::move(chunk);
    }
};

std::vector<std::size_t> spatial_primitive_order(const BimCacheChunkDTO& source) {
    std::vector<std::size_t> order(source.primitives.size());
    std::iota(order.begin(), order.end(), std::size_t{0});
    std::sort(order.begin(), order.end(), [&](std::size_t first, std::size_t second) {
        const auto a = bounds_center(source.primitives[first].bounds);
        const auto b = bounds_center(source.primitives[second].bounds);
        if (a.z != b.z) return a.z < b.z;
        if (a.y != b.y) return a.y < b.y;
        if (a.x != b.x) return a.x < b.x;
        return source.primitives[first].element_id.value < source.primitives[second].element_id.value;
    });
    return order;
}

void refine_chunk(
    BimCacheChunkDTO source,
    const BimCacheChunkingPolicy& policy,
    std::vector<BimCacheChunkDTO>& output
) {
    if (within_limits(source, policy)) {
        output.push_back(std::move(source));
        return;
    }
    if (source.primitives.empty()) {
        throw std::runtime_error("oversized BIM cache chunk has no primitive ranges for refinement");
    }
    if (source.positions.size() % 3 != 0 || source.indices.size() % 3 != 0) {
        throw std::runtime_error("oversized BIM cache chunk is not triangle-aligned");
    }

    auto builder = ChunkBuilder(source);
    const auto flush_builder = [&]() mutable {
        if (builder.empty()) return;
        output.push_back(builder.finish(policy.seed_tile_size_meters));
        builder = ChunkBuilder(source);
    };

    for (const auto primitive_index : spatial_primitive_order(source)) {
        const auto& primitive = source.primitives[primitive_index];
        const auto first_index = static_cast<std::size_t>(primitive.first_index);
        const auto index_count = static_cast<std::size_t>(primitive.index_count);
        if (index_count == 0) continue;
        if (index_count % 3 != 0 || first_index > source.indices.size() ||
            index_count > source.indices.size() - first_index) {
            throw std::runtime_error("BIM cache primitive range is invalid during chunk refinement");
        }

        std::size_t consumed = 0;
        bool first_fragment = true;
        while (consumed < index_count) {
            if (builder.chunk.primitives.size() >= policy.max_elements_per_chunk) {
                flush_builder();
            }

            const auto fragment_first_index = builder.chunk.indices.size();
            AABB3D fragment_bounds{};
            bool fragment_has_bounds = false;

            while (consumed < index_count) {
                const auto offset = first_index + consumed;
                const auto first = source.indices[offset];
                const auto second = source.indices[offset + 1];
                const auto third = source.indices[offset + 2];
                if (!builder.can_append_triangle(first, second, third, policy)) {
                    if (builder.chunk.indices.size() == fragment_first_index) {
                        // Existing geometry may have consumed the remaining
                        // budget. Flush it and retry this triangle in a fresh
                        // chunk. If the fresh chunk still cannot fit, the
                        // policy is internally impossible for this geometry.
                        if (!builder.empty()) {
                            flush_builder();
                            continue;
                        }
                        throw std::runtime_error("one BIM triangle exceeds the configured chunk budget");
                    }
                    break;
                }
                builder.append_triangle(
                    source,
                    first,
                    second,
                    third,
                    fragment_bounds,
                    fragment_has_bounds
                );
                consumed += 3;
            }

            const auto fragment_index_count = builder.chunk.indices.size() - fragment_first_index;
            if (fragment_index_count == 0 || !fragment_has_bounds) {
                continue;
            }
            if (fragment_first_index > std::numeric_limits<std::uint32_t>::max() ||
                fragment_index_count > std::numeric_limits<std::uint32_t>::max()) {
                throw std::runtime_error("BIM cache refined primitive exceeds 32-bit index range");
            }
            builder.chunk.primitives.push_back(BimCachePrimitiveDTO{
                .element_id = primitive.element_id,
                .kind = primitive.kind,
                .revision = primitive.revision,
                .first_index = static_cast<std::uint32_t>(fragment_first_index),
                .index_count = static_cast<std::uint32_t>(fragment_index_count),
                .bounds = fragment_bounds,
                // Large primitives are normally imported proxies and carry no
                // architectural feature edges. Keep authored edges on one
                // fragment only so a split wall/proxy never draws duplicates.
                .feature_edges = first_fragment ? primitive.feature_edges : std::vector<RenderSceneFeatureEdgeDTO>{},
                .metadata = primitive.metadata,
            });
            first_fragment = false;

            // If the primitive did not fit, this chunk is at one of the hard
            // limits. Finalize it immediately; the next fragment starts with a
            // clean vertex remap and a tight spatial bound.
            if (consumed < index_count) {
                flush_builder();
            }
        }
    }

    flush_builder();
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

AABB3D bounds_for_chunks(
    const BimCacheSceneDTO& scene,
    const std::vector<std::uint32_t>& indices,
    std::size_t begin,
    std::size_t end
) {
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

void rebuild_bvh(BimCacheSceneDTO& scene) {
    scene.bvh_nodes.clear();
    scene.bvh_chunk_indices.clear();
    if (scene.chunks.empty()) return;

    std::vector<std::uint32_t> chunk_indices(scene.chunks.size());
    for (std::size_t index = 0; index < chunk_indices.size(); ++index) {
        if (index > std::numeric_limits<std::uint32_t>::max()) {
            throw std::runtime_error("BIM cache has too many refined chunks for 32-bit BVH indices");
        }
        chunk_indices[index] = static_cast<std::uint32_t>(index);
    }
    (void)build_bvh(scene, chunk_indices, 0, chunk_indices.size());
}

BimCacheSceneDTO refine_dense_chunks(
    BimCacheSceneDTO scene,
    const BimCacheChunkingPolicy& policy
) {
    std::vector<BimCacheChunkDTO> refined;
    refined.reserve(scene.chunks.size());
    for (auto& chunk : scene.chunks) {
        refine_chunk(std::move(chunk), policy, refined);
    }
    scene.chunks = std::move(refined);
    rebuild_bvh(scene);
    return scene;
}

} // namespace

BimCacheSceneDTO compile(
    const RenderSceneDTO& scene,
    BimCacheSourceDTO source
) {
    return compile_bounded(scene, std::move(source), BimCacheChunkingPolicy{});
}

BimCacheSceneDTO compile_bounded(
    const RenderSceneDTO& scene,
    BimCacheSourceDTO source,
    const BimCacheChunkingPolicy& policy
) {
    validate_policy(policy);
    // The proven seed compiler remains the single place that maps render
    // semantics, feature edges and imported proxy parts into cache primitives.
    // This overload has three arguments, so it resolves to RuntimeSceneCache.cpp
    // rather than recursively calling the two-argument bounded entry point.
    auto compiled = compile(scene, std::move(source), policy);
    return refine_dense_chunks(std::move(compiled), policy);
}

} // namespace tbe::api::runtime_cache
