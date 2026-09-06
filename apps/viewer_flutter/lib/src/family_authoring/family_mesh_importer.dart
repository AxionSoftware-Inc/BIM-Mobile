import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

import 'family_document.dart';

/// Result of importing a render-ready mesh into the independent Family format.
final class FamilyMeshImportResult {
  const FamilyMeshImportResult({
    required this.document,
    required this.path,
    required this.vertexCount,
    required this.faceCount,
  });

  final FamilyDocument document;
  final String path;
  final int vertexCount;
  final int faceCount;
}

/// Imports Blender glTF 2.0 models and keeps the legacy OBJ parser for
/// programmatic/backward-compatible callers.
///
/// Imported glTF coordinates are treated as metres, centred on X/Z, and placed
/// on the family ground plane. The resulting mesh is kept as editable
/// family-local geometry and is resized by the family type values.
abstract final class FamilyMeshImporter {
  static Future<FamilyMeshImportResult?> pickGltf() async {
    const typeGroup = XTypeGroup(
      label: 'Blender glTF model',
      extensions: <String>['glb', 'gltf'],
    );
    final location =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (location == null) return null;
    return fromGltfFile(location.path);
  }

  static Future<FamilyMeshImportResult> fromGltfFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final normalized = path.toLowerCase();
    if (normalized.endsWith('.glb')) {
      return fromGlbBytes(
        bytes,
        name: _fileStem(path),
        path: path,
      );
    }
    if (!normalized.endsWith('.gltf')) {
      throw const FormatException('Select a .glb or .gltf file.');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('The glTF JSON document is invalid.');
    }
    final buffers = await _loadExternalBuffers(decoded, path);
    return _fromGltfDocument(
      decoded.cast<String, Object?>(),
      buffers,
      name: _fileStem(path),
      path: path,
      sourceFormat: 'gltf',
    );
  }

  static FamilyMeshImportResult fromGlbBytes(
    Uint8List bytes, {
    required String name,
    String path = '',
  }) {
    if (bytes.length < 20) {
      throw const FormatException('The GLB file is too small.');
    }
    final header = ByteData.sublistView(bytes);
    if (header.getUint32(0, Endian.little) != 0x46546c67 ||
        header.getUint32(4, Endian.little) != 2) {
      throw const FormatException('Only glTF 2.0 GLB files are supported.');
    }
    final declaredLength = header.getUint32(8, Endian.little);
    if (declaredLength > bytes.length || declaredLength < 20) {
      throw const FormatException('The GLB length header is invalid.');
    }
    var offset = 12;
    Map<String, Object?>? document;
    Uint8List? binary;
    while (offset + 8 <= declaredLength) {
      final chunkLength = header.getUint32(offset, Endian.little);
      final chunkType = header.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + chunkLength;
      if (chunkEnd > declaredLength || chunkEnd > bytes.length) {
        throw const FormatException('The GLB chunk extends past the file.');
      }
      final chunk = bytes.sublist(chunkStart, chunkEnd);
      if (chunkType == 0x4e4f534a) {
        final decoded = jsonDecode(utf8.decode(chunk).trim());
        if (decoded is! Map) {
          throw const FormatException('The GLB JSON chunk is invalid.');
        }
        document = decoded.cast<String, Object?>();
      } else if (chunkType == 0x004e4942) {
        binary = Uint8List.fromList(chunk);
      }
      offset = chunkEnd;
    }
    if (document == null) {
      throw const FormatException('The GLB file has no JSON chunk.');
    }
    return _fromGltfDocument(
      document,
      <Uint8List>[binary ?? Uint8List(0)],
      name: name,
      path: path,
      sourceFormat: 'glb',
    );
  }

  static Future<FamilyMeshImportResult?> pickObj() async {
    const typeGroup = XTypeGroup(
      label: 'Blender mesh',
      extensions: <String>['obj'],
    );
    final location =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (location == null) return null;
    final path = location.path;
    final text = await File(path).readAsString();
    return fromObjText(text, name: _fileStem(path), path: path);
  }

  static FamilyMeshImportResult fromObjText(
    String text, {
    required String name,
    String path = '',
    double unitScale = 1.0,
  }) {
    if (!unitScale.isFinite || unitScale <= 0.0) {
      throw const FormatException('OBJ unit scale must be positive.');
    }

    final sourceVertices = <_ObjPoint>[];
    final sourceFaces = <List<int>>[];
    final lines = text.split(RegExp(r'\r?\n'));
    for (var lineNumber = 0; lineNumber < lines.length; lineNumber++) {
      final line = lines[lineNumber].trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final comment = line.indexOf('#');
      final content = (comment >= 0 ? line.substring(0, comment) : line).trim();
      if (content.isEmpty) continue;
      final tokens = content.split(RegExp(r'\s+'));
      final command = tokens.first.toLowerCase();
      if (command == 'v') {
        if (tokens.length < 4) {
          throw FormatException(
              'Invalid OBJ vertex on line ${lineNumber + 1}.');
        }
        final x = double.tryParse(tokens[1]);
        final y = double.tryParse(tokens[2]);
        final z = double.tryParse(tokens[3]);
        if (x == null ||
            y == null ||
            z == null ||
            !x.isFinite ||
            !y.isFinite ||
            !z.isFinite) {
          throw FormatException(
              'Invalid OBJ vertex on line ${lineNumber + 1}.');
        }
        sourceVertices
            .add(_ObjPoint(x * unitScale, y * unitScale, z * unitScale));
      } else if (command == 'f') {
        if (tokens.length < 4) {
          throw FormatException(
              'OBJ face needs at least 3 vertices on line ${lineNumber + 1}.');
        }
        final face = <int>[];
        for (final token in tokens.skip(1)) {
          final rawIndex = int.tryParse(token.split('/').first);
          if (rawIndex == null || rawIndex == 0) {
            throw FormatException(
                'Invalid OBJ face index on line ${lineNumber + 1}.');
          }
          final index =
              rawIndex > 0 ? rawIndex - 1 : sourceVertices.length + rawIndex;
          if (index < 0 || index >= sourceVertices.length) {
            throw FormatException(
                'OBJ face index is out of range on line ${lineNumber + 1}.');
          }
          if (face.isEmpty || face.last != index) face.add(index);
        }
        if (face.length >= 3 && face.first == face.last) face.removeLast();
        if (face.length >= 3) sourceFaces.add(face);
      }
    }

    if (sourceVertices.isEmpty || sourceFaces.isEmpty) {
      throw const FormatException(
          'OBJ must contain vertices and at least one face.');
    }

    return _buildFamilyDocument(
      <List<double>>[
        for (final point in sourceVertices) <double>[point.x, point.z, point.y],
      ],
      sourceFaces,
      name: name,
      path: path,
      sourceFormat: 'obj',
    );
  }

  static Future<List<Uint8List>> _loadExternalBuffers(
    Map document,
    String gltfPath,
  ) async {
    final rawBuffers = document['buffers'];
    if (rawBuffers is! List || rawBuffers.isEmpty) {
      throw const FormatException('The glTF document has no buffers.');
    }
    final directory = File(gltfPath).parent;
    final buffers = <Uint8List>[];
    for (final rawBuffer in rawBuffers) {
      if (rawBuffer is! Map) {
        throw const FormatException('The glTF buffer definition is invalid.');
      }
      final uri = rawBuffer['uri']?.toString();
      if (uri == null || uri.isEmpty) {
        throw const FormatException(
            'A .gltf file needs an external .bin or data URI buffer.');
      }
      if (uri.startsWith('data:')) {
        final separator = uri.indexOf(',');
        if (separator < 0) {
          throw const FormatException('The glTF data URI is invalid.');
        }
        final payload = uri.substring(separator + 1);
        try {
          buffers.add(base64.decode(payload));
        } catch (_) {
          throw const FormatException('The glTF data URI is invalid.');
        }
      } else {
        final externalPath = Uri.decodeComponent(uri);
        final externalFile = File(
          '${directory.path}${Platform.pathSeparator}$externalPath',
        );
        if (!await externalFile.exists()) {
          throw FormatException('Missing glTF buffer: $externalPath');
        }
        buffers.add(await externalFile.readAsBytes());
      }
    }
    return buffers;
  }

  static FamilyMeshImportResult _fromGltfDocument(
    Map<String, Object?> document,
    List<Uint8List> buffers, {
    required String name,
    required String path,
    required String sourceFormat,
  }) {
    final builder = _GltfMeshBuilder(document, buffers);
    builder.build();
    if (builder.vertices.isEmpty || builder.faces.isEmpty) {
      throw const FormatException('The glTF file has no renderable triangles.');
    }
    return _buildFamilyDocument(
      builder.vertices,
      builder.faces,
      name: name,
      path: path,
      sourceFormat: sourceFormat,
    );
  }

  static FamilyMeshImportResult _buildFamilyDocument(
    List<List<double>> sourceVertices,
    List<List<int>> sourceFaces, {
    required String name,
    required String path,
    required String sourceFormat,
  }) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    var minZ = double.infinity;
    var maxZ = -double.infinity;
    for (final vertex in sourceVertices) {
      minX = math.min(minX, vertex[0]);
      maxX = math.max(maxX, vertex[0]);
      minY = math.min(minY, vertex[1]);
      maxY = math.max(maxY, vertex[1]);
      minZ = math.min(minZ, vertex[2]);
      maxZ = math.max(maxZ, vertex[2]);
    }
    final centerX = (minX + maxX) * 0.5;
    final centerZ = (minZ + maxZ) * 0.5;
    final vertices = <List<double>>[
      for (final vertex in sourceVertices)
        <double>[vertex[0] - centerX, vertex[1] - minY, vertex[2] - centerZ],
    ];
    final width = maxX - minX;
    final height = maxY - minY;
    final depth = maxZ - minZ;
    final familyName = _displayName(name);
    final parameters = <FamilyParameterDefinition>[
      const FamilyParameterDefinition(
        id: 'width',
        label: 'Overall width',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.001,
      ),
      const FamilyParameterDefinition(
        id: 'depth',
        label: 'Overall depth',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.001,
      ),
      const FamilyParameterDefinition(
        id: 'height',
        label: 'Overall height',
        kind: FamilyParameterKind.length,
        defaultValue: 1.0,
        minimum: 0.001,
      ),
    ];
    final document = FamilyDocument(
      id: 'family-imported-${DateTime.now().microsecondsSinceEpoch}',
      name: familyName,
      category: FamilyCategory.genericModel,
      description:
          'Imported Blender glTF mesh. Geometry remains family-local and type-scalable.',
      parameters: parameters,
      types: <FamilyTypeDefinition>[
        FamilyTypeDefinition(
          id: 'type-imported-1',
          name: '$familyName · Original size',
          values: <String, Object?>{
            'width': _safeDimension(width),
            'depth': _safeDimension(depth),
            'height': _safeDimension(height),
          },
        ),
      ],
      features: <FamilyFeature>[
        FamilyFeature(
          id: 'feature-imported-obj',
          kind: FamilyFeatureKind.freeformMesh,
          label: 'Imported ${sourceFormat.toUpperCase()} mesh',
          parameters: <String, Object?>{
            'sourceFormat': sourceFormat,
            'sourceFileName': _displayName(name),
            'vertices': vertices,
            'faces': sourceFaces,
          },
        ),
      ],
    );
    return FamilyMeshImportResult(
      document: document,
      path: path,
      vertexCount: vertices.length,
      faceCount: sourceFaces.length,
    );
  }

  static double _safeDimension(double value) {
    if (!value.isFinite || value <= 0.001) return 0.001;
    return value;
  }

  static String _fileStem(String path) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  static String _displayName(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? 'Imported Blender Model' : trimmed;
  }
}

