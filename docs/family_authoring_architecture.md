# Family Authoring boundary

Family Authoring is a reusable-content authoring product inside Tablet BIM. It
owns family documents and geometry intent; it does **not** own another project
renderer, another orbit camera, or another wall implementation.

## Non-negotiable viewport invariant

Family 3D uses the production project viewport:

```text
FamilyDocument / FamilyGeometryEvaluator
        -> FamilyRenderSceneAdapter
        -> RenderScene
        -> RenderSceneViewportController
        -> RenderSceneViewport
        -> Android Filament or project fallback renderer
```

Family sketch navigation also reuses the project plan contracts:

```text
FamilySketch
        -> FamilySketchViewport
        -> RenderSceneViewport(topDown)
        -> project pan/zoom/hit-test
        -> PlanSketchGeometry snapping/inference
```

Do **not** add a second Family-specific 3D orbit camera, renderer, hit-test
implementation or fixed-scale sketch camera. Project viewport fixes must flow
into Family automatically.

Family coordinates are `X = width`, `Y = height/vertical`, `Z = depth`.
RenderScene uses `X/Y` as the plan plane and `Z` as elevation, so the adapter
performs the single axis conversion `(x, z, y)` and fixes winding once at that
boundary.

### Rotation compatibility invariant

The historic serialized transform field is named `rotationZ`. That name is a
schema compatibility artifact; it is **not** the physical Family rotation axis.
User-facing Rotate is plan/yaw rotation around Family `Y`, because Family `Y`
is vertical. Therefore both ordinary Transform features and nested-family
transforms rotate in the Family `X/Z` plane using the same positive-angle
convention.

Do not reinterpret legacy `rotationZ` as an X/Y rotation. Ordinary Transform
may read a future/explicit `rotationY` value first, but current writers continue
to persist `rotationZ` so existing `.bimfamily` files remain compatible.

## Main ownership boundaries

- `family_document.dart` — serializable `.bimfamily` contract.
- `family_parameter_resolver.dart` — deterministic parameter/formula values.
- `family_constraint_models.dart` — persistent sketch constraint intent.
- `family_constraint_solver.dart` — stable-point geometric solving.
- `family_csg.dart` — exact closed-manifold union/subtraction.
- `family_dependency_resolver.dart` — nested-family dependency DAG and cycle
  rejection.
- `family_geometry.dart` — synchronous evaluated family geometry.
- `family_validation.dart` — semantic gate before save/import/placement.
- `family_file_store.dart` — validated local library persistence.
- `family_render_scene_adapter.dart` — final Family mesh -> project RenderScene.
- `family_authoring_scene_builder.dart` — transient per-feature RenderScene used
  for viewport Base/Tool/source picking during authoring.
- `family_authoring_viewport.dart` — thin host around the project viewport plus
  authoring gizmo overlays; it does not implement a camera.
- `family_sketch_viewport.dart` — project top-down viewport host for profile
  drawing and point dragging.
- `family_editor_v5_page.dart` — single active direct-manipulation editor.
- `family_library_dialog.dart` — library search/filter/type/edit workflow.
- `family_instance_adapter.dart` — project placement boundary.

V2/V3/V4 editor classes are compatibility aliases only. New navigation enters
V5 directly. Do not put new editor logic into those compatibility files.

## Schema v6 and compatibility

`FamilyDocument.currentSchemaVersion` is **6**. Schema v1 through v5 remain
readable. Any authored edit saves using v6.

Schema evolution:

- **v1** — family/type/feature/sketch core.
- **v2** — numeric parameter formulas.
- **v3** — formula-driven reference planes plus Horizontal, Vertical,
  Coincident and Point-on-reference-plane constraints.
- **v4** — Distance, Angle, Parallel, Perpendicular and Equal-length relations.
- **v5** — stable sketch-point identities and ID-first constraint references.
- **v6** — nested-family feature references with stable family/type identity and
  transform expressions.

Legacy point-index constraints are hydrated with deterministic point ids at
load. Legacy family files therefore do not need an up-front migration.

## Parameter/formula path

Supported numeric expressions are deliberately deterministic:

- numeric literals and parameter ids;
- `+`, `-`, `*`, `/`, parentheses and unary `+/-`;
- constant `pi`;
- `min`, `max`, `abs`, `clamp`.

The shared semantic path is:

