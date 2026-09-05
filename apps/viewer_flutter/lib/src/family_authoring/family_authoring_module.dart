import 'package:flutter/material.dart';

import 'family_editor_page.dart';

export 'family_document.dart';
export 'family_editor_page.dart';
export 'family_file_store.dart';
export 'family_geometry.dart';
export 'family_library_dialog.dart';
export 'family_plan_symbol.dart';
export 'family_sketch_canvas.dart';
export 'family_validation.dart';

/// Single registration point for the detachable Family Authoring feature.
///
/// The project start flow depends only on this facade. Removing the family
/// module means removing one import and one callback, while project scene
/// persistence remains unchanged.
abstract final class FamilyAuthoringModule {
  static const String key = 'family_authoring';

  static Future<void> createFamily(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FamilyEditorPage(),
      ),
    );
  }
}
