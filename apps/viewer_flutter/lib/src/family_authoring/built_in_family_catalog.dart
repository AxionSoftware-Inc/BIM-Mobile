import 'family_document.dart';

/// Curated families shipped with the authoring module.
///
/// These are normal `.bimfamily` documents once installed into the local
/// family library. Keeping the definitions here makes the first project
/// usable without a separate download while leaving the family/project file
/// boundaries intact.
abstract final class BuiltInFamilyCatalog {
  static List<FamilyDocument> get families => <FamilyDocument>[
        _exteriorColumn(),
        _storageCabinet(),
      ];

  static FamilyDocument _exteriorColumn() {
    const width = 0.62;
    const depth = 0.62;
    const height = 3.12;
    return const FamilyDocument(
      id: 'builtin-exterior-column-v1',
      name: 'Exterior Column · Classic',
      category: FamilyCategory.column,
      description:
          'A classical exterior column with a stepped base, shaft and capital.',
      parameters: <FamilyParameterDefinition>[
        FamilyParameterDefinition(
          id: 'width',
          label: 'Overall width',
          kind: FamilyParameterKind.length,
          defaultValue: width,
          minimum: 0.1,
        ),
        FamilyParameterDefinition(
          id: 'depth',
          label: 'Overall depth',
          kind: FamilyParameterKind.length,
          defaultValue: depth,
          minimum: 0.1,
        ),
        FamilyParameterDefinition(
          id: 'height',
          label: 'Overall height',
          kind: FamilyParameterKind.length,
          defaultValue: height,
          minimum: 0.3,
        ),
      ],
      types: <FamilyTypeDefinition>[
        FamilyTypeDefinition(
          id: 'exterior-column-classic',
          name: 'Classic 620 × 620 × 3120',
          values: <String, Object?>{
            'width': width,
            'depth': depth,
            'height': height,
          },
        ),
      ],
      sketches: <FamilySketch>[
        FamilySketch(
          id: 'column-lathe-profile',
          name: 'Stepped lathe profile',
          plane: FamilySketchPlane.xz,
          closed: true,
          points: <FamilySketchPoint>[
            FamilySketchPoint(x: 0.0, y: 0.0),
            FamilySketchPoint(x: 0.22, y: 0.0),
            FamilySketchPoint(x: 0.22, y: 0.14),
            FamilySketchPoint(x: 0.30, y: 0.14),
            FamilySketchPoint(x: 0.30, y: 0.28),
            FamilySketchPoint(x: 0.24, y: 0.36),
            FamilySketchPoint(x: 0.18, y: 0.48),
            FamilySketchPoint(x: 0.18, y: 2.64),
            FamilySketchPoint(x: 0.24, y: 2.76),
            FamilySketchPoint(x: 0.30, y: 2.84),
            FamilySketchPoint(x: 0.30, y: 2.98),
            FamilySketchPoint(x: 0.22, y: 2.98),
            FamilySketchPoint(x: 0.22, y: 3.12),
            FamilySketchPoint(x: 0.0, y: 3.12),
          ],
        ),
      ],
      features: <FamilyFeature>[
        FamilyFeature(
          id: 'column-revolve',
          kind: FamilyFeatureKind.revolve,
          label: 'Classic stepped column',
          parameters: <String, Object?>{
            'profileId': 'column-lathe-profile',
            'angle': 360.0,
          },
        ),
      ],
    );
  }

