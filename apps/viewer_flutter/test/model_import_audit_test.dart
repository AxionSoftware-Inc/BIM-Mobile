import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/src/model_import/ifc_source_inventory.dart';
import '../lib/src/model_import/model_import_audit.dart';
import '../lib/src/render_scene_models.dart';

void main() {
  test('IFC inventory counts renderable products without loading whole model API', () async {
    final directory = await Directory.systemTemp.createTemp('tbe_ifc_inventory_');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/inventory.ifc');
    await file.writeAsString('''
ISO-10303-21;
DATA;
#10=IFCWALL('W1',\$, 'Wall A',\$,\$,#20,#30,\$);
#11=IFCFURNISHINGELEMENT('F1',\$,'Fridge',\$,\$,#21,#31,\$);
#12=IFCPROPERTYSET('P1',\$,'Identity',\$,());
#13=IFCRELDEFINESBYPROPERTIES('R1',\$,\$,\$,(#10),#12);
ENDSEC;
END-ISO-10303-21;
''');

    final inventory = await const IfcSourceInventoryReader().readPath(file.path);

    expect(inventory.physicalProductCount, 2);
    expect(inventory.typeCounts['IFCWALL'], 1);
    expect(inventory.typeCounts['IFCFURNISHINGELEMENT'], 1);
    expect(inventory.products.map((item) => item.globalId), containsAll(<String>['W1', 'F1']));
  });

  test('audit exposes uncovered IFC products instead of silently dropping them', () {
    const source = IfcSourceInventory(
      assignmentCount: 4,
      physicalProductCount: 2,
      products: <IfcSourceProduct>[
        IfcSourceProduct(stepId: 10, entityType: 'IFCWALL', globalId: 'W1'),
        IfcSourceProduct(stepId: 11, entityType: 'IFCFURNISHINGELEMENT', globalId: 'F1'),
      ],
      typeCounts: <String, int>{'IFCWALL': 1, 'IFCFURNISHINGELEMENT': 1},
    );

    final parsed = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 1,
        'units': 'm',
        'coordinate_system': 'right-handed-z-up',
        'object_count': 1,
        'vertex_count': 3,
        'index_count': 3,
        'bounds': <String, Object?>{
          'min': <String, double>{'x': 0, 'y': 0, 'z': 0},
          'max': <String, double>{'x': 1, 'y': 1, 'z': 1},
        },
        'levels': const <Object?>[],
        'materials': const <Object?>[],
        'sections': const <Object?>[],
        'objects': <Object?>[
          <String, Object?>{
            'element_id': 1,
            'kind': 'Wall',
            'level_id': 1,
            'selectable': true,
            'visible_by_default': true,
            'revision': 1,
            'bounds': <String, Object?>{
              'min': <String, double>{'x': 0, 'y': 0, 'z': 0},
              'max': <String, double>{'x': 1, 'y': 1, 'z': 1},
            },
            'mesh': <String, Object?>{
              'positions': <Object?>[
                <String, double>{'x': 0, 'y': 0, 'z': 0},
                <String, double>{'x': 1, 'y': 0, 'z': 0},
                <String, double>{'x': 0, 'y': 1, 'z': 0},
              ],
              'indices': <int>[0, 1, 2],
            },
            'material_category': 'generic',
            'metadata': <String, Object?>{
              'ifc_guid': 'W1',
              'ifc_entity': 'IFCWALL',
              'ifc_exact_geometry': true,
            },
          },
        ],
      }),
      source: 'audit-test',
    );
    expect(parsed.scene, isNotNull);

    final audit = ModelImportAudit.build(source: source, scene: parsed.scene!);

    expect(audit.sourcePhysicalProducts, 2);
    expect(audit.importedSourceProducts, 1);
    expect(audit.unmatchedSourceProducts, 1);
    expect(audit.unmatched.single.globalId, 'F1');
    expect(audit.hasSilentDrops, isFalse);
    expect(audit.isComplete, isFalse);
  });
}
