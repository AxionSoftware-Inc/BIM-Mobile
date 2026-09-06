import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/family_authoring/family_authoring_module.dart';

void main() {
  test('GLB millimetres import as real metre family dimensions', () {
    final imported = FamilyMeshImporter.fromGlbBytes(
      _triangleGlb(),
      name: 'Millimetre fixture',
      unitScale: 0.001,
    );

    final type = imported.document.types.single;
    expect(type.values['width'], closeTo(1.0, 1e-9));
    expect(type.values['height'], closeTo(2.0, 1e-9));
    expect(type.values['depth'], closeTo(3.0, 1e-9));

    final feature = imported.document.features.single;
    expect(feature.parameters['sourceUnitScaleMeters'], 0.001);

    final mesh = FamilyGeometryEvaluator.evaluateMesh(
      imported.document,
      type,
    );
    final xs = mesh.vertices.map((vertex) => vertex.x).toList();
    final ys = mesh.vertices.map((vertex) => vertex.y).toList();
    final zs = mesh.vertices.map((vertex) => vertex.z).toList();
    expect(_span(xs), closeTo(1.0, 1e-9));
    expect(_span(ys), closeTo(2.0, 1e-9));
    expect(_span(zs), closeTo(3.0, 1e-9));
    expect(ys.reduce((a, b) => a < b ? a : b), closeTo(0.0, 1e-9));
  });

  test('glTF unit scale must be positive and finite', () {
    final glb = _triangleGlb();
    expect(
      () => FamilyMeshImporter.fromGlbBytes(
        glb,
        name: 'Invalid scale',
        unitScale: 0.0,
      ),
      throwsFormatException,
    );
    expect(
      () => FamilyMeshImporter.fromGlbBytes(
        glb,
        name: 'Invalid scale',
        unitScale: double.infinity,
      ),
      throwsFormatException,
    );
  });
}

double _span(List<double> values) {
  final min = values.reduce((a, b) => a < b ? a : b);
  final max = values.reduce((a, b) => a > b ? a : b);
  return max - min;
}

Uint8List _triangleGlb() {
  final binary = Uint8List(36);
  final data = ByteData.sublistView(binary);
  const points = <List<double>>[
    <double>[0, 0, 0],
    <double>[1000, 0, 0],
    <double>[0, 2000, 3000],
  ];
  var offset = 0;
  for (final point in points) {
    for (final component in point) {
      data.setFloat32(offset, component, Endian.little);
      offset += 4;
    }
  }

  final document = <String, Object?>{
    'asset': <String, Object?>{'version': '2.0'},
    'buffers': <Object?>[
      <String, Object?>{'byteLength': binary.length},
    ],
    'bufferViews': <Object?>[
      <String, Object?>{
        'buffer': 0,
        'byteOffset': 0,
        'byteLength': binary.length,
      },
    ],
    'accessors': <Object?>[
      <String, Object?>{
        'bufferView': 0,
        'componentType': 5126,
        'count': 3,
        'type': 'VEC3',
      },
    ],
    'meshes': <Object?>[
      <String, Object?>{
        'primitives': <Object?>[
          <String, Object?>{
            'attributes': <String, Object?>{'POSITION': 0},
            'mode': 4,
          },
        ],
      },
    ],
    'nodes': <Object?>[
      <String, Object?>{'mesh': 0},
    ],
    'scenes': <Object?>[
      <String, Object?>{
        'nodes': <int>[0],
      },
    ],
    'scene': 0,
  };

  var jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(document)));
  final jsonPadding = (4 - jsonBytes.length % 4) % 4;
  if (jsonPadding != 0) {
    jsonBytes = Uint8List.fromList(<int>[
      ...jsonBytes,
      ...List<int>.filled(jsonPadding, 0x20),
    ]);
  }
  var binBytes = binary;
  final binPadding = (4 - binBytes.length % 4) % 4;
  if (binPadding != 0) {
    binBytes = Uint8List.fromList(<int>[
      ...binBytes,
      ...List<int>.filled(binPadding, 0),
    ]);
  }

  final totalLength = 12 + 8 + jsonBytes.length + 8 + binBytes.length;
  final output = Uint8List(totalLength);
  final header = ByteData.sublistView(output);
  header.setUint32(0, 0x46546c67, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, totalLength, Endian.little);

  var cursor = 12;
  header.setUint32(cursor, jsonBytes.length, Endian.little);
  header.setUint32(cursor + 4, 0x4e4f534a, Endian.little);
  cursor += 8;
  output.setRange(cursor, cursor + jsonBytes.length, jsonBytes);
  cursor += jsonBytes.length;

  header.setUint32(cursor, binBytes.length, Endian.little);
  header.setUint32(cursor + 4, 0x004e4942, Endian.little);
  cursor += 8;
  output.setRange(cursor, cursor + binBytes.length, binBytes);
  return output;
}
