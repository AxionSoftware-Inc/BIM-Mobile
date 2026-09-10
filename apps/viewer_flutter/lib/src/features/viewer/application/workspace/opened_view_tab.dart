import '../../../schedules/domain/project_schedule_kind.dart';
import '../../../../render_scene_models.dart';
import '../../domain/view/view_configuration.dart';
import '../../domain/view/view_presentation.dart';

/// A semantic reference to a view opened in the model workspace.
///
/// Geometry remains owned by the active project. A tab only stores the recipe
/// required to restore a view and its presentation preferences.
enum OpenedViewKind {
  threeD,
  floorPlan,
  elevation,
  section,
  sheet,
  schedule,
}

class OpenedViewTab {
  OpenedViewTab({
    required this.id,
    required this.label,
    required this.kind,
    this.projectionMode,
    this.levelId,
    this.section,
    this.sheetId,
    this.scheduleKind,
    RenderSceneDisplayStyle displayStyle = RenderSceneDisplayStyle.solid,
    bool shadowsEnabled = false,
    RenderSceneOrbitProjectionStyle orbitProjectionStyle =
        RenderSceneOrbitProjectionStyle.perspective,
  }) : presentation = ViewPresentation(
          displayStyle: displayStyle,
          shadowsEnabled: shadowsEnabled,
          orbitProjectionStyle: orbitProjectionStyle,
        );

  final String id;
  final String label;
  final OpenedViewKind kind;
  final RenderSceneProjectionMode? projectionMode;
  final int? levelId;
  final RenderSceneSection? section;
  final String? sheetId;
  final ProjectScheduleKind? scheduleKind;
  final ViewPresentation presentation;

  RenderSceneDisplayStyle get displayStyle => presentation.displayStyle;
  bool get shadowsEnabled => presentation.shadowsEnabled;
  RenderSceneOrbitProjectionStyle get orbitProjectionStyle =>
      presentation.orbitProjectionStyle;

  OpenedViewTab copyWith({
    RenderSceneProjectionMode? projectionMode,
    RenderSceneDisplayStyle? displayStyle,
    bool? shadowsEnabled,
    RenderSceneOrbitProjectionStyle? orbitProjectionStyle,
  }) {
    return OpenedViewTab(
      id: id,
      label: label,
      kind: kind,
      projectionMode: projectionMode ?? this.projectionMode,
      levelId: levelId,
      section: section,
      sheetId: sheetId,
      scheduleKind: scheduleKind,
      displayStyle: displayStyle ?? this.displayStyle,
      shadowsEnabled: shadowsEnabled ?? this.shadowsEnabled,
      orbitProjectionStyle: orbitProjectionStyle ?? this.orbitProjectionStyle,
    );
  }
}
