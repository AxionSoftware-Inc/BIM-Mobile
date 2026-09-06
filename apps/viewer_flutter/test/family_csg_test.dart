import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_csg.dart';

void main() {
  test('CSG normalizes mixed face winding on a closed box', () {
    final box = _box(0, 0, 0, 1, 1, 1, mixedWinding: true);
    expect(FamilyCsgKernel.isClosedTwoManifold(box), isTrue);
  });

  test('exact CSG union preserves the expected overlapping-box volume', () {
    final left = _box(0, 0, 0, 1, 1, 1, mixedWinding: true);
    final right = _box(0.5, 0, 0, 1.5, 1, 1);
    final result = FamilyCsgKernel.apply(
      left: left,
      right: right,
      operation: FamilyCsgOperation.union,
    );

    expect(result, isNotNull);
    final mesh = result!;
    expect(mesh.vertices, isNotEmpty);
    expect(mesh.faces, isNotEmpty);
    expect(_volume(mesh), closeTo(1.5, 1e-6));
    final xs = mesh.vertices.map((vertex) => vertex.x);
    expect(xs.reduce(math.min), closeTo(0.0, 1e-7));
    expect(xs.reduce(math.max), closeTo(1.5, 1e-7));
  });

  test('exact CSG subtract removes the overlapping half-volume', () {
    final left = _box(0, 0, 0, 1, 1, 1);
    final cutter = _box(0.5, -0.2, -0.2, 1.2, 1.2, 1.2);
    final result = FamilyCsgKernel.apply(
      left: left,
      right: cutter,
      operation: FamilyCsgOperation.subtract,
    );

    expect(result, isNotNull);
    expect(_volume(result!), closeTo(0.5, 1e-6));
  });

  test('open mesh is rejected instead of producing fake boolean geometry', () {
    final closed = _box(0, 0, 0, 1, 1, 1);
    final open = FamilyCsgMesh(
      vertices: closed.vertices,
      faces: closed.faces.take(closed.faces.length - 1).toList(),
    );
    expect(FamilyCsgKernel.isClosedTwoManifold(open), isFalse);
    expect(
      FamilyCsgKernel.apply(
        left: closed,
        right: open,
        operation: FamilyCsgOperation.union,
      ),
      isNull,
    );
  });
}

FamilyCsgMesh _box(
  double minX,
  double minY,
  double minZ,
  double maxX,
  double maxY,
  double maxZ, {
  bool mixedWinding = false,
}) {
  final vertices = <FamilyCsgVertex>[
    FamilyCsgVertex(minX, minY, minZ),
    FamilyCsgVertex(maxX, minY, minZ),
    FamilyCsgVertex(maxX, maxY, minZ),
    FamilyCsgVertex(minX, maxY, minZ),
    FamilyCsgVertex(minX, minY, maxZ),
    FamilyCsgVertex(maxX, minY, maxZ),
    FamilyCsgVertex(maxX, maxY, maxZ),
    FamilyCsgVertex(minX, maxY, maxZ),
  ];
  final faces = <FamilyCsgFace>[
    const FamilyCsgFace(<int>[0, 3, 2, 1]),
    const FamilyCsgFace(<int>[4, 5, 6, 7]),
    const FamilyCsgFace(<int>[0, 1, 5, 4]),
    const FamilyCsgFace(<int>[1, 2, 6, 5]),
    const FamilyCsgFace(<int>[2, 3, 7, 6]),
    const FamilyCsgFace(<int>[3, 0, 4, 7]),
  ];
  if (mixedWinding) {
    faces[1] = FamilyCsgFace(faces[1].indices.reversed.toList());
    faces[4] = FamilyCsgFace(faces[4].indices.reversed.toList());
  }
  return FamilyCsgMesh(vertices: vertices, faces: faces);
}

double _volume(FamilyCsgMesh mesh) {
  var volume = 0.0;
  for (final face in mesh.faces) {
    final a = mesh.vertices[face.indices[0]];
    for (var i = 1; i < face.indices.length - 1; i++) {
      final b = mesh.vertices[face.indices[i]];
      final c = mesh.vertices[face.indices[i + 1]];
      volume +=
          (a.x * (b.y * c.z - b.z * c.y) -
                  a.y * (b.x * c.z - b.z * c.x) +
                  a.z * (b.x * c.y - b.y * c.x)) /
              6.0;
    }
  }
  return volume.abs();
}
