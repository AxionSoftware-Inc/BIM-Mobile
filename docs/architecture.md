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
   - Open CASCADE adapter for wall extrusion, openings, solids, booleans, tessellation, and geometric validation.
   - Keep OCCT behind interfaces so a cloud worker or different backend can be introduced later.

5. Cloud services
   - Project storage, version history, collaboration, heavy geometry jobs, IFC import/export pipelines.

## Performance Rules

- Keep the authoritative BIM model separate from generated render meshes.
- Run tessellation, import/export, and analysis as cancellable background jobs.
- Use incremental rebuilds instead of regenerating the whole project after every edit.
- Cache render meshes by element revision.
- Design for degraded tablet mode: large jobs can be queued locally or sent to cloud workers.
