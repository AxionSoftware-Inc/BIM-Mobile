import 'dart:io';

import '../project_lifecycle_service.dart';
import '../render_scene_models.dart';
import '../viewer_project_session.dart';
import '../viewer_scene_gateway.dart';
import 'ifc_source_inventory.dart';
import 'model_import_audit.dart';
import 'model_import_cache.dart';
import 'model_import_models.dart';

abstract interface class ModelImportAdapter<T extends ViewerEngineSession> {
  ModelImportFormatDescriptor get descriptor;

  Future<ProjectSessionResult<T>> importSource(ModelImportSource source);

  Future<String> semanticCheckpoint(T session);
}

class IfcModelImportAdapter<T extends ViewerEngineSession>
    implements ModelImportAdapter<T> {
  IfcModelImportAdapter({
    required ProjectLifecycleService<T> lifecycle,
    required this.descriptor,
  }) : _lifecycle = lifecycle;

  final ProjectLifecycleService<T> _lifecycle;

  @override
  final ModelImportFormatDescriptor descriptor;

  @override
  Future<ProjectSessionResult<T>> importSource(ModelImportSource source) {
    return _lifecycle.loadIfc(
      projectName: source.displayName,
      ifcPath: source.path,
    );
  }

  @override
  Future<String> semanticCheckpoint(T session) {
    return session.snapshotImportedProjectJson();
  }
}

/// Transaction boundary for every external model import.
///
/// No adapter receives the active workspace session. A fresh candidate is
/// parsed and queried first; only the caller can commit it to the workspace.
/// This keeps a malformed source or stale cache from corrupting the open model.
class ModelImportService<T extends ViewerEngineSession> {
  ModelImportService({
    required ProjectLifecycleService<T> lifecycle,
    required ModelImportRegistry registry,
    required Iterable<ModelImportAdapter<T>> adapters,
    ModelImportCacheStore? cache,
    IfcSourceInventoryReader? ifcInventoryReader,
  })  : _lifecycle = lifecycle,
        registry = registry,
        _adapters = <String, ModelImportAdapter<T>>{
          for (final adapter in adapters) adapter.descriptor.id: adapter,
        },
        _cache = cache ?? ModelImportCacheStore(),
        _ifcInventoryReader =
            ifcInventoryReader ?? const IfcSourceInventoryReader();

  factory ModelImportService.standard({
    required ProjectLifecycleService<T> lifecycle,
  }) {
    final registry = ModelImportRegistry.standard();
    final ifc = registry.formats.firstWhere((format) => format.id == 'ifc');
    return ModelImportService<T>(
      lifecycle: lifecycle,
      registry: registry,
      adapters: <ModelImportAdapter<T>>[
        IfcModelImportAdapter<T>(lifecycle: lifecycle, descriptor: ifc),
      ],
    );
  }

  final ProjectLifecycleService<T> _lifecycle;
  final Map<String, ModelImportAdapter<T>> _adapters;
  final ModelImportCacheStore _cache;
  final IfcSourceInventoryReader _ifcInventoryReader;
  final ModelImportRegistry registry;

  void _progress(
    ModelImportProgressCallback? callback,
    ModelImportStage stage,
    double fraction,
    String message,
  ) {
    callback?.call(
      ModelImportProgress(
        stage: stage,
        fraction: fraction.clamp(0.0, 1.0),
        message: message,
      ),
    );
  }