final class _ObjPoint {
  const _ObjPoint(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;
}

final class _GltfMeshBuilder {
  _GltfMeshBuilder(this.document, this.buffers);

  static const _maxVertices = 200000;
  static const _maxFaces = 200000;

  final Map<String, Object?> document;
  final List<Uint8List> buffers;
  final vertices = <List<double>>[];
  final faces = <List<int>>[];
  final Set<int> _activeNodes = <int>{};

  void build() {
    final nodes = _asList(document['nodes']);
    final scenes = _asList(document['scenes']);
    final sceneIndex = _asInt(document['scene']) ?? 0;
    if (scenes != null &&
        scenes.isNotEmpty &&
        sceneIndex >= 0 &&
        sceneIndex < scenes.length) {
      final scene = _asMap(scenes[sceneIndex]);
      final roots = _asList(scene?['nodes']);
      if (roots != null) {
        for (final rawNode in roots) {
          final nodeIndex = _asInt(rawNode);
          if (nodeIndex != null) _visitNode(nodeIndex, _Mat4.identity());
        }
        return;
      }
    }
    if (nodes != null && nodes.isNotEmpty) {
      final childNodes = <int>{};
      for (final rawNode in nodes) {
        final node = _asMap(rawNode);
        for (final rawChild
            in _asList(node?['children']) ?? const <Object?>[]) {
          final child = _asInt(rawChild);
          if (child != null) childNodes.add(child);
        }
      }
      for (var index = 0; index < nodes.length; index++) {
        if (!childNodes.contains(index)) _visitNode(index, _Mat4.identity());
      }
      return;
    }
    final meshes = _asList(document['meshes']) ?? const <Object?>[];
    for (var index = 0; index < meshes.length; index++) {
      _appendMesh(index, _Mat4.identity());
    }
  }

