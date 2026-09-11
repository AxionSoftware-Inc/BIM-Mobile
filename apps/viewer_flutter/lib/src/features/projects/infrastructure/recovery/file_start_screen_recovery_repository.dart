import '../../application/start_screen/start_screen_recovery_repository.dart';
import '../project_recovery_store.dart';

/// File-backed adapter for the narrow recovery contract consumed by the start
/// flow. Project recovery naming, path validation and deletion rules stay in
/// [ProjectRecoveryStore].
final class FileStartScreenRecoveryRepository
    implements StartScreenRecoveryRepository {
  FileStartScreenRecoveryRepository({ProjectRecoveryStore? store})
      : _store = store ?? ProjectRecoveryStore();

  final ProjectRecoveryStore _store;
  final Map<String, ProjectRecoveryEntry> _entries =
      <String, ProjectRecoveryEntry>{};

  @override
  Future<List<StartScreenRecoveryCandidate>> list() async {
    final entries = await _store.list();
    _entries
      ..clear()
      ..addEntries(entries.map((entry) => MapEntry(entry.jsonPath, entry)));
    return <StartScreenRecoveryCandidate>[
      for (final entry in entries)
        StartScreenRecoveryCandidate(
          id: entry.jsonPath,
          projectName: entry.projectName,
          updatedAt: entry.updatedAt,
        ),
    ];
  }

  @override
  Future<String> readJson(StartScreenRecoveryCandidate candidate) async {
    final entry = await _resolve(candidate);
    return entry.readJson();
  }

  @override
  Future<void> delete(StartScreenRecoveryCandidate candidate) async {
    final entry = await _resolve(candidate);
    await _store.deleteEntry(entry);
    _entries.remove(candidate.id);
  }

  Future<ProjectRecoveryEntry> _resolve(
    StartScreenRecoveryCandidate candidate,
  ) async {
    final cached = _entries[candidate.id];
    if (cached != null) return cached;
    final entries = await _store.list();
    for (final entry in entries) {
      _entries[entry.jsonPath] = entry;
      if (entry.jsonPath == candidate.id) return entry;
    }
    throw StateError('Recovery entry is no longer available.');
  }
}
