import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'render_scene_models.dart';
import 'tbe_engine_worker.dart';

abstract interface class RenderSceneSource {
  Future<RenderSceneLoadResult> loadBundledSample();
  Future<RenderSceneLoadResult> loadFromFile(String path);
  Future<RenderSceneLoadResult> loadFromJson(
    String json, {
    String source,
  });
}

/// Loads a project through the C API and returns the engine's current
/// RenderScene snapshot. The asset source remains available for parser tests
/// and for platforms where the native engine has not been linked yet.
class EngineRenderSceneSource implements RenderSceneSource {
  EngineRenderSceneSource({
    this.projectAssetPath = 'assets/sample_project.json',
  });

  final String projectAssetPath;

  TbeEngineWorker? _worker;

  Future<TbeEngineWorker> _engineWorker() async {
    return _worker ??= await TbeEngineWorker.start();
  }

  @override
  Future<RenderSceneLoadResult> loadBundledSample() async {
    final json = await rootBundle.loadString(projectAssetPath);
    return loadFromJson(json, source: projectAssetPath);
  }

  @override
  Future<RenderSceneLoadResult> loadFromFile(String path) async {
    final json = await File(path).readAsString();
    return loadFromJson(json, source: path);
  }

  @override
  Future<RenderSceneLoadResult> loadFromJson(
    String json, {
    String source = 'project.json',
  }) async {
    try {
      final renderSceneJson =
          await (await _engineWorker()).loadProjectJson(json);
      return parseRenderSceneJson(
        renderSceneJson,
        source: 'engine:$source',
      );
    } catch (error) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is! Map || decoded['document'] is! Map) {
          return RenderSceneLoadResult(
            scene: null,
            warnings: const <String>[],
            errors: <String>['Engine project load failed for $source: $error'],
          );
        }
      } on FormatException {
        return RenderSceneLoadResult(
          scene: null,
          warnings: const <String>[],
          errors: <String>['Engine project load failed for $source: $error'],
        );
      }
      final fallback = await const AssetRenderSceneSource().loadFromAsset(
        'assets/render_scene.json',
      );
      return RenderSceneLoadResult(
        scene: fallback.scene,
        warnings: <String>[
          'Engine project load failed for $source; using the validated RenderScene fallback: $error',
          ...fallback.warnings,
        ],
        errors: fallback.errors,
      );
    }
  }

  Future<RenderSceneLoadResult> refreshFromEngine() async {
    try {
      final json = await (await _engineWorker()).renderSceneJson();
      return parseRenderSceneJson(json, source: 'engine:current');
    } catch (error) {
      return RenderSceneLoadResult(
        scene: null,
        warnings: const <String>[],
        errors: <String>['Engine refresh failed: $error'],
      );
    }
  }

  Future<int> createWall({
    required String name,
    required int levelId,
    required double startX,
    required double startY,
    required double endX,
    required double endY,
    required double thicknessMeters,
    required double heightMeters,
  }) {
    return _engineWorker().then(
      (worker) => worker.createWall(
        name: name,
        levelId: levelId,
        startX: startX,
        startY: startY,
        endX: endX,
        endY: endY,
        thicknessMeters: thicknessMeters,
        heightMeters: heightMeters,
      ),
    );
  }

  Future<void> undo() async {
    await (await _engineWorker()).undo();
  }

  Future<void> redo() async {
    await (await _engineWorker()).redo();
  }

  void dispose() {
    final worker = _worker;
    _worker = null;
    if (worker != null) {
      unawaited(worker.dispose());
    }
  }
}

class AssetRenderSceneSource implements RenderSceneSource {
  const AssetRenderSceneSource({
    this.sampleAssetPath = 'assets/render_scene.json',
  });

  final String sampleAssetPath;

  @override
  Future<RenderSceneLoadResult> loadBundledSample() {
    return loadFromAsset(sampleAssetPath);
  }

  Future<RenderSceneLoadResult> loadFromAsset(String assetPath) async {
    final json = await rootBundle.loadString(assetPath);
    return parseRenderSceneJson(json, source: assetPath);
  }

  @override
  Future<RenderSceneLoadResult> loadFromFile(String path) async {
    final json = await File(path).readAsString();
    return parseRenderSceneJson(json, source: path);
  }

  @override
  Future<RenderSceneLoadResult> loadFromJson(
    String json, {
    String source = 'render_scene.json',
  }) async {
    return parseRenderSceneJson(json, source: source);
  }
}

class MemoryRenderSceneSource implements RenderSceneSource {
  const MemoryRenderSceneSource(this.json, {this.source = 'memory'});

  final String json;
  final String source;

  @override
  Future<RenderSceneLoadResult> loadBundledSample() {
    return loadFromJson(json, source: source);
  }

  @override
  Future<RenderSceneLoadResult> loadFromFile(String path) async {
    return parseRenderSceneJson(json, source: source);
  }

  @override
  Future<RenderSceneLoadResult> loadFromJson(
    String json, {
    String source = 'render_scene.json',
  }) async {
    return parseRenderSceneJson(json, source: source);
  }
}
