import 'dart:math' as math;

import 'family_document.dart';

/// A small, engine-independent preview result for the Family Authoring page.
///
/// This is deliberately not a project render mesh. The future native family
/// evaluator can consume the same document and produce a real mesh without
/// making the authoring UI depend on the project viewport.
final class FamilyPreviewShape {
  const FamilyPreviewShape({
    required this.profile,
    required this.depth,
    required this.source,
    this.angle = 360.0,
  });

  final List<FamilySketchPoint> profile;
  final double depth;
  final String source;
  final double angle;

  FamilyPreviewShape copyWith({
    List<FamilySketchPoint>? profile,
    double? depth,
    String? source,
    double? angle,
  }) {
    return FamilyPreviewShape(
      profile: profile ?? this.profile,
      depth: depth ?? this.depth,
      source: source ?? this.source,
      angle: angle ?? this.angle,
    );
  }
}

final class FamilyMeshVertex {
  const FamilyMeshVertex({required this.x, required this.y, required this.z});

  final double x;
  final double y;
  final double z;

  FamilyMeshVertex copyWith({double? x, double? y, double? z}) {
    return FamilyMeshVertex(
      x: x ?? this.x,
      y: y ?? this.y,
      z: z ?? this.z,
    );
  }
}

final class FamilyMeshFace {
  const FamilyMeshFace(this.indices);

  final List<int> indices;
}

/// Engine-independent evaluated mesh used by the family preview/evaluator
/// boundary. It is deliberately separate from the project's render mesh type.
final class FamilyEvaluatedMesh {
  const FamilyEvaluatedMesh({
    required this.vertices,
    required this.faces,
    required this.source,
    this.isApproximate = false,
  });

  final List<FamilyMeshVertex> vertices;
  final List<FamilyMeshFace> faces;
  final String source;
  final bool isApproximate;

  FamilyEvaluatedMesh copyWith({
    List<FamilyMeshVertex>? vertices,
    List<FamilyMeshFace>? faces,
    String? source,
    bool? isApproximate,
  }) {
    return FamilyEvaluatedMesh(
      vertices: vertices ?? this.vertices,
      faces: faces ?? this.faces,
      source: source ?? this.source,
      isApproximate: isApproximate ?? this.isApproximate,
    );
  }
}

abstract final class FamilyGeometryEvaluator {
  static FamilyPreviewShape evaluate(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    for (var index = document.features.length - 1; index >= 0; index--) {
      if (_isSolidFeature(document.features[index])) {
        return _evaluateFeature(document, type, index);
      }
    }
    return _boxShape(document, type);
  }

  static FamilyEvaluatedMesh evaluateMesh(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    for (var index = document.features.length - 1; index >= 0; index--) {
      if (_isSolidFeature(document.features[index])) {
        return _evaluateMeshFeature(document, type, index);
      }
    }
    return _boxMesh(document, type);
  }

  static FamilyEvaluatedMesh _evaluateMeshFeature(
    FamilyDocument document,
    FamilyTypeDefinition type,
    int index,
  ) {
    final feature = document.features[index];
    switch (feature.kind) {
      case FamilyFeatureKind.box:
        return _boxMesh(document, type);
      case FamilyFeatureKind.extrude:
        final shape = _profileFeatureShape(document, type, feature);
        return shape == null
            ? _boxMesh(document, type).copyWith(isApproximate: true)
            : _extrudeMesh(shape, feature.label);
      case FamilyFeatureKind.revolve:
        final shape = _profileFeatureShape(document, type, feature);
        return shape == null
            ? _boxMesh(document, type).copyWith(isApproximate: true)
            : _revolveMesh(shape, feature.label);
      case FamilyFeatureKind.transform:
        final previous = _inputOrPreviousSolidIndex(document, index, feature);
        final base = previous == null
            ? _boxMesh(document, type)
            : _evaluateMeshFeature(document, type, previous);
        return _transformMesh(document, type, base, feature);
      case FamilyFeatureKind.booleanUnion:
      case FamilyFeatureKind.booleanSubtract:
        final previous = _inputOrPreviousSolidIndex(document, index, feature);
        final base = previous == null
            ? _boxMesh(document, type)
            : _evaluateMeshFeature(document, type, previous);
        // Exact CSG is kept behind the family evaluator boundary. Until the
        // robust kernel is connected, retain the base mesh and mark it so the
        // caller cannot mistake this preview for final boolean geometry.
        return base.copyWith(
          source: feature.label.isEmpty
              ? _featureName(feature.kind)
              : feature.label,
          isApproximate: true,
        );
      case FamilyFeatureKind.freeformMesh:
        return _freeformMesh(feature) ??
            _boxMesh(document, type).copyWith(
              source: feature.label.isEmpty ? 'Freeform mesh' : feature.label,
              isApproximate: true,
            );
      case FamilyFeatureKind.profile:
        return _boxMesh(document, type);
    }
  }

