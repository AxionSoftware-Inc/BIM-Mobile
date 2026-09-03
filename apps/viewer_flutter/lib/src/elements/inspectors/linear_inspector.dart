part of '../../property_editor.dart';

Widget _buildLinearInspector(_ObjectInspectorContext context) =>
    _buildLinearInspectorFromParameters(
      context,
      LinearElementParameters.fromObject(context.object),
    );

Widget _buildLinearInspectorFromParameters(
  _ObjectInspectorContext context,
  LinearElementParameters parameters,
) =>
    _ReadOnlyObjectSection(
      object: context.object,
      title: '${_label(context.object)} properties',
      rows: <String, String>{
        'Level': context.object.levelId?.toString() ?? '-',
        'Height (${context.units.lengthSymbol})':
            parameters.heightMeters == null
                ? '-'
                : context.units.formatLength(parameters.heightMeters!),
        'Length (${context.units.lengthSymbol})':
            parameters.lengthMeters == null
                ? '-'
                : context.units.formatLength(parameters.lengthMeters!),
        'Material': context.object.materialCategory,
      },
    );
