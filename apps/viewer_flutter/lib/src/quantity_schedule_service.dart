import 'dart:isolate';

import 'render_scene_editor.dart';
import 'render_scene_estimator.dart';
import 'render_scene_models.dart';

/// Lazy result used only by schedule/quantity surfaces.
final class QuantityScheduleResult {
  const QuantityScheduleResult({
    required this.detectedScene,
    required this.summary,
  });

  final RenderScene detectedScene;
  final RenderSceneEstimateSummary summary;
}

/// Keeps BIM analytics out of the viewport lifecycle.
///
/// Nothing is calculated until a schedule/quantity surface explicitly asks
/// for [forScene]. The first request is moved to a worker isolate and cached by
/// immutable RenderScene identity; reopening the same schedule reuses the
/// completed Future instead of scanning the model again.
final class QuantityScheduleService {
  QuantityScheduleService._();

  static final Expando<Future<QuantityScheduleResult>> _cache =
      Expando<Future<QuantityScheduleResult>>('quantity_schedule_cache');

  static Future<QuantityScheduleResult> forScene(
    RenderScene scene, {
    bool refresh = false,
  }) {
    if (!refresh) {
      final cached = _cache[scene];
      if (cached != null) return cached;
    }

    final future = Isolate.run<QuantityScheduleResult>(() {
      final detected = RenderSceneEditor.detectRooms(scene);
      final summary = RenderSceneEstimator.summarize(detected);
      return QuantityScheduleResult(
        detectedScene: detected,
        summary: summary,
      );
    });
    _cache[scene] = future;
    return future;
  }
}
