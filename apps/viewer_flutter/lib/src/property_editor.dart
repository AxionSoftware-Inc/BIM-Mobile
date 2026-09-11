// COMPATIBILITY: temporary facade for legacy property editor imports. It owns
// the legacy local Family adapter so the canonical presentation feature stays
// infrastructure-neutral.
// REMOVE WHEN: viewer_app imports the canonical PropertyEditor and passes
// ViewerAppDependencies.familyAssets explicitly.
import 'package:flutter/foundation.dart';

import 'core/application/render_scene/render_scene_models.dart';
import 'core/domain/units/project_unit_settings.dart';
import 'features/authoring/application/authoring_command_service.dart';
import 'features/elements/presentation/inspector_controller.dart';
import 'features/elements/presentation/property_editor/property_editor.dart'
    as canonical;
import 'features/families/infrastructure/library/local_family_asset_repository.dart';

export 'features/elements/presentation/property_editor/property_editor.dart'
    hide PropertyEditor;

class PropertyEditor extends canonical.PropertyEditor {
  const PropertyEditor({
    super.key,
    required RenderScene scene,
    required InspectorTarget target,
    required AuthoringCommandService commands,
    required canonical.ApplyInspectorResult onApplied,
    required VoidCallback onClearSelection,
    required ProjectUnitSettings units,
    required double viewRangeMeters,
    required Future<void> Function(double value) onViewRangeChanged,
    required bool showPlanViewRange,
    required RenderSceneLevel? activePlanLevel,
  }) : super(
          scene: scene,
          target: target,
          commands: commands,
          familyAssets: const LocalFamilyAssetRepository(),
          onApplied: onApplied,
          onClearSelection: onClearSelection,
          units: units,
          viewRangeMeters: viewRangeMeters,
          onViewRangeChanged: onViewRangeChanged,
          showPlanViewRange: showPlanViewRange,
          activePlanLevel: activePlanLevel,
        );
}
