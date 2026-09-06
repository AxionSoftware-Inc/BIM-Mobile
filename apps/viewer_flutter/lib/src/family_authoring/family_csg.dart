import 'dart:math' as math;

/// Boolean operation supported by the family solid kernel.
enum FamilyCsgOperation { union, subtract }

final class FamilyCsgVertex {
  const FamilyCsgVertex(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

final class FamilyCsgFace {
  const FamilyCsgFace(this.indices);

  final List<int> indices;
}

final class FamilyCsgMesh {
  const FamilyCsgMesh({required this.vertices, required this.faces});

  final List<FamilyCsgVertex> vertices;
  final List<FamilyCsgFace> faces;
}

/// Dependency-free BSP solid kernel used by Family Authoring boolean features.
///
/// The input contract is deliberately strict: both operands must be finite,
/// closed, orientable two-manifold meshes. Face winding is normalized before
/// BSP evaluation, so imported meshes do not need to use the same winding as
/// the native family primitives. Invalid/open inputs return `null` instead of
/// producing a plausible-looking but topologically incorrect project mesh.
abstract final class FamilyCsgKernel {
  static const double _epsilon = 1.0e-7;

  static FamilyCsgMesh? apply({
    required FamilyCsgMesh left,
    required FamilyCsgMesh right,
    required FamilyCsgOperation operation,
  }) {
    final normalizedLeft = _normalizeClosedMesh(left);
    final normalizedRight = _normalizeClosedMesh(right);
    if (normalizedLeft == null || normalizedRight == null) return null;

    final leftPolygons = _polygonsFromMesh(normalizedLeft);
    final rightPolygons = _polygonsFromMesh(normalizedRight);
    if (leftPolygons.isEmpty || rightPolygons.isEmpty) return null;

    try {
      final a = _Solid(leftPolygons);
      final b = _Solid(rightPolygons);
      final result = switch (operation) {
        FamilyCsgOperation.union => a.union(b),
        FamilyCsgOperation.subtract => a.subtract(b),
      };
      final mesh = _meshFromPolygons(result.polygons);
      if (mesh == null || mesh.faces.isEmpty || mesh.vertices.isEmpty) {
        return null;
      }
      return mesh;
    } catch (_) {
      // A CSG failure must remain contained inside the family evaluator. The
      // caller can preserve an approximate preview without corrupting project
      // geometry or crashing the editor.
      return null;
    }
  }

  /// Useful at import/diagnostic boundaries. This checks topology and winding
  /// orientability; the kernel then normalizes every connected component.
  static bool isClosedTwoManifold(FamilyCsgMesh mesh) =>
      _normalizeClosedMesh(mesh) != null;

  static FamilyCsgMesh? _normalizeClosedMesh(FamilyCsgMesh mesh) {
    if (mesh.vertices.length < 4 || mesh.faces.length < 4) return null;
    for (final vertex in mesh.vertices) {
      if (!vertex.x.isFinite || !vertex.y.isFinite || !vertex.z.isFinite) {
        return null;
      }
    }

    final faces = <List<int>>[];
    for (final face in mesh.faces) {
      if (face.indices.length < 3) return null;
      final indices = <int>[];
      for (final index in face.indices) {
        if (index < 0 || index >= mesh.vertices.length) return null;
        if (indices.isEmpty || indices.last != index) indices.add(index);
      }
      if (indices.length > 1 && indices.first == indices.last) {
        indices.removeLast();
      }
      if (indices.length < 3 || indices.toSet().length < 3) return null;
      faces.add(indices);
    }

    final edgeUses = <String, List<_EdgeUse>>{};
    String edgeKey(int a, int b) => a < b ? '$a:$b' : '$b:$a';
    for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
      final face = faces[faceIndex];
      for (var i = 0; i < face.length; i++) {
        final from = face[i];
        final to = face[(i + 1) % face.length];
        if (from == to) return null;
        edgeUses
            .putIfAbsent(edgeKey(from, to), () => <_EdgeUse>[])
            .add(_EdgeUse(faceIndex, from, to));
      }
    }
    if (edgeUses.values.any((uses) => uses.length != 2)) return null;

    final adjacency = <List<_FaceAdjacency>>[
      for (var index = 0; index < faces.length; index++) <_FaceAdjacency>[],
    ];
    for (final uses in edgeUses.values) {
      final a = uses[0];
      final b = uses[1];
      final sameDirection = a.from == b.from && a.to == b.to;
      adjacency[a.face].add(_FaceAdjacency(b.face, sameDirection));
      adjacency[b.face].add(_FaceAdjacency(a.face, sameDirection));
    }

    final flips = List<bool?>.filled(faces.length, null);
    final components = <List<int>>[];
    for (var seed = 0; seed < faces.length; seed++) {
      if (flips[seed] != null) continue;
      flips[seed] = false;
      final queue = <int>[seed];
      var cursor = 0;
      while (cursor < queue.length) {
        final face = queue[cursor++];
        final currentFlip = flips[face]!;
        for (final neighbor in adjacency[face]) {
          final expected = currentFlip ^ neighbor.sameDirection;
          final existing = flips[neighbor.face];
          if (existing == null) {
            flips[neighbor.face] = expected;
            queue.add(neighbor.face);
          } else if (existing != expected) {
            // Non-orientable or inconsistent topology.
            return null;
          }
        }
      }
      components.add(List<int>.unmodifiable(queue));
    }

    final oriented = <List<int>>[
      for (var i = 0; i < faces.length; i++)
        flips[i] == true ? faces[i].reversed.toList() : List<int>.of(faces[i]),
    ];

    // Each disconnected shell needs its own outward orientation. Using one
    // global signed volume can make two opposite shells cancel each other.
    for (final component in components) {
      final componentFaces = <List<int>>[
        for (final faceIndex in component) oriented[faceIndex],
      ];
      final volume = _signedVolume(mesh.vertices, componentFaces);
      if (!volume.isFinite || volume.abs() <= _epsilon) return null;
      if (volume < 0.0) {
        for (final faceIndex in component) {
          oriented[faceIndex] = oriented[faceIndex].reversed.toList();
        }
      }
    }

    return FamilyCsgMesh(
      vertices: List<FamilyCsgVertex>.unmodifiable(mesh.vertices),
      faces: List<FamilyCsgFace>.unmodifiable(
        oriented.map(
          (indices) => FamilyCsgFace(List<int>.unmodifiable(indices)),
        ),
      ),
    );
  }

  static double _signedVolume(
    List<FamilyCsgVertex> vertices,
    List<List<int>> faces,
  ) {
    var volume = 0.0;
    for (final face in faces) {
      final a = _Vec.fromVertex(vertices[face[0]]);
      for (var i = 1; i < face.length - 1; i++) {
        final b = _Vec.fromVertex(vertices[face[i]]);
        final c = _Vec.fromVertex(vertices[face[i + 1]]);
        volume += a.dot(b.cross(c)) / 6.0;
      }
    }
    return volume;
  }

  static List<_Polygon> _polygonsFromMesh(FamilyCsgMesh mesh) {
    final polygons = <_Polygon>[];
    for (final face in mesh.faces) {
      final root = face.indices[0];
      for (var i = 1; i < face.indices.length - 1; i++) {
        final vertices = <_Vertex>[
          _Vertex(_Vec.fromVertex(mesh.vertices[root])),
          _Vertex(_Vec.fromVertex(mesh.vertices[face.indices[i]])),
          _Vertex(_Vec.fromVertex(mesh.vertices[face.indices[i + 1]])),
        ];
        final normal = (vertices[1].position - vertices[0].position)
            .cross(vertices[2].position - vertices[0].position);
        if (normal.length <= _epsilon) continue;
        polygons.add(_Polygon(vertices));
      }
    }
    return polygons;
  }

  static FamilyCsgMesh? _meshFromPolygons(List<_Polygon> polygons) {
    if (polygons.isEmpty) return null;
    final vertices = <FamilyCsgVertex>[];
    final faces = <FamilyCsgFace>[];
    final vertexIndex = <String, int>{};

    int indexFor(_Vec value) {
      final qx = (value.x / _epsilon).round();
      final qy = (value.y / _epsilon).round();
      final qz = (value.z / _epsilon).round();
      final key = '$qx:$qy:$qz';
      final existing = vertexIndex[key];
      if (existing != null) return existing;
      final index = vertices.length;
      vertices.add(FamilyCsgVertex(value.x, value.y, value.z));
      vertexIndex[key] = index;
      return index;
    }

    for (final polygon in polygons) {
      final indices = <int>[];
      for (final vertex in polygon.vertices) {
        final index = indexFor(vertex.position);
        if (indices.isEmpty || indices.last != index) indices.add(index);
      }
      if (indices.length > 1 && indices.first == indices.last) {
        indices.removeLast();
      }
      if (indices.length < 3 || indices.toSet().length < 3) continue;

      // BSP splitting can leave collinear points in a polygon. Keep the face
      // contract simple by dropping those points before render triangulation.
      var changed = true;
      while (changed && indices.length > 3) {
        changed = false;
        for (var i = 0; i < indices.length; i++) {
          final previous = _Vec.fromVertex(
            vertices[indices[(i - 1 + indices.length) % indices.length]],
          );
          final current = _Vec.fromVertex(vertices[indices[i]]);
          final next = _Vec.fromVertex(
            vertices[indices[(i + 1) % indices.length]],
          );
          final area = (current - previous).cross(next - current).length;
          if (area <= _epsilon) {
            indices.removeAt(i);
            changed = true;
            break;
          }
        }
      }
      if (indices.length >= 3) {
        faces.add(FamilyCsgFace(List<int>.unmodifiable(indices)));
      }
    }

    if (vertices.length < 4 || faces.length < 4) return null;
    return FamilyCsgMesh(
      vertices: List<FamilyCsgVertex>.unmodifiable(vertices),
      faces: List<FamilyCsgFace>.unmodifiable(faces),
    );
  }
}

final class _EdgeUse {
  const _EdgeUse(this.face, this.from, this.to);

