# Production Architecture Contract

## Goal

The mobile BIM product is a modular native application. It is not a network
microservice system: authoring, viewing and core calculations must continue to
work offline with predictable latency. "Service" below means an in-process
application boundary with an explicit contract, not a remote process.

The architecture is migrated incrementally. A migration may move ownership or
dependencies, but must not change authored-project semantics, render-scene JSON
contracts, or existing user-visible behaviour without a separately approved
product change.

## Dependency direction

```text
Flutter app shell / feature presentation
                ↓
feature controller / application service
                ↓
repository interface
                ↓
engine bridge (FFI, DTO mapping, platform loading)
                ↓
C++ API application layer
                ↓
C++ domain, geometry and analysis
```

Dependencies only point down this diagram. In particular:

- Flutter widgets do not call C FFI symbols directly.
- A viewport consumes `RenderScene` and interaction commands; it does not own
  document mutation, schedules, or project persistence.
- A feature may depend on shared models and application interfaces, but not on
  another feature's private widgets or controller state.
- C++ geometry and analysis do not depend on JSON, C ABI, Flutter, or UI DTOs.
- JSON and C ABI are adapters around stable application contracts.

## Flutter module ownership

```text
app/             startup, dependency composition, application shell
engine_bridge/   FFI ABI, platform library loading, DTO translation
engine_contracts/ immutable bridge results, errors and snapshots
scene/           immutable RenderScene data and pure scene utilities
viewport/        camera, projection, painter, hit-test, interaction boundary
features/
  project_browser/  view tree and view-navigation requests
  authoring/        wall/opening/surface/stair authoring controllers
  inspector/        selected-element property editing
  sections/         section definition and section scene navigation
  materials/        material and assembly editing
```

`ProjectBrowserPanel` and `ProjectBrowserViews` are extracted production
feature components. They accept immutable scene data plus callbacks only; they
have no FFI, repository, or viewport-controller dependency.

`ViewerAuthoringGateway` is the application boundary for Inspector and
authoring mutations. Feature services use semantic commands and authoritative
`RenderSceneLoadResult` snapshots rather than a concrete FFI repository.

`ViewerSectionGateway` and `SectionSceneService` provide the same narrow
boundary for generated section views. The Project Browser and section dialog
only request a cut line and render the returned snapshot; they do not call the
native repository directly.

`ViewerSceneGateway` and `SceneViewService` own read-only render-scene refresh,
active-level navigation, and full-scene streaming scope. This keeps viewport
policy separate from project lifecycle and persistence.

`ViewerProjectGateway` and `ProjectPersistenceService` own native JSON
checkpoints, durable save paths, reload and project JSON replacement. Material
editing therefore uses a persistence use-case rather than reaching through to
the FFI repository.

`ViewerProjectSession`, `ViewerSessionFactory` and `ProjectLifecycleService`
own session creation, template launch, JSON/package import and failure cleanup.
`NativeViewerSessionFactory` is the sole Flutter-side adapter that prepares the
native library and constructs `ViewerRepository`; the application shell only
accepts a successful replacement session.

`ProjectSessionController` owns active-session replacement and disposal. This
keeps native-handle ownership out of widgets and prevents a failed/new session
from leaking or silently replacing the active project.

`NativeEngineLibraryLoader` owns Android library preparation and platform
library discovery. `TbeViewerApi` now owns ABI symbol binding/marshalling only.

`WorkspaceAppBar`, `AuthoringToolPalette`, and `ViewportControlDeck` form the
tablet workspace chrome. They are presentation-only components: each receives
state and callbacks from the app shell, and none can import the native bridge
or mutate a document directly. This keeps the authoring palette compact while
allowing view navigation to remain in the Project Browser.

`PlanSketchGeometry` is the shared, UI-independent plan-authoring kernel. It
owns grid and candidate snapping, orthogonal constraints, rectangle profiles,
and endpoint-based line operations. Wall, slab, ceiling, roof, stair, and
future line tools must use this kernel instead of copying coordinate logic into
widgets. Stateful tools such as `TrimExtendToolController` only collect an
intent and preview it; `AuthoringCommandService` forwards the committed
operation through `ViewerAuthoringGateway` to the native transaction.

### Current authoring contracts

- Wall and hosted opening mutations are semantic engine transactions. Complex
  joins and openings are regenerated from the same wall graph, and the
  Flutter fallback consumes the native curve/opening contract instead of
  inventing a second aperture model.
- Floor, ceiling and roof share the profile contract. Room-bound creation is a
  convenience source; a freeform polygon is persisted as the authoritative
  footprint and is used by both native and fallback plan rendering.
- A stair is one semantic element. Its path, layout kind, landing depth and
  railing flag are persisted together, so Straight/L/U geometry and Inspector
  edits cannot fragment into unrelated flight objects.
- The plan painter follows one depth order: surfaces/patterns, joined wall
  footprint, opening symbols and feature edges. Sub-pixel passive outlines are
  suppressed to reduce zoom-induced flicker.

`viewer_viewport_stair_editing.dart` is the first dedicated viewport authoring
coordinator. `viewer_viewport_input.dart` is now an event router plus wall and
level adapters; surface, wall editing and workspace interaction remain separate
parts. New feature families must add a coordinator/controller and a gateway
command rather than growing the app shell or duplicating FFI calls.

## Native C++ module ownership

```text
domain/          Document, Element, Material, Assembly, Level
geometry/        wall/slab/roof/stair mesh generation and joins
analysis/        rooms, validation, quantities, schedules
application/     commands, queries, template creation, freshness policy
infrastructure/  project JSON and package import/export
api/              DTO conversion and C ABI only
```

The first physical split is in place: `tbe_core_geometry` builds
`GeometryService` independently, while `tbe_core_analysis` compiles schedule
calculation, material takeoff and validation separately. `tbe_core_persistence`
owns document JSON serialization/deserialization. Both contribute objects to
the core archive. `tbe_core` now retains document state and commands; roof
surface fallback remains a narrow geometry metric used by analysis so AutoFootprint
quantities retain their existing accuracy. The dependency is one-way:
`tbe_core` links `tbe_core_geometry`; geometry does not link document state or
API code.

## Production quality gates

Every architectural slice must pass before the next slice begins:

1. C++ core/API tests and ASAN tests for native changes.
2. Flutter formatter, analyzer, and widget tests for Flutter changes.
3. Project JSON save/load and RenderScene contract regression tests whenever a
   document, DTO, or bridge boundary changes.
4. `git diff --check`.
5. No new feature work is mixed into a refactoring slice.

The repository workflow `.github/workflows/quality-gates.yml` enforces the
native tests, a separate ASAN/UBSAN native test job, Flutter analyzer, Flutter
regression suite, and diff hygiene on every push and pull request.
`tools/check_architecture.sh` also rejects direct native session construction
from the app shell, native bridge imports in presentation modules and shared
sketch tools, and analysis methods returning to `Document.cpp`.

## Migration order

1. Establish contracts and extract presentation-only feature widgets.
2. Extract feature controllers/use-cases from `viewer_app.dart`.
3. Separate FFI ABI bindings from engine repository/application services.
4. Split C++ geometry, analysis, persistence, and API orchestration.
5. Enforce the dependency direction with CI import/layer checks.

The migration deliberately retains compatibility shims until the relevant
project JSON, C ABI, and Flutter regression suites prove the replacement path.