  static FamilyPreviewShape _evaluateFeature(
    FamilyDocument document,
    FamilyTypeDefinition type,
    int index,
  ) {
    final feature = document.features[index];
    switch (feature.kind) {
      case FamilyFeatureKind.box:
        return _boxShape(document, type);
      case FamilyFeatureKind.extrude:
        final extrude = _profileFeatureShape(document, type, feature);
        return extrude ?? _boxShape(document, type);
      case FamilyFeatureKind.revolve:
        final revolve = _profileFeatureShape(document, type, feature);
        if (revolve == null) return _boxShape(document, type);
        final minX = revolve.profile.map((point) => point.x).reduce(math.min);
        final maxX = revolve.profile.map((point) => point.x).reduce(math.max);
        return revolve.copyWith(
          depth: math.max(maxX - minX, 0.1).toDouble(),
          angle: _resolveScalar(
            feature.parameters['angle'],
            document,
            type,
            fallback: 360,
          ).clamp(1.0, 360.0).toDouble(),
          source: feature.label.isEmpty ? 'Revolve' : feature.label,
        );
      case FamilyFeatureKind.booleanUnion:
      case FamilyFeatureKind.booleanSubtract:
      case FamilyFeatureKind.transform:
        final previous = _previousSolidIndex(document, index);
        final base = previous == null
            ? _boxShape(document, type)
            : _evaluateFeature(document, type, previous);
        return base.copyWith(
          source: feature.label.isEmpty
              ? _featureName(feature.kind)
              : feature.label,
        );
      case FamilyFeatureKind.freeformMesh:
        return _boxShape(
          document,
          type,
        ).copyWith(
            source: feature.label.isEmpty ? 'Freeform mesh' : feature.label);
      case FamilyFeatureKind.profile:
        return _boxShape(document, type);
    }
  }

  static FamilyPreviewShape? _profileFeatureShape(
    FamilyDocument document,
    FamilyTypeDefinition type,
    FamilyFeature feature,
  ) {
    final profileId = feature.parameters['profileId']?.toString();
    FamilySketch? sketch;
    for (final item in document.sketches) {
      if (item.id == profileId) {
        sketch = item;
        break;
      }
    }
    if (sketch == null || !sketch.isValid) return null;
    return FamilyPreviewShape(
      profile: sketch.points,
      depth: _resolveLength(
        feature.parameters['depth'],
        document,
        type,
        fallback: 1.0,
      ),
      angle: feature.kind == FamilyFeatureKind.revolve
          ? _resolveScalar(
              feature.parameters['angle'],
              document,
              type,
              fallback: 360,
            ).clamp(1.0, 360.0).toDouble()
          : 360.0,
      source: feature.label.isEmpty ? sketch.name : feature.label,
    );
  }

  static FamilyEvaluatedMesh _boxMesh(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    final shape = _boxShape(document, type);
    return _extrudeMesh(shape, shape.source);
  }

  static FamilyEvaluatedMesh _extrudeMesh(
    FamilyPreviewShape shape,
    String source,
  ) {
    final profile = shape.profile;
    final count = profile.length;
    final vertices = <FamilyMeshVertex>[
      for (final point in profile)
        FamilyMeshVertex(x: point.x, y: point.y, z: 0),
      for (final point in profile)
        FamilyMeshVertex(x: point.x, y: point.y, z: shape.depth),
    ];
    final faces = <FamilyMeshFace>[
      FamilyMeshFace(List<int>.generate(count, (index) => index)),
      FamilyMeshFace(
        List<int>.generate(count, (index) => count + count - index - 1),
      ),
    ];
    for (var index = 0; index < count; index++) {
      final next = (index + 1) % count;
      faces
          .add(FamilyMeshFace(<int>[index, next, count + next, count + index]));
    }
    return FamilyEvaluatedMesh(
      vertices: List<FamilyMeshVertex>.unmodifiable(vertices),
      faces: List<FamilyMeshFace>.unmodifiable(faces),
      source: source,
    );
  }

