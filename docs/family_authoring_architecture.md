# Family Authoring boundary

Family Authoring is a separate authoring product inside Tablet BIM. It is not
another wall implementation and it does not edit a project scene directly.

## Boundary

- `apps/viewer_flutter/lib/src/family_authoring/family_document.dart` owns the
  serializable `.bimfamily` contract.
- `family_parameter_resolver.dart` owns deterministic effective parameter
  values and numeric formulas.
- `family_validation.dart` is the semantic gate before save/import/placement.
- `family_file_store.dart` owns validated persistence and local Library state.
- `family_editor_v2_page.dart` is the single production authoring surface for
  both new and existing library assets.
- `family_library_dialog.dart` owns search, filters, type choice, favorites,
  recents, cached previews and the edit-existing-family workflow.
- `family_instance_adapter.dart` is the project boundary and the shared resolver
  facade used by placement and Inspector code.

The family contract has three independent layers:

1. Family metadata and category (`Generic Model`, `Column`, `Door`, `Window`,
   `Wall Sweep`, `Furniture`, `Casework`, `Stair`, `Structural`).
2. Parameter definitions and named Family Types. A type supplies values for
   reusable parameters; it is not a separate geometry copy.
3. An ordered feature graph for profile, extrude, revolve, transform, boolean
   union/subtract and freeform mesh.

## Schema v2 and compatibility

`FamilyDocument.currentSchemaVersion` is 2. Schema v1 remains readable. Future
schema versions are rejected instead of being guessed at. Any authored edit is
written back as schema v2.

Schema v2 adds optional numeric parameter formulas. The supported expression
language is deliberately small and deterministic:

- numeric literals and parameter ids;
- `+`, `-`, `*`, `/`, parentheses and unary `+/-`;
- constant `pi`;
- `min(a,b)`, `max(a,b)`, `abs(x)` and `clamp(x,min,max)`.

Formulas may drive `length`, `number` and `angle` parameters. They cannot call
Dart, access files/network, mutate state or depend on text/material/boolean
values. The resolver rejects unknown ids, cycles, division by zero, invalid
ranges and non-finite results.

A formula-driven parameter ignores its own stale per-type override. Its
dependencies still read the selected Family Type. This rule is shared by:

```text
Family Editor preview
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

## Authoring UX

The editor has two user levels without splitting the file format:

- **Simple**: name/category/description, named type choice, all declared type
  values and a GLB/glTF import fast path. A chair, table, cabinet or appliance
  can be created as reusable content without writing Dart code.
- **Advanced**: type duplicate/rename/delete, generic parameter-definition
  add/edit/delete, formulas, touch profile editing, extrude, revolve,
  transform, union/subtract feature nodes and the feature graph.

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
- unique parameter/type/feature/sketch ids;
- unique Family Type names (case-insensitive);
- parameter kinds, defaults, ranges and formula compatibility;
- every selected type's effective resolved values;
- formula cycles, unknown references and invalid arithmetic;
- feature input existence and ordering (feature nodes may only depend on earlier
  feature nodes);
- solid-only input requirements for transforms and booleans;
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
If a formula is invalid, placement fails before an element is created. Door and
Window use the hosted-opening path; Wall Sweep is projected onto its selected
wall; free-standing supported families use native family/proxy geometry.

Inspector reconstructs the selected Family Type from the asset and stored
instance dependency values, then resolves formulas again before geometry and
metadata are committed. Formula-driven fields are read-only in Inspector.
Changing a dependency therefore updates 3D geometry, plan symbol and persisted
effective formula values together; restart cannot surface a stale formula
snapshot.

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

The following are still separate engine/content tasks and are **not** claimed
as finished:

1. **Exact CSG**. Boolean union/subtract preview remains explicitly approximate
   until a robust solid kernel is connected.
2. **Geometric constraint solver**. Numeric dependency formulas are real, but
   Revit-class reference planes, alignment/equality locks, dimensional
   constraints and a geometric constraint graph are not implemented yet.
3. **Nested families**. Child-family dependency/version/transform semantics need
   a real dependency model before they can safely ship.
4. **GLB material/texture preservation**. Geometry import works; production
   material/texture import, explicit unit selection, decimation and LOD
   generation remain separate importer/rendering work.
5. **Large repeated-instance performance certification**. The reference design
   avoids copying feature graphs, but large tablet scenes still require measured
   device regression budgets.

Do not mark any of these as supported merely by storing metadata for them. The
engine/evaluator must consume the data and save/reopen tests must prove it.

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
7. external invalid `.bimfamily` cannot enter the reusable library;
8. import GLB/glTF -> save -> reopen -> place repeatedly;
9. favorite/recent state can be missing/corrupt without breaking assets;
10. schema-v1 family -> edit -> save -> schema-v2 family remains loadable.
