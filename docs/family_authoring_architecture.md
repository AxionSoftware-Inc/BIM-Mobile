# Family Authoring boundary

Family Authoring is a separate authoring product inside Tablet BIM. It is not
another wall implementation and it does not edit a project scene directly.

## Boundary

- `apps/viewer_flutter/lib/src/family_authoring/family_document.dart` owns the
  serializable family contract.
- `family_file_store.dart` owns `.bimfamily` persistence and local library UI
  preferences.
- `family_editor_v2_page.dart` is the default authoring surface.
- `family_editor_page.dart` remains in-tree as the previous editor/reference
  while V2 is exercised on tablets.
- `family_library_dialog.dart` owns family discovery, search, type choice,
  favorites, recent items and cached previews.
- `family_authoring_module.dart` is the only entry point used by the start
  screen. The project editor does not need to know the family document shape.

The family contract has three independent layers:

1. Family metadata and category (`Generic Model`, `Column`, `Door`, `Window`,
   `Wall Sweep`, `Furniture`, `Casework`, `Stair`, `Structural`).
2. Parameter definitions and named Family Types. A type supplies values for
   reusable parameters; it is not a separate copy of the geometry.
3. An ordered feature graph for profile, extrude, revolve, transform, boolean
   union/subtract and freeform mesh.

## V2 authoring UX

The V2 editor has two user levels without splitting the file format:

- **Simple**: name/category/description, named type choice, all declared type
  values and a GLB/glTF import fast path. A normal chair, table, cabinet or
  appliance can therefore be created as content without writing Dart code.
- **Advanced**: type duplicate/rename/delete, generic parameter-definition
  add/edit/delete, touch profile editing, extrude, revolve, transform,
  union/subtract feature nodes and the feature graph.

Parameter value controls are generated from `FamilyParameterDefinition`; the
editor no longer assumes that the only editable values are width/depth/height.
Core dimensions remain protected from deletion because existing evaluators and
placement adapters use them as the stable sizing contract. A non-core parameter
cannot be deleted while a feature node references its id.

## Library V2

The project-side Family Library is designed to scale beyond the curated starter
set:

- full-text search across family name, description, category and type names;
- category filtering;
- persistent Favorites and Recent scopes;
- family/type mesh preview cache for smooth scrolling;
- explicit Family Type selection before placement;
- preferred type is carried into the existing placement dialog instead of
  silently falling back to `document.types.first`;
- imported `.bimfamily` files on Android are copied into the app-owned family
  library, so adding reusable content does not require a source-code change or
  application rebuild.

Favorites and recents live in `.family_library_state.json` beside the app-owned
family library. They are UI preferences, not BIM project data, and corrupt
preference state is ignored rather than preventing family assets from loading.

## Project integration rule

Project instances reference a family asset and a stable type id, then store
placement and instance values. They must not copy the family feature graph into
every placed element. This keeps repeated objects cheap and allows a family
asset to remain the semantic source.

```text
FamilyDocument + type id
        -> Family evaluator
        -> project instance mesh / bounds / pick proxy
```

`family_instance_adapter.dart` is deliberately outside the
`family_authoring/` package. It translates a validated family type into the
existing native creation gateways and writes the family/type reference on the
project element. Door and Window use the existing hosted-opening path. Wall
Sweep is projected onto its host wall. Other supported free-standing families
use native family/proxy geometry as appropriate.

The Library's selected type is an in-memory placement preference. The
`.bimfamily` file itself is not reordered or rewritten just to place a type.
This preserves stable file content while remaining backward-compatible with
the existing placement UI.

## Blender mesh import

The Family Editor imports Blender-exported GLB/glTF mesh primitives, indices
and node transforms, centres the model on X/Z, places its lowest point on the
family ground plane, and creates a `freeformMesh` feature with width, depth and
height type values.

On Android, selecting an external `.bimfamily` through **Import family** copies
that family into the app-owned reusable library. This is the content-driven
extension path: teams can add families without adding entries to
`BuiltInFamilyCatalog`.

## Important production limits — do not hide these in UI or docs

The following are still real engine/content tasks and are **not** claimed as
finished by V2:

1. **Exact CSG**. Current boolean union/subtract preview remains approximate
   until a robust solid kernel is connected. The editor shows this explicitly.
2. **Constraint solver / formulas**. A Revit-class reference-plane, equality,
   lock/alignment and dependency-formula system requires a real constraint
   graph and cycle-safe evaluator; it must not be faked by storing labels that
   do not drive geometry.
3. **Nested families**. Reusable child-family references need dependency,
   versioning and transform semantics before they can safely ship.
4. **GLB material/texture preservation**. Geometry import works; production
   material/texture import, unit selection, decimation and LOD generation are
   separate importer/rendering work.
5. **Repeated-instance performance validation**. The reference architecture is
   designed for reuse, but large-scene tablet budgets still need measured
   regression tests.

These boundaries are deliberate. Do not mark any of the above as "supported"
until the evaluator/engine actually consumes the data and project reload tests
prove the behavior.

## Regression expectations

At minimum, family changes should preserve these workflows:

1. open Family Library -> search/filter -> choose family -> choose type -> Place;
2. selected type remains selected when the placement dialog opens;
3. place -> edit supported family parameters in Inspector -> project geometry
   updates -> save project -> restart -> reopen;
4. import external `.bimfamily` -> it appears in future Library sessions;
5. favorite/recent state can be corrupt or missing without breaking assets;
6. create V2 family -> duplicate/rename type -> add a generic parameter -> save
   -> reopen/parse with `FamilyDocument.fromJson`;
7. GLB/glTF import remains a freeform family and can be placed repeatedly.
