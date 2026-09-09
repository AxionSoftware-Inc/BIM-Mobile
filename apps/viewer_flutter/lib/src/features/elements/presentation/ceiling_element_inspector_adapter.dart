import 'package:flutter/widgets.dart';

import '../application/parameters/surface_element_parameters.dart';
import '../domain/bim_element_module.dart';
import 'bim_element_inspector_adapter.dart';
import 'bim_inspector_primitives.dart';

final class CeilingElementInspectorAdapter
    implements BimElementInspectorAdapter {
  const CeilingElementInspectorAdapter();

  @override
  String get key => BimElementInspectorKeys.ceiling;

  @override
  Widget build(BuildContext context, BimInspectorContext inspector) {
    final object = inspector.object;
    final parameters = SurfaceElementParameters.fromObject(object);
    return BimReadOnlyObjectSection(
      object: object,
      title: '${bimInspectorLabel(object)} properties',
      rows: <String, String>{
        'Level': parameters.levelId?.toString() ?? '-',
        'Area (${inspector.units.areaSymbol})':
            parameters.areaSquareMeters == null
                ? '-'
                : inspector.units.formatArea(parameters.areaSquareMeters!),
        'Thickness (${inspector.units.lengthSymbol})':
            parameters.thicknessMeters == null
                ? '-'
                : inspector.units.formatLength(parameters.thicknessMeters!),
        'Vertical offset (${inspector.units.lengthSymbol})':
            parameters.verticalOffsetMeters == null
                ? '-'
                : inspector.units
                    .formatLength(parameters.verticalOffsetMeters!),
      },
    );
  }
}
