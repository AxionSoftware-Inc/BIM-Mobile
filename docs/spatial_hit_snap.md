# Spatial Hit/Snap Foundation

## Overview

Level 11.5 upgrades the interaction foundation from a simple cached bounds list to a real per-level uniform-grid spatial index. The API remains UI-independent and portable C++20, but queries are now structured for future tablet, desktop, and cloud editing workflows.

## Grid Index Design

- The engine builds a per-level `SpatialIndex2D` cache.
- Each level stores:
  - spatial entries
  - a uniform bucket grid
  - bucket-to-entry index lists
- Each spatial entry stores:
  - element id
  - element kind
  - preferred hit kind
  - 2D AABB
  - optional footprint polygon
  - optional axis line

Indexed categories currently include:

- walls
- doors and windows
- rooms
- slabs
- floor systems
- ceiling systems
- roofs
- columns
- beams
- stairs

Queries use bucket overlap first, then exact candidate filtering on the reduced set.

## Dirty / Rebuild Behavior

- wall create/move/split/delete marks the spatial cache dirty
- opening move/resize marks the cache dirty
- room recompute changes room bounds and invalidates the cache
- slab/floor/ceiling/roof/column/beam/stair edits invalidate the cache
- undo/redo rebuild the cache from restored project JSON
- load/save-final flows rebuild the cache cleanly

Public stats report:

- element count
- bucket count
- average bucket occupancy
- max bucket occupancy
- version
- dirty flag

## Hit Priority Rules

Hit candidates are ordered with stable priority first, then distance:

1. openings
2. columns
3. stairs
4. wall body
5. beams
6. wall axis
7. floor systems
8. ceiling systems
9. slabs
10. roofs
11. room interior fallback

Important behavior:

- room interior is intentionally a low-priority fallback
- floor systems and ceiling systems now use dedicated hit kinds
- element kind and hit kind are reported separately

## Snap Behavior

Supported snap types:

- endpoint
- midpoint
- wall axis
- wall intersection
- grid
- orthogonal projection
- room corner

`SnapOptionsDTO` lets callers enable or disable:

- grid snap
- endpoints
- midpoints
- intersections
- wall-axis snap
- orthogonal projection
- room corners
- custom grid size

This allows stylus-drag and desktop-pointer flows to request only the candidate families they need.

## Placement Interval Solver

`compute_wall_free_intervals()` and the updated `find_wall_host_at_point()` are designed for practical door/window placement.

The solver:

1. projects the requested point onto the wall axis
2. computes a wall-local requested offset
3. subtracts edge clearance from both wall ends
4. subtracts existing opening spans
5. expands blocked spans by placement clearance and requested opening width
6. merges blocked intervals
7. returns the remaining free intervals
8. adjusts to the nearest valid offset when the requested offset is blocked

The placement result reports:

- wall id
- requested offset
- adjusted valid offset
- validity flag
- free intervals
- warning strings

If no legal interval exists, the API returns a non-throwing invalid placement result with warnings instead of pretending placement is valid.

## Performance Notes

- The grid index is still intentionally simple and portable.
- Rebuild cost is acceptable for current MVP document sizes.
- Bucketed querying reduces unnecessary candidate scans compared with the Level 11 full-level vector walk.
- Performance profiles still apply: cached queries can rebuild on demand, while `FinalExact` recompute forces clean derived state.

## Current Limitations

- The grid cell size is fixed and not yet adaptive to model scale.
- Hit testing is still 2D-plan based, without Z-aware disambiguation between floor and ceiling.
- Placement intervals are wall-axis based and do not yet consider asymmetric jamb rules or family-specific constraints.
- Snap solving is geometric and deterministic, but not constraint-driven yet.
- Mesh-aware snapping against detailed generated geometry is still out of scope.
