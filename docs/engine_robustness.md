# Engine Robustness

This note tracks the wall, opening, and room cases we currently support well enough for the MVP engine.

## Wall joins

Supported:

- L-corner joins with horizontal/vertical walls in either direction.
- Reversed wall directions.
- Near-equal endpoints within tolerance.
- Repeated `auto_join_walls()` without duplicate joins.
- T-junctions detected from either side of the junction wall.
- Split walls that preserve valid joins where possible.
- Delete and move operations that invalidate or refresh connected joins.

Limited or intentionally simple:

- Crossing `X`-style wall overlaps are not treated as a full structural intersection model.
- Join behavior remains orthogonal/straight-wall focused.
- Very short walls are rejected or reported by validation.

## Openings

Supported:

- Doors/windows hosted on a wall face.
- Openings inside the wall placement interval.
- Clearance-aware placement intervals for local editing helpers.
- Save/load round-trips for hosted openings.
- Moving or resizing an opening marks the host wall dirty.

Validation and repair rules:

- Openings outside the wall body are rejected or reported.
- Overlapping openings are reported.
- Host wall deletion must either remove dependent openings or leave a validation error instead of silently corrupting state.
- Repair can remove orphan openings and fix missing level references when safe.

## Room solver

Supported:

- Simple rectangles.
- Orthogonal multi-room layouts.
- Shared walls between adjacent rooms.
- L-shaped orthogonal rooms.
- Repeated detection without duplicate room creation.

Known limitations:

- The solver is still orthogonal and boundary-graph driven.
- Non-orthogonal room geometry is not a goal here.
- Self-crossing or malformed wall loops are rejected when detected.

## Tolerance rules

- Wall joins use point tolerance to merge near-identical endpoints.
- Placement intervals subtract existing opening spans plus edge clearance.
- Room recompute should keep ids stable when boundaries do not change.

## Slabs, floors, ceilings, roofs, columns, beams, stairs

Supported:

- Rectangular or orthogonal slab boundaries with positive thickness.
- Floor and ceiling systems derived from valid room boundaries.
- Flat roofs over closed building footprints.
- Rectangular columns and beams.
- Straight stairs with positive rise, run, width, riser count, and tread count.

Assumptions and limitations:

- Floor and ceiling systems are room-bound and assembly-driven, not freeform slabs.
- Roof support remains simple and orthogonal; complex pitched roofs are placeholders.
- Columns and beams are rectangular, parametric fallback geometry.
- Stair support is basic straight-run geometry, not a full multi-flight solver.
- Material takeoff is quantity foundation work, not a final estimating engine.

See `docs/quantity_correctness.md` for the current quantity formulas and tolerance rules used by the tests and CLI torture mode.
See `docs/performance_stress.md` for the large-model stress scenarios and diagnostics.

Unsupported or intentionally limited:

- Curved slabs, roofs, beams, or stairs.
- Non-orthogonal room-to-system dependency logic beyond the current MVP.
- Revit-grade opening/roof/stair automation.