  static FamilyEvaluatedMesh _revolveMesh(
    FamilyPreviewShape shape,
    String source,
  ) {
    final double angle = shape.angle.clamp(1.0, 360.0).toDouble();
    final fullRevolution = angle >= 359.999;
    final segments = math.max(8, (24 * angle / 360).ceil()).toInt();
    final rings = fullRevolution ? segments : segments + 1;
    final profile = shape.profile;
    final vertices = <FamilyMeshVertex>[];
    for (var segment = 0; segment < rings; segment++) {
      final radians = (segment / segments) * angle * math.pi / 180.0;
      final cosine = math.cos(radians);
      final sine = math.sin(radians);
      for (final point in profile) {
        final radius = point.x.abs();
        vertices.add(
          FamilyMeshVertex(
            x: radius * cosine,
            y: point.y,
            z: radius * sine,
          ),
        );
      }
    }
    final faces = <FamilyMeshFace>[];
    final faceSegments = fullRevolution ? segments : segments - 1;
    for (var segment = 0; segment < faceSegments; segment++) {
      final nextSegment = fullRevolution ? (segment + 1) % rings : segment + 1;
      for (var point = 0; point < profile.length - 1; point++) {
        final current = segment * profile.length + point;
        final nextPoint = current + 1;
        final nextRing = nextSegment * profile.length;
        faces.add(
          FamilyMeshFace(<int>[
            current,
            nextPoint,
            nextRing + point + 1,
            nextRing + point,
          ]),
        );
      }
    }
    if (!fullRevolution) {
      faces.add(
        FamilyMeshFace(
          List<int>.generate(profile.length, (index) => index),
        ),
      );
      final lastRing = (rings - 1) * profile.length;
      faces.add(
        FamilyMeshFace(
          List<int>.generate(
            profile.length,
            (index) => lastRing + profile.length - index - 1,
          ),
        ),
      );
    }
    return FamilyEvaluatedMesh(
      vertices: List<FamilyMeshVertex>.unmodifiable(vertices),
      faces: List<FamilyMeshFace>.unmodifiable(faces),
      source: source,
    );
  }

  static FamilyEvaluatedMesh _transformMesh(
    FamilyDocument document,
    FamilyTypeDefinition type,
    FamilyEvaluatedMesh base,
    FamilyFeature feature,
  ) {
    final translateX = _resolveScalar(
      feature.parameters['translationX'],
      document,
      type,
      fallback: 0,
    );
    final translateY = _resolveScalar(
      feature.parameters['translationY'],
      document,
      type,
      fallback: 0,
    );
    final translateZ = _resolveScalar(
      feature.parameters['translationZ'],
      document,
      type,
      fallback: 0,
    );
    final rotation = _resolveScalar(
          feature.parameters['rotationZ'],
          document,
          type,
          fallback: 0,
        ) *
        math.pi /
        180.0;
    final scale = _resolveScalar(
      feature.parameters['scale'],
      document,
      type,
      fallback: 1,
    );
    final cosine = math.cos(rotation);
    final sine = math.sin(rotation);
    final vertices = <FamilyMeshVertex>[];
    for (final vertex in base.vertices) {
      final x = vertex.x * scale;
      final y = vertex.y * scale;
      vertices.add(
        FamilyMeshVertex(
          x: x * cosine - y * sine + translateX,
          y: x * sine + y * cosine + translateY,
          z: vertex.z * scale + translateZ,
        ),
      );
    }
    return base.copyWith(
      vertices: List<FamilyMeshVertex>.unmodifiable(vertices),
      source: feature.label.isEmpty ? 'Transform' : feature.label,
    );
  }

  /// Reads a compact, editor-independent mesh payload used by curated
  /// families and by future freeform authoring tools. Keeping this parser in
  /// the evaluator means the project adapter receives the same validated
  /// mesh as the family preview without importing family files into the
  /// native document model.
  static FamilyEvaluatedMesh? _freeformMesh(FamilyFeature feature) {
    final rawVertices = feature.parameters['vertices'];
    final rawFaces = feature.parameters['faces'];
    if (rawVertices is! List || rawFaces is! List) return null;

    final vertices = <FamilyMeshVertex>[];
    for (final rawVertex in rawVertices) {
      double? x;
      double? y;
      double? z;
      if (rawVertex is List && rawVertex.length >= 3) {
        x = _finiteDouble(rawVertex[0]);
        y = _finiteDouble(rawVertex[1]);
        z = _finiteDouble(rawVertex[2]);
      } else if (rawVertex is Map) {
        x = _finiteDouble(rawVertex['x']);
        y = _finiteDouble(rawVertex['y']);
        z = _finiteDouble(rawVertex['z']);
      }
      if (x == null || y == null || z == null) return null;
      vertices.add(FamilyMeshVertex(x: x, y: y, z: z));
    }

    final faces = <FamilyMeshFace>[];
    for (final rawFace in rawFaces) {
      if (rawFace is! List || rawFace.length < 3) return null;
      final indices = <int>[];
      for (final rawIndex in rawFace) {
        final index =
            rawIndex is int ? rawIndex : int.tryParse(rawIndex.toString());
        if (index == null || index < 0 || index >= vertices.length) {
          return null;
        }
        indices.add(index);
      }
      faces.add(FamilyMeshFace(List<int>.unmodifiable(indices)));
    }
    if (vertices.isEmpty || faces.isEmpty) return null;
    return FamilyEvaluatedMesh(
      vertices: List<FamilyMeshVertex>.unmodifiable(vertices),
      faces: List<FamilyMeshFace>.unmodifiable(faces),
      source: feature.label.isEmpty ? 'Freeform mesh' : feature.label,
    );
  }