  final int face;
  final int from;
  final int to;
}

final class _FaceAdjacency {
  const _FaceAdjacency(this.face, this.sameDirection);

  final int face;
  final bool sameDirection;
}

final class _Vec {
  const _Vec(this.x, this.y, this.z);

  factory _Vec.fromVertex(FamilyCsgVertex vertex) =>
      _Vec(vertex.x, vertex.y, vertex.z);

  final double x;
  final double y;
  final double z;

  _Vec operator +(_Vec other) => _Vec(x + other.x, y + other.y, z + other.z);
  _Vec operator -(_Vec other) => _Vec(x - other.x, y - other.y, z - other.z);
  _Vec operator *(double value) => _Vec(x * value, y * value, z * value);

  double dot(_Vec other) => x * other.x + y * other.y + z * other.z;

  _Vec cross(_Vec other) => _Vec(
        y * other.z - z * other.y,
        z * other.x - x * other.z,
        x * other.y - y * other.x,
      );

  double get length => math.sqrt(dot(this));

  _Vec unit() {
    final magnitude = length;
    if (magnitude <= FamilyCsgKernel._epsilon) {
      throw StateError('Degenerate CSG plane');
    }
    return this * (1.0 / magnitude);
  }

  _Vec lerp(_Vec other, double t) => this + (other - this) * t;
}

final class _Vertex {
  const _Vertex(this.position);

