#pragma once

#include "tbe/api/EngineApi.hpp"

#include <cstdint>
#include <optional>
#include <string>

namespace tbe::api::runtime_cache {

inline constexpr std::uint32_t kBimCacheFormatVersion = 1;

BimCacheSourceDTO source_signature(const std::string& source_ifc_path);
BimCacheSceneDTO compile(const RenderSceneDTO& scene, BimCacheSourceDTO source);
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