  void _visitNode(int nodeIndex, _Mat4 parent) {
    final nodes = _asList(document['nodes']);
    if (nodes == null || nodeIndex < 0 || nodeIndex >= nodes.length) {
      throw FormatException('The glTF node index is out of range: $nodeIndex');
    }
    if (!_activeNodes.add(nodeIndex)) {
      throw const FormatException('The glTF node graph contains a cycle.');
    }
    final node = _asMap(nodes[nodeIndex]);
    if (node == null) {
      throw const FormatException('The glTF node definition is invalid.');
    }
    final transform = parent * _Mat4.fromNode(node);
    final meshIndex = _asInt(node['mesh']);
    if (meshIndex != null) _appendMesh(meshIndex, transform);
    for (final rawChild in _asList(node['children']) ?? const <Object?>[]) {
      final child = _asInt(rawChild);
      if (child != null) _visitNode(child, transform);
    }
    _activeNodes.remove(nodeIndex);
  }

  void _appendMesh(int meshIndex, _Mat4 transform) {
    final meshes = _asList(document['meshes']);
    if (meshes == null || meshIndex < 0 || meshIndex >= meshes.length) {
      throw FormatException('The glTF mesh index is out of range: $meshIndex');
    }
    final mesh = _asMap(meshes[meshIndex]);
    final primitives = _asList(mesh?['primitives']);
    if (primitives == null) {
      throw const FormatException('The glTF mesh has no primitives.');
    }
    for (final rawPrimitive in primitives) {
      final primitive = _asMap(rawPrimitive);
      final attributes = _asMap(primitive?['attributes']);
      final positionAccessor = _asInt(attributes?['POSITION']);
      if (positionAccessor == null) continue;
      final positions = _readAccessor(positionAccessor, expectedType: 'VEC3');
      final mode = _asInt(primitive?['mode']) ?? 4;
      final indices = _asInt(primitive?['indices']) == null
          ? List<int>.generate(positions.length, (index) => index)
          : _readIndices(_asInt(primitive?['indices'])!);
      final baseVertex = vertices.length;
      for (final position in positions) {
        final transformed =
            transform.transform(position[0], position[1], position[2]);
        vertices.add(transformed);
      }
      final primitiveFaces = _triangles(indices, mode);
      for (final face in primitiveFaces) {
        if (face.any((index) => index < 0 || index >= positions.length)) {
          throw const FormatException(
              'The glTF primitive index is out of range.');
        }
        faces.add(<int>[for (final index in face) baseVertex + index]);
      }
      if (vertices.length > _maxVertices || faces.length > _maxFaces) {
        throw const FormatException(
            'The glTF mesh is too large for a tablet family asset.');
      }
    }
  }

