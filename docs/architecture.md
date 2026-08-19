# Architecture Notes

For the detailed engine-first MVP plan, see `docs/engine_mvp_architecture.md`.

## Goal

Build a lightweight but reliable CAD/BIM core that can run on Android tablets, iPad, macOS, Windows, and future cloud workers from one shared native engine.

## Layering

1. Product UI
   - Later Flutter or native shells for tablet UI, project management, properties, account, sync, and collaboration.

2. Native viewport
   - Android Vulkan renderer later.
   - Desktop preview renderer can be added for development speed.

3. Engine core
   - C++ model, commands, undo/redo, BIM rules, element graph, jobs, serialization boundaries.
   - Must not depend directly on Flutter, Android, iOS, macOS, or Windows UI frameworks.

4. Geometry backend
   - `IGeometryBackend` is the only backend boundary visible to the core geometry service.
   - The fallback adapter is always available; the Open CASCADE adapter performs wall solids, opening cuts, and tessellation when OCCT is found.
   - Keep OCCT types behind the adapter so a cloud worker or different backend can be introduced later.

5. Cloud services
   - Project storage, version history, collaboration, heavy geometry jobs, IFC import/export pipelines.

## Runtime ownership boundaries

- `Document` is the semantic model facade. It owns authoritative elements and
  relationship state; generated meshes are derived data.
- `DependencyGraphService` owns the relationship-index cache and versioning;
  `Document` delegates graph reads and invalidation to it.
- `GeometryService` owns geometry backend selection and all generated mesh
  construction. Callers can inspect `backend_name()` and
  `supports_exact_solids()` instead of guessing from build flags.
- `EngineSession` owns application caches, freshness state, package/export
  orchestration, and the interaction index.
- The C ABI owns one session per opaque handle and serializes calls on that
  handle. C++ `EngineSession` objects remain single-owner objects and must be
  externally synchronized if shared between threads.
- `RenderScene` and the edit command envelope are versioned contracts shared
  by native and viewer layers. Viewer code must not mutate `project.json`
  directly.

## Performance Rules

- Keep the authoritative BIM model separate from generated render meshes.
- Run tessellation, import/export, and analysis as cancellable background jobs.
- Use incremental rebuilds instead of regenerating the whole project after every edit.
- Cache render meshes by element revision.
- Design for degraded tablet mode: large jobs can be queued locally or sent to cloud workers.
