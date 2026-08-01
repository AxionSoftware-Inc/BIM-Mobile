# Quantity Correctness

This note records the quantity formulas currently used by the engine MVP so tests and CLI torture modes can verify the same math.

## Wall quantities

- Wall length comes from the wall axis.
- Gross wall area is `length * height`.
- Opening area is `width * height` for each hosted opening.
- Net wall area is `max(0, gross - openings)`.
- Wall volume is based on the wall thickness and net wall area.
- Wall assembly layer volume is `net_area * layer_thickness`.
- Assemblies remain the ordered semantic source of truth. Interactive viewport
  geometry uses one lightweight wall envelope; explicit layered mesh detail is
  available to core authoring/tests without being required for quantities.

## Opening quantities

- Door/window area is `width * height`.
- Host wall id and level id are preserved through save/load and scheduling.

## Room quantities

- Centerline area comes from the room solver boundary polygon.
- Interior area comes from the interior finish-face boundary polygon.
- Floor finish area and ceiling area currently mirror interior area.
- Baseboard length mirrors interior perimeter.

## Floor and ceiling systems

- Layer quantity is stored as volume: `area * layer_thickness`.
- Material takeoff aggregates floor and ceiling quantities by material id and quantity type.

## Slabs, roofs, columns, beams, stairs

- Slab volume is `boundary_area * thickness`.
- Layered slab volume is aggregated per material as
  `boundary_area * layer_thickness`; the first assembly layer is the bottom
  layer and the last is the top layer.
- Flat roof volume is `roof_area * thickness`.
- Column volume is `width * depth * height`.
- Beam volume is `length * width * height`.
- Straight stair volume is currently a simple prism estimate derived from footprint and rise.

## Tolerance and validation

- Small floating-point differences are expected and tests use tolerant comparisons.
- Negative or near-negative derived quantities are clamped or reported by validation.
- Repeated save/load cycles should remain stable within tolerance.

## Aggregation rules

- Material takeoff rows are grouped by material id and quantity type.
- Area and volume rows are kept separate.
- Slab layer volumes are included in material takeoff alongside walls, floors,
  ceilings and roofs.
- The residential template creates one foundation slab per building and one
  full layered floor slab per storey; it does not also create a duplicate
  floor-system takeoff for the same footprint.
- Estimated cost, when present, is derived from row quantity and material unit cost.
- Report DTOs expose both the material `unit_cost` and the resulting
  `estimated_cost`; missing prices remain missing rather than silently becoming
  zero.

## Deferred computation

- Interactive preview regenerates envelope geometry only and leaves room,
  schedule, validation and material-takeoff data dirty/stale.
- Normal editing may refresh room metrics when requested by the session, but
  schedules and cost takeoff are not part of viewport rendering.
- `FinalExact`/documentation/report APIs perform the exact room, schedule,
  validation and material-cost calculations on demand.

## Known simplifications

- This is still an MVP quantity engine, not a full estimating system.
- Complex professional cases such as waste factors, phase-based takeoff, compound units, and trade-specific rules are not modeled yet.
