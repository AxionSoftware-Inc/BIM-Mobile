part of 'widget_test.dart';

void registerElementModuleRegistryTests() {
  test('standard element modules own shared BIM semantics', () {
    const registry = BimElementRegistry.standard;

    expect(registry.normalizeKind('FloorSystem'), 'floor');
    expect(registry.normalizeKind('ceiling_system'), 'ceiling');
    expect(registry.normalizeKind('opening'), 'door');
    expect(registry.normalizeKind('foreign_mesh'), 'proxy');
    expect(registry.displayName('wall'), 'Wall');
    expect(registry.isOpening('door'), isTrue);
    expect(registry.isOpening('window'), isTrue);
    expect(registry.isOpening('wall'), isFalse);
    expect(
        registry.levelLockedKinds,
        containsAll(<String>[
          'wall',
          'door',
          'window',
          'floor',
          'ceiling',
          'roof',
          'slab',
          'column',
          'beam',
          'stair',
        ]));
    expect(registry.levelLockedKinds, isNot(contains('room')));
    expect(
        registry.planCoreKinds,
        containsAll(<String>[
          'wall',
          'door',
          'window',
        ]));
  });

  test('new modules and types extend the boundary without viewport changes',
      () {
    const type = BimElementTypeDefinition(
      id: 'wall.exterior.300',
      name: 'Exterior 300',
      family: BimElementTypeFamily.wall,
      parameters: <String, Object?>{
        'thickness_meters': 0.30,
        'layer_count': 4,
      },
    );
    const customModule = BimElementModule(
      kindKey: 'furniture',
      displayName: 'Furniture',
      typeFamily: BimElementTypeFamily.none,
      aliases: <String>{'furniture', 'casework'},
      isArchitectural: false,
      defaultVisibleIn3d: false,
      typeDefinitions: <BimElementTypeDefinition>[type],
    );
    final registry = BimElementRegistry(<BimElementModule>[
      ...BimElementRegistry.standard.modules,
      customModule,
    ]);

    expect(registry.normalizeKind('casework'), 'furniture');
    expect(registry.displayName('casework'), 'Furniture');
    expect(
      registry.typeCatalog
          .find(BimElementTypeFamily.wall, 'wall.exterior.300')
          ?.parameters['layer_count'],
      4,
    );
    expect(registry.architecturalKinds, isNot(contains('furniture')));
  });
}
