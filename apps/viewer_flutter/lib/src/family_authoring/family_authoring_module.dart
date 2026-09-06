import 'package:flutter/material.dart';

import 'family_editor_v2_page.dart';

export 'family_document.dart';
export 'family_editor_v2_page.dart';
export 'family_file_store.dart';
export 'family_geometry.dart';
export 'family_library_dialog.dart';
export 'family_mesh_importer.dart';
export 'family_parameter_resolver.dart';
export 'family_plan_symbol.dart';
export 'family_sketch_canvas.dart';
export 'family_validation.dart';

/// Single registration point for the detachable Family Authoring feature.
abstract final class FamilyAuthoringModule {
  static const String key = 'family_authoring';

  static Future<void> createFamily(BuildContext context) async {
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => const FamilyEditorV2Page(),
      ),
    );
  }
}
