import 'dart:math' as math;

import 'family_constraint_solver.dart';
import 'family_csg.dart';
import 'family_document.dart';
import 'family_parameter_resolver.dart';

/// A small, engine-independent preview result for the Family Authoring page.
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
    final solved = _solveForPreview(document, type);
    for (var index = solved.features.length - 1; index >= 0; index--) {
      if (_isSolidFeature(solved.features[index])) {
        return _evaluateFeature(solved, type, index);
      }
    }
    return _boxShape(solved, type);
  }

  static FamilyEvaluatedMesh evaluateMesh(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    final solved = _solveForPreview(document, type);
    late final FamilyEvaluatedMesh mesh;
    for (var index = solved.features.length - 1; index >= 0; index--) {
      if (_isSolidFeature(solved.features[index])) {
        mesh = _evaluateMeshFeature(solved, type, index);
        return _fitMeshToTypeParameters(solved, type, mesh);
      }
    }
    return _fitMeshToTypeParameters(solved, type, _boxMesh(solved, type));
  }

  static FamilyDocument _solveForPreview(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    try {
      return FamilyConstraintSolver.solveDocument(document, type);
    } on FormatException {
      return document;
    }
  }

  static FamilyEvaluatedMesh _fitMeshToTypeParameters(
    FamilyDocument document,
    FamilyTypeDefinition type,
    FamilyEvaluatedMesh mesh,
  ) {
    if (mesh.vertices.isEmpty) return mesh;
    final width = _parameterLength(document, type, 'width');
    final depth = _parameterLength(document, type, 'depth');
    final height = _parameterLength(document, type, 'height');
    if (width == null && depth == null && height == null) return mesh;

    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final vertex in mesh.vertices) {
      minX = math.min(minX, vertex.x);
      minY = math.min(minY, vertex.y);
      minZ = math.min(minZ, vertex.z);
      maxX = math.max(maxX, vertex.x);
      maxY = math.max(maxY, vertex.y);
      maxZ = math.max(maxZ, vertex.z);
    }
    final sourceWidth = maxX - minX;
    final sourceHeight = maxY - minY;
    final sourceDepth = maxZ - minZ;
    final scaleX =
        width != null && sourceWidth > 1e-9 ? width / sourceWidth : 1.0;
    final scaleY =
        height != null && sourceHeight > 1e-9 ? height / sourceHeight : 1.0;
    final scaleZ =
        depth != null && sourceDepth > 1e-9 ? depth / sourceDepth : 1.0;
    if (scaleX == 1.0 && scaleY == 1.0 && scaleZ == 1.0) return mesh;

    final anchorX = minX < -1e-9 ? (minX + maxX) * 0.5 : minX;
    final anchorY = minY;
    final anchorZ = minZ < -1e-9 ? (minZ + maxZ) * 0.5 : minZ;
    final vertices = <FamilyMeshVertex>[
      for (final vertex in mesh.vertices)
        FamilyMeshVertex(
          x: anchorX + (vertex.x - anchorX) * scaleX,
          y: anchorY + (vertex.y - anchorY) * scaleY,
          z: anchorZ + (vertex.z - anchorZ) * scaleZ,
        ),
    ];
    return mesh.copyWith(
      vertices: List<FamilyMeshVertex>.unmodifiable(vertices),
    );
  }

  static double? _parameterLength(
    FamilyDocument document,
    FamilyTypeDefinition type,
    String id,
  ) {
    final parameter = _parameterById(document, id);
    if (parameter == null || parameter.kind != FamilyParameterKind.length) {
      return null;
    }
    try {
      final value = FamilyParameterResolver(document, type).resolveNumber(id);
      return value.isFinite && value > 0.0 ? value : null;
    } on FormatException {
      return null;
    }
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
        return _booleanMesh(document, type, index, feature);
      case FamilyFeatureKind.freeformMesh:
        return _freeformMesh(feature) ??
            _boxMesh(document, type).copyWith(
              source: feature.label.isEmpty ? 'Freeform mesh' : feature.label,
              isApproximate: true,
            );
      case FamilyFeatureKind.nestedFamily:
        throw FormatException(
          'Nested feature ${feature.id} must be resolved before geometry evaluation.',
        );
      case FamilyFeatureKind.profile:
        return _boxMesh(document, type);
    }
  }

  static FamilyEvaluatedMesh _booleanMesh(
    FamilyDocument document,
    FamilyTypeDefinition type,
    int index,
    FamilyFeature feature,
  ) {
    final inputIndices = _booleanInputIndices(document, index, feature);
    if (inputIndices.length < 2) {
      final previous = _previousSolidIndex(document, index);
      final fallback = previous == null
          ? _boxMesh(document, type)
          : _evaluateMeshFeature(document, type, previous);
      return fallback.copyWith(
        source: feature.label.isEmpty ? _featureName(feature.kind) : feature.label,
        isApproximate: true,
      );
    }

    final left = _evaluateMeshFeature(document, type, inputIndices[0]);
    final right = _evaluateMeshFeature(document, type, inputIndices[1]);
    final source = feature.label.isEmpty ? _featureName(feature.kind) : feature.label;
    final result = FamilyCsgKernel.apply(
      left: _toCsgMesh(left),
      right: _toCsgMesh(right),
      operation: feature.kind == FamilyFeatureKind.booleanUnion
          ? FamilyCsgOperation.union
          : FamilyCsgOperation.subtract,
    );
    if (result != null) return _fromCsgMesh(result, source: source);

    if (feature.kind == FamilyFeatureKind.booleanUnion) {
      return _mergeMeshes(left, right, source: source).copyWith(
        isApproximate: true,
      );
    }
    return left.copyWith(source: source, isApproximate: true);
  }

  static FamilyCsgMesh _toCsgMesh(FamilyEvaluatedMesh mesh) => FamilyCsgMesh(
        vertices: <FamilyCsgVertex>[
          for (final vertex in mesh.vertices)
            FamilyCsgVertex(vertex.x, vertex.y, vertex.z),
        ],
        faces: <FamilyCsgFace>[
          for (final face in mesh.faces)
            FamilyCsgFace(List<int>.unmodifiable(face.indices)),
        ],
      );

  static FamilyEvaluatedMesh _fromCsgMesh(
    FamilyCsgMesh mesh, {
    required String source,
  }) =>
      FamilyEvaluatedMesh(
        vertices: List<FamilyMeshVertex>.unmodifiable(
          mesh.vertices.map(
            (vertex) => FamilyMeshVertex(
              x: vertex.x,
              y: vertex.y,
              z: vertex.z,
            ),
          ),
        ),
        faces: List<FamilyMeshFace>.unmodifiable(
          mesh.faces.map(
            (face) => FamilyMeshFace(List<int>.unmodifiable(face.indices)),
          ),
        ),
        source: source,
      );

  static FamilyEvaluatedMesh _mergeMeshes(
    FamilyEvaluatedMesh left,
    FamilyEvaluatedMesh right, {
    required String source,
  }) {
    final offset = left.vertices.length;
    return FamilyEvaluatedMesh(
      vertices: List<FamilyMeshVertex>.unmodifiable(
        <FamilyMeshVertex>[...left.vertices, ...right.vertices],
      ),
      faces: List<FamilyMeshFace>.unmodifiable(
        <FamilyMeshFace>[
          ...left.faces,
          for (final face in right.faces)
            FamilyMeshFace(
              List<int>.unmodifiable(
                face.indices.map((index) => index + offset),
              ),
            ),
        ],
      ),
      source: source,
      isApproximate: true,
    );
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
        return _boxShape(document, type).copyWith(
          source: feature.label.isEmpty ? 'Freeform mesh' : feature.label,
        );
      case FamilyFeatureKind.nestedFamily:
        return _boxShape(document, type).copyWith(
          source: feature.label.isEmpty
              ? 'Nested family (resolve to preview)'
              : feature.label,
        );
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
      faces.add(
        FamilyMeshFace(<int>[index, next, count + next, count + index]),
      );
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
    final angle = shape.angle.clamp(1.0, 360.0).toDouble();
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
        FamilyMeshFace(List<int>.generate(profile.length, (index) => index)),
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

    // Family coordinates are X = width, Y = vertical/height, Z = depth.
    // The historical serialized field is named `rotationZ`, but the user-facing
    // Rotate tool is a plan/yaw rotation and must therefore rotate around the
    // Family Y (vertical) axis. Keep the serialized key for schema compatibility
    // while applying the physically correct vertical-axis transform here.
    final yaw = _resolveScalar(
          feature.parameters['rotationY'] ?? feature.parameters['rotationZ'],
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
    final cosine = math.cos(yaw);
    final sine = math.sin(yaw);
    final vertices = <FamilyMeshVertex>[];
    for (final vertex in base.vertices) {
      final x = vertex.x * scale;
      final y = vertex.y * scale;
      final z = vertex.z * scale;
      vertices.add(
        FamilyMeshVertex(
          x: x * cosine + z * sine + translateX,
          y: y + translateY,
          z: -x * sine + z * cosine + translateZ,
        ),
      );
    }
    return base.copyWith(
      vertices: List<FamilyMeshVertex>.unmodifiable(vertices),
      source: feature.label.isEmpty ? 'Transform' : feature.label,
    );
  }

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
        if (index == null || index < 0 || index >= vertices.length) return null;
        indices.add(index);
      }
      faces.add(FamilyMeshFace(List<int>.unmodifiable(indices));
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

  static List<int> _booleanInputIndices(
    FamilyDocument document,
    int index,
    FamilyFeature feature,
  ) {
    final result = <int>[];
    for (final input in feature.inputs) {
      final inputIndex = document.features.indexWhere(
        (candidate) => candidate.id == input,
      );
      if (inputIndex >= 0 &&
          inputIndex < index &&
          _isSolidFeature(document.features[inputIndex]) &&
          !result.contains(inputIndex)) {
        result.add(inputIndex);
        if (result.length == 2) return result;
      }
    }

    for (var cursor = index - 1; cursor >= 0 && result.length < 2; cursor--) {
      if (_isSolidFeature(document.features[cursor]) &&
          !result.contains(cursor)) {
        result.add(cursor);
      }
    }
    if (feature.inputs.isEmpty && result.length == 2) {
      return result.reversed.toList(growable: false);
    }
    return result;
  }

  static bool _isSolidFeature(FamilyFeature feature) {
    return feature.kind == FamilyFeatureKind.box ||
        feature.kind == FamilyFeatureKind.extrude ||
        feature.kind == FamilyFeatureKind.revolve ||
        feature.kind == FamilyFeatureKind.booleanUnion ||
        feature.kind == FamilyFeatureKind.booleanSubtract ||
        feature.kind == FamilyFeatureKind.transform ||
        feature.kind == FamilyFeatureKind.freeformMesh ||
        feature.kind == FamilyFeatureKind.nestedFamily;
  }

  static String _featureName(FamilyFeatureKind kind) {
    return switch (kind) {
      FamilyFeatureKind.booleanUnion => 'Boolean union',
      FamilyFeatureKind.booleanSubtract => 'Boolean subtract',
      FamilyFeatureKind.transform => 'Transform',
      FamilyFeatureKind.nestedFamily => 'Nested family',
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
    final parameter = _parameterById(document, token);
    if (parameter == null) return fallback;
    try {
      final value = FamilyParameterResolver(document, type).resolveNumber(token);
      return value.isFinite ? value.abs() : fallback;
    } on FormatException {
      return fallback;
    }
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
    final parameter = _parameterById(document, token);
    if (parameter == null) return fallback;
    try {
      return FamilyParameterResolver(document, type).resolveNumber(token);
    } on FormatException {
      return fallback;
    }
  }

  static FamilyParameterDefinition? _parameterById(
    FamilyDocument document,
    String id,
  ) {
    for (final parameter in document.parameters) {
      if (parameter.id == id) return parameter;
    }
    return null;
  }
}
