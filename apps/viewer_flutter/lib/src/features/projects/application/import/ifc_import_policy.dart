/// Pure policy for choosing the large-IFC native-first transfer path.
///
/// The threshold changes only how data reaches the viewport. IFC source
/// geometry remains authoritative regardless of the selected route.
abstract final class IfcImportPolicy {
  static const int nativeFirstThresholdBytes = 8 * 1024 * 1024;

  static bool shouldPreferNativeFirst({
    required int sourceBytes,
    required bool nativeViewport,
  }) {
    return nativeViewport && sourceBytes >= nativeFirstThresholdBytes;
  }
}
