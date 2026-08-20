part of 'tbe_ffi.dart';

/// Read-only native scene boundary used by the Flutter gateways.
///
/// It owns JSON-to-RenderScene conversion, nearby/full scene policy and
/// spatial hit-test calls. Authoring and project persistence stay outside this
/// module so a query cannot accidentally mutate the native document.
final class TbeSceneQueryRepository {
  TbeSceneQueryRepository({
    required TbeViewerApi api,
    required ffi.Pointer<ffi.Void>? Function() handle,
    required int Function() activeLevelId,
    required bool Function() fullSceneRenderScope,
  })  : _api = api,
        _handle = handle,
        _activeLevelId = activeLevelId,
        _fullSceneRenderScope = fullSceneRenderScope;

  final TbeViewerApi _api;
  final ffi.Pointer<ffi.Void>? Function() _handle;
  final int Function() _activeLevelId;
  final bool Function() _fullSceneRenderScope;

  Future<RenderSceneLoadResult> currentRenderScene() async {
    final handle = _requireHandle();
    final levelId = _activeLevelId();
    final timer = Stopwatch()..start();
    final nearby = !_fullSceneRenderScope() && levelId > 0;
    final json = nearby
        ? _api.getRenderSceneJsonNearLevel(handle, levelId)
        : _api.getRenderSceneJson(handle);
    timer.stop();
    final source = nearby
        ? 'engine:nearby levels active=$levelId · '
            '${timer.elapsedMilliseconds} ms · ${json.length ~/ 1024} KiB'
        : 'engine:full 3D snapshot · ${timer.elapsedMilliseconds} ms · '
            '${json.length ~/ 1024} KiB';
    return parseRenderSceneJson(json, source: source);
  }

  Future<RenderSceneLoadResult> sectionScene(
    RenderScenePoint start,
    RenderScenePoint end,
  ) async {
    final json = _api.getSectionSceneJson(_requireHandle(), start, end);
    return parseRenderSceneJson(json, source: 'engine:section');
  }

  List<HitCandidateView> hitTest(
    double modelX,
    double modelY, {
    double toleranceMeters = 0.25,
  }) {
    return _api.hitTestCandidates(
      _requireHandle(),
      _activeLevelId(),
      modelX,
      modelY,
      toleranceMeters: toleranceMeters,
    );
  }

  ffi.Pointer<ffi.Void> _requireHandle() {
    final handle = _handle();
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    return handle;
  }
}
