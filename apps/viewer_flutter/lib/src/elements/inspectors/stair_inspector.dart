part of '../../property_editor.dart';

Widget _buildStairInspector(_ObjectInspectorContext context) =>
    _buildStairInspectorFromParameters(
      context,
      StairElementParameters.fromObject(context.object),
    );

Widget _buildStairInspectorFromParameters(
  _ObjectInspectorContext context,
  StairElementParameters parameters,
) =>
    _ReadOnlyObjectSection(
      object: context.object,
      title: 'Stair properties',
      rows: <String, String>{
        'Base level': parameters.baseLevelId?.toString() ?? '-',
        'Top level': parameters.topLevelId?.toString() ?? '-',
        'Width (${context.units.lengthSymbol})': parameters.widthMeters == null
            ? '-'
            : context.units.formatLength(parameters.widthMeters!),
        'Run / rise (${context.units.lengthSymbol})':
            '${parameters.totalRunMeters == null ? '-' : context.units.formatLength(parameters.totalRunMeters!)} / '
                '${parameters.totalRiseMeters == null ? '-' : context.units.formatLength(parameters.totalRiseMeters!)}',
        'Treads / risers':
            '${parameters.treadCount?.toString() ?? '-'} / ${parameters.riserCount?.toString() ?? '-'}',
      },
    );
