part of 'render_scene_editor.dart';

class _WallGeometry {
  const _WallGeometry({
    required this.start,
    required this.end,
    required this.thickness,
    this.centerline = const <RenderScenePoint>[],
  });

  final RenderScenePoint start;
  final RenderScenePoint end;
  final double thickness;
  final List<RenderScenePoint> centerline;

  List<RenderScenePoint> get path =>
      centerline.length >= 2 ? centerline : <RenderScenePoint>[start, end];

  double get length {
    final points = path;
    var total = 0.0;
    for (var index = 1; index < points.length; index += 1) {
      total += points[index - 1].distanceTo(points[index]);
    }
    return total;
  }

  bool get isCurved => centerline.length >= 3;
}

class _OpeningCutSpec {
  const _OpeningCutSpec({
    required this.startOffset,
    required this.endOffset,
    required this.bottomZ,
    required this.topZ,
  });

  final double startOffset;
  final double endOffset;
  final double bottomZ;
  final double topZ;
}

class _BuiltMeshResult {
  const _BuiltMeshResult({
    required this.mesh,
    required this.bounds,
  });

  final Map<String, Object?> mesh;
  final RenderSceneBounds bounds;
}

class _GridCell {
  const _GridCell(this.i, this.j);

  final int i;
  final int j;
}

class _ResolvedOpeningSpec {
  const _ResolvedOpeningSpec({
    required this.hostWall,
    required this.offsetMeters,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
    required this.panelThicknessMeters,
  });

  final _WallEntry hostWall;
  final double offsetMeters;
  final double widthMeters;
  final double heightMeters;
  final double sillHeightMeters;
  final double panelThicknessMeters;
}

class _WallEntry {
  const _WallEntry({
    required this.objectId,
    required this.objectMap,
    required this.geometry,
    required this.heightMeters,
  });

  final int objectId;
  final Map<String, Object?> objectMap;
  final _WallGeometry geometry;
  final double heightMeters;
}