  static double? _finiteDouble(Object? raw) {
    final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
    return value != null && value.isFinite ? value : null;
  }

  static int? _previousSolidIndex(FamilyDocument document, int index) {
    for (var cursor = index - 1; cursor >= 0; cursor--) {
      if (_isSolidFeature(document.features[cursor])) return cursor;
    }
    return null;
  }

  static int? _inputOrPreviousSolidIndex(
    FamilyDocument document,
    int index,
    FamilyFeature feature,
  ) {
    for (final input in feature.inputs.reversed) {
      final inputIndex = document.features.indexWhere(
        (candidate) => candidate.id == input,
      );
      if (inputIndex >= 0 &&
          inputIndex < index &&
          _isSolidFeature(document.features[inputIndex])) {
        return inputIndex;
      }
    }
    return _previousSolidIndex(document, index);
  }

  static bool _isSolidFeature(FamilyFeature feature) {
    return feature.kind == FamilyFeatureKind.box ||
        feature.kind == FamilyFeatureKind.extrude ||
        feature.kind == FamilyFeatureKind.revolve ||
        feature.kind == FamilyFeatureKind.booleanUnion ||
        feature.kind == FamilyFeatureKind.booleanSubtract ||
        feature.kind == FamilyFeatureKind.transform ||
        feature.kind == FamilyFeatureKind.freeformMesh;
  }

  static String _featureName(FamilyFeatureKind kind) {
    return switch (kind) {
      FamilyFeatureKind.booleanUnion => 'Boolean union',
      FamilyFeatureKind.booleanSubtract => 'Boolean subtract',
      FamilyFeatureKind.transform => 'Transform',
      _ => kind.name,
    };
  }

  static FamilyPreviewShape _boxShape(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    final width = _resolveLength(
      _featureValue(document, FamilyFeatureKind.box, 'width'),
      document,
      type,
      fallback: 1.0,
    );
    final height = _resolveLength(
      _featureValue(document, FamilyFeatureKind.box, 'height'),
      document,
      type,
      fallback: 1.0,
    );
    final depth = _resolveLength(
      _featureValue(document, FamilyFeatureKind.box, 'depth'),
      document,
      type,
      fallback: 1.0,
    );
    return FamilyPreviewShape(
      profile: <FamilySketchPoint>[
        FamilySketchPoint(x: -width / 2, y: 0),
        FamilySketchPoint(x: width / 2, y: 0),
        FamilySketchPoint(x: width / 2, y: height),
        FamilySketchPoint(x: -width / 2, y: height),
      ],
      depth: depth,
      source: 'Box solid',
    );
  }

  static Object? _featureValue(
    FamilyDocument document,
    FamilyFeatureKind kind,
    String key,
  ) {
    for (final feature in document.features.reversed) {
      if (feature.kind == kind && feature.parameters.containsKey(key)) {
        return feature.parameters[key];
      }
    }
    return null;
  }

  static double _resolveLength(
    Object? raw,
    FamilyDocument document,
    FamilyTypeDefinition type, {
    required double fallback,
  }) {
    if (raw is num && raw.isFinite) return raw.toDouble().abs();
    final token = raw?.toString().trim();
    if (token == null || token.isEmpty) return fallback;
    final direct = double.tryParse(token.replaceAll(',', '.'));
    if (direct != null && direct.isFinite) return direct.abs();
    final parameter = document.parameters.firstWhere(
      (item) => item.id == token,
      orElse: () => const FamilyParameterDefinition(
        id: '',
        label: '',
        kind: FamilyParameterKind.number,
        defaultValue: null,
      ),
    );
    final value = type.values[token] ?? parameter.defaultValue;
    if (value is num && value.isFinite) return value.toDouble().abs();
    return fallback;
  }

  static double _resolveScalar(
    Object? raw,
    FamilyDocument document,
    FamilyTypeDefinition type, {
    required double fallback,
  }) {
    if (raw is num && raw.isFinite) return raw.toDouble();
    final token = raw?.toString().trim();
    if (token == null || token.isEmpty) return fallback;
    final direct = double.tryParse(token.replaceAll(',', '.'));
    if (direct != null && direct.isFinite) return direct;
    final parameter = document.parameters.firstWhere(
      (item) => item.id == token,
      orElse: () => const FamilyParameterDefinition(
        id: '',
        label: '',
        kind: FamilyParameterKind.number,
        defaultValue: null,
      ),
    );
    final value = type.values[token] ?? parameter.defaultValue;
    if (value is num && value.isFinite) return value.toDouble();
    return fallback;
  }
}
