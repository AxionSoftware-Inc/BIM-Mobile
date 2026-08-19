# Edit command contract

All interactive clients use the same command names and payload fields. The
native `tbe_apply_command` executable is the reference adapter for the local
Next.js bridge; the C++ API methods are the canonical implementation of each
operation.

Every command is a JSON object with a required `type` field. Numeric values are
finite SI metres and element identifiers are positive integers.

| Command | Required payload |
| --- | --- |
| `create_wall` | `start`, `end`, `thickness_meters`, `height_meters` |
| `insert_door` | `host_wall_id`, `offset_meters`, `width_meters`, `height_meters` |
| `insert_window` | `host_wall_id`, `offset_meters`, `width_meters`, `height_meters`, `sill_height_meters` |
| `delete_element` | `element_id` |
| `set_wall_axis` | `wall_id`, `start`, `end` |
| `update_wall_properties` | `wall_id`, `thickness_meters`, `height_meters` |
| `update_door_properties` | `door_id`, `offset_meters`, `width_meters`, `height_meters` |
| `update_window_properties` | `window_id`, `offset_meters`, `width_meters`, `height_meters`, `sill_height_meters` |
| `move_hosted_opening` | `opening_id`, `offset_meters` |

The local bridge returns one envelope shape:

```json
{
  "success": true,
  "command": "create_wall",
  "message": "...",
  "validation": { "errors": 0, "warnings": 0 },
  "updatedFiles": [],
  "output": "",
  "error": null,
  "commandOutput": {}
}
```

After a successful mutation, `project.json`, `render_scene.json`, and the
optional debug/export artifacts are regenerated from the same native session.
Clients must not mutate semantic project JSON directly.
