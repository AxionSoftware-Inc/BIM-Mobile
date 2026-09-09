import 'dart:isolate';

import '../../viewer/application/runtime/bim_compact_instance_store.dart';
import '../../../render_scene_editor.dart';
import '../../../render_scene_estimator.dart';
import '../../../render_scene_models.dart';
import 'bim_compact_estimator.dart';

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
/// SCHEDULE APPLICATION OWNERSHIP: nothing is calculated until a schedule or
/// quantity surface explicitly asks for [forScene]. The first request runs in
/// a worker isolate and is cached by immutable RenderScene identity. This
/// policy must not leak back into camera/render lifecycle code.
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
      final compact = BimCompactInstanceStore.fromScene(detected);
      final summary = BimCompactEstimator.summarize(compact);
      return QuantityScheduleResult(
        detectedScene: detected,
        summary: summary,
      );
    });
    _cache[scene] = future;
    return future;
  }
}
