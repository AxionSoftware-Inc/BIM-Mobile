# Family Authoring boundary

Family Authoring is a separate authoring product inside Tablet BIM. It is not
another wall implementation and it does not edit a project scene directly.

## Boundary

- `apps/viewer_flutter/lib/src/family_authoring/family_document.dart` owns the
  serializable family contract.
- `family_file_store.dart` owns `.bimfamily` file persistence.
- `family_editor_page.dart` owns the first authoring surface.
- `family_authoring_module.dart` is the only entry point used by the start
  screen. The project editor does not need to know the family document shape.

The family contract has three independent layers:

1. Family metadata and category (`Generic Model`, `Column`, `Door`, `Window`,
   and future categories).
2. Parameter definitions and named Family Types. A type supplies values for
   the reusable parameters; it is not a separate copy of the geometry.
3. An ordered feature graph. The graph already reserves semantic operations
   for profile, extrude, revolve, transform, boolean union/subtract, and
   freeform mesh. Geometry evaluation will be added behind this contract.

## Project integration rule

Project instances should reference a family asset and a type id, then store
only placement and instance overrides. They must not copy the family feature
graph into every placed element. This keeps thousands of identical objects
cheap and makes a family update deterministic.

The project-side adapter is the only integration point:

```text
FamilyDocument + type id
        -> Family evaluator
        -> project instance mesh / bounds / pick proxy
```

`family_instance_adapter.dart` is deliberately outside the
`family_authoring/` package. It translates a validated family type into the
existing native creation gateways and writes only a family/type reference on
the project element. Column is currently created as a native parametric
column; Door and Window use the existing hosted-opening creation path. Other
categories fail with an explicit unsupported-category message instead of
silently creating an unrelated project element.

If Family Authoring is disabled or removed, the project editor can keep a
lightweight proxy for existing instances. No project scene serializer or wall
logic should be imported into the family module.

## Delivery stages

- Stage 1: independent file contract, named types, parametric box preview,
  start-screen entry, and save boundary.
- Stage 2: touch profile canvas with point editing and explicit close,
  parametric extrude, and an engine-independent preview evaluator.
- Stage 3: revolve, transform and boolean feature nodes, document
  validation before save, local undo/redo history, and an isolated mesh
  evaluator for box/extrude/revolve/transform. Boolean results are explicitly
  marked approximate until the exact CSG kernel is connected.
- Stage 4 (current, partial): project placement/reference adapter, Android
  app-owned family library, family reload and repeated-instance reference
  semantics. Column placement is the first supported family workflow; Door and
  Window are mapped to the existing hosted-opening path. Remaining work is
  sketch constraints, freeform mesh editing, exact CSG, instance overrides and
  performance tests for repeated instances.
