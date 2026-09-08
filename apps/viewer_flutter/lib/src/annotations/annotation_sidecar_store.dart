import 'dart:io';

import '../atomic_file_writer.dart';
import 'annotation_store.dart';
import 'annotation_store_codec.dart';

/// Durable annotation document stored beside the BIM project checkpoint.
///
/// Keeping documentation in a sidecar is intentional for the migration phase:
/// annotation edits do not rewrite or invalidate the native BIM geometry/cache.
/// The format is versioned by AnnotationStoreCodec, so a future native package
/// container can absorb this payload without changing the runtime store.
final class AnnotationSidecarStore {
  const AnnotationSidecarStore();

  File sidecarFor(File projectFile) => File('${projectFile.path}.annotations.json');

  Future<void> save({
    required File projectFile,
    required AnnotationStore store,
  }) async {
    final sidecar = sidecarFor(projectFile);
    await SerializedFileWriter().write(sidecar, AnnotationStoreCodec.encode(store));
  }

  Future<AnnotationStore?> load(File projectFile) async {
    final sidecar = sidecarFor(projectFile);
    if (!await sidecar.exists()) return null;
    final source = await sidecar.readAsString();
    if (source.trim().isEmpty) return AnnotationStore.empty();
    return AnnotationStoreCodec.decode(source);
  }

  Future<void> delete(File projectFile) async {
    final sidecar = sidecarFor(projectFile);
    if (await sidecar.exists()) await sidecar.delete();
  }
}
