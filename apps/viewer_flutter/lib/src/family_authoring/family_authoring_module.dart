import 'package:flutter/material.dart';

import 'family_editor_v5_page.dart';

export '../features/families/infrastructure/library/family_library_authoring_scene_builder.dart';
export '../features/families/presentation/viewport/family_authoring_viewport.dart';
export '../features/families/infrastructure/catalog/family_bundled_catalog.dart';
export '../features/families/domain/constraints/family_constraint_models.dart';
export '../features/families/domain/constraints/family_constraint_solver.dart';
export '../features/families/presentation/panels/family_constraints_panel.dart';
export '../features/families/domain/geometry/family_csg.dart';
export '../features/families/application/dependencies/family_dependency_resolver.dart';
export '../features/families/domain/document/family_document.dart';
export '../features/families/application/library/family_asset_file.dart';
export '../features/families/application/library/family_library_preferences.dart';
export 'family_editor_v5_page.dart';
export '../features/families/infrastructure/library/family_file_store.dart';
export '../features/families/domain/geometry/family_geometry.dart';
export 'family_library_dialog.dart';
export '../features/families/application/library/family_library_metadata.dart';
export 'family_mesh_importer.dart';
export '../features/families/application/authoring/family_parameter_authoring.dart';
export '../features/families/domain/parameters/family_parameter_resolver.dart';
export '../features/families/presentation/panels/family_parameters_panel.dart';
export '../features/families/application/representation/family_plan_symbol.dart';
export '../features/families/application/integration/family_render_scene_adapter.dart';
export '../features/families/presentation/sketch/family_sketch_canvas.dart';
export '../features/families/presentation/sketch/family_sketch_viewport.dart';
export '../features/families/presentation/panels/family_type_matrix_panel.dart';
export '../features/families/domain/validation/family_validation.dart';

/// Backwards-compatible name used by older integrations and widget tests.
/// The production entry point is [FamilyEditorV5Page].
typedef FamilyEditorPage = FamilyEditorV5Page;

/// Single registration point for the detachable Family Authoring feature.
///
/// New navigation enters V5 directly. V2/V3/V4 classes remain tiny compatibility
/// aliases for old callers only; none of them owns a viewport or editor anymore.
abstract final class FamilyAuthoringModule {
  static const String key = 'family_authoring';

  static Future<void> createFamily(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const FamilyEditorV5Page(),
      ),
    );
  }
}
