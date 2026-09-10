/// Supplemental document state that follows the authoritative BIM project.
///
/// Examples are view annotations or other project-adjacent documents that are
/// persisted separately from geometry. Project application services depend on
/// this port instead of importing another feature's runtime implementation.
abstract interface class ProjectCompanionDocument {
  /// Stable canonical registration key, for example `annotations`.
  String get key;

  /// Reset state when a brand-new/IFC-backed project becomes active.
  Future<void> resetForNewProject();

  /// Restore state that belongs beside an existing project/package path.
  Future<void> restoreForProjectPath(String? projectPath);

  /// Persist state after the authoritative project checkpoint is durable.
  Future<void> saveForProjectPath(String projectPath);
}

/// Immutable composition-root collection of project companion documents.
///
/// REGISTRATION CONTRACT:
/// - keys are normalized once;
/// - duplicate keys are rejected during composition;
/// - feature implementations are never discovered through a global locator.
final class ProjectCompanionDocuments {
  ProjectCompanionDocuments(Iterable<ProjectCompanionDocument> documents)
      : _documents = List<ProjectCompanionDocument>.unmodifiable(documents) {
    final keys = <String>{};
    for (final document in _documents) {
      final key = _canonicalKey(document.key);
      if (key.isEmpty) {
        throw StateError('Project companion document key must not be empty.');
      }
      if (!keys.add(key)) {
        throw StateError('Duplicate project companion document key: $key');
      }
    }
  }

  static final ProjectCompanionDocuments empty =
      ProjectCompanionDocuments(const <ProjectCompanionDocument>[]);

  final List<ProjectCompanionDocument> _documents;

  List<ProjectCompanionDocument> get documents => _documents;

  Future<void> resetForNewProject() async {
    for (final document in _documents) {
      await document.resetForNewProject();
    }
  }

  Future<void> restoreForProjectPath(String? projectPath) async {
    for (final document in _documents) {
      await document.restoreForProjectPath(projectPath);
    }
  }

  Future<void> saveForProjectPath(String projectPath) async {
    for (final document in _documents) {
      await document.saveForProjectPath(projectPath);
    }
  }

  static String _canonicalKey(String value) => value.trim().toLowerCase();
}
