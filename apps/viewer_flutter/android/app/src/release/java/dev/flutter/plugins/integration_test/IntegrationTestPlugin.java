package dev.flutter.plugins.integration_test;

import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * Release-only no-op companion for Flutter's generated plugin registrant.
 *
 * integration_test is intentionally a dev dependency. The Flutter tool still
 * emits its registrar entry when it generates the release source set, but the
 * test plugin itself must not be packaged into a production APK. This class
 * keeps the generated registrar linkable while leaving the test bridge absent
 * at runtime.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
