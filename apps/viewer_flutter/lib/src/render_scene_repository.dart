import 'dart:io';

import 'package:flutter/services.dart';

import 'render_scene_models.dart';

abstract interface class RenderSceneSource {
  Future<RenderSceneLoadResult> loadBundledSample();
  Future<RenderSceneLoadResult> loadFromFile(String path);
  Future<RenderSceneLoadResult> loadFromJson(
    String json, {
    String source,
  });
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
