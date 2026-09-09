# Arvela 0.3.2 Architecture Charter

This document is the migration target for the 0.3.2 architecture-cleanup branch.
It is intentionally stricter than the current tree. Existing code may violate a
rule during migration, but new code must not create a new violation.

## Goals

1. Keep the app maintainable as Architecture, Structure, MEP, Analysis,
   Documentation and future disciplines grow independently.
2. Keep large-scene performance work isolated from UI and authoring code.
3. Give every piece of mutable data one authoritative owner.
4. Replace cross-project switch statements and stringly-typed routing with
   registries assembled at one composition root.
5. Make features removable/testable without constructing the full application.
6. Keep platform/native details behind explicit ports.

## Top-level dependency direction

Dependencies point inward only:

```text
presentation -> application -> domain
                    |             ^
                    v             |
              infrastructure -----+
```

`domain` never imports Flutter, FFI, Android, Filament, file pickers or widgets.
`application` coordinates use-cases and owns no platform handles.
`infrastructure` implements ports for native engine, files, cache and telemetry.
`presentation` owns widgets, painters and interaction state only.

A feature may depend on `core` contracts, but one feature must not reach into
another feature's private implementation directory.

## Target Flutter tree

```text
lib/src/
  app/
    bootstrap/
    composition/
    routing/
    workspace/

  core/
    domain/
      geometry/
      ids/
      units/
      view/
    application/
      commands/
      events/
      registry/
    infrastructure/
      io/
      telemetry/
    presentation/
      design_system/

  features/
    project/
      domain/
      application/
      infrastructure/
      presentation/
    viewer/
      domain/
      application/
      infrastructure/
      presentation/
    authoring/
      domain/
      application/
      presentation/
    elements/
      domain/
      application/
      presentation/
    family/
      authoring/
      runtime/
    annotations/
    documentation/
    schedules/

  platform/
    native_engine/
    android_bridge/
```

The migration is incremental. Public facade files may remain temporarily at the
old path and re-export the new implementation until callers are migrated.

## Native Android renderer target

`RenderSceneFilamentHostView` becomes a coordinator, not a renderer subsystem.
Target modules:

```text
renderer/
  FilamentRendererHost.kt
  RendererLifecycle.kt
  RendererSceneState.kt
  camera/
    ViewportCameraController.kt
    CameraProjection.kt
  streaming/
    NativeChunkStreamer.kt
    ChunkResidencyState.kt
    NativeSpatialStreamingPolicy.kt
  geometry/
    FaceBatchRenderer.kt
    EdgeBatchRenderer.kt
    NativeGeometryUpload.kt
  materials/
    ArchitecturalMaterialSystem.kt
    MaterialInstanceCache.kt
  selection/
    NativeSelectionRenderer.kt
    NativePickingAdapter.kt
  sections/
    SectionBoxRenderer.kt
  diagnostics/
    RendererTelemetry.kt
    RendererBenchmarkAdapter.kt
```

The host may coordinate these modules, but must not own their algorithms.

## Native C++ target

`src/core` owns presentation-independent BIM/domain algorithms.
`src/api` owns ABI/session/cache adapters only.
Android JNI files are adapters and must not become authoritative model owners.

Runtime cache ownership:

```text
project/document (authoritative semantics)
        -> runtime cache (derived, rebuildable)
        -> CPU resident chunk views (derived, bounded)
        -> GPU resources (derived, bounded)
```

Derived caches must always be safe to drop and rebuild.

## Data ownership rules

Each logical datum has one owner.

- Project/document semantics: native project/document model.
- `RenderScene`: compatibility/read-model, not the long-term write authority.
- `BimCompactInstanceStore`: derived runtime read model.
- Family definition/type: family domain/library.
- Family instances: project placement data; runtime store is derived.
- Annotation store: annotation document; renderer batches are derived.
- Native `.bimcache`: derived acceleration data.
- Selection: workspace interaction state; never persisted as project semantics.

No derived representation may silently mutate an authoritative representation.

## Registry and composition rules

All production registration happens in one app composition root.

Registries are for identity/capability resolution, not service location.
A registry must:

- be immutable after composition;
- reject duplicate canonical keys;
- provide O(1) lookup for hot routes;
- expose typed descriptors instead of unstructured maps where practical;
- not construct widgets/native sessions internally;
- not import a feature's private implementation.

Primary registries expected during migration:

- `BimElementRegistry`
- inspector adapter registry
- authoring tool registry
- import format/adapter registry
- workspace tab/discipline registry
- render style/material registry

A new element/discipline should be addable by registering a descriptor/module,
not by editing five unrelated switch statements.

## Object/model rules

Do not model millions of scene instances as heavyweight object graphs.
Use immutable definitions/types plus packed/data-oriented instance stores for
large repeated data. Object-oriented facades are acceptable at editing/UI
boundaries, but must not become the runtime storage format for large scenes.

Prefer stable IDs and explicit references over object back-pointers.
Avoid circular ownership. Parent/child relationships are IDs or indices unless
there is a strong local reason otherwise.

## Command and mutation rules

All document mutations go through an application command/use-case boundary.
UI code does not directly edit native/project persistence structures.

Commands should support:

- validation before commit;
- one undo unit per user action;
- dirty/invalidation reporting;
- narrow affected-element/chunk scopes;
- no hidden full-scene rebuild unless explicitly documented.

## File and size rules

A large file is a design smell, not an automatic bug.

Soft limits for new code:

- ~300 lines for ordinary classes/widgets;
- ~500 lines for cohesive algorithms;
- files above ~800 lines require an explicit reason in the file header;
- no new God object may combine lifecycle + UI + persistence + native handles.

Existing large files are migrated by responsibility, not by arbitrary line
count. Splitting one 2,000-line class into five partial files with the same
shared mutable state does not count as architecture cleanup.

## Compatibility policy

During migration, compatibility facades are allowed only when marked:

```text
COMPATIBILITY: temporary facade for <old API>
REMOVE WHEN: <named caller/milestone>
```

No new feature should depend on a compatibility facade when the new contract is
available.

## Repository hygiene

Do not commit IDE workspace state, generated build output, temporary screenshots
or local machine configuration. Test fixtures/assets must have an intentional
name and documented consumer.

## Architecture migration order

1. Repository hygiene + architecture guardrails.
2. Composition root and registry normalization.
3. Split native renderer host by owned responsibility.
4. Split Flutter workspace/project lifecycle by use-case.
5. Move viewport interaction/editing into application controllers.
6. Consolidate project persistence/import/recovery contracts.
7. Consolidate element/type/inspector registries.
8. Move renderer/material/view styles behind typed contracts.
9. Remove compatibility paths after callers migrate.
10. Run full regression/stress suite, version and freeze.

## Performance rule during this refactor

0.3.2 architecture work is behavior-preserving by default. Do not change a
proven streaming/memory algorithm merely to make the code look cleaner. Any
performance-semantic change must have a focused benchmark/regression test.

## Test strategy

Refactor tests should prefer contracts over implementation details:

- project open/save/import round-trip;
- viewport scene policy;
- bounded streaming/residency;
- selection/picking identity;
- family definition/type/instance separation;
- annotation codec/history/view filtering;
- registry duplicate-key rejection and lookup;
- no forbidden cross-layer imports for migrated modules.
