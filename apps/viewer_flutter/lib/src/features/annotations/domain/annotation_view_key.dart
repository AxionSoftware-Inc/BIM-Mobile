import 'dart:convert';

/// Stable 63-bit identity used by persistent annotation rows.
///
/// DOMAIN CONTRACT: workspace view ids may be presentation strings, while the
/// packed annotation database stores Int64 keys. This conversion must remain
/// deterministic across app launches and platform implementations.
abstract final class AnnotationViewKey {
  static int fromWorkspaceId(String value) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(value)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
    }
    // Zero is reserved for "no active view".
    return hash == 0 ? 1 : hash;
  }
}