  List<List<int>> _triangles(List<int> indices, int mode) {
    switch (mode) {
      case 4: // TRIANGLES
        return <List<int>>[
          for (var index = 0; index + 2 < indices.length; index += 3)
            <int>[indices[index], indices[index + 1], indices[index + 2]],
        ];
      case 5: // TRIANGLE_STRIP
        return <List<int>>[
          for (var index = 0; index + 2 < indices.length; index++)
            index.isEven
                ? <int>[indices[index], indices[index + 1], indices[index + 2]]
                : <int>[indices[index + 1], indices[index], indices[index + 2]],
        ];
      case 6: // TRIANGLE_FAN
        return <List<int>>[
          for (var index = 1; index + 1 < indices.length; index++)
            <int>[indices.first, indices[index], indices[index + 1]],
        ];
      default:
        // POINTS, LINES and LINE_STRIP have no filled faces for Family mesh.
        return const <List<int>>[];
    }
  }

  List<List<double>> _readAccessor(
    int accessorIndex, {
    required String expectedType,
  }) {
    final accessor = _mapAt(document['accessors'], accessorIndex, 'accessor');
    if (accessor['type']?.toString() != expectedType) {
      throw FormatException('glTF accessor must be $expectedType.');
    }
    final componentType = _asInt(accessor['componentType']);
    final count = _asInt(accessor['count']);
    final viewIndex = _asInt(accessor['bufferView']);
    if (componentType == null ||
        count == null ||
        viewIndex == null ||
        count < 0) {
      throw const FormatException('The glTF accessor definition is invalid.');
    }
    final view = _mapAt(document['bufferViews'], viewIndex, 'bufferView');
    final bufferIndex = _asInt(view['buffer']) ?? 0;
    if (bufferIndex < 0 || bufferIndex >= buffers.length) {
      throw const FormatException('The glTF buffer index is out of range.');
    }
    final componentCount = expectedType == 'VEC3' ? 3 : 1;
    final componentSize = _componentSize(componentType);
    final stride = _asInt(view['byteStride']) ?? componentCount * componentSize;
    final baseOffset = (_asInt(view['byteOffset']) ?? 0) +
        (_asInt(accessor['byteOffset']) ?? 0);
    final buffer = buffers[bufferIndex];
    final requiredBytes = count == 0
        ? baseOffset
        : baseOffset + (count - 1) * stride + componentCount * componentSize;
    if (baseOffset < 0 || requiredBytes > buffer.length) {
      throw const FormatException('The glTF accessor exceeds its buffer.');
    }
    final data = ByteData.sublistView(buffer);
    final normalized = accessor['normalized'] == true;
    return <List<double>>[
      for (var index = 0; index < count; index++)
        <double>[
          for (var component = 0; component < componentCount; component++)
            _readComponent(
              data,
              baseOffset + index * stride + component * componentSize,
              componentType,
              normalized,
            ),
        ],
    ];
  }

