part of '../../property_editor.dart';

// COMPATIBILITY: retained as a part-library shim while property_editor.dart
// still lists the legacy Inspector parts.
// REMOVE WHEN: generic_inspector.dart is removed from PropertyEditor's parts.
Widget _buildGenericInspector(_ObjectInspectorContext context) =>
    BimReadOnlyObjectSection(
      object: context.object,
      title: '${bimInspectorLabel(context.object)} properties',
      rows: <String, String>{
        'Level': context.object.levelId?.toString() ?? '-',
        'Material': context.object.materialCategory,
      },
    );
