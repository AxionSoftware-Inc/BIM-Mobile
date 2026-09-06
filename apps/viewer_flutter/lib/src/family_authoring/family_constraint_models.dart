/// Reference-plane and sketch-constraint data contract for `.bimfamily`.
///
/// The model is deliberately renderer-independent. The solver lives in
/// `family_constraint_solver.dart`; these objects only describe persistent
/// authoring intent.
enum FamilyReferencePlaneAxis { x, y }

enum FamilySketchConstraintKind {
  horizontal,
  vertical,
  coincident,
  pointOnReferencePlane,
  distance,
  parallel,
  perpendicular,
  equalLength,
  angle,
}

final class FamilyReferencePlane {
  const FamilyReferencePlane({
    required this.id,
    required this.name,
    required this.sketchId,
    required this.axis,
    required this.expression,
  });

  final String id;
  final String name;
  final String sketchId;
  final FamilyReferencePlaneAxis axis;

  /// Numeric expression evaluated with the selected Family Type.
  /// Examples: `0`, `width / 2`, `-height * 0.25`.
  final String expression;

  FamilyReferencePlane copyWith({
    String? name,
    String? sketchId,
    FamilyReferencePlaneAxis? axis,
    String? expression,
  }) =>
      FamilyReferencePlane(
        id: id,
        name: name ?? this.name,
        sketchId: sketchId ?? this.sketchId,
        axis: axis ?? this.axis,
        expression: expression ?? this.expression,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'sketch_id': sketchId,
        'axis': axis.name,
        'expression': expression,
      };

  static FamilyReferencePlane? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final name = raw['name']?.toString().trim() ?? '';
    final sketchId = raw['sketch_id']?.toString().trim() ?? '';
    final expression = raw['expression']?.toString().trim() ?? '';
    final axisName = raw['axis']?.toString();
    FamilyReferencePlaneAxis? axis;
    for (final candidate in FamilyReferencePlaneAxis.values) {
      if (candidate.name == axisName) {
        axis = candidate;
        break;
      }
    }
    if (id.isEmpty ||
        name.isEmpty ||
        sketchId.isEmpty ||
        expression.isEmpty ||
        axis == null) {
      return null;
    }
    return FamilyReferencePlane(
      id: id,
      name: name,
      sketchId: sketchId,
      axis: axis,
      expression: expression,
    );
  }
}

final class FamilySketchConstraint {
  const FamilySketchConstraint({
    required this.id,
    required this.sketchId,
    required this.kind,
    required this.pointAIndex,
    this.pointBIndex,
    this.pointCIndex,
    this.pointDIndex,
    this.referencePlaneId,
    this.expression,
  });

  final String id;
  final String sketchId;
  final FamilySketchConstraintKind kind;
  final int pointAIndex;
  final int? pointBIndex;

  /// Optional second segment for segment-to-segment constraints.
  final int? pointCIndex;
  final int? pointDIndex;
  final String? referencePlaneId;

  /// Numeric target evaluated with the active Family Type.
  /// `distance` uses family length units; `angle` uses degrees.
  final String? expression;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'sketch_id': sketchId,
        'kind': kind.name,
        'point_a': pointAIndex,
        if (pointBIndex != null) 'point_b': pointBIndex,
        if (pointCIndex != null) 'point_c': pointCIndex,
        if (pointDIndex != null) 'point_d': pointDIndex,
        if (referencePlaneId != null) 'reference_plane_id': referencePlaneId,
        if (expression?.trim().isNotEmpty == true)
          'expression': expression!.trim(),
      };

  static FamilySketchConstraint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final sketchId = raw['sketch_id']?.toString().trim() ?? '';
    final kindName = raw['kind']?.toString();
    FamilySketchConstraintKind? kind;
    for (final candidate in FamilySketchConstraintKind.values) {
      if (candidate.name == kindName) {
        kind = candidate;
        break;
      }
    }
    final pointA = _asInt(raw['point_a']);
    final pointB = _asInt(raw['point_b']);
    final pointC = _asInt(raw['point_c']);
    final pointD = _asInt(raw['point_d']);
    final referencePlaneId = raw['reference_plane_id']?.toString().trim();
    final expression = raw['expression']?.toString().trim();
    if (id.isEmpty || sketchId.isEmpty || kind == null || pointA == null) {
      return null;
    }
    return FamilySketchConstraint(
      id: id,
      sketchId: sketchId,
      kind: kind,
      pointAIndex: pointA,
      pointBIndex: pointB,
      pointCIndex: pointC,
      pointDIndex: pointD,
      referencePlaneId:
          referencePlaneId == null || referencePlaneId.isEmpty
              ? null
              : referencePlaneId,
      expression: expression == null || expression.isEmpty ? null : expression,
    );
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
