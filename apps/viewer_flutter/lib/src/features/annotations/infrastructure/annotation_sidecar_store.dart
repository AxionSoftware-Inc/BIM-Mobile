import 'dart:io';

import '../../../core/infrastructure/io/atomic_file_writer.dart';
import '../domain/annotation_store.dart';
import 'annotation_store_codec.dart';

/// Durable annotation document stored beside the BIM project checkpoint.
///
/// INFRASTRUCTURE OWNERSHIP: this adapter owns only file-system persistence for
/// the annotation document. It does not own annotation editing state or BIM
/// geometry/cache lifetime.
final class AnnotationSidecarStore {
  const AnnotationSidecarStore();

  File sidecarFor(File projectFile) =>
      File('${projectFile.path}.annotations.json');

  Future<void> save({
    required File projectFile,
    required AnnotationStore store,
  }) async {
    final sidecar = sidecarFor(projectFile);
    await SerializedFileWriter().write(
      sidecar,
      AnnotationStoreCodec.encode(store),
    );
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