  final _Vec position;

  _Vertex clone() => _Vertex(position);
  _Vertex interpolate(_Vertex other, double t) =>
      _Vertex(position.lerp(other.position, t));
}

final class _Plane {
  const _Plane(this.normal, this.w);

  factory _Plane.fromVertices(List<_Vertex> vertices) {
    if (vertices.length < 3) throw StateError('CSG polygon needs 3 vertices');
    final a = vertices[0].position;
    for (var i = 1; i < vertices.length - 1; i++) {
      for (var j = i + 1; j < vertices.length; j++) {
        final normal = (vertices[i].position - a).cross(vertices[j].position - a);
        if (normal.length > FamilyCsgKernel._epsilon) {
          final unit = normal.unit();
          return _Plane(unit, unit.dot(a));
        }
      }
    }
    throw StateError('Degenerate CSG polygon');
  }

  static const int _coplanar = 0;
  static const int _front = 1;
  static const int _back = 2;
  static const int _spanning = 3;

  final _Vec normal;
  final double w;

  _Plane clone() => _Plane(normal, w);
  _Plane flipped() => _Plane(normal * -1.0, -w);

  void splitPolygon(
    _Polygon polygon,
    List<_Polygon> coplanarFront,
    List<_Polygon> coplanarBack,
    List<_Polygon> front,
    List<_Polygon> back,
  ) {
    var polygonType = _coplanar;
    final types = <int>[];
    for (final vertex in polygon.vertices) {
      final t = normal.dot(vertex.position) - w;
      final type = t < -FamilyCsgKernel._epsilon
          ? _back
          : t > FamilyCsgKernel._epsilon
              ? _front
              : _coplanar;
      polygonType |= type;
      types.add(type);
    }

    switch (polygonType) {
      case _coplanar:
        (normal.dot(polygon.plane.normal) > 0
                ? coplanarFront
                : coplanarBack)
            .add(polygon);
        return;
      case _front:
        front.add(polygon);
        return;
      case _back:
        back.add(polygon);
        return;
      case _spanning:
        final frontVertices = <_Vertex>[];
        final backVertices = <_Vertex>[];
        for (var i = 0; i < polygon.vertices.length; i++) {
          final j = (i + 1) % polygon.vertices.length;
          final ti = types[i];
          final tj = types[j];
          final vi = polygon.vertices[i];
          final vj = polygon.vertices[j];
          if (ti != _back) frontVertices.add(vi);
          if (ti != _front) backVertices.add(vi.clone());
          if ((ti | tj) == _spanning) {
            final direction = vj.position - vi.position;
            final denominator = normal.dot(direction);
            if (denominator.abs() <= FamilyCsgKernel._epsilon) continue;
            final t = (w - normal.dot(vi.position)) / denominator;
            final vertex = vi.interpolate(vj, t);
            frontVertices.add(vertex);
            backVertices.add(vertex.clone());
          }
        }
        if (frontVertices.length >= 3) front.add(_Polygon(frontVertices));
        if (backVertices.length >= 3) back.add(_Polygon(backVertices));
        return;
    }
  }
}

final class _Polygon {
  _Polygon(List<_Vertex> vertices)
      : vertices = List<_Vertex>.unmodifiable(vertices),
        plane = _Plane.fromVertices(vertices);

