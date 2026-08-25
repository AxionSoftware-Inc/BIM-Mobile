#include "tbe/core/Units.hpp"

namespace tbe::core {

double length_to_meters(double value, LengthUnit unit) noexcept {
    switch (unit) {
    case LengthUnit::Millimeter: return value * 0.001;
    case LengthUnit::Centimeter: return value * 0.01;
    case LengthUnit::Meter: return value;
    case LengthUnit::Inch: return value * 0.0254;
    case LengthUnit::Foot: return value * 0.3048;
    }
    return value;
}

double meters_to_length(double value, LengthUnit unit) noexcept {
    switch (unit) {
    case LengthUnit::Millimeter: return value * 1000.0;
    case LengthUnit::Centimeter: return value * 100.0;
    case LengthUnit::Meter: return value;
    case LengthUnit::Inch: return value / 0.0254;
    case LengthUnit::Foot: return value / 0.3048;
    }
    return value;
}

std::string_view unit_system_to_string(UnitSystem system) noexcept {
    return system == UnitSystem::Imperial ? "imperial" : "metric";
}

std::string_view length_unit_to_string(LengthUnit unit) noexcept {
    switch (unit) {
    case LengthUnit::Millimeter: return "millimeter";
    case LengthUnit::Centimeter: return "centimeter";
    case LengthUnit::Meter: return "meter";
    case LengthUnit::Inch: return "inch";
    case LengthUnit::Foot: return "foot";
    }
    return "meter";
}

UnitSystem string_to_unit_system(std::string_view value) noexcept {
    return value == "imperial" ? UnitSystem::Imperial : UnitSystem::Metric;
}

LengthUnit string_to_length_unit(std::string_view value) noexcept {
    if (value == "millimeter") return LengthUnit::Millimeter;
    if (value == "centimeter") return LengthUnit::Centimeter;
    if (value == "inch") return LengthUnit::Inch;
    if (value == "foot") return LengthUnit::Foot;
    return LengthUnit::Meter;
}

} // namespace tbe::core
