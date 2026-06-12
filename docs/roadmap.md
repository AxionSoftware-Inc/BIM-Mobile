# MVP Roadmap

## Phase 1: Native Engine Foundation

- C++20 core library
- Project and document model
- Element identity and basic BIM primitives
- Job system for background work
- OCCT adapter boundary
- Developer CLI and tests

## Phase 2: Geometry Kernel

- OCCT wall/door/window solid generation
- Tessellation cache
- Element revision tracking
- Bounding boxes and spatial index
- Picking and snapping data structures

## Phase 3: Tablet Viewport

- Android native surface
- Vulkan renderer
- Pan, zoom, orbit, select
- Level/plan mode and simple 3D mode
- Flutter shell integration through FFI/native view

## Phase 4: BIM Features

- Walls, doors, windows, columns, slabs
- Rooms and levels
- Dimensions and annotations
- Undo/redo command stack
- Local project file format

## Phase 5: Cloud

- Account and project sync
- Version history
- Heavy IFC import/export on workers
- Collaboration events
- Conflict-aware document updates

