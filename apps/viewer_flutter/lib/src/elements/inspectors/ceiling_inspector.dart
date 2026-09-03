part of '../../property_editor.dart';

Widget _buildCeilingInspector(_ObjectInspectorContext context) =>
    _buildCeilingInspectorFromParameters(
      context,
      SurfaceElementParameters.fromObject(context.object),
    );

Widget _buildCeilingInspectorFromParameters(
  _ObjectInspectorContext context,
  SurfaceElementParameters parameters,
) =>
    _ReadOnlyObjectSection(
      object: context.object,
      title: '${_label(context.object)} properties',
      rows: <String, String>{
        'Level': parameters.levelId?.toString() ?? '-',
        'Area (${context.units.areaSymbol})':
            parameters.areaSquareMeters == null
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
