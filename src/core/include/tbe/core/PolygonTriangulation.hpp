#pragma once

#include "tbe/core/Element.hpp"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace tbe::core {

namespace detail {

inline constexpr double polygon_triangulation_epsilon = 1.0e-9;

inline double triangle_cross(Point2 first, Point2 second, Point2 third) {
    return (second.x - first.x) * (third.y - first.y) -
        (second.y - first.y) * (third.x - first.x);
}

inline double polygon_signed_area_for_triangulation(
    const std::vector<Point2>& polygon
) {
    auto area = 0.0;
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        const auto& current = polygon[index];
        const auto& next = polygon[(index + 1) % polygon.size()];
        area += (current.x * next.y) - (next.x * current.y);
    }
    return area * 0.5;
}

inline bool point_in_or_on_ccw_triangle(
    Point2 point,
    Point2 first,
    Point2 second,
    Point2 third
) {
    return triangle_cross(first, second, point) >=
            -polygon_triangulation_epsilon &&
        triangle_cross(second, third, point) >=
            -polygon_triangulation_epsilon &&
        triangle_cross(third, first, point) >=
            -polygon_triangulation_epsilon;
}

} // namespace detail

/// Triangulates a simple polygon without assuming it is convex.
///
/// A triangle fan is not valid for a concave boundary because its diagonals
/// can pass through a notch. Ear clipping keeps every generated triangle
/// inside the authored contour and preserves the original vertex indices.
inline std::vector<std::uint32_t> triangulate_simple_polygon(
    const std::vector<Point2>& polygon
) {
    using detail::polygon_triangulation_epsilon;
    using detail::point_in_or_on_ccw_triangle;
    using detail::polygon_signed_area_for_triangulation;
    using detail::triangle_cross;

    if (polygon.size() < 3) {
        return {};
    }

    std::vector<std::size_t> ring;
    ring.reserve(polygon.size());
    for (std::size_t index = 0; index < polygon.size(); ++index) {
        ring.push_back(index);
    }

    // Collinear vertices remain in the mesh for exact side faces but are not
    // needed in the top/bottom triangulation ring.
    bool removed_collinear = true;
    while (removed_collinear && ring.size() > 3) {
        removed_collinear = false;
        for (std::size_t index = 0; index < ring.size(); ++index) {
            const auto previous = polygon[ring[(index + ring.size() - 1) % ring.size()]];
            const auto current = polygon[ring[index]];
            const auto next = polygon[ring[(index + 1) % ring.size()]];
            if (std::abs(triangle_cross(previous, current, next)) <=
                polygon_triangulation_epsilon) {
                ring.erase(ring.begin() + static_cast<std::ptrdiff_t>(index));
                removed_collinear = true;
                break;
            }
        }
    }
    if (ring.size() < 3) {
        return {};
    }

    if (polygon_signed_area_for_triangulation(polygon) < 0.0) {
        std::reverse(ring.begin(), ring.end());
    }

    std::vector<std::uint32_t> triangles;
    triangles.reserve((ring.size() - 2) * 3);
    while (ring.size() > 3) {
        bool found_ear = false;
        for (std::size_t index = 0; index < ring.size(); ++index) {
            const auto previous_index = ring[(index + ring.size() - 1) % ring.size()];
            const auto current_index = ring[index];
            const auto next_index = ring[(index + 1) % ring.size()];
            const auto previous = polygon[previous_index];
            const auto current = polygon[current_index];
            const auto next = polygon[next_index];

            if (triangle_cross(previous, current, next) <=
                polygon_triangulation_epsilon) {
                continue;
            }

            bool contains_vertex = false;
            for (const auto candidate_index : ring) {
                if (candidate_index == previous_index ||
                    candidate_index == current_index ||
                    candidate_index == next_index) {
                    continue;
                }
                if (point_in_or_on_ccw_triangle(
                        polygon[candidate_index], previous, current, next)) {
                    contains_vertex = true;
                    break;
                }
            }
            if (contains_vertex) {
                continue;
            }

            triangles.push_back(static_cast<std::uint32_t>(previous_index));
            triangles.push_back(static_cast<std::uint32_t>(current_index));
            triangles.push_back(static_cast<std::uint32_t>(next_index));
            ring.erase(ring.begin() + static_cast<std::ptrdiff_t>(index));
            found_ear = true;
            break;
        }
        if (!found_ear) {
            // Validated simple polygons always have an ear. Avoid emitting a
            // malformed fan if invalid external data reaches this helper.
            return {};
        }
    }

    if (triangle_cross(
            polygon[ring[0]], polygon[ring[1]], polygon[ring[2]]) <=
        polygon_triangulation_epsilon) {
        return {};
    }
    triangles.push_back(static_cast<std::uint32_t>(ring[0]));
    triangles.push_back(static_cast<std::uint32_t>(ring[1]));
    triangles.push_back(static_cast<std::uint32_t>(ring[2]));
    return triangles;
}

} // namespace tbe::core
