import 'dart:io';

/// Replaces a small JSON checkpoint without exposing a partially-written
/// target file to the next application start.
Future<void> atomicWriteString(File target, String contents) async {
  final temporary = File(
    '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    await temporary.writeAsString(contents, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (!await target.exists()) rethrow;
      await target.delete();
      await temporary.rename(target.path);
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

/// Replaces a binary artifact (for example an exported PDF or cached IFC)
/// without deleting a known-good previous artifact first.
Future<void> atomicWriteBytes(File target, List<int> bytes) async {
  final temporary = File(
    '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    try {
      await temporary.rename(target.path);
    } on FileSystemException {
      if (!await target.exists()) rethrow;
      await target.delete();
      await temporary.rename(target.path);
    }
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

/// Serializes writes to one logical file while preserving the original
/// operation error for its caller.
final class SerializedFileWriter {
  Future<void> _tail = Future<void>.value();

  Future<void> write(File target, String contents) {
    final next = _tail.then<void>(
      (_) => atomicWriteString(target, contents),
    );
    _tail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }
}
