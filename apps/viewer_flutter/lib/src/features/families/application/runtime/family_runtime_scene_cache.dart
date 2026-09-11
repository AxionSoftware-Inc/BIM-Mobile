import '../render_scene_models.dart';
import 'family_2d_asset_library.dart';
import 'family_gpu_residency.dart';
import 'family_instance_store.dart';
import 'family_scene_runtime_compiler.dart';
import 'family_spatial_streaming.dart';

/// Per-scene family runtime compilation cache.
///
/// RenderScene snapshots are immutable in the viewer workflow, so identity is
/// a safe migration key: a new authoritative snapshot gets a new compact store
/// while repeated camera frames reuse the same typed arrays, compiled 2D
/// symbols, spatial index and family GPU residency history.
final class FamilyRuntimeSceneState {
  FamilyRuntimeSceneState({
    required this.store,
    required this.twoDimensionalAssets,
    required this.spatialIndex,
    required this.gpuResidency,
  });

  final FamilyInstanceStore store;
  final Family2dAssetLibrary twoDimensionalAssets;
  final FamilySpatialIndex spatialIndex;

  /// Shared residency controller for a future/native 3D family bridge.
  ///
  /// Keeping this beside the immutable scene runtime is important: recreating
  /// it per frame would erase warm-cache hysteresis and make assets churn at
  /// camera/frustum boundaries.
  final FamilyGpuResidencyController gpuResidency;
}

abstract final class FamilyRuntimeSceneCache {
  static final Expando<FamilyRuntimeSceneState> _cache =
      Expando<FamilyRuntimeSceneState>('family-runtime-scene');

  static FamilyRuntimeSceneState forScene(RenderScene scene) {
    final cached = _cache[scene];
    if (cached != null) return cached;
    final compilation = FamilySceneRuntimeCompiler.compileRuntime(scene);
    final state = FamilyRuntimeSceneState(
      store: compilation.store,
      twoDimensionalAssets: compilation.twoDimensionalAssets,
      spatialIndex: FamilySpatialIndex.build(compilation.store),
      gpuResidency: FamilyGpuResidencyController(),
    );
    _cache[scene] = state;
    return state;
  }
}
