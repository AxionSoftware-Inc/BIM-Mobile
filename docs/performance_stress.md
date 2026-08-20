# Performance Stress

This note describes the synthetic large-model stress cases used to harden the engine without turning timing into a brittle pass/fail gate.

## Scenarios

- 5x5 room grid.
- 10x10 room grid.
- 20x20 room grid when the CLI is asked for it and the machine can handle it comfortably.
- Optional openings, floor systems, ceiling systems, slab, roof, columns, beams, and stair placeholder elements.
- Engine-authored residential templates: `1 × 9` storey tower and `6 × 9`
  storey campus. These are the mandatory authoring regression scenarios.

## What we measure

- Model generation.
- Auto-join.
- Room detection.
- Geometry regeneration.
- Schedule generation.
- Material takeoff generation.
- Validation.
- JSON save and load.
- Package export and import.
- Spatial index rebuild and query.

## Why there are no strict timing assertions

- Hardware varies too much between laptops, desktops, and CI.
- The goal is to catch regressions in correctness and obvious algorithmic blowups, not to fail a run because a CPU is busy.
- CLI output is still useful for comparing runs manually or in perf notes.

## Current expectations

- 10x10 should remain practical for local development.
- 20x20 may be slower, but it should still complete without crashes or invalid state.
- Cached and final recompute paths should leave the model clean when expected.
- The native API test always creates both `1 × 9` and `6 × 9` templates and
  requests a nearby-level snapshot. A crash, invalid snapshot, or loss of the
  authoritative engine path fails CI.

## Local template benchmark

Run this after an engine change; it does not build or install Flutter/Android:

```sh
cmake --build build --target tbe_cli
./build/apps/tbe_cli/tbe_cli --benchmark-template --buildings 1 --stories 9 --device-class mid
./build/apps/tbe_cli/tbe_cli --benchmark-template --buildings 6 --stories 9 --device-class flagship
```

The report measures native template creation, nearby snapshot, final compute,
save and reload, plus object/vertex/triangle counts. `Correctness gate: PASS`
is required. The device-class geometry budget is an early review signal, not a
substitute for Android CPU, FPS and thermal telemetry on a real tablet.

## Limitations

- The stress model is orthogonal and synthetic.
- It does not replace real customer datasets.
- Timing results are informative, not contractual.
