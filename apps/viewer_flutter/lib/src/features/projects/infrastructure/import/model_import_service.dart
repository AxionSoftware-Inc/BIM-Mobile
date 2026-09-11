import 'dart:convert';
import 'dart:io';

import '../../../../core/application/engine/viewer_project_session.dart';
import '../../../../core/application/engine/viewer_scene_gateway.dart';
import '../../../../core/application/render_scene/render_scene_models.dart';
import '../../application/import/model_import_audit.dart';
import '../../application/import/model_import_models.dart';
import 'ifc_source_inventory_reader.dart';
import 'model_import_cache.dart';

abstract interface class ModelImportAdapter<T extends ViewerEngineSession> {
  ModelImportFormatDescriptor get descriptor;

  Future<T> importSource(ModelImportSource source);

  Future<String> semanticCheckpoint(T session);
}

class IfcModelImportAdapter<T extends ViewerEngineSession>
    implements ModelImportAdapter<T> {
  IfcModelImportAdapter({
    required ModelImportSessionLoader<T> lifecycle,
    required this.descriptor,
  }) : _lifecycle = lifecycle;

  final ModelImportSessionLoader<T> _lifecycle;

  @override
  final ModelImportFormatDescriptor descriptor;

  @override
  Future<T> importSource(ModelImportSource source) {
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
    required ModelImportSessionLoader<T> lifecycle,
    required this.registry,
    required Iterable<ModelImportAdapter<T>> adapters,
    ModelImportCacheStore? cache,
    IfcSourceInventoryReader? ifcInventoryReader,
  })  : _lifecycle = lifecycle,
        _adapters = <String, ModelImportAdapter<T>>{
          for (final adapter in adapters) adapter.descriptor.id: adapter,
        },
        _cache = cache ?? ModelImportCacheStore(),
        _ifcInventoryReader =
            ifcInventoryReader ?? const IfcSourceInventoryReader();

  factory ModelImportService.standard({
    required ModelImportSessionLoader<T> lifecycle,
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

  final ModelImportSessionLoader<T> _lifecycle;
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
    final format = await _resolveFormat(path, displayName);
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

  Future<ModelImportFormatDescriptor?> _resolveFormat(
    String path,
    String displayName,
  ) async {
    final byPath =
        registry.resolvePath(path) ?? registry.resolvePath(displayName);
    if (byPath != null) return byPath;

    final looksLikeProviderTempFile = path.toLowerCase().endsWith('.bin') ||
        displayName.toLowerCase().endsWith('.bin');
    if (looksLikeProviderTempFile && registry.formats.length == 1) {
      return registry.formats.single;
    }

    // Android's document provider may expose an IFC URI as a private
    // temporary `.bin` file and may also return that temporary basename as
    // the display name. The STEP header is tiny and authoritative, so sniff
    // only the first few KiB instead of copying the model into memory.
    try {
      final headerBytes = await File(path)
          .openRead(0, 8192)
          .fold<List<int>>(<int>[], (buffer, chunk) {
        buffer.addAll(chunk);
        return buffer;
      });
      final header =
          utf8.decode(headerBytes, allowMalformed: true).toUpperCase();
      if (header.contains('ISO-10303-21') ||
          header.contains('FILE_DESCRIPTION(')) {
        return registry.formats.firstWhere(
          (format) => format.id == 'ifc',
          orElse: () => throw StateError('IFC format is not registered.'),
        );
      }
    } catch (_) {
      // The normal extension path and source validation below report the
      // actionable error if the temporary document cannot be sampled.
    }
    return null;
  }

  Future<ModelImportCandidate<T>> prepare({
    required String path,
    required String displayName,
    ModelImportProgressCallback? onProgress,
  }) async {
    _progress(
      onProgress,
      ModelImportStage.inspecting,
      0.02,
      'Inspecting model source…',
    );
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

    _progress(
      onProgress,
      ModelImportStage.inventory,
      0.08,
      'Inventorying IFC products…',
    );
    var sourceInventory = await _cache.readIfcInventory(source);
    if (sourceInventory == null) {
      sourceInventory = await _ifcInventoryReader.readPath(source.path);
      await _cache.writeIfcInventory(source, sourceInventory);
    }

    _progress(
      onProgress,
      ModelImportStage.semanticCache,
      0.14,
      'Checking semantic cache…',
    );
    final cached = await _cache.readSemantic(source);
    if (cached != null) {
      T? cachedLaunch;
      try {
        cachedLaunch = await _lifecycle.loadJson(
          projectName: source.displayName,
          json: cached.json,
          sourcePath: cached.path,
        );
        _progress(
          onProgress,
          ModelImportStage.validating,
          0.62,
          'Validating cached BIM scene…',
        );
        final initialScene = await _validatedInitialScene(cachedLaunch);
        final audit = ModelImportAudit.build(
          source: sourceInventory,
          scene: initialScene.scene!,
        );
        _progress(
          onProgress,
          ModelImportStage.ready,
          1.0,
          audit.compactSummary,
        );
        return ModelImportCandidate<T>(
          session: cachedLaunch,
          source: source,
          initialScene: initialScene,
          origin: ModelImportOrigin.semanticCache,
          runtimeCachePath: await _cache.runtimeCachePath(source),
          audit: audit,
        );
      } catch (_) {
        cachedLaunch?.dispose();
        await _cache.invalidateSemantic(source);
        // A stale or incompatible cache is never fatal. Fall through to the
        // original source and rebuild a clean checkpoint.
      }
    }

    T? launch;
    try {
      _progress(
        onProgress,
        ModelImportStage.parsing,
        0.20,
        'Parsing IFC semantics and geometry…',
      );
      launch = await adapter.importSource(source);
      _progress(
        onProgress,
        ModelImportStage.validating,
        0.68,
        'Validating imported BIM scene…',
      );
      final initialScene = await _validatedInitialScene(launch);
      final audit = ModelImportAudit.build(
        source: sourceInventory,
        scene: initialScene.scene!,
      );
      _progress(
        onProgress,
        ModelImportStage.checkpointing,
        0.78,
        'Writing semantic checkpoint…',
      );
      final semanticJson = await adapter.semanticCheckpoint(launch);
      await _cache.writeSemantic(source, semanticJson);
      _progress(
        onProgress,
        ModelImportStage.runtimeCache,
        0.90,
        'Preparing native render acceleration…',
      );
      final runtimeCachePath = await _cache.runtimeCachePath(source);
      _progress(
        onProgress,
        ModelImportStage.ready,
        1.0,
        audit.compactSummary,
      );
      return ModelImportCandidate<T>(
        session: launch,
        source: source,
        initialScene: initialScene,
        origin: ModelImportOrigin.sourceFile,
        runtimeCachePath: runtimeCachePath,
        audit: audit,
      );
    } catch (_) {
      launch?.dispose();
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
