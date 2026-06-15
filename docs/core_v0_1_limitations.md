# Core v0.1 Limitations

This engine is a portable BIM-oriented core MVP, not a full production authoring system yet.

## Geometry / Modeling

- fallback mesh generation is the default path
- full OCCT solid modeling is optional and not required
- no public OCCT types are exposed through the SDK
- walls, rooms, slabs, roofs, stairs, and similar elements are still mostly simple parametric/orthogonal forms

## Room Solver

- current room solving is focused on orthogonal floorplan cases
- advanced non-orthogonal and curved room detection is not complete
- complex nested boundaries, shafts, and high-end authoring edge cases are not fully supported

## Interop

- no IFC import/export yet
- no DWG/DXF integration yet
- no direct Revit interoperability layer yet

## Element Behavior

- roof behavior is intentionally simple
- stair behavior is placeholder/simple straight stair oriented
- hosted opening logic is practical but not family-system-complete
- placement intervals are wall-axis based, not full parametric constraint solving

## Persistence / Packaging

- project package export is directory-based today
- zip packaging is future work

## Viewer / UI

- no full viewer/UI is included yet
- hit/snap and SDK contracts are intended to support future viewer work, but rendering/editor UX still needs to be built

## Positioning

- this is not a full Revit replacement
- the goal of v0.1 is a stable portable core SDK that a lightweight viewer/editor can safely depend on
