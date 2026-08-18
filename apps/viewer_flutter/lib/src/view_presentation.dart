import 'package:flutter/foundation.dart';

import 'render_scene_viewport_types.dart';

/// Immutable display state shared by opened views and sheet placements.
///
/// Geometry and camera position stay in the viewport controller. This value
/// only describes how a view is presented, so view tabs, sheets and sections
/// can exchange it without duplicating field semantics.
@immutable
class ViewPresentation {
  const ViewPresentation({
    this.displayStyle = RenderSceneDisplayStyle.solid,
    this.shadowsEnabled = false,
    this.orbitProjectionStyle = RenderSceneOrbitProjectionStyle.perspective,
  });

  final RenderSceneDisplayStyle displayStyle;
  final bool shadowsEnabled;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;

  ViewPresentation copyWith({
    RenderSceneDisplayStyle? displayStyle,
    bool? shadowsEnabled,
    RenderSceneOrbitProjectionStyle? orbitProjectionStyle,
  }) {
    return ViewPresentation(
      displayStyle: displayStyle ?? this.displayStyle,
      shadowsEnabled: shadowsEnabled ?? this.shadowsEnabled,
      orbitProjectionStyle: orbitProjectionStyle ?? this.orbitProjectionStyle,
    );
  }
}
