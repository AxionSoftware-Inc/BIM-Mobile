import 'package:flutter/foundation.dart';

import 'render_scene_models.dart';
import 'render_scene_repository.dart';

/// Owns project loading state independently from the widget tree and viewport.
class ViewerDocumentController extends ChangeNotifier {
  ViewerDocumentController({required this.source});

  final RenderSceneSource source;

  RenderScene? scene;
  bool isBusy = false;
  String? errorMessage;
  List<String> warnings = const <String>[];

  Future<RenderSceneLoadResult> loadBundledSample() async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await source.loadBundledSample();
      _apply(result);
      return result;
    } catch (error) {
      final result = RenderSceneLoadResult(
        scene: null,
        warnings: const <String>[],
        errors: <String>[error.toString()],
      );
      _apply(result);
      return result;
    }
  }

  Future<RenderSceneLoadResult> reload() => loadBundledSample();

  void _apply(RenderSceneLoadResult result) {
    scene = result.scene;
    warnings = result.warnings;
    errorMessage = result.errors.isEmpty ? null : result.errors.join('\n');
    isBusy = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (source is EngineRenderSceneSource) {
      (source as EngineRenderSceneSource).dispose();
    }
    super.dispose();
  }
}
