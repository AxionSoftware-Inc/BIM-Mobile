# Viewer architecture isolation

This branch establishes an explicit boundary between the authoritative BIM
model and viewport presentation.

## Invariants

- Wall, door, window, level, surface, and assembly changes produce an
  authoritative `RenderScene` through the engine/repository layer.
- Wall creation, its level constraint, and an eligible endpoint auto-join are
  one native-session transaction; no intermediate wall snapshot is exposed.
- The viewport receives that snapshot through `_applySceneChange`, the single
  presentation commit lane owned by `_sceneCommitQueue`.
- Native authoring calls use `_authoringQueue` in `ViewerRepository`, which
  serializes each FFI command together with its snapshot refresh.
- Projection filtering, default visible categories, plan-core visibility, and
  the default solid display style live in `ViewerViewportScenePolicy`.
- Selection is a central `SelectionController` concern. The shared workspace
  slot renders either `ProjectBrowserPanel` or `PropertyEditor` through the
  explicit `WorkspaceSidePanelTab` state; selecting a Level or model object
  opens the Inspector without creating a second selection or scene cache.
- Viewport code may render and select a snapshot; it must not regenerate BIM
  geometry or mutate authoring data.
- The native Filament renderer remains a frozen presentation boundary. Changes
  to wall or door authoring must not require edits in the native viewport
  host.

## Why the commit lane matters

Native mutations are asynchronous and the native session is mutable. The
repository queue ensures a door mutation cannot start while a wall command is
still refreshing its snapshot. The presentation queue then preserves the
order in which authoritative results are submitted before updating the
viewport, preventing a late result from replacing a newer visible snapshot.
Both queues recover after a failed operation so one engine error cannot leave
the authoring or presentation path permanently blocked.

## Safe change map

| Change | Primary boundary | Expected viewport impact |
| --- | --- | --- |
| Wall/door/window authoring | Engine/repository + authoring gateway | New immutable scene commit only |
| Material assembly/layers | Element assembly gateway | Scene data changes; viewport policy unchanged |
| Plan range/category defaults | `ViewerViewportScenePolicy` | Presentation only |
| Camera/gesture behavior | Viewport camera/gesture modules | Camera only |
| Inspector property display | `InspectorController` + `PropertyEditor` | Selection/UI only |
| Filament material/edge rendering | Native viewport host | Renderer only; keep freeze comment |

When a change crosses more than one row, add a focused module test for the
boundary instead of wiring the new behavior into a widget callback.
