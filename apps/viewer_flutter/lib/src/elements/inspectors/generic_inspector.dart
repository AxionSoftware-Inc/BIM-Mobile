part of '../../property_editor.dart';

// COMPATIBILITY: retained as a part-library shim while property_editor.dart
// still lists the legacy Inspector parts.
// REMOVE WHEN: generic_inspector.dart is removed from PropertyEditor's parts.
Widget _buildGenericInspector(_ObjectInspectorContext context) =>
    const GenericElementInspectorAdapter().build(
      // Legacy callers never provide a BuildContext to the old builder shape;
      // this shim is intentionally no longer routed. Keep it only as a source
      // compatibility symbol until the part declaration is removed.
      throw StateError('Legacy generic Inspector builder is no longer routed.'),
      BimInspectorContext(
        scene: context.scene,
        object: context.object,
        units: context.units,
        commands: context.commands,
        onApplied: context.onApplied,
      ),
    );
