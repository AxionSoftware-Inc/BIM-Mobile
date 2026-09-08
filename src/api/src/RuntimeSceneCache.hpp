#pragma once

#include "tbe/api/EngineApi.hpp"

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>

namespace tbe::api::runtime_cache {

inline constexpr std::uint32_t kBimCacheFormatVersion = 3;
// Bumped when cached render geometry or the interactive chunk/proxy policy
// changes. Existing device caches must be rebuilt so stale wall/opening meshes
// or legacy opening-profile texture hints cannot survive an APK update.
inline constexpr std::uint32_t kBimCacheSceneCompilerVersion = 14;
inline constexpr std::uint32_t kBimCacheObjectMappingVersion = 4;
inline constexpr std::uint32_t kBimCacheFormatFlags = 0x00000001u;

// A 24 m seed tile gives the compiler a predictable spatial starting point,
// but it is deliberately policy rather than a permanent format rule. Dense
// tiles are refined after seed compilation using these hard element/triangle/
// GPU-buffer limits while keeping the serialized cache contract stable.
struct BimCacheChunkingPolicy {
    double seed_tile_size_meters{24.0};
    std::size_t max_elements_per_chunk{4096};
    std::size_t max_triangles_per_chunk{250000};
    std::size_t max_gpu_buffer_bytes{16ull * 1024ull * 1024ull};
};

BimCacheSourceDTO source_signature(const std::string& source_ifc_path);

// Production/default entry point. Seed chunks are compiled first, then dense
// chunks are spatially refined so no resident GPU chunk can grow without the
// policy's element/triangle/buffer bounds.
BimCacheSceneDTO compile(
    const RenderSceneDTO& scene,
    BimCacheSourceDTO source
);

// Explicit bounded entry point for tests, benchmarks and future device-specific
// policies. This is the preferred API when a non-default policy is required.
BimCacheSceneDTO compile_bounded(
    const RenderSceneDTO& scene,
    BimCacheSourceDTO source,
    const BimCacheChunkingPolicy& policy
);

// Low-level seed compiler retained in RuntimeSceneCache.cpp. Callers should use
// compile()/compile_bounded(); this overload exists so the refinement layer can
// reuse the proven seed compiler without duplicating IFC/cache semantics.
BimCacheSceneDTO compile(
    const RenderSceneDTO& scene,
    BimCacheSourceDTO source,
    const BimCacheChunkingPolicy& policy
);

// Traverses the cache's chunk BVH, then precise cached triangles. Coordinates
// use the engine's X/Y-plan/Z-up convention. The bit mask uses ApiElementKind
// ordinals and lets a renderer respect its currently visible categories.
std::optional<ElementIdDTO> pick(
    const BimCacheSceneDTO& scene,
    const Vec3& ray_origin,
    const Vec3& ray_direction,
    std::uint64_t visible_kind_mask = UINT64_MAX
);
void write_file(const std::string& cache_path, const BimCacheSceneDTO& scene);
BimCacheSceneDTO read_file(const std::string& cache_path, const std::string& expected_source_ifc_path);
BimCacheStatsDTO stats_for(const BimCacheSceneDTO& scene, std::size_t byte_size, bool source_valid);

} // namespace tbe::api::runtime_cache
