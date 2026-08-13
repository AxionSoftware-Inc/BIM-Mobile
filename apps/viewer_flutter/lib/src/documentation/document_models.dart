import '../render_scene_models.dart';
import '../render_scene_viewport_types.dart';

enum DocumentationScope {
  currentFloorPlan,
  allFloorPlans,
}

class SheetDocumentSettings {
  const SheetDocumentSettings({
    required this.projectName,
    required this.author,
    required this.sheetPrefix,
    required this.scaleDenominator,
    required this.scope,
    required this.generatedAt,
  });

  final String projectName;
  final String author;
  final String sheetPrefix;
  final int scaleDenominator;
  final DocumentationScope scope;
  final DateTime generatedAt;

  String get safeFileName {
    final normalized = projectName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    return '${normalized.isEmpty ? 'tablet_bim' : normalized}_documentation.pdf';
  }

  SheetDocumentSettings copyWith({
    String? projectName,
    String? author,
    String? sheetPrefix,
    int? scaleDenominator,
    DocumentationScope? scope,
    DateTime? generatedAt,
  }) {
    return SheetDocumentSettings(
      projectName: projectName ?? this.projectName,
      author: author ?? this.author,
      sheetPrefix: sheetPrefix ?? this.sheetPrefix,
      scaleDenominator: scaleDenominator ?? this.scaleDenominator,
      scope: scope ?? this.scope,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }
}

class DocumentationSheet {
  const DocumentationSheet({
    required this.number,
    required this.title,
    required this.level,
  });

  final String number;
  final String title;
  final RenderSceneLevel level;
}

enum SheetViewKind {
  threeD,
  floorPlan,
  elevation,
  section,
}

/// Immutable browser payload used by the tablet drag-and-drop sheet workflow.
///
/// It contains only a semantic view reference. RenderScene snapshots are kept
/// outside the document model so a sheet cannot accidentally become a second
/// source of truth for building geometry.
class SheetViewReference {
  const SheetViewReference({
    required this.id,
    required this.label,
    required this.kind,
    required this.projectionMode,
    this.levelId,
    this.section,
    this.displayStyle = RenderSceneDisplayStyle.solid,
    this.shadowsEnabled = false,
    this.orbitProjectionStyle = RenderSceneOrbitProjectionStyle.perspective,
  });

  final String id;
  final String label;
  final SheetViewKind kind;
  final RenderSceneProjectionMode projectionMode;
  final int? levelId;
  final RenderSceneSection? section;
  final RenderSceneDisplayStyle displayStyle;
  final bool shadowsEnabled;
  final RenderSceneOrbitProjectionStyle orbitProjectionStyle;

  SheetViewReference copyWith({
    RenderSceneDisplayStyle? displayStyle,
    bool? shadowsEnabled,
    RenderSceneOrbitProjectionStyle? orbitProjectionStyle,
  }) {
    return SheetViewReference(
      id: id,
      label: label,
      kind: kind,
      projectionMode: projectionMode,
      levelId: levelId,
      section: section,
      displayStyle: displayStyle ?? this.displayStyle,
      shadowsEnabled: shadowsEnabled ?? this.shadowsEnabled,
      orbitProjectionStyle: orbitProjectionStyle ?? this.orbitProjectionStyle,
    );
  }
}

class SheetViewportPlacement {
  const SheetViewportPlacement({
    required this.id,
    required this.view,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String id;
  final SheetViewReference view;

  /// Normalized A3 paper coordinates. Keeping layout independent of pixels
  /// makes the same sheet deterministic on tablets and in PDF output.
  final double left;
  final double top;
  final double width;
  final double height;

  SheetViewportPlacement copyWith({
    SheetViewReference? view,
    double? left,
    double? top,
    double? width,
    double? height,
  }) {
    return SheetViewportPlacement(
      id: id,
      view: view ?? this.view,
      left: left ?? this.left,
      top: top ?? this.top,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}

class ProjectSheet {
  const ProjectSheet({
    required this.id,
    required this.number,
    required this.title,
    this.placements = const <SheetViewportPlacement>[],
  });

  final String id;
  final String number;
  final String title;
  final List<SheetViewportPlacement> placements;

  ProjectSheet copyWith({
    String? title,
    List<SheetViewportPlacement>? placements,
  }) {
    return ProjectSheet(
      id: id,
      number: number,
      title: title ?? this.title,
      placements: placements ?? this.placements,
    );
  }
}

List<DocumentationSheet> resolveDocumentationSheets({
  required RenderScene scene,
  required SheetDocumentSettings settings,
  required int? activeLevelId,
}) {
  final levels = scene.levels.toList(growable: false)
    ..sort((a, b) => a.elevationMeters.compareTo(b.elevationMeters));
  if (levels.isEmpty) return const <DocumentationSheet>[];
  final selectedLevels = settings.scope == DocumentationScope.allFloorPlans
      ? levels
      : <RenderSceneLevel>[
          scene.levelById(activeLevelId) ?? levels.first,
        ];
  final prefix = settings.sheetPrefix.trim().isEmpty
      ? 'A'
      : settings.sheetPrefix.trim().toUpperCase();
  return <DocumentationSheet>[
    for (var index = 0; index < selectedLevels.length; index += 1)
      DocumentationSheet(
        number: '$prefix${(101 + index).toString().padLeft(3, '0')}',
        title: _sheetTitle(selectedLevels[index]),
        level: selectedLevels[index],
      ),
  ];
}

String _sheetTitle(RenderSceneLevel level) {
  final lower = level.name.toLowerCase();
  if (lower.contains('roof')) return 'Roof Plan';
  return '${level.name} Floor Plan';
}
