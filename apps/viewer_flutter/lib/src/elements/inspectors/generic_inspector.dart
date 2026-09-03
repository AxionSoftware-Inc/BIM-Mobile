part of '../../property_editor.dart';

Widget _buildGenericInspector(_ObjectInspectorContext context) =>
    _ReadOnlyObjectSection(
      object: context.object,
      title: '${_label(context.object)} properties',
      rows: <String, String>{
        'Level': context.object.levelId?.toString() ?? '-',
        'Material': context.object.materialCategory,
      },
    );
