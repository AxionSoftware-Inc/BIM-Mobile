# IFC native cache tablet benchmark

Device: Xiaomi Pad 7 / 25099RP13G, Android debug build.  Model: the bundled
OpenIFC PRIMARK IFC (8,420 mapped elements, 313,196 triangles).

The IFC source and authoritative LOD0 geometry are not simplified or changed
by either run.  `OLD_JSON` is the legacy route that exports the render scene
as JSON and transfers it through Flutter/Android.  `NEW_BIMCACHE` keeps vertex
and index buffers native and sends only cache metadata to the application UI.

| Metric | OLD JSON | NEW BIMCACHE, warm cache | Change |
| --- | ---: | ---: | ---: |
| Result | Failed: Java heap OOM before a stable first frame | Passed | Removes the blocker |
| First visible frame | N/A | 163 ms | N/A (old run did not render) |
| Full scene ready | N/A | 339 ms | N/A |
| Cache apply | N/A | 160 ms | N/A |
| Idle FPS | N/A | 116.12 | N/A |
| Orbit FPS | N/A | 116.57 | N/A |
| Zoom/pan FPS | N/A | 116.56 | N/A |
| Average / p95 / p99 frame | N/A | 8.59 / 8.33 / 16.67 ms | N/A |
| CPU scene-submit average / p95 | N/A | 0.48 / 0.92 ms | N/A |
| Filament renderables / draw calls | N/A | 14 / 14 | 8,420 IFC elements are batched |
| Loaded / visible chunks | N/A | 14 / 14 | Native spatial streaming |
| Native cache bytes | 121,793,275 B JSON cache | 9,363,248 B BIM cache | **92.3% smaller (13.0x)** |
| Java / native heap at measured render point | Old run OOM at a 256 MB Java heap limit | 40.4 / 115.1 MB | Old run is not a stable A/B sample |
| GC events during measurement | Repeated blocking GC then OOM | 4 | Not directly comparable after an OOM |

The legacy JSON trial started processing at about 16:01:16 and terminated at
about 16:02:14.  It recorded 3.0--6.7 s main-thread `DartMessenger` stalls,
multiple 141--275 ms GCs, then allocation failures even for small objects.
Therefore it would be misleading to invent old-path FPS or readiness values.

The latest cold renderer run compiled in 16,025 ms and produced 9,363,248 B;
its first visible frame was 163 ms and full scene ready was 407 ms.  The warm
reopen above completed without recompilation.  A separate format-v2 device
smoke test also compiled and reopened the header, validating the source
fingerprint plus 8,420 object mappings (413,582 vertices, 939,588 indices).
Its first 16 bytes were:

```
54 42 45 42 49 4d 43 32 02 00 00 00 04 03 02 01
```

That is `TBEBIMC2`, format version 2, and the endian marker.

## Decision

The measured bottleneck is not Filament submission: native CPU submit remains
below 1 ms and the renderer has 14 batches.  The blocker is the legacy
JSON/Kotlin normalization and MethodChannel transfer.  Large IFC opens now use
the native-first hand-off: a tiny placeholder mounts the Android view, C++
opens or compiles the cache in the background, and Flutter receives compact
element bounds/metadata only.  The old JSON renderer remains a migration
fallback.

The next performance milestone is resident GPU-memory budgeting and eviction
(`visible → near → recently used → far`), measured on models that exceed the
current 14-chunk PRIMARK scene.  It must preserve source IFC data and cache
object/primitive mappings.
