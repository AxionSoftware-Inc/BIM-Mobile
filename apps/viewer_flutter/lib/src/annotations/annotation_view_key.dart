import 'dart:convert';

/// Stable 63-bit key used by the packed annotation store.
///
/// Workspace view ids are strings because they are UI/document references;
/// the data-oriented store uses Int64List. Keep the conversion deterministic
/// across process launches so persisted annotations reopen in the same view.
abstract final class AnnotationViewKey {
  static int fromWorkspaceId(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    // Reserve zero for callers that explicitly mean "no view".
    return hash == 0 ? 1 : hash;
  }
}
