part of '../../property_editor.dart';

Widget _buildLinearInspector(_ObjectInspectorContext context) =>
    _buildLinearInspectorFromParameters(
      context,
      LinearElementParameters.fromObject(context.object),
    );

Widget _buildLinearInspectorFromParameters(
  _ObjectInspectorContext context,
  LinearElementParameters parameters,
) {
  final level = context.scene.levelById(context.object.levelId);
  final familyName = elementParameterText(
    context.object,
    'property.family_name',
  );
  final familyType = elementParameterText(
    context.object,
    'property.family_type_name',
  );
  final isColumn = context.object.kindKey == 'column';
  final rows = <String, String>{
    if (familyName != null) 'Family': familyName,
    if (familyType != null) 'Type': familyType,
    'Level': level?.name ?? context.object.levelId?.toString() ?? '-',
    if (isColumn) ...<String, String>{
      'Width (${context.units.lengthSymbol})': parameters.widthMeters == null
          ? '-'
          : context.units.formatLength(parameters.widthMeters!),
      'Depth (${context.units.lengthSymbol})': parameters.depthMeters == null
          ? '-'
          : context.units.formatLength(parameters.depthMeters!),
    },
    'Height (${context.units.lengthSymbol})': parameters.heightMeters == null
        ? '-'
        : context.units.formatLength(parameters.heightMeters!),
    if (!isColumn)
      'Length (${context.units.lengthSymbol})': parameters.lengthMeters == null
          ? '-'
          : context.units.formatLength(parameters.lengthMeters!),
    'Material': context.object.materialCategory,
  };
  final card = _ReadOnlyObjectSection(
    object: context.object,
    title: '${_label(context.object)} properties',
    rows: rows,
  );
  if (elementParameterText(context.object, 'property.family_asset_id') ==
      null) {
    return card;
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      card,
      const SizedBox(height: 6),
      _FamilyPropertiesSection(
        object: context.object,
        scene: context.scene,
        levels: context.levels,
        units: context.units,
        commands: context.commands,
        onApplied: context.onApplied,
      ),
    ],
  );
}