```text
Family Type values
        -> FamilyParameterResolver
        -> reference-plane / distance / angle expressions
        -> FamilyConstraintSolver
        -> solved profile geometry
        -> FamilyGeometryEvaluator
        -> FamilyPlanSymbolGenerator
        -> FamilyInstanceAdapter/native creation
        -> Project Inspector
        -> persisted effective instance values
```

Do not bypass the resolver and treat raw `type.values` as effective dimensions.

## Sketch constraints and identity

`FamilySketchPoint.id` is persistent semantic identity. Constraint point ids are
authoritative; legacy indexes are recovery snapshots only. Reordering points
must not move a constraint to a different semantic point.

Supported exact/inference constraints:

- Horizontal
- Vertical
- Coincident
- Point on reference plane
- Distance
- Parallel
- Perpendicular
- Equal length
- Angle

Over-constrained systems are rejected rather than averaged into plausible
geometry. Constraint solving drives actual Extrude/Revolve geometry, plan
symbols, placement and Inspector regeneration.

### Sketch authoring UX

V5 sketch mode provides:

- Rectangle and Circle quick primitives;
- manual point placement;
- direct point drag;
- project plan pan/zoom/hit-test behavior;
- project `PlanSketchGeometry` snapping/inference;
- default 50 mm Family grid snap with a visible Snap toggle;
- endpoint snap and horizontal/vertical inference feedback;
- Close/Reopen and Finish;
- optional advanced reference-plane/constraint panel.

A Family-only snap kernel must not be introduced. New reusable snap behavior
belongs in the project plan geometry layer first.

## Exact CSG

`family_csg.dart` performs BSP union/subtraction for closed orientable
2-manifold solids. Boolean features require exactly two explicit earlier solid
inputs. Topology is validated and winding normalized before exact evaluation.

If an imported mesh cannot satisfy the exact-solid contract, the preview is
explicitly approximate rather than silently pretending the CSG succeeded.

## Nested families

Nested families are implemented as stable dependency references, not embedded
copies. A nested feature stores child `familyId + typeId` plus transform
expressions. `FamilyDependencyResolver`:

- resolves against the Family Library;
- evaluates dependency DAGs recursively;
- rejects missing families/types;
- rejects cycles;
- materializes a transient child mesh for the synchronous geometry evaluator.

Nested X/Y/Z translation uses Family coordinates. Nested rotation follows the
same vertical-axis/yaw convention as ordinary Transform; the persisted
`rotationZ` token is retained only for file compatibility.

Placement and Inspector regeneration use the same dependency path.

## V5 direct-manipulation editor UX

The active editor is task-oriented and model-first.

### Ribbon

- **CREATE** — Sketch, Extrude, Revolve
- **MODIFY** — Move, Rotate, Scale
- **COMBINE** — Union, Subtract
- **INSERT** — Nested, Import

History is optional and hidden by default. It is a feature-history aid, not the
primary way a normal user must operate the editor.

### 3D operations

All operations use the project 3D viewport.

- **Move** — tap a solid, drag X/Y/Z handles.
- **Rotate** — tap a solid, drag the vertical-axis rotation ring.
- **Scale** — tap a solid, drag the scale handle.
- **Extrude** — live result plus direct blue `D` depth handle; numeric field and
  slider remain available for precision.
- **Revolve** — live result plus direct angle ring; numeric input remains
  available for precision.
- **Union/Subtract** — viewport enters candidate-pick mode. Tap Base then Tool,
  inspect the live result, then Apply or Cancel.

`FamilyAuthoringSceneBuilder` exposes intermediate solids as separate selectable
project `RenderSceneObject`s only while an operation needs them. Final/result
mode remains one evaluated family object.

### Command semantics

Modal operations have explicit live-draft boundaries:

1. begin tool;
2. choose/pick input(s);
3. manipulate live preview;
4. Apply or complete a direct gizmo step;
5. Cancel returns to the pre-tool document.

A cancelled/interrupted gizmo drag must **never** create an undo step. Flutter
`onPanCancel` restores the pre-drag snapshot with zero delta and does not call
the commit path. This matters when a second touch, OS gesture or gesture arena
cancels a drag.

Native Android selection is synchronized back through
`RenderSceneViewportController`; clearing/changing a pick resets the Family
selection dedupe token so selecting the same solid again is a valid new action.

### Keyboard contract

