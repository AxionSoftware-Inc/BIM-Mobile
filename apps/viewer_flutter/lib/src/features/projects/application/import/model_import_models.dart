import '../../../../core/application/engine/viewer_project_session.dart';
import '../../../../core/application/render_scene/render_scene_models.dart';
import 'model_import_audit.dart';

/// Stable description of one source-model format.
///
/// UI, cache and orchestration depend on this descriptor rather than on IFC
/// names. Adding a new importer therefore means registering a descriptor and
/// adapter instead of teaching the workspace a second import flow.
class ModelImportFormatDescriptor {
  const ModelImportFormatDescriptor({
    required this.id,
    required this.label,
    required this.extensions,
    required this.semanticCacheVersion,
    this.supportsNativeRuntimeCache = false,
    this.runtimeCacheVersion = 0,
  });

  final String id;
  final String label;
  final List<String> extensions;
  final int semanticCacheVersion;
  final bool supportsNativeRuntimeCache;
  final int runtimeCacheVersion;

  bool acceptsPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return false;
    final extension = path.substring(dot + 1).toLowerCase();
    return extensions.any((value) => value.toLowerCase() == extension);
  }
}

class ModelImportSource {
  const ModelImportSource({
    required this.path,
    required this.displayName,
    required this.format,
    required this.byteSize,
    required this.modifiedMilliseconds,
  });

  final String path;
  final String displayName;
  final ModelImportFormatDescriptor format;
  final int byteSize;
  final int modifiedMilliseconds;
}

enum ModelImportOrigin { semanticCache, sourceFile }

enum ModelImportStage {
  inspecting,
  inventory,
  semanticCache,
  parsing,
  validating,
  checkpointing,
  runtimeCache,
  ready,
}

class ModelImportProgress {
  const ModelImportProgress({
    required this.stage,
    required this.fraction,
    required this.message,
  });

  final ModelImportStage stage;
  final double fraction;
  final String message;
}

typedef ModelImportProgressCallback = void Function(ModelImportProgress progress);

/// A fully validated candidate. Ownership is transferred to the workspace only
/// after this object is returned; failed imports dispose their candidate session
/// before the active project can be touched.
class ModelImportCandidate<T extends ViewerEngineSession> {
  const ModelImportCandidate({
    required this.session,
    required this.source,
    required this.initialScene,
    required this.origin,
    required this.runtimeCachePath,
    required this.audit,
  });

  final T session;
  final ModelImportSource source;
  final RenderSceneLoadResult initialScene;
  final ModelImportOrigin origin;
  final String? runtimeCachePath;
  final ModelImportAudit audit;
}

class ModelImportRegistry {
  ModelImportRegistry(Iterable<ModelImportFormatDescriptor> formats)
      : _formats = List<ModelImportFormatDescriptor>.unmodifiable(formats);

  factory ModelImportRegistry.standard() => ModelImportRegistry(
        const <ModelImportFormatDescriptor>[
          ModelImportFormatDescriptor(
            id: 'ifc',
            label: 'IFC model',
            extensions: <String>['ifc'],
            semanticCacheVersion: 5,
            supportsNativeRuntimeCache: true,
            runtimeCacheVersion: 7,
          ),
        ],
      );

  final List<ModelImportFormatDescriptor> _formats;

  List<ModelImportFormatDescriptor> get formats => _formats;

  List<String> get extensions => _formats
      .expand((format) => format.extensions)
      .map((extension) => extension.toLowerCase())
      .toSet()
      .toList(growable: false);

  ModelImportFormatDescriptor? resolvePath(String path) {
    for (final format in _formats) {
      if (format.acceptsPath(path)) return format;
    }
    return null;
  }
}
