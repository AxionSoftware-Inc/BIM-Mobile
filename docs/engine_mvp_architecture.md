# Engine MVP Architecture

## Product Direction

The first milestone is not a UI product. The first milestone is a reliable, automated, BIM-like native engine that can later power Android tablet, iPad, macOS, Windows, and cloud workflows from one shared codebase.

This engine should not try to become full Revit. It should focus on the most valuable Revit-like automation:

- Draw a wall as a semantic BIM element, not just lines.
- Automatically extrude walls into solids.
- Automatically join walls at intersections and corners.
- Insert doors and windows into hosted walls.
- Automatically cut wall openings for hosted elements.
- Keep 2D plan data, 3D solids, dimensions, and metadata connected.
- Regenerate only the changed parts of the model.

## Current State

The repository is currently a C++20 engine foundation with an early automated BIM pipeline:

- `tbe_core` library exists.
- `Project`, `Document`, and basic `Element` types exist.
- Levels, walls, doors, windows, rooms, joins, openings, and generated geometry cache exist as semantic data.
- `GeometryService` creates fallback 2D profiles and 3D extrusion mesh buffers.
- `JobSystem` exists for multi-core background work.
- Command objects and transaction logging exist for basic engine operations.
- Documents can serialize to JSON, reload, and regenerate geometry.
- CLI and unit tests exist for smoke testing.
- Open CASCADE is optional and not yet used for real solid modeling.

Current limitation: fallback geometry is still a lightweight mesh/profile generator, not real OCCT solids or boolean cuts. Room detection is intentionally simple and currently focused on axis-aligned rectangular loops.

## Target MVP State

The MVP engine should support a small but solid BIM-like workflow:

- Levels: create floor levels with elevation.
- Walls: create, edit, split, trim, join, and auto-extrude walls.
- Doors/windows: place hosted openings on walls by offset, width, height, sill/header rules.
- Columns/slabs: create basic structural primitives.
- Auto-join: resolve wall intersections, T-junctions, L-corners, and simple cleanup.
- Openings: subtract door/window voids from wall solids.
- Model graph: track relationships between walls, hosted elements, levels, and generated geometry.
- Regeneration: update affected geometry after edits, not the whole project.
- Validation: detect invalid dimensions, broken hosts, overlapping openings, and failed joins.
- Serialization: save/load a compact project file independent of UI.
- Tests: cover geometry rules and document behavior before UI work expands.

## Platform Strategy

One engine should be compiled for every platform:

- macOS Intel: main development machine and first desktop test target.
- macOS Apple Silicon: later native build.
- Windows: desktop test target and future professional workflow.
- Android tablet: primary mobile field/design target.
- iPadOS: future target, likely through native C++ library plus platform UI.
- Cloud workers: heavy import/export, batch regeneration, IFC conversion, model validation.

The engine must stay independent from Flutter, Android, iOS, Win32, or Cocoa. Platform-specific code belongs in thin app/adaptor layers.

## Recommended Layering

1. Core model
   - Projects, documents, levels, elements, parameters, IDs, relationships.
   - No UI types and no Open CASCADE public types.

2. Command system
   - Create wall, move wall, join walls, insert door, insert window, edit parameters.
   - Each command produces model changes and supports undo/redo later.

3. BIM rules engine
   - Hosting rules, wall joins, opening constraints, level constraints, validation.
   - This is the main product value.

4. Geometry adapter
   - Open CASCADE implementation for solids, booleans, curve operations, tessellation.
   - Hidden behind engine interfaces.

5. Regeneration pipeline
   - Determines which elements are dirty.
   - Rebuilds only affected geometry.
   - Uses `JobSystem` for parallel background work where safe.

6. Rendering data
   - Meshes, edges, selection IDs, bounding boxes.
   - Generated from engine state, not stored as the authoritative model.

7. Platform bindings
   - C API or stable ABI wrapper for Flutter/Swift/Kotlin/C#/desktop shells.
   - UI calls commands; UI does not mutate the model directly.

## Core Data Model

Minimum internal entities:

- `Project`: owns documents and global settings.
- `Document`: owns levels, elements, materials, command history.
- `Level`: name, elevation, story height.
- `Element`: stable ID, type, parameters, transform, revision.
- `Wall`: baseline curve, height, thickness, level, join policy.
- `Door`: host wall, offset along wall, width, height, swing metadata.
- `Window`: host wall, offset along wall, width, height, sill height.
- `Slab`: boundary profile, thickness, level.
- `GeneratedGeometry`: solid reference, mesh cache, bounding box, revision.

Authoritative data should be semantic BIM data. Meshes and solids are generated caches.

## Wall Automation MVP

Wall creation should work like this:

1. User or test command provides a baseline, thickness, height, and level.
2. Engine creates a semantic wall element.
3. BIM rules engine finds nearby/intersecting walls.
4. Join solver adjusts endpoints or join metadata.
5. Geometry adapter extrudes the wall profile into a solid.
6. Hosted openings are applied.
7. Mesh and picking data are generated for viewport use.
8. Only affected walls and hosted objects receive new revisions.

## Door And Window MVP

Door/window placement should work like this:

1. Command receives host wall ID and placement offset.
2. Engine validates that the host is a wall.
3. Engine checks dimensions and avoids overlapping openings.
4. Door/window becomes a hosted BIM element.
5. Wall receives a dirty geometry mark.
6. Regeneration subtracts an opening from the wall solid.
7. Generated mesh and 2D plan symbols update together.

## Multi-Core Strategy

Use multiple cores for expensive but isolated work:

- Tessellation of independent elements.
- Bounding box and spatial index rebuild.
- Validation passes.
- IFC import/export later.
- Cloud worker regeneration.

Keep these mostly single-writer or carefully staged:

- Document mutation.
- Command application.
- Undo/redo history.
- Relationship graph updates.
- Final merge of generated geometry.

This keeps tablets responsive without making the core model fragile.

## Open CASCADE Usage

Use OCCT for:

- Curves and profiles.
- Solid extrusion.
- Boolean cuts for openings.
- Wall cleanup where geometry operations are needed.
- Tessellation for viewport meshes.
- Shape validity checks.

Avoid leaking OCCT types into public engine APIs. That keeps the door open for cloud-specific adapters, testing fakes, or future optimization.

## Near-Term Implementation Order

1. Replace placeholder `Element` with typed element data for level, wall, door, window, slab.
2. Add command objects for create/edit operations.
3. Add stable IDs, revisions, dirty flags, and relationship tracking.
4. Add wall baseline geometry and 2D intersection/join solver.
5. Add OCCT adapter for wall extrusion.
6. Add hosted door/window placement and opening cuts.
7. Add serialization tests and geometry rule tests.
8. Add a minimal native debug viewer only after engine behavior is testable.

## What To Avoid For Now

- Full Revit family system.
- Full MEP.
- Full IFC authoring as the first milestone.
- Complex parametric constraints.
- UI-first development.
- Direct dependency from engine core to Flutter or any platform UI.
