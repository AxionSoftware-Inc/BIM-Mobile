import 'package:flutter/widgets.dart';

import '../domain/bim_element_module.dart';
import 'bim_element_inspector_adapter.dart';
import 'bim_inspector_primitives.dart';

/// Standalone fallback Inspector for element kinds without a specialized UI.
final class GenericElementInspectorAdapter
    implements BimElementInspectorAdapter {
  const GenericElementInspectorAdapter();

  @override
  String get key => BimElementInspectorKeys.generic;

  @override
  Widget build(BuildContext context, BimInspectorContext inspector) {
    final object = inspector.object;
    return BimReadOnlyObjectSection(
      object: object,
      title: '${bimInspectorLabel(object)} properties',
      rows: <String, String>{
        'Level': object.levelId?.toString() ?? '-',
        'Material': object.materialCategory,
      },
    );
  }
}
