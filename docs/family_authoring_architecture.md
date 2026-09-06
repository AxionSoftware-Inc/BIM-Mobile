# Family Authoring boundary

Family Authoring is a separate authoring product inside Tablet BIM. It is not
another wall implementation and it does not edit a project scene directly.

## Boundary

- `apps/viewer_flutter/lib/src/family_authoring/family_document.dart` owns the
  serializable `.bimfamily` contract.
- `family_parameter_resolver.dart` owns deterministic effective parameter
  values and the safe numeric expression language.
- `family_constraint_models.dart` owns persistent reference-plane and sketch
  constraint intent.
- `family_constraint_solver.dart` resolves stable point identities, exact
  coordinate constraints and deterministic dimensional/segment constraints
  into transient solved sketches used by real geometry evaluation.
- `family_csg.dart` owns closed-manifold solid union/subtraction.
- `family_validation.dart` is the semantic gate before save/import/placement.
- `family_file_store.dart` owns validated persistence and local Library state.
- `family_editor_v2_page.dart` is the single production authoring surface for
  both new and existing library assets.
- `family_constraints_panel.dart` is the tablet authoring UI for reference
  planes and geometric constraints.
- `family_library_dialog.dart` owns search, filters, type choice, favorites,
  recents, cached previews and edit-existing-family workflow.
- `family_instance_adapter.dart` is the project boundary and shared resolver
  facade used by placement and Inspector code.

The family contract has four independent layers:

1. Family metadata and category (`Generic Model`, `Column`, `Door`, `Window`,
   `Wall Sweep`, `Furniture`, `Casework`, `Stair`, `Structural`).
2. Parameter definitions and named Family Types. A type supplies values for
   reusable parameters; it is not a separate geometry copy.
3. Sketch intent: stable points, formula-driven reference planes and geometric
   constraints.
4. An ordered feature graph for profile, extrude, revolve, transform, boolean
   union/subtract and freeform mesh.

## Schema v5 and compatibility

`FamilyDocument.currentSchemaVersion` is 5. Schema v1 through v4 remain
readable. Future schema versions are rejected rather than guessed. Any authored
edit is written using schema v5.

Schema evolution:

- **v1**: family/type/feature/sketch core.
- **v2**: optional numeric parameter formulas.
- **v3**: formula-driven reference planes plus Horizontal, Vertical,
  Coincident and Point-on-reference-plane constraints.
- **v4**: formula-driven Distance and Angle targets plus Parallel,
  Perpendicular and Equal-length segment relations.
- **v5**: stable sketch-point identities and ID-first constraint references.
  Legacy point indexes remain compatibility snapshots only.

Old assets do not need an up-front migration. When a v1-v4 sketch is loaded,
points without ids receive deterministic ids such as `profile:point-0`, and
legacy index-only constraints are hydrated with those ids. The loaded document
keeps its original schema number until the first authored edit, then saves as
v5.

## Stable sketch topology identity

`FamilySketchPoint.id` is the persistent identity of a point. In schema v5,
`FamilySketchConstraint` stores both:

- `point_a_id` / `point_b_id` / `point_c_id` / `point_d_id` — authoritative;
- `point_a` / `point_b` / `point_c` / `point_d` — legacy/recovery snapshots.

The solver resolves a stable id first. A snapshot index is used only when a
stable id is absent. Therefore a point reorder does not move a constraint to a
different semantic point. Missing stable ids are explicit errors and duplicate
point ids are rejected by validation.

Constraint authoring stabilizes point ids before it creates the constraint.
Sketch point editing preserves an existing id when a drag supplies new X/Y
coordinates. Solved profiles preserve ids as well; the solver never bakes a new
identity into transient geometry.

This is sufficient for the current point/line sketch model and makes future
insert/reorder/delete authoring safe as long as those operations preserve the
point object's id. First-class curve/edge topology ids are a separate future
extension because arcs and splines do not exist in the current sketch contract.

## Numeric formulas

The supported numeric expression language is deliberately small and
deterministic:

- numeric literals and parameter ids;
- `+`, `-`, `*`, `/`, parentheses and unary `+/-`;
- constant `pi`;
- `min(a,b)`, `max(a,b)`, `abs(x)` and `clamp(x,min,max)`.

Parameter formulas may drive `length`, `number` and `angle` parameters.
Reference-plane offsets, Distance targets and Angle targets use the same safe
resolver. Examples include `-width / 2`, `width / 2`, `height`, `width * 0.25`
and `clamp(angleParam, 0, 180)`.

Expressions cannot call Dart, access files/network, mutate state or depend on
text/material/boolean values. The resolver rejects unknown ids, cycles,
division by zero, invalid ranges and non-finite results.

The semantic path is shared:

