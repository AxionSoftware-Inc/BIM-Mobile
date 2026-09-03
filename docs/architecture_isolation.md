# Viewer architecture isolation

This document defines the explicit boundary between the authoritative BIM
model and viewport presentation on `main`.

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

## Element module boundary

The Flutter application resolves element identity and cross-cutting
capabilities through `elements/bim_element_registry.dart`. Wall, door, window,
floor, ceiling, roof, slab, level, room, column, beam, stair, and imported
proxy elements each have a small module with its own aliases, display name,
level-hosting behavior, plan participation, type family, and Inspector adapter
route. This replaces shared policy lists as the place where a new element is
introduced.

Inspector routing is centralized in `elements/inspector_registry.dart`, but
element parameters and their UI/apply behavior are isolated under
`elements/inspectors/*_inspector.dart`. `PropertyEditor` owns only the common
target shell, selection/view-range plumbing, shared controls, and the delete
action. It does not contain an object-kind switch. Adding an editable element
therefore means adding its element module route and one adapter file; existing
wall, opening, surface, and roof inspectors remain untouched.

Type records use `BimElementTypeDefinition` and `BimElementTypeCatalog`. The
native `ProjectCatalog` is the single bootstrap point for standard materials,
wall types, and floor/roof/stair assemblies; templates and the API reuse its
document-local IDs instead of defining parallel catalogs. Flutter exposes the
same records to the Inspector through `elements/wall_type_catalog.dart` and
`elements/floor_type_catalog.dart`, while the native document remains the
source of truth for persistence and geometry. A legacy Wall-kind assembly is
accepted only as a load-time compatibility format and is normalized to one
`WallTypeData` source before an engine scene is exposed. A wall can therefore
never have both `wall_type_id` and `assembly_id` in a loaded authoring project.
Inspector layer edits use one native wall-type upsert command with
copy-on-write: a type is edited in place only while it has one wall user; a
shared type is cloned at most once and then reused by later edits. UI code must
not implement a create-type-then-assign sequence for an existing wall.

The document deliberately separates authored instances from type definitions.
Each wall/opening/floor keeps a lightweight identity, placement, constraints,
relations, and edit history because selection, hosting, joins, and undo/redo
need that identity. Repeated instances reference one shared type record by ID,
so layers, materials, and type-level geometry inputs are stored once. A future
render prototype cache can therefore use a key such as
`(type/assembly revision, instance geometry parameters)` without changing the
authoring model or collapsing logical elements into one object.

Element-specific geometry and commands remain behind the authoring/repository
boundary. The module registry owns semantics, not generated meshes, camera
state, or FFI calls. This prevents a wall type or opening type change from
coupling to the frozen Filament renderer.

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
| Wall type/material layers | Native wall-type command + Inspector | Scene data changes; viewport policy unchanged |
| Plan range/category defaults | `ViewerViewportScenePolicy` | Presentation only |
| Camera/gesture behavior | Viewport camera/gesture modules | Camera only |
| Inspector property display | `InspectorController` + `PropertyEditor` | Selection/UI only |
| Filament material/edge rendering | Native viewport host | Renderer only; keep freeze comment |
| Element identity/capabilities/types | `elements/*_element_module.dart` + registry | Shared semantic policy only |

When a change crosses more than one row, add a focused module test for the
boundary instead of wiring the new behavior into a widget callback.

### Adding a new element or type

1. Add one element module with aliases, capabilities, and a type family.
2. Register it in `BimElementRegistry.standardModules`.
3. Add native payload/commands and a gateway only if the element is
   authorable; keep that code out of viewport widgets.
4. Add the Inspector adapter under `elements/inspectors/` and register its
   route in the element module; add a focused module test.
5. Add a renderer branch only for genuinely new visual semantics; do not edit
   the frozen Filament host for ordinary type/catalog changes.
