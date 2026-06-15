# Performance Stress

This note describes the synthetic large-model stress cases used to harden the engine without turning timing into a brittle pass/fail gate.

## Scenarios

- 5x5 room grid.
- 10x10 room grid.
- 20x20 room grid when the CLI is asked for it and the machine can handle it comfortably.
- Optional openings, floor systems, ceiling systems, slab, roof, columns, beams, and stair placeholder elements.

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

## Limitations

- The stress model is orthogonal and synthetic.
- It does not replace real customer datasets.
- Timing results are informative, not contractual.