  final List<_Vertex> vertices;
  final _Plane plane;

  _Polygon clone() => _Polygon(vertices.map((vertex) => vertex.clone()).toList());
  _Polygon flipped() => _Polygon(
        vertices.reversed.map((vertex) => vertex.clone()).toList(),
      );
}

final class _Node {
  _Node([List<_Polygon>? polygons]) {
    if (polygons != null && polygons.isNotEmpty) build(polygons);
  }

  _Plane? plane;
  _Node? front;
  _Node? back;
  List<_Polygon> polygons = <_Polygon>[];

  _Node clone() {
    final node = _Node();
    node.plane = plane?.clone();
    node.front = front?.clone();
    node.back = back?.clone();
    node.polygons = polygons.map((polygon) => polygon.clone()).toList();
    return node;
  }

  void invert() {
    polygons = polygons.map((polygon) => polygon.flipped()).toList();
    plane = plane?.flipped();
    front?.invert();
    back?.invert();
    final swap = front;
    front = back;
    back = swap;
  }

  List<_Polygon> clipPolygons(List<_Polygon> input) {
    final splitter = plane;
    if (splitter == null) {
      return input.map((polygon) => polygon.clone()).toList();
    }
    var frontPolygons = <_Polygon>[];
    var backPolygons = <_Polygon>[];
    for (final polygon in input) {
      splitter.splitPolygon(
        polygon,
        frontPolygons,
        backPolygons,
        frontPolygons,
        backPolygons,
      );
    }
    if (front != null) frontPolygons = front!.clipPolygons(frontPolygons);
    if (back != null) {
      backPolygons = back!.clipPolygons(backPolygons);
    } else {
      backPolygons = <_Polygon>[];
    }
    return <_Polygon>[...frontPolygons, ...backPolygons];
  }

  void clipTo(_Node bsp) {
    polygons = bsp.clipPolygons(polygons);
    front?.clipTo(bsp);
    back?.clipTo(bsp);
  }

  List<_Polygon> allPolygons() => <_Polygon>[
        ...polygons,
        ...?front?.allPolygons(),
        ...?back?.allPolygons(),
      ];

  void build(List<_Polygon> input) {
    if (input.isEmpty) return;
    plane ??= input.first.plane.clone();
    final frontPolygons = <_Polygon>[];
    final backPolygons = <_Polygon>[];
    for (final polygon in input) {
      plane!.splitPolygon(
        polygon,
        polygons,
        polygons,
        frontPolygons,
        backPolygons,
      );
    }
    if (frontPolygons.isNotEmpty) {
      front ??= _Node();
      front!.build(frontPolygons);
    }
    if (backPolygons.isNotEmpty) {
      back ??= _Node();
      back!.build(backPolygons);
    }
  }
}

final class _Solid {
  _Solid(List<_Polygon> polygons)
      : polygons = polygons.map((polygon) => polygon.clone()).toList();

  final List<_Polygon> polygons;

  _Solid union(_Solid other) {
    final a = _Node(polygons.map((polygon) => polygon.clone()).toList());
    final b = _Node(other.polygons.map((polygon) => polygon.clone()).toList());
    a.clipTo(b);
    b.clipTo(a);
    b.invert();
    b.clipTo(a);
    b.invert();
    a.build(b.allPolygons());
    return _Solid(a.allPolygons());
  }

  _Solid subtract(_Solid other) {
    final a = _Node(polygons.map((polygon) => polygon.clone()).toList());
    final b = _Node(other.polygons.map((polygon) => polygon.clone()).toList());
    a.invert();
    a.clipTo(b);
    b.clipTo(a);
    b.invert();
    b.clipTo(a);
    b.invert();
    a.build(b.allPolygons());
    a.invert();
    return _Solid(a.allPolygons());
  }
}
