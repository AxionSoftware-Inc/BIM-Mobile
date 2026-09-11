import '../../../core/application/engine/viewer_element_authoring_gateway.dart';
import '../../../core/application/engine/viewer_project_session.dart';
import '../../../core/application/engine/viewer_level_authoring_gateway.dart';
import '../../../core/application/engine/viewer_opening_authoring_gateway.dart';
import '../../../core/application/engine/viewer_roof_authoring_gateway.dart';
import '../../../core/application/engine/viewer_stair_authoring_gateway.dart';
import '../../../core/application/engine/viewer_wall_authoring_gateway.dart';

/// Explicit composition of the independent authoring capabilities.
///
/// This is deliberately not a catch-all engine gateway. A caller receives the
/// smallest capability set needed by its use-case, while the native session
/// can still implement all capabilities at the composition boundary.
final class ViewerAuthoringPorts {
  const ViewerAuthoringPorts({
    required this.levels,
    required this.walls,
    required this.openings,
    required this.elements,
    required this.roofs,
    required this.stairs,
  });

  factory ViewerAuthoringPorts.fromSession(ViewerEngineSession session) {
    return ViewerAuthoringPorts(
      levels: session,
      walls: session,
      openings: session,
      elements: session,
      roofs: session,
      stairs: session,
    );
  }

  final ViewerLevelAuthoringGateway levels;
  final ViewerWallAuthoringGateway walls;
  final ViewerOpeningAuthoringGateway openings;
  final ViewerElementAuthoringGateway elements;
  final ViewerRoofAuthoringGateway roofs;
  final ViewerStairAuthoringGateway stairs;
}
