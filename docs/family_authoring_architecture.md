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
- `family_constraint_solver.dart` solves exact coordinate constraints plus
  deterministic dimensional/segment constraints into transient solved sketches
  used by real geometry evaluation.
- `family_csg.dart` owns closed-manifold solid union/subtraction.
- `family_validation.dart` is the semantic gate before save/import/placement.
- `family_file_store.dart` owns validated persistence and local Library state.
- `family_editor_v2_page.dart` is the single production authoring surface for
  both new and existing library assets.
- `family_constraints_panel.dart` is the tablet authoring UI for reference
  planes and geometric constraints.
- `family_library_dialog.dart` owns search, filters, type choice, favorites,
  recents, cached previews and the edit-existing-family workflow.
- `family_instance_adapter.dart` is the project boundary and the shared resolver
  facade used by placement and Inspector code.

The family contract has four independent layers:

1. Family metadata and category (`Generic Model`, `Column`, `Door`, `Window`,
   `Wall Sweep`, `Furniture`, `Casework`, `Stair`, `Structural`).
2. Parameter definitions and named Family Types. A type supplies values for
   reusable parameters; it is not a separate geometry copy.
3. Sketch intent: raw points, formula-driven reference planes and geometric
   constraints.
4. An ordered feature graph for profile, extrude, revolve, transform, boolean
   union/subtract and freeform mesh.

## Schema v4 and compatibility

`FamilyDocument.currentSchemaVersion` is 4. Schema v1, v2 and v3 remain
readable. Future schema versions are rejected instead of being guessed at. Any
authored edit is written back using schema v4.

Schema evolution:

- **v1**: family/type/feature/sketch core.
- **v2**: optional numeric parameter formulas.
- **v3**: formula-driven reference planes plus Horizontal, Vertical,
  Coincident and Point-on-reference-plane constraints.
- **v4**: formula-driven Distance and Angle targets plus Parallel,
  Perpendicular and Equal-length segment relations.

Old family assets do not need migration before opening. Missing newer fields
mean the older feature is simply absent. The first authored save rewrites the
asset in the current schema.

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

A formula-driven parameter ignores its own stale per-type override. Its
dependencies still read the selected Family Type. This rule is shared by:

```text
Family Type values
        -> FamilyParameterResolver
        -> reference-plane / distance / angle expressions
        -> FamilyConstraintSolver
        -> solved profile geometry
        -> FamilyGeometryEvaluator
        -> FamilyPlanSymbolGenerator
        -> FamilyInstanceAdapter/native creation
        -> Project Inspector edits
        -> persisted effective instance values
```

Do not bypass `FamilyParameterResolver`/`FamilyInstanceAdapter.resolvedValues`
in a new geometry/placement/Inspector path and read `type.values` directly for
an effective dimension. Doing so would make plan, 3D and saved project
instances disagree.

## Geometric constraints

Reference planes are sketch-scoped and fix one coordinate:

- `axis: x` describes a vertical reference plane at a formula-driven X offset;
- `axis: y` describes a horizontal reference plane at a formula-driven Y
  offset.

Exact coordinate constraints are:

- **Horizontal**: two points share Y.
- **Vertical**: two points share X.
- **Coincident**: two points share both X and Y.
- **Point on reference plane**: one point's X or Y is pinned to the plane's
  resolved expression.

Dimensional/segment constraints are:

- **Distance**: distance between Point A and Point B equals a Family Type
  expression.
- **Parallel**: segment AB is parallel to segment CD.
- **Perpendicular**: segment AB is perpendicular to segment CD.
- **Equal length**: segment CD is projected to the length of segment AB.
- **Angle**: the unsigned angle between segment AB and segment CD equals a
  formula-driven value from 0 to 180 degrees.

`FamilyConstraintSolver` first solves X and Y equality graphs and fixed
reference-plane coordinates exactly. It then projects the dimensional/segment
constraints deterministically, re-applies the exact coordinate constraints
after every pass, and checks the residuals. The current solver uses at most 64
passes with a `1e-6` residual budget. A system that cannot satisfy both layers
is rejected as **over-constrained** instead of being silently averaged into an
incorrect shape.

Distance must resolve to a positive value. Angle must resolve to 0…180 degrees.
Zero-length source segments are rejected for segment-direction constraints.
Every target expression is resolved separately for every Family Type, so type
changes can move reference planes and dimensions through one semantic path.