```text
Family Type values
        -> FamilyParameterResolver
        -> reference-plane / distance / angle expressions
        -> stable point resolution
        -> FamilyConstraintSolver
        -> solved profile geometry
        -> FamilyGeometryEvaluator
        -> FamilyPlanSymbolGenerator
        -> FamilyInstanceAdapter/native creation
        -> Project Inspector edits
        -> persisted effective instance values
```

Do not bypass `FamilyParameterResolver` or
`FamilyInstanceAdapter.resolvedValues` and read `type.values` directly for an
effective dimension. That would make plan, 3D and persisted instances disagree.

## Geometric constraints

Reference planes are sketch-scoped and fix one coordinate:

- `axis: x` describes a vertical plane at a formula-driven X offset;
- `axis: y` describes a horizontal plane at a formula-driven Y offset.

Exact coordinate constraints:

- **Horizontal**: two points share Y.
- **Vertical**: two points share X.
- **Coincident**: two points share X and Y.
- **Point on reference plane**: one point's X or Y is pinned to a plane.

Dimensional/segment constraints:

- **Distance**: distance AB equals a Family Type expression.
- **Parallel**: segment AB is parallel to CD.
- **Perpendicular**: segment AB is perpendicular to CD.
- **Equal length**: CD is projected to the length of AB.
- **Angle**: unsigned angle AB↔CD equals a formula-driven 0…180° target.

`FamilyConstraintSolver` first resolves all stable point ids. X/Y equality
constraints and fixed reference-plane coordinates are then solved exactly.
Stage-2 dimensional/segment constraints are projected deterministically,
Stage-1 is reapplied after every pass, and residuals are checked. The current
solver uses at most 64 passes with a `1e-6` residual budget. A system that
cannot satisfy both layers is rejected as **over-constrained**, not silently
averaged into plausible-looking geometry.

Distance must be positive. Angle must resolve to 0…180°. Zero-length source
segments are rejected. Every target expression resolves independently for each
Family Type, so changing a type can move planes and dimensions through the
same semantic path.

Unfixed exact equality groups use the deterministic average of authored raw
coordinates. Constraint intent remains persistent while solved coordinates are
transient. `FamilyGeometryEvaluator.evaluate()` and `evaluateMesh()` solve
sketches before profile/extrude/revolve evaluation, so constraints drive actual
3D geometry and Inspector regeneration rather than editor-only metadata.

### Constraint authoring UX

Advanced Family Editor supports:

- add/edit/delete reference planes;
- live resolved plane offsets for the selected Family Type;
- Horizontal, Vertical, Coincident and Point-on-plane constraints;
- formula-driven Distance and Angle constraints;
- Parallel, Perpendicular and Equal-length relations between explicit segments;
- Point A/B/C/D selection;
- one-click **Parametric rectangle**:
  - left = `-width / 2`
  - right = `width / 2`
  - bottom = `0`
  - top = `height`
- solved sketch rendering so constrained points visually snap to their solved
  position.

Clearing a profile removes its point constraints, avoiding ghost references.
Reference planes may remain and can be reused after points are redrawn.

## Exact solid booleans

`family_csg.dart` provides dependency-free BSP union and subtraction for closed,
orientable two-manifold meshes. Boolean feature nodes consume exactly two
explicit earlier solid inputs in graph order.

Before BSP evaluation the kernel validates finite vertices/indices, checks that
each boundary edge belongs to exactly two faces, propagates consistent face
orientation, orients disconnected shells outward by signed volume and rejects
zero-volume/non-orientable/open topology.

Successful boolean evaluation returns `isApproximate == false`. If an imported
mesh cannot satisfy the solid contract, the editor keeps a safe approximate
preview: union shows both operands and subtraction keeps the left operand.
Invalid topology is never silently presented as exact CSG.

## Authoring UX

The editor has two user levels without splitting the file format:

- **Simple**: identity/category/description, named type choice, all declared type
  values and GLB/glTF import. Ordinary furniture/equipment can become reusable
  content without Dart changes or an app rebuild.
- **Advanced**: type duplicate/rename/delete, parameter definitions, formulas,
  touch profile editing, reference planes, constraints, extrude, revolve,
  transform, exact manifold union/subtract and feature graph.

Parameter controls are generated from `FamilyParameterDefinition`. Core
width/depth/height remain length parameters and cannot be removed because they
are the stable sizing contract for evaluators/placement.

Metadata and ordinary type values update while the user types. Save does not
depend on pressing Enter. Formula fields are read-only at the type-value layer
and show their effective computed value.

The same editor edits existing `FamilyAssetFile`s in place. GLB/glTF import
while editing intentionally starts a new family asset rather than overwriting
the original.

## Library

Family Library supports:

- full-text search across family name, description, category, type and parameter
  labels;
- category filtering;
- persistent Favorites and Recent scopes;
- family/type mesh preview cache;
- explicit Family Type choice before placement;
- direct Edit Family and disk reload/cache invalidation;
- selected type carried into placement rather than silently using
  `document.types.first`;
