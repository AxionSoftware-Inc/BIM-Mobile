#pragma once

#include <string_view>

namespace tbe::api {

inline constexpr int TBE_RENDER_SCENE_VERSION = 1;
inline constexpr std::string_view TBE_RENDER_SCENE_UNITS = "meters";
inline constexpr std::string_view TBE_RENDER_SCENE_COORDINATE_SYSTEM = "X/Y plan, Z up";

} // namespace tbe::api