  List<int> _readIndices(int accessorIndex) {
    final accessor =
        _mapAt(document['accessors'], accessorIndex, 'index accessor');
    if (accessor['type']?.toString() != 'SCALAR') {
      throw const FormatException('glTF indices must use a SCALAR accessor.');
    }
    final componentType = _asInt(accessor['componentType']);
    final count = _asInt(accessor['count']);
    final viewIndex = _asInt(accessor['bufferView']);
    if (componentType == null ||
        count == null ||
        viewIndex == null ||
        count < 0) {
      throw const FormatException('The glTF index accessor is invalid.');
    }
    if (componentType != 5121 &&
        componentType != 5123 &&
        componentType != 5125) {
      throw const FormatException('The glTF index component type is invalid.');
    }
    final view = _mapAt(document['bufferViews'], viewIndex, 'index bufferView');
    final bufferIndex = _asInt(view['buffer']) ?? 0;
    if (bufferIndex < 0 || bufferIndex >= buffers.length) {
      throw const FormatException('The glTF index buffer is out of range.');
    }
    final componentSize = _componentSize(componentType);
    final stride = _asInt(view['byteStride']) ?? componentSize;
    final baseOffset = (_asInt(view['byteOffset']) ?? 0) +
        (_asInt(accessor['byteOffset']) ?? 0);
    final buffer = buffers[bufferIndex];
    final requiredBytes = count == 0
        ? baseOffset
        : baseOffset + (count - 1) * stride + componentSize;
    if (baseOffset < 0 || requiredBytes > buffer.length) {
      throw const FormatException(
          'The glTF index accessor exceeds its buffer.');
    }
    final data = ByteData.sublistView(buffer);
    return <int>[
      for (var index = 0; index < count; index++)
        _readComponent(
          data,
          baseOffset + index * stride,
          componentType,
          false,
        ).round(),
    ];
  }