Unfixed exact equality groups use the deterministic average of their authored
raw coordinates. Constraint intent remains persistent while solved coordinates
are transient: geometry evaluation receives a solved document, but the
`.bimfamily` does not replace authored points with baked solved points.

`FamilyGeometryEvaluator.evaluate()` and `evaluateMesh()` solve sketches before
profile/extrude/revolve evaluation. Therefore constraints drive actual 3D
placement and Inspector regeneration; they are not editor-only metadata.
Invalid/incomplete constraints may temporarily show the raw authoring preview,
but `FamilyDocumentValidator` blocks save/import/placement until every Family
Type solves successfully.

### Constraint authoring UX

Advanced Family Editor includes a dedicated constraints panel:

- add/edit/delete reference planes;
- show each plane's live resolved offset for the active Family Type;
- add/delete Horizontal, Vertical, Coincident and Point-on-plane constraints;
- add formula-driven Distance and Angle constraints;
- add Parallel, Perpendicular and Equal-length relations between two explicit
  sketch segments;
- choose Point A/B/C/D explicitly from the active profile;
- one-click **Parametric rectangle** for a four-point profile, creating:
  - left = `-width / 2`
  - right = `width / 2`
  - bottom = `0`
  - top = `height`
- the sketch canvas renders solved points, so a constrained point snaps back to
  its solved coordinate rather than visually pretending the drag broke the
  constraint.

Clearing a profile removes its point constraints so no ghost point references
remain. Reference planes may remain and can be reused after points are redrawn.

## Exact solid booleans

`family_csg.dart` provides dependency-free BSP union and subtraction for closed,
orientable two-manifold meshes. Boolean feature nodes consume exactly two
explicit earlier solid inputs in graph order.

Before BSP evaluation the kernel:

- validates finite vertices and face indices;
- verifies every boundary edge belongs to exactly two faces;
- propagates consistent face orientation across each connected shell;
- orients every disconnected shell outward using signed volume;
- rejects zero-volume/non-orientable/open topology rather than inventing a
  solid result.

Successful boolean evaluation returns `isApproximate == false`. If an imported
or otherwise malformed/open mesh cannot satisfy the solid contract, the editor
keeps a safe approximate preview: union shows both operands and subtraction
keeps the left operand. Exact CSG therefore never silently turns invalid
topology into a project solid.

## Authoring UX

The editor has two user levels without splitting the file format:

- **Simple**: name/category/description, named type choice, all declared type
  values and a GLB/glTF import fast path. A chair, table, cabinet or appliance
  can be created as reusable content without writing Dart code.
- **Advanced**: type duplicate/rename/delete, generic parameter-definition
  add/edit/delete, formulas, touch profile editing, reference planes,
  constraints, extrude, revolve, transform, exact manifold union/subtract and
  the feature graph.

Parameter controls are generated from `FamilyParameterDefinition`; the editor
does not assume width/depth/height are the only values. Core dimensions remain
length parameters and cannot be removed because evaluators/placement use them
as the stable sizing contract.

Metadata and ordinary type values update as the user types. Saving does not
depend on pressing Enter or dismissing the keyboard first. Formula-driven type
fields are read-only and show the effective computed value.

The same editor accepts an optional `FamilyAssetFile`. When opened from Library,
Save updates that stable asset path. Importing GLB/glTF while editing
intentionally starts a new family asset rather than overwriting the original.

## Library

The project-side Family Library is designed to scale beyond the curated starter
set:

- full-text search across family name, description, category, type and parameter
  labels;
- category filtering;
- persistent Favorites and Recent scopes;
- family/type mesh preview cache;
- explicit Family Type selection before placement;
- direct Edit Family action, followed by a disk reload and preview-cache
  invalidation;
- selected type is carried into placement instead of silently falling back to
  `document.types.first`;
- imported `.bimfamily` files on Android are copied into app-owned storage, so
  adding reusable content does not require a source-code change or app rebuild.

Favorites and recents live in `.family_library_state.json`. Preference writes
are serialized so rapid taps cannot let an older write overwrite a newer state.
Corrupt preference state is ignored rather than blocking family assets.

Family identity is the stable `family.id`, not the filename. Saving a renamed
family scans the library for that id and updates the existing asset instead of
creating a duplicate under a new display-name filename.

Every family read from disk is semantically validated. Corrupt/invalid assets
are skipped in the catalog and cannot cross into project placement.

## Validation invariants

Before a family is saved, imported or placed, validation checks at least:

