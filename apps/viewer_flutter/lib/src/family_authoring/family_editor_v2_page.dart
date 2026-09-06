import 'family_editor_v4_page.dart';

/// Compatibility entry point kept for Library/navigation callers.
///
/// Family document/geometry schemas remain unchanged. The active authoring
/// shell is V4, which reuses the project RenderScene viewport and exposes a
/// task-oriented CAD workflow instead of the old graph-first editor.
class FamilyEditorV2Page extends FamilyEditorV4Page {
  const FamilyEditorV2Page({
    super.key,
    super.initialAsset,
  });
}
