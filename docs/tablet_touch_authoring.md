# Tablet Touch Authoring Contract

## Gesture model

- One finger edits while an authoring tool is active.
- Two fingers always pan and zoom; they never create geometry.
- Wall and stair use press-drag-release for a complete segment/run.
- Wall also supports tap-to-tap chaining. A committed endpoint becomes the
  next segment start until the user presses Done or cancels the draft.
- Floor, ceiling and roof Rectangle mode uses press-drag-release and commits
  the valid rectangle immediately.
- Boundary mode places consecutive snapped corners. Touching the first corner
  again closes and commits a valid loop.
- Pick Walls and Auto Room use enlarged touch targets. Contact resolves and
  highlights the candidate immediately because touch has no hover state.
- Undo removes one boundary point, one picked wall, or the active rectangle
  without leaving the tool.

## Picking and performance

Plan picking in an engine-backed project must use the core per-level spatial
index. The touch radius is converted from screen pixels to model metres and is
clamped so it stays usable at extreme zoom levels. The Flutter triangle picker
is only a fallback for non-engine scenes.

This is important for large projects: pointer movement must query nearby grid
buckets, not scan every triangle in every visible object.

## UI rules

- Context controls appear only while their tool is active.
- The context bar states the gesture in plain language and keeps Finish/Done,
  Undo and Cancel visible.
- Authoring and navigation do not require a desktop hover or right click.
- Numeric precision remains available in the Inspector after direct placement.

## Architecture boundary

- `RenderSceneViewport` translates pointer streams into tap/drag callbacks.
- Tool controllers own transient draft state and reversible touch decisions.
- `PlanSketchGeometry` owns grid, endpoint and orthogonal geometry rules.
- `ViewerApp` adapts a completed gesture to an engine transaction.
- The engine remains authoritative for BIM creation, joins, constraints and
  spatial hit candidates.
