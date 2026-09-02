# v0.1 Architecture Boundaries

The engine/BIM baseline is `0.1.0`. The Flutter package has an independent
mobile release version (currently `0.2.3+5`), so Play Store version codes never
need to be reduced when engine contracts evolve. A project document keeps
schema version `1`; the render-scene contract is version `2`. These versions
intentionally move independently: a rendering change must not mutate BIM
authoring data.

## Ownership

```
Document / commands
        |
GeometryService (wall solid + true opening void)
        |
Engine render scene v2 (mesh + feature_edges)
        |                         |
  BIM cache compiler              Flutter / Android adapters
        |                         |
  native cache renderer      projection, input, presentation only
```

- `Document` owns relationships, validation, undo/redo and hosted-opening
  transactions. It does not own viewport state.
- `GeometryService` is the only owner of a wall's physical mesh. A door or
  window cuts the host mesh before it reaches rendering.
- The API publishes `feature_edges`. Wall silhouettes and every opening's
  sill, head and jamb contours are explicit world-space segments.
- Flutter and Filament can choose colour, line width, camera and visibility,
  but do not infer opening contours from triangle adjacency or metadata.
- The BIM cache persists the same feature edges. Its compiler version is `12`
  and format is `3`; older caches are rejected and rebuilt deliberately.

## Change rules

1. A modeling change starts in `Document` and is verified with core tests.
2. A visual semantic change is added to the render-scene DTO and covered by an
   API test before either viewport consumes it.
3. A viewport change is limited to adapter/presentation modules. It cannot
   call FFI from painter or tool code, mutate `Document`, or parse wall opening
   metadata to create geometry.
4. Compatibility is explicit: new fields are optional to readers, but any
   cache binary layout change bumps the cache format/compiler versions.

This makes a wall/window defect diagnosable at one boundary: the physical cut
in core, its semantic edges in the API/cache, or a renderer that failed to
project those supplied edges.