  Future<ModelImportSource> inspectSource({
    required String path,
    required String displayName,
  }) async {
    // Android's file selector may materialize a picked document URI as a
    // private temporary file with a generic `.bin` suffix. The user-visible
    // display name still retains the authoritative IFC extension, so use it
    // as a safe format hint when the materialized path has no known suffix.
    final format =
        registry.resolvePath(path) ?? registry.resolvePath(displayName);
    if (format == null) {
      throw UnsupportedError('Unsupported model format: $displayName');
    }
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file || stat.size <= 0) {
      throw StateError('Model source is missing or empty: $displayName');
    }
    return ModelImportSource(
      path: path,
      displayName: displayName,
      format: format,
      byteSize: stat.size,
      modifiedMilliseconds: stat.modified.millisecondsSinceEpoch,
    );
  }

  Future<ModelImportCandidate<T>> prepare({
    required String path,
    required String displayName,
    ModelImportProgressCallback? onProgress,
  }) async {
    _progress(onProgress, ModelImportStage.inspecting, 0.02,
        'Inspecting model source…');
    final source = await inspectSource(path: path, displayName: displayName);
    final adapter = _adapters[source.format.id];
    if (adapter == null) {
      throw UnsupportedError(
        'No ${source.format.label} importer is registered.',
      );
    }

    if (source.format.id != 'ifc') {
      throw UnsupportedError(
        '${source.format.label} does not yet provide a source coverage audit.',
      );
    }

    _progress(onProgress, ModelImportStage.inventory, 0.08,
        'Inventorying IFC products…');
    var sourceInventory = await _cache.readIfcInventory(source);
    if (sourceInventory == null) {
      sourceInventory = await _ifcInventoryReader.readPath(source.path);
      await _cache.writeIfcInventory(source, sourceInventory);
    }

    _progress(onProgress, ModelImportStage.semanticCache, 0.14,
        'Checking semantic cache…');
    final cached = await _cache.readSemantic(source);
    if (cached != null) {
      ProjectSessionResult<T>? cachedLaunch;
      try {
        cachedLaunch = await _lifecycle.loadJson(
          projectName: source.displayName,
          json: cached.json,
          sourcePath: cached.path,
        );
        _progress(onProgress, ModelImportStage.validating, 0.62,
            'Validating cached BIM scene…');
        final initialScene = await _validatedInitialScene(cachedLaunch.session);
        final audit = ModelImportAudit.build(
          source: sourceInventory,
          scene: initialScene.scene!,
        );
        _progress(
            onProgress, ModelImportStage.ready, 1.0, audit.compactSummary);
        return ModelImportCandidate<T>(
          session: cachedLaunch.session,
          source: source,
          initialScene: initialScene,
          origin: ModelImportOrigin.semanticCache,
          runtimeCachePath: await _cache.runtimeCachePath(source),
          audit: audit,
        );
      } catch (_) {
        cachedLaunch?.session.dispose();
        await _cache.invalidateSemantic(source);
        // A stale or incompatible cache is never fatal. Fall through to the
        // original source and rebuild a clean checkpoint.
      }
    }

    ProjectSessionResult<T>? launch;
    try {
      _progress(onProgress, ModelImportStage.parsing, 0.20,
          'Parsing IFC semantics and geometry…');
      launch = await adapter.importSource(source);
      _progress(onProgress, ModelImportStage.validating, 0.68,
          'Validating imported BIM scene…');
      final initialScene = await _validatedInitialScene(launch.session);
      final audit = ModelImportAudit.build(
        source: sourceInventory,
        scene: initialScene.scene!,
      );
      _progress(onProgress, ModelImportStage.checkpointing, 0.78,
          'Writing semantic checkpoint…');
      final semanticJson = await adapter.semanticCheckpoint(launch.session);
      await _cache.writeSemantic(source, semanticJson);
      _progress(onProgress, ModelImportStage.runtimeCache, 0.90,
          'Preparing native render acceleration…');
      final runtimeCachePath = await _cache.runtimeCachePath(source);
      _progress(onProgress, ModelImportStage.ready, 1.0, audit.compactSummary);
      return ModelImportCandidate<T>(
        session: launch.session,
        source: source,
        initialScene: initialScene,
        origin: ModelImportOrigin.sourceFile,
        runtimeCachePath: runtimeCachePath,
        audit: audit,
      );
    } catch (_) {
      launch?.session.dispose();
      rethrow;
    }
  }

  Future<RenderSceneLoadResult> _validatedInitialScene(T session) async {
    final result = session is ViewerPrimarySceneGateway
        ? await (session as ViewerPrimarySceneGateway)
            .currentPrimaryRenderScene()
        : await session.currentRenderScene();
    final scene = result.scene;
    if (scene == null) {
      final detail = result.errors.isEmpty
          ? 'The importer returned no semantic scene.'
          : result.errors.join('\n');
      throw StateError(detail);
    }
    if (scene.levels.isEmpty && scene.objects.isEmpty) {
      throw StateError('The imported model contains no usable BIM elements.');
    }
    if (!scene.bounds.isFinite) {
      throw StateError('The imported model has invalid non-finite bounds.');
    }
    return result;
  }
}
