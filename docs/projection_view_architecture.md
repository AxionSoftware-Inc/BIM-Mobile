# Projection View Architecture

This document explains the current Flutter viewport projection architecture for
`apps/viewer_flutter`.

## Goal

All 2D views must be different **projections of one scene**, not separate
renderers with duplicated logic.

That means:

- `2D` plan
- `North`
- `South`
- `East`
- `West`

all come from one shared projection registry and one shared planar math layer.

## Core idea

The viewport now has a single projection registry in:

- `apps/viewer_flutter/lib/src/render_scene_viewport_planar.dart`

Each projection mode is described by a `RenderSceneProjectionSpec`.

The spec owns:

- user-facing labels
- status strings
- fit-to-view strings
- whether the mode is planar or 3D
- whether the mode is an elevation
- planar axis mapping
- sign / handedness
- preferred 3D orbit direction when returning to 3D
- explicit cardinal `viewDirection`

## Planar descriptor

Planar 2D modes use `RenderScenePlanarDescriptor`.

The descriptor defines:

- `horizontalAxis`
- `verticalAxis`
- `depthAxis`
- `horizontalSign`
- `verticalSign`
- `depthSign`

From this one descriptor, the app derives:

- project model point -> screen point
- unproject screen point -> model point
- planar pan
- focal zoom
- fit-to-bounds width/height
- grid generation
- level line generation

## Cardinal views

Current mappings:

- `2D` = `X/Y` plane, `Z` depth
- `North` = `X/Z` plane, looking along `-Y`
- `South` = `X/Z` plane, looking along `+Y`
- `East` = `Y/Z` plane, looking along `-X`
- `West` = `Y/Z` plane, looking along `+X`

This is why `North/South` mirror each other horizontally, and `East/West`
mirror each other horizontally, while all elevation views keep vertical `Z`
behavior consistent.

## 3D relationship

The cardinal view specs also store preferred orbit direction metadata for 3D.
They also store an explicit `viewDirection` vector so the semantic meaning of
each orthographic view is written down directly, not inferred indirectly from
camera yaw alone.

When switching from an elevation view back to `3D`, the orbit camera now opens
from the matching side direction instead of jumping to an unrelated generic
camera angle.

This helps keep the mental model consistent:

- `North` 2D view corresponds to a north-facing 3D camera direction
- `East` 2D view corresponds to an east-facing 3D camera direction

Current view directions:

- `North` -> `(0, -1, 0)`
- `South` -> `(0, 1, 0)`
- `East` -> `(-1, 0, 0)`
- `West` -> `(1, 0, 0)`
- `2D` plan -> `(0, 0, -1)`

## Intentional plan-only behavior

Not every edit affordance should exist in every 2D mode.

There is an intentional distinction between:

- shared projection math
- plan-only footprint editing UX

Example plan-only behaviors:

- thick wall footprint draft fill
- wall endpoint grip handles in plan

These are intentionally gated through semantic helpers such as:

- `supportsPlanFootprintEditing`

This keeps the architecture unified without pretending that every editing tool
belongs in every orthographic view.

## Why this is better

Before this change, there was a real risk that side/front/elevation views could
become “special case” renderers with duplicated math.

Now:

- new orthographic views can be added from one registry
- labels and toolbar buttons come from the same source
- controller fallback rules are centralized
- projection behavior is regression-tested

## Regression coverage

The widget tests currently verify:

- cardinal specs come from one projection registry
- `North/South/East/West` are true planar re-projections of one model
- interaction fallback uses shared defaults
- switching from elevation to 3D preserves directional meaning

## Known limits

- orthographic visual styling is still a fallback painter, not final hidden-line CAD output
- section/cut-plane rendering is not implemented yet
- some editing tools remain intentionally plan-only

## Next good step

The next architectural step is not more projection branching.

It is improving the orthographic visual language on top of the unified
projection system:

- hidden-line cleanup
- cut-line emphasis
- cleaner elevation graphics
