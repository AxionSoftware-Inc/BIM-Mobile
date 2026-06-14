# Level 5 Room Solver Notes

## Current Choice

The engine currently detects rooms from wall centerlines, not wall inner faces.

Why:
- centerlines match the semantic wall model already stored in the core;
- they keep the solver independent from OCCT;
- they are easier to update incrementally after edits, splits, and undo/redo.

Implication:
- reported room area/perimeter are centerline-based space metrics for now;
- future inner-boundary room metrics can be added as a separate pass.

## Solver Shape Support

Current solver:
- supports multiple orthogonal closed loops on the same level;
- supports rooms sharing walls;
- supports repeated detection without duplicating unchanged rooms;
- supports many non-rectangular orthogonal rooms, including simple L-shapes;
- preserves room ids when the same boundary wall set is detected again.

Current limitations:
- assumes axis-aligned orthogonal wall centerlines;
- does not target curved rooms;
- does not yet handle complex holes/courtyards as first-class room interiors;
- room id stability is based on boundary wall identity, not a full topological signature.

## Detection Strategy

The solver builds a level-local orthogonal cell grid from wall endpoint coordinates plus an outside padding ring.

Then it:
- treats wall centerlines as blocking edges between neighboring cells;
- flood-fills open cell connectivity;
- marks components touching the padded outer ring as outside space;
- turns remaining closed components into rooms;
- derives boundary walls, polygon, area, and perimeter from the component boundary.

## Dependency Cache

The document keeps a cached dependency graph plus a version counter.

Invalidation rules:
- wall create/delete/move/split: invalidate graph cache, recompute joins/rooms, mark wall geometry dirty;
- opening create/move/resize/delete: invalidate graph cache, mark host wall geometry dirty;
- room detection: rebuild room elements, then invalidate the dependency cache;
- save/load/restore/remove element operations: invalidate the dependency cache.

The full dependency graph rebuild path is still available through `build_dependency_graph()` for debug and validation.

## Room Lifecycle

Current room lifecycle rules:
- if a detected room has the same ordered boundary wall set key, reuse the previous room id;
- if a previous room is no longer detected, delete it;
- if a room is detected again, recompute `boundary_wall_ids`, `boundary_polygon`, `area`, and `perimeter`;
- `boundary_wall_ids` are stored sorted for stable comparisons;
- invalid rooms are currently removed rather than kept as tombstones.

## Known Unsupported Cases

- non-orthogonal geometry;
- curved walls;
- robust hole/island room topology;
- mixed centerline and finish-face area standards;
- advanced semantic separation where one long wall should behave like several logical boundaries without splits.