V5 handles hardware keyboard commands through the editor's real command paths,
not a parallel shortcut model:

- `Esc` — cancel active tool; in Select, clear current feature selection.
- `Enter` / numpad Enter — Finish Sketch or Apply the active operation.
- `Delete` / `Backspace` — run the normal dependency-safe selected-feature
  delete flow, including confirmation.
- `Ctrl/Cmd+Z` — model Undo.
- `Ctrl/Cmd+Shift+Z` or `Ctrl/Cmd+Y` — model Redo.
- `Ctrl/Cmd+S` — Save when no modal tool is active.

When an `EditableText` owns focus, text editing keeps native Undo/Delete/Enter
behavior and model shortcuts do not hijack the field. Escape remains a CAD
command boundary and can cancel the current modal operation.

## Family Library

Library supports:

- full-text search;
- category filters;
- Favorites and Recent;
- cached previews;
- explicit Family Type selection before placement;
- Edit Family;
- stable-family-id save/update rather than filename identity;
- Android external `.bimfamily` import into app-owned storage.

Invalid external family files cannot cross the validation boundary into project
placement.

## GLB/glTF import

Geometry import supports glTF 2.0 mesh primitives, indices, node transforms and
explicit unit scale (`m`, `cm`, `mm`, custom). Imported geometry is normalized
into Family coordinates and becomes a `freeformMesh` feature.

The current native family-proxy ABI carries vertices and triangle indices. It
does **not** yet carry UV sets, material slots or texture resources. Do not
claim GLB material/texture preservation until the renderer contract is extended
through Flutter -> project gateway -> native engine -> Filament.

## Validation invariants

Before save/import/placement, validation checks at least:

- supported schema version;
- non-empty family/type/feature state;
- unique parameter/type/feature/sketch/reference-plane/constraint ids;
- stable/unique sketch point ids;
- valid formulas and no formula cycles;
- valid type ranges;
- constraint ownership, operands and numeric domains;
- every Family Type can solve constrained sketches;
- feature dependency existence/order;
- closed profiles for Extrude/Revolve;
- solid-only Transform/Boolean inputs;
- exactly two distinct earlier Boolean solids;
- freeform mesh validity and limits;
- nested-family reference/transform integrity.

Keep this gate at the file/project boundary even if the UI already prevents the
same error.

## Production limits — do not fake these

These remain separate engine/rendering work, not hidden editor switches:

1. **Curved sketch topology** — first-class arcs/splines, persistent edge ids,
   tangent/curve constraints and true curve editing are not yet in the sketch
   contract. Circle quick-create is currently polygonal profile generation.
2. **Material/texture proxy rendering** — UVs/material slots/images are not yet
   carried by the family proxy ABI.
3. **Large repeated-instance certification** — the reference model avoids
   per-instance feature graph copies, but large tablet scenes still require
   measured target-device budgets and renderer instancing work where needed.

## Regression expectations

At minimum, Family changes must preserve:

1. Library -> search/filter -> family -> type -> Place.
2. Selected type remains selected in placement.
3. Edit Family -> Save -> same stable family reloads.
4. Formula/constraint changes agree in 3D, plan, Inspector and persistence.
5. Exact CSG succeeds only on valid closed solids.
6. Nested dependency cycle/missing child fails before placement/save.
7. GLB/glTF -> unit conversion -> save -> reopen -> place.
8. Family 3D uses `RenderSceneViewport`, never a duplicate orbit renderer.
9. Family Sketch uses project top-down viewport navigation and project snap
   geometry.
10. Sketch -> Rectangle/manual profile -> Finish -> Extrude works entirely from
    the visible UI.
11. Extrude/Revolve direct handles update live preview before Apply.
12. Move/Rotate/Scale work from viewport selection and direct gizmos.
13. Boolean exposes intermediate solids as separately pickable candidates.
14. Base then Tool selection produces a live Union/Subtract preview.
15. Clearing and re-picking the same native solid reports a fresh selection.
16. A cancelled gizmo gesture restores the draft and never commits.
17. Ordinary Transform and nested-family rotation both preserve Family Y as
    vertical and use the same positive yaw direction.
18. Hardware Enter/Escape/Undo/Redo/Delete use the editor command/history paths;
    text fields retain native editing semantics.
19. Obsolete Family-specific pseudo-3D preview/workbench implementations do not
    return to the active module.
