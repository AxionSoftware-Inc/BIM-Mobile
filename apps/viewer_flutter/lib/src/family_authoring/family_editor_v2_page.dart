import 'family_editor_v3_page.dart';

/// Compatibility entry point kept for Library/navigation callers.
///
/// Family document/geometry schemas remain V6; only the authoring shell moved
/// to the interactive V3 implementation. Existing routes therefore gain orbit,
/// zoom and editable feature-graph controls without a migration.
class FamilyEditorV2Page extends FamilyEditorV3Page {
  const FamilyEditorV2Page({
    super.key,
    super.initialAsset,
  });
}
