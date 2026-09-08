import '../render_scene_models.dart';
import 'family_instance_store.dart';
import 'family_scene_runtime_compiler.dart';
import 'family_spatial_streaming.dart';

/// Per-scene family runtime compilation cache.
///
/// RenderScene snapshots are immutable in the viewer workflow, so identity is
/// a safe migration key: a new authoritative snapshot gets a new compact store
/// while repeated camera frames reuse the same typed arrays and spatial index.
final class FamilyRuntimeSceneState {
  const FamilyRuntimeSceneState({
    required this.store,
    required this.spatialIndex,
  });

  final FamilyInstanceStore store;
  final FamilySpatialIndex spatialIndex;
}

abstract final class FamilyRuntimeSceneCache {
  static final Expando<FamilyRuntimeSceneState> _cache =
      Expando<FamilyRuntimeSceneState>('family-runtime-scene');

  static FamilyRuntimeSceneState forScene(RenderScene scene) {
    final cached = _cache[scene];
    if (cached != null) return cached;
    final store = FamilySceneRuntimeCompiler.compile(scene);
    final state = FamilyRuntimeSceneState(
      store: store,
      spatialIndex: FamilySpatialIndex.build(store),
    );
    _cache[scene] = state;
    return state;
  }
}