- supported schema version;
- non-empty family name, type list and feature list;
- unique parameter/type/feature/sketch/reference-plane/constraint ids;
- unique Family Type names (case-insensitive);
- parameter kinds, defaults, ranges and formula compatibility;
- every selected type's effective resolved values;
- formula cycles, unknown references and invalid arithmetic;
- reference-plane sketch ownership and expression validity;
- two-point and two-segment operand integrity;
- Distance/Angle target expressions and valid numeric domains per Family Type;
- constraints do not carry incompatible plane/expression/segment fields;
- every Family Type can solve every constrained sketch inside the residual
  budget without an over-constraint;
- feature input existence and ordering (feature nodes may only depend on earlier
  feature nodes);
- solid-only input requirements for transforms and booleans;
- exactly two distinct earlier solid inputs for every boolean node;
- closed profiles for extrude/revolve;
- freeform-mesh vertex/face/index validity and size limits.

Keep this validation at the file/project boundary even when the editor already
prevents the same error in its UI. External `.bimfamily` files do not pass
through the editor.

## Project integration and Inspector rule

Project instances reference a family asset and stable type id, then persist
placement plus effective instance values. They must not copy the family feature
graph into every placed element. This keeps repeated objects cheap and the
family asset semantic.

`family_instance_adapter.dart` resolves the full type before native mutation.
If a formula or geometric constraint is invalid, validation fails before a
family instance is placed. Door and Window use the hosted-opening path; Wall
Sweep is projected onto its selected wall; free-standing supported families use
native family/proxy geometry.

Inspector reconstructs the selected Family Type from the asset and stored
instance dependency values, then evaluates the same family geometry path.
Formula-driven fields are read-only in Inspector. Changing a dependency can
therefore move a reference plane, re-solve the sketch, rebuild 3D geometry and
update the plan symbol in one semantic path.

The Library's selected type is an in-memory placement preference. The source
`.bimfamily` is not reordered or rewritten just to place a type.

## Blender mesh import

The editor imports Blender-exported GLB/glTF mesh primitives, indices and node
transforms, centres the model on X/Z, places its lowest point on the family
ground plane, and creates a `freeformMesh` feature with width/depth/height type
values.

On Android, selecting an external `.bimfamily` through **Import family** copies
the validated family into the app-owned reusable library.

## Important production limits — do not fake these

The following remain separate engine/content tasks and are not claimed as
finished merely because data can be stored:

1. **Curve/topology-aware constraints**. Point/line constraints above are real.
   Still missing are tangent/arc/curve relations and stable topology-aware
   point/edge identities. Current constraints reference sketch point indexes;
   this is safe with today's add/move/clear workflow but must be upgraded before
   arbitrary point insertion/reorder/deletion ships.
2. **Nested families**. Child-family dependency/version/transform semantics need
   a real dependency model and synchronous evaluated-child boundary before they
   can safely participate in parent geometry.
3. **GLB material/texture preservation**. Geometry import works; production
   material/texture import, explicit unit selection, decimation and LOD
   generation still require importer/render-contract work.
4. **Large repeated-instance performance certification**. The reference design
   avoids copying feature graphs, but large tablet scenes still require measured
   device regression budgets.

## Regression expectations

At minimum, family changes should preserve these workflows:

1. Library -> search/filter -> family -> type -> Place;
2. selected type remains selected in project placement;
3. Library -> Edit Family -> Save -> return -> same family remains selected and
   preview/type data reload from disk;
4. rename an existing family -> Save -> stable id updates one asset, not a
   duplicate file;
5. create formula parameter -> change its dependency in a Family Type -> 3D,
   plan symbol, Inspector and placed effective values all change consistently;
6. cyclic/unknown/invalid formulas cannot be saved or placed;
7. exact union/subtract on overlapping closed solids produces non-approximate
   geometry with the expected volume; open topology is rejected by the kernel;
8. boolean graph nodes must name exactly two distinct earlier solid operands;
9. four-point Parametric rectangle -> change width/height -> solved profile and
   resulting geometry move with its reference planes;
10. Distance follows its Family Type expression; Parallel, Perpendicular,
    Equal-length and Angle produce geometry inside the residual budget;
11. incompatible fixed reference planes plus dimensional targets are rejected
    as over-constrained;
12. schema-v1/v2/v3 family -> edit -> save -> schema-v4 family remains loadable;
13. external invalid `.bimfamily` cannot enter the reusable library;
14. import GLB/glTF -> save -> reopen -> place repeatedly;
15. favorite/recent state can be missing/corrupt without breaking assets.
