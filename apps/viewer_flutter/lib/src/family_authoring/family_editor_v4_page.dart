import 'family_editor_v5_page.dart';

/// Compatibility alias for callers that still reference the V4 page.
///
/// V5 is the single active Family Editor. It keeps the production project
/// viewport, adds viewport solid picking, live tool previews and direct
/// Move/Rotate/Scale gizmos so older navigation routes cannot fall back to the
/// previous inspector-first authoring shell.
class FamilyEditorV4Page extends FamilyEditorV5Page {
  const FamilyEditorV4Page({
    super.key,
    super.initialAsset,
  });
}
