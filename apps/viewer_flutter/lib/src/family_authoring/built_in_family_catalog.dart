import 'family_document.dart';

/// Curated families shipped with the authoring module.
///
/// These are normal `.bimfamily` documents once installed into the local
/// family library. Keeping the definitions here makes the first project
/// usable without a separate download while leaving family and project file
/// boundaries intact. The catalog is deliberately small: common choices,
/// stable ids and simple geometry that remains pleasant on a tablet.
abstract final class BuiltInFamilyCatalog {
  static List<FamilyDocument> get families => <FamilyDocument>[
        _exteriorColumn(),
        _reinforcedConcreteColumn(),
        _singleFlushDoor(),
        _doubleGlazedDoor(),
        _singleCasementWindow(),
        _widePictureWindow(),
        _straightStair(),
        _lStair(),
        _wallSweepBelt(),
        _storageCabinet(),
        _kitchenBaseCabinet(),
        _refrigerator(),
        _toiletFixture(),
        _bathroomVanity(),
        _bathtub(),
        _threeSeatSofa(),
        _sectionalSofa(),
        _diningTable(),
        _kitchenIsland(),
        _diningChair(),
        _officeChair(),
        _doubleBed(),
        _singleBed(),
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

  static FamilyDocument _reinforcedConcreteColumn() => _meshFamily(
        id: 'builtin-column-concrete-v1',
        name: 'Column · Reinforced Concrete',
        category: FamilyCategory.column,
        description: 'A clean square concrete column for interiors and frames.',
        width: 0.40,
        depth: 0.40,
        height: 3.20,
        typeName: 'Concrete 400 × 400 × 3200',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.30, 0.00, -0.30, 0.30, 0.18, 0.30);
          _appendBox(mesh, -0.20, 0.18, -0.20, 0.20, 3.02, 0.20);
          _appendBox(mesh, -0.30, 3.02, -0.30, 0.30, 3.20, 0.30);
        }),
      );

  static FamilyDocument _singleFlushDoor() => _boxFamily(
        id: 'builtin-door-single-flush-v1',
        name: 'Door · Single Flush',
        category: FamilyCategory.door,
        description: 'A compact single-leaf interior door.',
        width: 0.90,
        depth: 0.20,
        height: 2.10,
        typeName: 'Single 900 × 2100',
      );

  static FamilyDocument _doubleGlazedDoor() => _boxFamily(
        id: 'builtin-door-double-glazed-v1',
        name: 'Door · Double Glazed',
        category: FamilyCategory.door,
        description: 'A wider double-leaf glazed entrance door.',
        width: 1.60,
        depth: 0.20,
        height: 2.20,
        typeName: 'Double 1600 × 2200',
      );

  static FamilyDocument _singleCasementWindow() => _openingFamily(
        id: 'builtin-window-single-casement-v1',
        name: 'Window · Single Casement',
        description: 'A practical single opening window for regular rooms.',
        width: 1.20,
        depth: 0.18,
        height: 1.40,
        sillHeight: 0.90,
        typeName: 'Casement 1200 × 1400',
      );

  static FamilyDocument _widePictureWindow() => _openingFamily(
        id: 'builtin-window-wide-picture-v1',
        name: 'Window · Wide Picture',
        description: 'A wide fixed window for living rooms and facades.',
        width: 2.40,
        depth: 0.18,
        height: 1.50,
        sillHeight: 0.75,
        typeName: 'Picture 2400 × 1500',
      );

  static FamilyDocument _straightStair() => _meshFamily(
        id: 'builtin-stair-straight-v1',
        name: 'Stair · Straight Run',
        category: FamilyCategory.stair,
        description: 'A simple straight stair with twelve readable treads.',
        width: 1.20,
        depth: 4.80,
        height: 3.20,
        typeName: 'Straight 1200 × 4800 × 3200',
        geometry: _geometry((mesh) {
          const count = 12;
          const tread = 4.80 / count;
          const rise = 3.20 / count;
          for (var index = 0; index < count; index++) {
            final minZ = -2.40 + index * tread;
            _appendBox(
              mesh,
              -0.60,
              0.00,
              minZ,
              0.60,
              (index + 1) * rise,
              minZ + tread,
            );
          }
        }),
      );

  static FamilyDocument _lStair() => _meshFamily(
        id: 'builtin-stair-l-shaped-v1',
        name: 'Stair · L Shape',
        category: FamilyCategory.stair,
        description: 'A compact quarter-turn stair with a central landing.',
        width: 2.40,
        depth: 3.60,
        height: 3.20,
        typeName: 'L Shape 2400 × 3600 × 3200',
        geometry: _geometry((mesh) {
          const count = 6;
          const tread = 1.80 / count;
          const rise = 1.60 / count;
          for (var index = 0; index < count; index++) {
            final minZ = -1.80 + index * tread;
            _appendBox(
              mesh,
              -1.20,
              0.00,
              minZ,
              0.00,
              (index + 1) * rise,
              minZ + tread,
            );
          }
          _appendBox(mesh, -1.20, 1.60, 0.00, 0.00, 1.76, 1.20);
          for (var index = 0; index < count; index++) {
            final minX = index * 1.20 / count;
            _appendBox(
              mesh,
              minX,
              1.60,
              0.00,
              minX + 1.20 / count,
              1.60 + (index + 1) * rise,
              1.20,
            );
          }
        }),
      );

  static FamilyDocument _wallSweepBelt() => _meshFamily(
        id: 'builtin-wall-sweep-belt-v1',
        name: 'Wall Sweep · Horizontal Belt',
        category: FamilyCategory.wallSweep,
        description:
            'A slim horizontal architectural belt hosted by a wall. Select a wall, choose a type, and place it along the wall direction.',
        width: 3.00,
        depth: 0.06,
        height: 0.24,
        typeName: 'Horizontal Belt 3000 × 60 × 240',
        geometry: _geometry((mesh) {
          // Family X follows the host wall, Y is vertical and Z is centered
          // around the wall centerline. This keeps the sweep flush on either
          // side of straight and curved wall hosts.
          _appendBox(mesh, -1.50, 1.20, -0.03, 1.50, 1.44, 0.03);
        }),
      );

  static FamilyDocument _storageCabinet() {
    final geometry = _geometry((mesh) {
      // Carcass, back, divider, shelf, framed doors, crown/plinth and handles.
      _appendBox(mesh, -1.20, 0.00, 0.00, -1.08, 2.40, 0.62);
      _appendBox(mesh, 1.08, 0.00, 0.00, 1.20, 2.40, 0.62);
      _appendBox(mesh, -1.20, 2.28, 0.00, 1.20, 2.40, 0.62);
      _appendBox(mesh, -1.20, 0.00, 0.00, 1.20, 0.12, 0.62);
      _appendBox(mesh, -1.20, 0.00, 0.50, 1.20, 2.40, 0.62);
      _appendBox(mesh, -0.04, 0.12, 0.00, 0.04, 2.28, 0.50);
      _appendBox(mesh, -1.08, 1.16, 0.00, 1.08, 1.24, 0.50);
      _appendBox(mesh, -1.06, 0.14, -0.035, -0.04, 2.26, 0.045);
      _appendBox(mesh, 0.04, 0.14, -0.035, 1.06, 2.26, 0.045);
      _appendBox(mesh, -1.28, 2.40, -0.02, 1.28, 2.52, 0.66);
      _appendBox(mesh, -1.28, -0.10, -0.02, 1.28, 0.00, 0.66);
      _appendBox(mesh, -0.16, 1.14, -0.10, -0.08, 1.30, -0.025);
      _appendBox(mesh, 0.08, 1.14, -0.10, 0.16, 1.30, -0.025);
    });
    return _meshFamily(
      id: 'builtin-storage-cabinet-v1',
      name: 'Cabinet · Storage Modern',
      category: FamilyCategory.casework,
      description:
          'A clean two-door storage cabinet with framed fronts and recessed handles.',
      width: 2.56,
      depth: 0.75,
      height: 2.62,
      typeName: 'Modern 2560 × 750 × 2620',
      geometry: geometry,
    );
  }

  static FamilyDocument _kitchenBaseCabinet() => _meshFamily(
        id: 'builtin-kitchen-base-cabinet-v1',
        name: 'Cabinet · Kitchen Base',
        category: FamilyCategory.casework,
        description: 'A modular lower kitchen cabinet with a durable worktop.',
        width: 2.40,
        depth: 0.65,
        height: 0.90,
        typeName: 'Base 2400 × 650 × 900',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -1.20, 0.00, -0.325, 1.20, 0.82, 0.325);
          _appendBox(mesh, -1.25, 0.82, -0.35, 1.25, 0.90, 0.35);
          _appendBox(mesh, -1.08, 0.12, -0.35, -0.04, 0.76, -0.315);
          _appendBox(mesh, 0.04, 0.12, -0.35, 1.08, 0.76, -0.315);
          _appendBox(mesh, -1.20, 0.00, 0.00, 1.20, 0.10, 0.24);
        }),
      );

  static FamilyDocument _refrigerator() => _meshFamily(
        id: 'builtin-appliance-refrigerator-v1',
        name: 'Appliance · Refrigerator',
        category: FamilyCategory.casework,
        description:
            'A full-height refrigerator sized for a residential kitchen.',
        width: 0.90,
        depth: 0.75,
        height: 2.05,
        typeName: 'Freestanding 900 × 750 × 2050',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.45, 0.00, -0.375, 0.45, 2.05, 0.375);
          _appendBox(mesh, -0.41, -0.015, -0.37, 0.41, 1.18, -0.335);
          _appendBox(mesh, -0.41, -0.015, 0.04, 0.41, 1.98, 0.37);
          _appendBox(mesh, -0.025, 0.18, -0.045, 0.025, 0.22, 0.12);
          _appendBox(mesh, -0.025, 1.40, -0.045, 0.025, 1.46, 0.12);
        }),
      );

  static FamilyDocument _toiletFixture() => _meshFamily(
        id: 'builtin-fixture-toilet-v1',
        name: 'Fixture · Toilet',
        category: FamilyCategory.genericModel,
        description:
            'A compact floor-mounted toilet for a residential bathroom.',
        width: 0.40,
        depth: 0.70,
        height: 0.45,
        typeName: 'Floor Mounted 400 × 700 × 450',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.20, 0.00, -0.35, 0.20, 0.10, 0.25);
          _appendBox(mesh, -0.18, 0.08, -0.10, 0.18, 0.28, 0.28);
          _appendBox(mesh, -0.17, 0.10, 0.10, 0.17, 0.45, 0.35);
        }),
      );

  static FamilyDocument _bathroomVanity() => _meshFamily(
        id: 'builtin-fixture-vanity-v1',
        name: 'Fixture · Bathroom Vanity',
        category: FamilyCategory.casework,
        description:
            'A single-basin bathroom vanity with a compact cabinet body.',
        width: 0.90,
        depth: 0.55,
        height: 0.85,
        typeName: 'Single 900 × 550 × 850',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.45, -0.275, 0.00, 0.45, 0.78, 0.275);
          _appendBox(mesh, -0.48, -0.30, 0.78, 0.48, 0.85, 0.30);
          _appendBox(mesh, -0.20, 0.83, -0.16, 0.20, 0.88, 0.16);
          _appendBox(mesh, -0.025, 0.85, -0.36, 0.025, 1.05, -0.30);
        }),
      );

  static FamilyDocument _bathtub() => _meshFamily(
        id: 'builtin-fixture-bathtub-v1',
        name: 'Fixture · Bathtub',
        category: FamilyCategory.genericModel,
        description: 'A standard residential bathtub with a raised rim.',
        width: 1.70,
        depth: 0.75,
        height: 0.60,
        typeName: 'Standard 1700 × 750 × 600',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.85, 0.00, -0.375, 0.85, 0.52, 0.375);
          _appendBox(mesh, -0.82, 0.52, -0.35, 0.82, 0.60, 0.35);
          _appendBox(mesh, -0.66, 0.50, -0.21, 0.66, 0.54, 0.21);
        }),
      );

  static FamilyDocument _threeSeatSofa() => _meshFamily(
        id: 'builtin-sofa-three-seat-v1',
        name: 'Sofa · Three Seat',
        category: FamilyCategory.furniture,
        description: 'A compact three-seat sofa for living rooms and lounges.',
        width: 2.20,
        depth: 0.90,
        height: 0.85,
        typeName: 'Three Seat 2200 × 900 × 850',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -1.05, 0.05, -0.42, 1.05, 0.25, 0.42);
          _appendBox(mesh, -1.00, 0.25, -0.38, 1.00, 0.48, 0.38);
          _appendBox(mesh, -1.00, 0.45, 0.25, 1.00, 0.85, 0.42);
          _appendBox(mesh, -1.10, 0.25, -0.40, -0.88, 0.70, 0.34);
          _appendBox(mesh, 0.88, 0.25, -0.40, 1.10, 0.70, 0.34);
        }),
      );

  static FamilyDocument _sectionalSofa() => _meshFamily(
        id: 'builtin-sofa-sectional-v1',
        name: 'Sofa · L Sectional',
        category: FamilyCategory.furniture,
        description: 'An L-shaped sectional sofa for larger living spaces.',
        width: 2.60,
        depth: 1.80,
        height: 0.85,
        typeName: 'L Sectional 2600 × 1800 × 850',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -1.30, 0.05, -0.90, 1.30, 0.25, 0.90);
          _appendBox(mesh, -1.20, 0.25, -0.80, 1.20, 0.48, 0.80);
          _appendBox(mesh, -1.20, 0.45, 0.55, 1.20, 0.85, 0.85);
          _appendBox(mesh, -1.30, 0.25, -0.85, -0.85, 0.70, 0.60);
          _appendBox(mesh, -1.30, 0.45, -0.85, -1.05, 0.85, 0.55);
        }),
      );

  static FamilyDocument _diningTable() => _meshFamily(
        id: 'builtin-table-dining-v1',
        name: 'Table · Dining',
        category: FamilyCategory.furniture,
        description: 'A four-leg dining table for kitchens and dining rooms.',
        width: 1.80,
        depth: 0.90,
        height: 0.75,
        typeName: 'Dining 1800 × 900 × 750',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.90, 0.68, -0.45, 0.90, 0.75, 0.45);
          for (final x in <double>[-0.80, 0.68]) {
            for (final z in <double>[-0.35, 0.25]) {
              _appendBox(mesh, x, 0.00, z, x + 0.12, 0.68, z + 0.12);
            }
          }
        }),
      );

  static FamilyDocument _kitchenIsland() => _meshFamily(
        id: 'builtin-table-kitchen-island-v1',
        name: 'Table · Kitchen Island',
        category: FamilyCategory.furniture,
        description: 'A practical kitchen island with a thick overhanging top.',
        width: 2.20,
        depth: 0.90,
        height: 0.95,
        typeName: 'Island 2200 × 900 × 950',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -1.10, 0.05, -0.45, 1.10, 0.85, 0.45);
          _appendBox(mesh, -1.18, 0.85, -0.48, 1.18, 0.95, 0.48);
          _appendBox(mesh, -0.96, 0.20, -0.47, -0.04, 0.74, -0.44);
          _appendBox(mesh, 0.04, 0.20, -0.47, 0.96, 0.74, -0.44);
        }),
      );

  static FamilyDocument _diningChair() => _meshFamily(
        id: 'builtin-chair-dining-v1',
        name: 'Chair · Dining',
        category: FamilyCategory.furniture,
        description: 'A simple dining chair with a comfortable back.',
        width: 0.52,
        depth: 0.55,
        height: 0.90,
        typeName: 'Dining 520 × 550 × 900',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.25, 0.43, -0.27, 0.25, 0.52, 0.27);
          _appendBox(mesh, -0.23, 0.52, 0.16, 0.23, 0.90, 0.27);
          for (final x in <double>[-0.21, 0.13]) {
            for (final z in <double>[-0.20, 0.08]) {
              _appendBox(mesh, x, 0.00, z, x + 0.08, 0.43, z + 0.08);
            }
          }
        }),
      );

  static FamilyDocument _officeChair() => _meshFamily(
        id: 'builtin-chair-office-v1',
        name: 'Chair · Office',
        category: FamilyCategory.furniture,
        description: 'A compact task chair with a high back and central base.',
        width: 0.68,
        depth: 0.68,
        height: 1.05,
        typeName: 'Office 680 × 680 × 1050',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.34, 0.48, -0.30, 0.34, 0.58, 0.30);
          _appendBox(mesh, -0.28, 0.55, 0.16, 0.28, 1.05, 0.30);
          _appendBox(mesh, -0.05, 0.00, -0.05, 0.05, 0.48, 0.05);
          _appendBox(mesh, -0.30, 0.00, -0.03, 0.30, 0.05, 0.03);
          _appendBox(mesh, -0.03, 0.00, -0.30, 0.03, 0.05, 0.30);
        }),
      );

  static FamilyDocument _doubleBed() => _meshFamily(
        id: 'builtin-bed-double-v1',
        name: 'Bed · Double',
        category: FamilyCategory.furniture,
        description: 'A double bed with a simple upholstered headboard.',
        width: 1.80,
        depth: 2.00,
        height: 1.05,
        typeName: 'Double 1800 × 2000 × 1050',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.90, 0.00, -1.00, 0.90, 0.25, 1.00);
          _appendBox(mesh, -0.86, 0.25, -0.90, 0.86, 0.55, 0.90);
          _appendBox(mesh, -0.90, 0.00, 0.78, 0.90, 1.05, 1.00);
        }),
      );

  static FamilyDocument _singleBed() => _meshFamily(
        id: 'builtin-bed-single-v1',
        name: 'Bed · Single',
        category: FamilyCategory.furniture,
        description: 'A compact single bed for bedrooms and guest rooms.',
        width: 1.00,
        depth: 2.00,
        height: 0.95,
        typeName: 'Single 1000 × 2000 × 950',
        geometry: _geometry((mesh) {
          _appendBox(mesh, -0.50, 0.00, -1.00, 0.50, 0.22, 1.00);
          _appendBox(mesh, -0.46, 0.22, -0.90, 0.46, 0.52, 0.90);
          _appendBox(mesh, -0.50, 0.00, 0.78, 0.50, 0.95, 1.00);
        }),
      );

  static FamilyDocument _boxFamily({
    required String id,
    required String name,
    required FamilyCategory category,
    required String description,
    required double width,
    required double depth,
    required double height,
    required String typeName,
  }) {
    return _meshOrBoxFamily(
      id: id,
      name: name,
      category: category,
      description: description,
      width: width,
      depth: depth,
      height: height,
      typeName: typeName,
      features: <FamilyFeature>[
        FamilyFeature(
          id: '$id-box',
          kind: FamilyFeatureKind.box,
          label: 'Parametric box',
          parameters: <String, Object?>{
            'width': 'width',
            'depth': 'depth',
            'height': 'height',
          },
        ),
      ],
    );
  }

  static FamilyDocument _openingFamily({
    required String id,
    required String name,
    required String description,
    required double width,
    required double depth,
    required double height,
    required double sillHeight,
    required String typeName,
  }) {
    final parameters = _dimensionParameters(
      width: width,
      depth: depth,
      height: height,
    )..add(
        FamilyParameterDefinition(
          id: 'sillHeight',
          label: 'Sill height',
          kind: FamilyParameterKind.length,
          defaultValue: sillHeight,
          minimum: 0.0,
        ),
      );
    return _meshOrBoxFamily(
      id: id,
      name: name,
      category: FamilyCategory.window,
      description: description,
      width: width,
      depth: depth,
      height: height,
      typeName: typeName,
      parameters: parameters,
      extraValues: <String, Object?>{'sillHeight': sillHeight},
      features: <FamilyFeature>[
        FamilyFeature(
          id: '$id-box',
          kind: FamilyFeatureKind.box,
          label: 'Window opening envelope',
          parameters: <String, Object?>{
            'width': 'width',
            'depth': 'depth',
            'height': 'height',
          },
        ),
      ],
    );
  }

  static FamilyDocument _meshFamily({
    required String id,
    required String name,
    required FamilyCategory category,
    required String description,
    required double width,
    required double depth,
    required double height,
    required String typeName,
    required Map<String, Object?> geometry,
  }) {
    return _meshOrBoxFamily(
      id: id,
      name: name,
      category: category,
      description: description,
      width: width,
      depth: depth,
      height: height,
      typeName: typeName,
      features: <FamilyFeature>[
        FamilyFeature(
          id: '$id-mesh',
          kind: FamilyFeatureKind.freeformMesh,
          label: 'Curated family mesh',
          parameters: geometry,
        ),
      ],
    );
  }

  static FamilyDocument _meshOrBoxFamily({
    required String id,
    required String name,
    required FamilyCategory category,
    required String description,
    required double width,
    required double depth,
    required double height,
    required String typeName,
    required List<FamilyFeature> features,
    List<FamilyParameterDefinition>? parameters,
    Map<String, Object?> extraValues = const <String, Object?>{},
  }) {
    final dimensionList = parameters ??
        _dimensionParameters(width: width, depth: depth, height: height);
    return FamilyDocument(
      id: id,
      name: name,
      category: category,
      description: description,
      parameters: List<FamilyParameterDefinition>.unmodifiable(dimensionList),
      types: <FamilyTypeDefinition>[
        FamilyTypeDefinition(
          id: '$id-type',
          name: typeName,
          values: <String, Object?>{
            'width': width,
            'depth': depth,
            'height': height,
            ...extraValues,
          },
        ),
      ],
      features: List<FamilyFeature>.unmodifiable(features),
    );
  }

  static List<FamilyParameterDefinition> _dimensionParameters({
    required double width,
    required double depth,
    required double height,
  }) =>
      <FamilyParameterDefinition>[
        FamilyParameterDefinition(
          id: 'width',
          label: 'Overall width',
          kind: FamilyParameterKind.length,
          defaultValue: width,
          minimum: 0.05,
        ),
        FamilyParameterDefinition(
          id: 'depth',
          label: 'Overall depth',
          kind: FamilyParameterKind.length,
          defaultValue: depth,
          minimum: 0.05,
        ),
        FamilyParameterDefinition(
          id: 'height',
          label: 'Overall height',
          kind: FamilyParameterKind.length,
          defaultValue: height,
          minimum: 0.05,
        ),
      ];

  static Map<String, Object?> _geometry(
    void Function(Map<String, Object?> mesh) build,
  ) {
    final mesh = <String, Object?>{
      'vertices': <List<double>>[],
      'faces': <List<int>>[],
    };
    build(mesh);
    return mesh;
  }

  static void _appendBox(
    Map<String, Object?> mesh,
    double minX,
    double minY,
    double minZ,
    double maxX,
    double maxY,
    double maxZ,
  ) {
    final vertices = mesh['vertices']! as List<List<double>>;
    final faces = mesh['faces']! as List<List<int>>;
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
