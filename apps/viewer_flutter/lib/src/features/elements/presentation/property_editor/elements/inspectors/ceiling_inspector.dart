part of '../../property_editor.dart';

// COMPATIBILITY: retained as a part-library shim while property_editor.dart
// still lists legacy Inspector parts.
// REMOVE WHEN: ceiling_inspector.dart is removed from PropertyEditor's parts.
Widget _buildCeilingInspector(_ObjectInspectorContext context) {
  final parameters = SurfaceElementParameters.fromObject(context.object);
  return BimReadOnlyObjectSection(
    object: context.object,
    title: '${bimInspectorLabel(context.object)} properties',
    rows: <String, String>{
      'Level': parameters.levelId?.toString() ?? '-',
      'Area (${context.units.areaSymbol})': parameters.areaSquareMeters == null
          ? '-'
          : context.units.formatArea(parameters.areaSquareMeters!),
      'Thickness (${context.units.lengthSymbol})':
          parameters.thicknessMeters == null
              ? '-'
              : context.units.formatLength(parameters.thicknessMeters!),
      'Vertical offset (${context.units.lengthSymbol})':
          parameters.verticalOffsetMeters == null
              ? '-'
              : context.units.formatLength(parameters.verticalOffsetMeters!),
    },
  );
}
