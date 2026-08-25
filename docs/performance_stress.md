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

## 100k element contract

Run the reproducible large-model gate with:

```sh
tbe_cli --benchmark-large-model --element-count 100000 --memory-budget-mib 768
```

It creates at least 100,000 lightweight semantic level elements plus a small
real mesh set and checks strict load, full project payload sizing, nearby-level
streaming reduction, worker-thread loading, object-count correctness, and a
resident-memory budget. This isolates 100k-element session behavior;
residential geometry stress remains in the template benchmark.

The scheduled/manual `.github/workflows/performance.yml` runs the same contract
with a 1536 MiB CI-host budget. Android profiling is still required for frame
time and thermal acceptance on real tablets.

## Limitations

- The stress model is orthogonal and synthetic.
- It does not replace real customer datasets.
- Timing results are informative, not contractual.