  static double _readComponent(
    ByteData data,
    int offset,
    int componentType,
    bool normalized,
  ) {
    final value = switch (componentType) {
      5120 => data.getInt8(offset).toDouble(),
      5121 => data.getUint8(offset).toDouble(),
      5122 => data.getInt16(offset, Endian.little).toDouble(),
      5123 => data.getUint16(offset, Endian.little).toDouble(),
      5125 => data.getUint32(offset, Endian.little).toDouble(),
      5126 => data.getFloat32(offset, Endian.little).toDouble(),
      _ => throw FormatException(
          'Unsupported glTF component type: $componentType'),
    };
    if (!normalized) return value;
    return switch (componentType) {
      5120 => math.max(value / 127.0, -1.0),
      5121 => value / 255.0,
      5122 => math.max(value / 32767.0, -1.0),
      5123 => value / 65535.0,
      _ => value,
    };
  }

  static int _componentSize(int componentType) {
    return switch (componentType) {
      5120 || 5121 => 1,
      5122 || 5123 => 2,
      5125 || 5126 => 4,
      _ => throw FormatException(
          'Unsupported glTF component type: $componentType'),
    };
  }

  static Map _mapAt(Object? raw, int index, String label) {
    final list = _asList(raw);
    if (list == null || index < 0 || index >= list.length) {
      throw FormatException('The glTF $label index is out of range.');
    }
    final value = _asMap(list[index]);
    if (value == null) throw FormatException('The glTF $label is invalid.');
    return value;
  }

  static List? _asList(Object? value) => value is List ? value : null;

  static Map? _asMap(Object? value) => value is Map ? value : null;

  static int? _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

final class _Mat4 {
  _Mat4(this.values);

  final List<double> values;

  factory _Mat4.identity() => _Mat4(<double>[
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        1,
      ]);

  factory _Mat4.fromNode(Map node) {
    final rawMatrix = node['matrix'];
    if (rawMatrix is List &&
        rawMatrix.length == 16 &&
        rawMatrix.every((value) => value is num)) {
      return _Mat4(
          <double>[for (final value in rawMatrix) (value as num).toDouble()]);
    }
    final translation = _vec3(node['translation'], <double>[0, 0, 0]);
    final scale = _vec3(node['scale'], <double>[1, 1, 1]);
    final rotation = _vec4(node['rotation'], <double>[0, 0, 0, 1]);
    final x = rotation[0];
    final y = rotation[1];
    final z = rotation[2];
    final w = rotation[3];
    final xx = x * x;
    final yy = y * y;
    final zz = z * z;
    final xy = x * y;
    final xz = x * z;
    final yz = y * z;
    final wx = w * x;
    final wy = w * y;
    final wz = w * z;
    return _Mat4(<double>[
      (1 - 2 * (yy + zz)) * scale[0],
      (2 * (xy + wz)) * scale[0],
      (2 * (xz - wy)) * scale[0],
      0,
      (2 * (xy - wz)) * scale[1],
      (1 - 2 * (xx + zz)) * scale[1],
      (2 * (yz + wx)) * scale[1],
      0,
      (2 * (xz + wy)) * scale[2],
      (2 * (yz - wx)) * scale[2],
      (1 - 2 * (xx + yy)) * scale[2],
      0,
      translation[0],
      translation[1],
      translation[2],
      1,
    ]);
  }

  _Mat4 operator *(_Mat4 other) {
    final result = List<double>.filled(16, 0.0);
    for (var column = 0; column < 4; column++) {
      for (var row = 0; row < 4; row++) {
        var value = 0.0;
        for (var index = 0; index < 4; index++) {
          value += values[index * 4 + row] * other.values[column * 4 + index];
        }
        result[column * 4 + row] = value;
      }
    }
    return _Mat4(result);
  }

  List<double> transform(double x, double y, double z) => <double>[
        values[0] * x + values[4] * y + values[8] * z + values[12],
        values[1] * x + values[5] * y + values[9] * z + values[13],
        values[2] * x + values[6] * y + values[10] * z + values[14],
      ];

  static List<double> _vec3(Object? raw, List<double> fallback) {
    if (raw is List &&
        raw.length >= 3 &&
        raw.take(3).every((value) => value is num)) {
      return <double>[
        for (final value in raw.take(3)) (value as num).toDouble()
      ];
    }
    return fallback;
  }

  static List<double> _vec4(Object? raw, List<double> fallback) {
    if (raw is List &&
        raw.length >= 4 &&
        raw.take(4).every((value) => value is num)) {
      return <double>[
        for (final value in raw.take(4)) (value as num).toDouble()
      ];
    }
    return fallback;
  }
}
