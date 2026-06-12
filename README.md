# Tablet BIM Engine

Tablet-first CAD/BIM engine foundation built around a small C++ core, with room for Open CASCADE geometry, mobile rendering, cloud sync, and future Flutter UI integration.

## Current Shape

- `src/core`: semantic BIM primitives, document model, wall automation, profile/mesh generation, geometry service boundary
- `apps/tbe_cli`: tiny developer CLI for smoke testing the core
- `tests`: dependency-free unit tests using simple assertions
- `cmake`: CMake helpers, including optional Open CASCADE discovery

Open CASCADE is treated as an optional geometry backend at this stage. The project builds without it, but switches on OCCT integration automatically when CMake can find a valid installation and `TBE_ENABLE_OCCT=ON`.

The fallback engine already generates wall-local 2D profiles, opening rectangles, and 3D extrusion mesh buffers without OCCT. OCCT can later consume the same profile/opening data to create real `TopoDS_Shape` solids.

Level 2 engine MVP also supports simple levels, rectangular room detection from four connected walls, room area/perimeter calculation, command transaction logging, JSON serialization, reload, and geometry regeneration after load.

## Build

```bash
cmake -S . -B build
cmake --build build
ctest --test-dir build
```

## Build With Open CASCADE

If OCCT is installed through a package manager or custom SDK, point CMake at it:

```bash
cmake -S . -B build -DTBE_ENABLE_OCCT=ON -DOpenCASCADE_DIR=/path/to/occt/lib/cmake/opencascade
cmake --build build
```

## Architecture Direction

- Keep the BIM document model independent from any geometry kernel.
- Put all OCCT-specific code behind adapter classes.
- Keep rendering separate from model/geometry so Android Vulkan, desktop preview, and cloud workers can evolve independently.
- Make expensive geometry work job-based and incremental so tablet hardware stays responsive.

## Engine MVP Direction

The first product milestone is engine behavior, not UI:

```text
create wall
-> store semantic wall data
-> keep 2D wall axis, thickness, and height
-> calculate wall joins
-> generate 2D wall profile
-> generate 3D fallback mesh/cache
-> host doors and windows on walls
-> project openings into wall-local rectangles
-> refresh dirty geometry cache
-> detect rectangular rooms
-> compute area and perimeter
-> serialize/reload document JSON
-> regenerate geometry after load
-> verify through CLI/tests
```

Detailed notes live in `docs/engine_mvp_architecture.md`.

## MVP Goal

The first engine milestone is not a full Revit replacement.  
The goal is to build a reliable tablet-first lightweight BIM core that can:

- represent walls, rooms, levels, doors, and windows as semantic BIM elements;
- automatically extrude walls into 3D solids;
- automatically join walls at intersections and corners;
- host doors/windows inside walls;
- cut openings from hosted walls;
- keep geometry cache incremental and mobile-friendly;
- run the same core on Android, iPadOS, macOS, Windows, and cloud workers.
