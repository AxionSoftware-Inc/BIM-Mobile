# Android renderer source ownership

The Kotlin package intentionally remains `com.example.viewer_flutter` while files are grouped by responsibility. Kotlin source discovery is recursive, so this is a source-layout refactor only and does not change runtime symbols.

- `MainActivity.kt` — Flutter host/composition entrypoint.
- `native/cache/` — BIM cache bridge.
- `native/family/` — family instancing policy.
- `native/telemetry/` — process/native telemetry.
- `renderer/host/` — Filament lifecycle/orchestration host.
- `renderer/platform/` — Flutter platform-view adapter.
- `renderer/geometry/` — edge/topology/projection geometry helpers.
- `renderer/materials/` — renderer material and architectural material policies.
- `renderer/streaming/` — spatial streaming policy.
- `renderer/stability/` — viewport stability guardrails.
- `renderer/benchmark/` — benchmark harness.

New renderer responsibilities must go into the narrowest owner directory rather than growing the host class. The Filament host is orchestration debt: behavior-preserving extraction should continue until lifecycle/orchestration remains there and geometry/material/streaming policies live in dedicated collaborators.
