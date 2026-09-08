#include "RuntimeSceneCache.hpp"

#include <algorithm>
#include <cassert>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace {

using namespace tbe::api;

RenderSceneObjectDTO make_quad(std::uint64_t id, double x, double y, double z = 0.0) {
    RenderSceneObjectDTO object;
    object.element_id = {.value = id};
    object.kind = ApiElementKind::Proxy;
    object.level_id = {.value = 1};
    object.bounds = {
        .min = {.x = x, .y = y, .z = z},
        .max = {.x = x + 1.0, .y = y + 1.0, .z = z},
    };
    object.mesh.positions = {
        {.x = x, .y = y, .z = z},
        {.x = x + 1.0, .y = y, .z = z},
        {.x = x + 1.0, .y = y + 1.0, .z = z},
        {.x = x, .y = y + 1.0, .z = z},
    };
    object.mesh.indices = {0, 1, 2, 0, 2, 3};
    object.material_category = "generic";
    return object;
}

RenderSceneObjectDTO make_large_fan(std::uint64_t id, std::size_t triangle_count) {
    RenderSceneObjectDTO object;
    object.element_id = {.value = id};
    object.kind = ApiElementKind::Proxy;
    object.level_id = {.value = 1};
    object.material_category = "generic";
    object.mesh.positions.push_back({.x = 0.0, .y = 0.0, .z = 0.0});
    constexpr double pi = 3.14159265358979323846;
    for (std::size_t index = 0; index <= triangle_count; ++index) {
        const auto angle = (2.0 * pi * static_cast<double>(index)) /
            static_cast<double>(triangle_count);
        object.mesh.positions.push_back({
            .x = 10.0 * std::cos(angle),
            .y = 10.0 * std::sin(angle),
            .z = static_cast<double>(index % 3) * 0.01,
        });
    }
    for (std::size_t index = 0; index < triangle_count; ++index) {
        object.mesh.indices.push_back(0);
        object.mesh.indices.push_back(static_cast<std::uint32_t>(index + 1));
        object.mesh.indices.push_back(static_cast<std::uint32_t>(index + 2));
    }
    object.bounds = {
        .min = {.x = -10.0, .y = -10.0, .z = 0.0},
        .max = {.x = 10.0, .y = 10.0, .z = 0.02},
    };
    object.feature_edges.push_back({
        .start = {.x = -10.0, .y = 0.0, .z = 0.0},
        .end = {.x = 10.0, .y = 0.0, .z = 0.0},
        .role = RenderSceneFeatureEdgeRole::Silhouette,
    });
    return object;
}

std::size_t gpu_bytes(const BimCacheChunkDTO& chunk) {
    return chunk.positions.size() * sizeof(float) +
        chunk.indices.size() * sizeof(std::uint32_t);
}

void assert_policy_limits(
    const BimCacheSceneDTO& cache,
    const tbe::api::runtime_cache::BimCacheChunkingPolicy& policy
) {
    for (const auto& chunk : cache.chunks) {
        assert(chunk.primitives.size() <= policy.max_elements_per_chunk);
        assert(chunk.indices.size() / 3 <= policy.max_triangles_per_chunk);
        assert(gpu_bytes(chunk) <= policy.max_gpu_buffer_bytes);
    }
    if (!cache.chunks.empty()) {
        assert(!cache.bvh_nodes.empty());
        assert(cache.bvh_chunk_indices.size() == cache.chunks.size());
    }
}

BimCacheSourceDTO synthetic_source() {
    return BimCacheSourceDTO{
        .source_path = "synthetic.ifc",
        .source_size_bytes = 1,
        .source_modified_ticks = 1,
        .source_fingerprint = 1,
    };
}

} // namespace

int main() {
    using namespace tbe::api;
    using namespace tbe::api::runtime_cache;

    {
        RenderSceneDTO scene;
        for (std::uint64_t index = 0; index < 12; ++index) {
            // All centers remain in the same 24 m seed tile. The refinement
            // layer, not the seed-grid hash, must enforce the element cap.
            scene.objects.push_back(make_quad(index + 1, 1.0 + index * 0.25, 1.0));
        }
        scene.object_count = scene.objects.size();
        scene.vertex_count = scene.objects.size() * 4;
        scene.index_count = scene.objects.size() * 6;

        const BimCacheChunkingPolicy policy{
            .seed_tile_size_meters = 24.0,
            .max_elements_per_chunk = 3,
            .max_triangles_per_chunk = 100,
            .max_gpu_buffer_bytes = 1024 * 1024,
        };
        const auto cache = compile_bounded(scene, synthetic_source(), policy);
        assert(cache.chunks.size() >= 4);
        assert_policy_limits(cache, policy);
        std::size_t primitive_count = 0;
        std::size_t index_count = 0;
        for (const auto& chunk : cache.chunks) {
            primitive_count += chunk.primitives.size();
            index_count += chunk.indices.size();
        }
        assert(primitive_count == scene.objects.size());
        assert(index_count == scene.index_count);
    }

    {
        RenderSceneDTO scene;
        scene.objects.push_back(make_large_fan(99, 30));
        scene.object_count = 1;
        scene.vertex_count = scene.objects.front().mesh.positions.size();
        scene.index_count = scene.objects.front().mesh.indices.size();

        const BimCacheChunkingPolicy policy{
            .seed_tile_size_meters = 24.0,
            .max_elements_per_chunk = 4,
            .max_triangles_per_chunk = 4,
            .max_gpu_buffer_bytes = 2048,
        };
        const auto cache = compile_bounded(scene, synthetic_source(), policy);
        assert(cache.chunks.size() >= 8);
        assert_policy_limits(cache, policy);

        std::size_t total_indices = 0;
        std::size_t total_feature_edges = 0;
        for (const auto& chunk : cache.chunks) {
            total_indices += chunk.indices.size();
            for (const auto& primitive : chunk.primitives) {
                assert(primitive.element_id.value == 99);
                total_feature_edges += primitive.feature_edges.size();
            }
        }
        assert(total_indices == scene.index_count);
        // A split primitive must not duplicate authored edge lines.
        assert(total_feature_edges == 1);
    }

    {
        // Production uses the two-argument compile(scene, source) overload.
        // Exceed its default 4096-element cap with a compact synthetic tile so
        // this test catches accidental routing back to the seed-only compiler.
        RenderSceneDTO scene;
        constexpr std::size_t object_count = 4100;
        scene.objects.reserve(object_count);
        for (std::size_t index = 0; index < object_count; ++index) {
            auto object = make_quad(static_cast<std::uint64_t>(index + 1), 1.0, 1.0);
            // One triangle is sufficient here and keeps the regression fast.
            object.mesh.indices = {0, 1, 2};
            scene.objects.push_back(std::move(object));
        }
        scene.object_count = scene.objects.size();
        scene.vertex_count = scene.objects.size() * 4;
        scene.index_count = scene.objects.size() * 3;

        const auto cache = compile(scene, synthetic_source());
        const BimCacheChunkingPolicy defaults{};
        assert(cache.chunks.size() >= 2);
        assert_policy_limits(cache, defaults);
    }

    return 0;
}