  static FamilyDocument _storageCabinet() {
    final geometry = <String, Object?>{
      'vertices': <List<double>>[],
      'faces': <List<int>>[],
    };
    final vertices = geometry['vertices']! as List<List<double>>;
    final faces = geometry['faces']! as List<List<int>>;

    // A compact built-in wardrobe: carcass, back, divider, shelf, framed
    // doors, crown/plinth and two recessed handles. Each box remains a
    // separate shell inside one family mesh so the project gets one instance.
    _appendBox(vertices, faces, -1.20, 0.00, 0.00, -1.08, 2.40, 0.62);
    _appendBox(vertices, faces, 1.08, 0.00, 0.00, 1.20, 2.40, 0.62);
    _appendBox(vertices, faces, -1.20, 2.28, 0.00, 1.20, 2.40, 0.62);
    _appendBox(vertices, faces, -1.20, 0.00, 0.00, 1.20, 0.12, 0.62);
    _appendBox(vertices, faces, -1.20, 0.00, 0.50, 1.20, 2.40, 0.62);
    _appendBox(vertices, faces, -0.04, 0.12, 0.00, 0.04, 2.28, 0.50);
    _appendBox(vertices, faces, -1.08, 1.16, 0.00, 1.08, 1.24, 0.50);
    _appendBox(vertices, faces, -1.06, 0.14, -0.035, -0.04, 2.26, 0.045);
    _appendBox(vertices, faces, 0.04, 0.14, -0.035, 1.06, 2.26, 0.045);
    _appendBox(vertices, faces, -1.28, 2.40, -0.02, 1.28, 2.52, 0.66);
    _appendBox(vertices, faces, -1.28, -0.10, -0.02, 1.28, 0.00, 0.66);
    _appendBox(vertices, faces, -0.16, 1.14, -0.10, -0.08, 1.30, -0.025);
    _appendBox(vertices, faces, 0.08, 1.14, -0.10, 0.16, 1.30, -0.025);

    return FamilyDocument(
      id: 'builtin-storage-cabinet-v1',
      name: 'Storage Cabinet · Modern',
      category: FamilyCategory.furniture,
      description:
          'A clean two-door storage cabinet with framed fronts, shelf and recessed handles.',
      parameters: const <FamilyParameterDefinition>[
        FamilyParameterDefinition(
          id: 'width',
          label: 'Overall width',
          kind: FamilyParameterKind.length,
          defaultValue: 2.56,
          minimum: 0.2,
        ),
        FamilyParameterDefinition(
          id: 'depth',
          label: 'Overall depth',
          kind: FamilyParameterKind.length,
          defaultValue: 0.75,
          minimum: 0.2,
        ),
        FamilyParameterDefinition(
          id: 'height',
          label: 'Overall height',
          kind: FamilyParameterKind.length,
          defaultValue: 2.62,
          minimum: 0.2,
        ),
      ],
      types: const <FamilyTypeDefinition>[
        FamilyTypeDefinition(
          id: 'storage-cabinet-modern',
          name: 'Modern 2560 × 750 × 2620',
          values: <String, Object?>{
            'width': 2.56,
            'depth': 0.75,
            'height': 2.62,
          },
        ),
      ],
      features: <FamilyFeature>[
        FamilyFeature(
          id: 'cabinet-mesh',
          kind: FamilyFeatureKind.freeformMesh,
          label: 'Modern framed storage cabinet',
          parameters: geometry,
        ),
      ],
    );
  }

  static void _appendBox(
    List<List<double>> vertices,
    List<List<int>> faces,
    double minX,
    double minY,
    double minZ,
    double maxX,
    double maxY,
    double maxZ,
  ) {
    final offset = vertices.length;
    vertices.addAll(<List<double>>[
      <double>[minX, minY, minZ],
      <double>[maxX, minY, minZ],
      <double>[maxX, maxY, minZ],
      <double>[minX, maxY, minZ],
      <double>[minX, minY, maxZ],
      <double>[maxX, minY, maxZ],
      <double>[maxX, maxY, maxZ],
      <double>[minX, maxY, maxZ],
    ]);
    faces.addAll(<List<int>>[
      <int>[offset, offset + 3, offset + 2, offset + 1],
      <int>[offset + 4, offset + 5, offset + 6, offset + 7],
      <int>[offset, offset + 1, offset + 5, offset + 4],
      <int>[offset + 3, offset + 7, offset + 6, offset + 2],
      <int>[offset, offset + 4, offset + 7, offset + 3],
      <int>[offset + 1, offset + 2, offset + 6, offset + 5],
    ]);
  }
}
