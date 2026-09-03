#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

fail_if_found() {
  local label="$1"
  local pattern="$2"
  shift 2
  if rg -n "$pattern" "$@"; then
    echo "Architecture violation: ${label}" >&2
    exit 1
  fi
}

flutter_root="apps/viewer_flutter/lib/src"

# Presentation and viewport modules only consume immutable scene models and
# callbacks. Native bridge details must stay below feature/application code.
fail_if_found \
  "presentation or sketch modules import native bridge" \
  "(tbe_ffi|native_engine_library_loader|native_viewer_session_factory)\\.dart" \
  "$flutter_root/render_scene_viewport.dart" \
  "$flutter_root/render_scene_viewport_controller.dart" \
  "$flutter_root/render_scene_viewport_painter.dart" \
  "$flutter_root/render_scene_viewport_planar.dart" \
  "$flutter_root/project_browser_panel.dart" \
  "$flutter_root/project_browser_views.dart" \
  "$flutter_root/workspace_chrome.dart" \
  "$flutter_root/tools/plan_sketch_geometry.dart" \
  "$flutter_root/tools/trim_extend_tool_controller.dart"

fail_if_found \
  "engine contracts depend on FFI or Flutter" \
  "(dart:(ffi|io)|package:flutter)" \
  "$flutter_root/viewer_engine_contracts.dart"

fail_if_found \
  "application shell constructs native sessions directly" \
  "(TbeViewerApi\\.|ViewerRepository\\()" \
  "$flutter_root/viewer_app.dart"

# Document analysis belongs to its own compilation unit. Keep this explicit so
# future edits do not silently return schedule/validation logic to Document.cpp.
fail_if_found \
  "Document.cpp contains analysis queries" \
  "Document::(validate_document|wall_room_adjacencies|generate_(wall|opening|room|slab|roof|column|beam|stair|floor_finish|ceiling|material_takeoff)_schedule|generate_material_takeoff)" \
  "src/core/src/Document.cpp"

# Opening contours are engine-authored render data. The Flutter fallback may
# project `featureEdges`, but it must never parse wall-opening metadata or
# reconstruct an aperture from mesh triangles.
fail_if_found \
  "Flutter viewport reconstructs opening contours from wall metadata" \
  "opening_profile|profile_corners" \
  "$flutter_root/render_scene_viewport_painter.dart" \
  "$flutter_root/render_scene_painter_render.dart"

# Inspector adapters must consume their element-family parameter model. Keep
# raw metadata decoding in one small boundary so adding a property cannot
# silently create a second schema inside a UI adapter.
fail_if_found \
  "Inspector adapters bypass typed element parameters" \
  "metadata\\[|metadata\\." \
  "$flutter_root/elements/inspectors"

# A hosted opening is one semantic change. Presentation/UI code cannot fall
# back to the old move-then-resize sequence, which could leave an invalid wall
# if the second command failed.
fail_if_found \
  "viewport performs split hosted-opening mutations" \
  "(moveHostedOpening|resizeOpening)" \
  "$flutter_root/authoring_command_service.dart" \
  "$flutter_root/viewer_viewport_surface_editing.dart" \
  "$flutter_root/viewer_workspace_ui_interactions.dart"
