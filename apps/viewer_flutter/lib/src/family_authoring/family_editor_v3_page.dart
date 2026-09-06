import 'family_editor_v4_page.dart';

/// Compatibility alias for callers that adopted the short-lived V3 shell.
///
/// V4 is the single active Family Editor. It uses the production project
/// RenderScene viewport, so no second family-specific orbit/camera/render path
/// can drift from the project workspace again.
class FamilyEditorV3Page extends FamilyEditorV4Page {
  const FamilyEditorV3Page({
    super.key,
    super.initialAsset,
  });
}
