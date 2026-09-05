import 'bim_element_module.dart';

final class ProxyElementModule extends BimElementModule {
  const ProxyElementModule()
      : super(
          kindKey: 'proxy',
          displayName: 'Imported element',
          typeFamily: BimElementTypeFamily.none,
          inspectorAdapterKey: BimElementInspectorKeys.family,
          aliases: const <String>{
            'proxy',
            'fbx',
            'fbxmesh',
            'fbxmodel',
            'fbximport',
            'fbx_import',
            'mesh',
            'meshmodel',
            'imported',
            'importedmesh',
            'importedmodel',
            'model3d',
            'external',
            'externalmesh',
            'foreignmesh',
          },
          isArchitectural: false,
        );
}
