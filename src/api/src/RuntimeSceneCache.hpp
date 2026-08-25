#pragma once

#include "tbe/api/EngineApi.hpp"

#include <string>

namespace tbe::api::runtime_cache {

inline constexpr std::uint32_t kBimCacheFormatVersion = 1;

BimCacheSourceDTO source_signature(const std::string& source_ifc_path);
BimCacheSceneDTO compile(const RenderSceneDTO& scene, BimCacheSourceDTO source);
void write_file(const std::string& cache_path, const BimCacheSceneDTO& scene);
BimCacheSceneDTO read_file(const std::string& cache_path, const std::string& expected_source_ifc_path);
BimCacheStatsDTO stats_for(const BimCacheSceneDTO& scene, std::size_t byte_size, bool source_valid);

} // namespace tbe::api::runtime_cache
