import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/projects/application/import/ifc_import_policy.dart';

void main() {
  test('native-first requires both native viewport and threshold-sized IFC', () {
    const threshold = IfcImportPolicy.nativeFirstThresholdBytes;

    expect(
      IfcImportPolicy.shouldPreferNativeFirst(
        sourceBytes: threshold - 1,
        nativeViewport: true,
      ),
      isFalse,
    );
    expect(
      IfcImportPolicy.shouldPreferNativeFirst(
        sourceBytes: threshold,
        nativeViewport: false,
      ),
      isFalse,
    );
    expect(
      IfcImportPolicy.shouldPreferNativeFirst(
        sourceBytes: threshold,
        nativeViewport: true,
      ),
      isTrue,
    );
  });
}
