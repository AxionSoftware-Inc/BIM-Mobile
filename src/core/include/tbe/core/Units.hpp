#pragma once

#include <string>
#include <string_view>

namespace tbe::core {

enum class UnitSystem {
    Metric,
    Imperial,
};

enum class LengthUnit {
    Millimeter,
    Centimeter,
    Meter,
    Inch,
    Foot,
};

struct UnitSettings {
    UnitSystem system{UnitSystem::Metric};
    LengthUnit length{LengthUnit::Meter};
    std::string angle{"degrees"};
};

[[nodiscard]] double length_to_meters(double value, LengthUnit unit) noexcept;
[[nodiscard]] double meters_to_length(double value, LengthUnit unit) noexcept;
[[nodiscard]] std::string_view unit_system_to_string(UnitSystem system) noexcept;
[[nodiscard]] std::string_view length_unit_to_string(LengthUnit unit) noexcept;
[[nodiscard]] UnitSystem string_to_unit_system(std::string_view value) noexcept;
[[nodiscard]] LengthUnit string_to_length_unit(std::string_view value) noexcept;

} // namespace tbe::core