- Android external `.bimfamily` import copied into app-owned reusable storage.

Favorites and recents live in `.family_library_state.json`; writes are
serialized and corrupt state is ignored. Family identity is stable `family.id`,
not filename. Saving a renamed family updates the asset with that id rather than
creating a duplicate.

Every disk family is semantically validated. Invalid external assets cannot
cross into project placement.

## Validation invariants

Before save/import/placement, validation checks at least:

- supported schema version;
- non-empty family name, type list and feature list;
- unique parameter/type/feature/sketch/reference-plane/constraint ids;
- duplicate non-empty sketch point ids;
- stable constraint point ids or valid legacy index fallbacks;
- unique Family Type names;
- parameter kinds/defaults/ranges/formulas;
- each Family Type's resolved parameter values;
- formula cycles, unknown references and invalid arithmetic;
- reference-plane ownership and expressions;
- two-point/two-segment operand integrity;
- Distance/Angle targets and numeric domains per Family Type;
- no incompatible plane/expression/segment fields;
- every Family Type can solve every constrained sketch inside residual budget;
- feature dependency existence/order;
- solid-only transform/boolean inputs;
- exactly two distinct earlier solids for each boolean;
- closed profiles for extrude/revolve;
- freeform mesh vertex/face/index validity and size limits.

Keep this semantic gate at the file/project boundary even when Editor already
prevents the same error. External files do not pass through Editor.

## Project integration and Inspector

Project instances reference a family asset and stable type id, then persist
placement plus effective instance values. They do not copy the family feature
graph into every placed element.

`family_instance_adapter.dart` resolves the selected type and evaluates family
geometry before native mutation. Invalid formulas or constraints fail before
placement. Door/Window use hosted-opening paths, Wall Sweep projects to its host
wall, and supported free-standing families use native analytical elements or a
family proxy mesh.

Inspector reconstructs the selected Family Type, evaluates the same family
geometry path and persists effective values. Changing a dependency can move a
reference plane, solve a sketch, rebuild 3D geometry and update plan graphics
through one path.

The Library's selected type is an in-memory placement preference; the source
family file is not reordered merely to place a type.

## Blender mesh import

The editor imports glTF 2.0 GLB/glTF mesh primitives, indices and node
transforms, centres geometry on X/Z, puts the lowest point on the family ground
plane and creates a scalable `freeformMesh` family. TRIANGLES,
TRIANGLE_STRIP and TRIANGLE_FAN primitive handling is explicit. Legacy OBJ
parsing remains available programmatically.

The current project/native family-proxy boundary carries vertices and triangle
indices. It does **not** carry UV sets, material slots or texture resources.
Therefore material/texture preservation is intentionally not claimed by the
importer alone; real support requires a renderer-capable mesh contract all the
way through the project/native boundary.

## Important production limits — do not fake these

These are separate subsystems, not hidden unfinished switches in Family Editor:

1. **Curve topology**. Stable point identity is implemented. First-class arcs,
   splines, curve/edge ids and tangent/curve constraints do not exist yet.
2. **Nested families**. A production implementation needs child-family identity,
   type/version dependencies, transforms, cycle detection and an async
   dependency-resolution boundary feeding the synchronous geometry evaluator.
3. **Material/texture rendering**. Current proxy ABI is position/index-only.
   UVs, normals, material slots, image resources and Filament lifecycle need a
   cross-layer renderer contract before GLB material preservation can be real.
4. **Large repeated-instance device certification**. The reference model avoids
   per-instance feature graph copies, but large tablet scenes still need measured
   performance budgets on target devices.

## Regression expectations

At minimum, family changes should preserve:

1. Library -> search/filter -> family -> type -> Place;
2. selected type remains selected in placement;
3. Edit Family -> Save -> return -> same family reloads from disk;
4. rename existing family -> stable id updates one asset;
5. formula dependency change -> 3D/plan/Inspector/effective values agree;
6. cyclic/unknown/invalid formulas cannot save/place;
7. exact CSG on closed solids returns non-approximate geometry; open topology is
   rejected by exact kernel;
8. boolean graph requires exactly two explicit earlier solids;
9. Parametric rectangle follows width/height;
10. Distance/Parallel/Perpendicular/Equal-length/Angle solve inside budget;
11. incompatible fixed planes + dimensions are rejected as over-constrained;
12. v1-v4 point-index constraints load with deterministic stable ids and first
    authored save becomes v5;
13. point reorder preserves constraint semantics by stable id even when snapshot
    indexes are stale;
14. duplicate point ids are rejected;
15. invalid external `.bimfamily` cannot enter reusable library;
16. GLB/glTF -> save -> reopen -> place repeatedly;
17. corrupt/missing favorite/recent state does not break assets.
