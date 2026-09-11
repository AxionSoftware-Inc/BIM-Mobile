import '../../application/recovery/project_recovery_checkpoint_repository.dart';
import '../project_recovery_store.dart';

/// File-backed workspace recovery adapter.
///
/// The durable generation/manifest logic stays in [ProjectRecoveryStore]; this
/// adapter exposes only the semantic checkpoint operations required by the
/// workspace application boundary.
final class FileProjectRecoveryCheckpointRepository
    implements ProjectRecoveryCheckpointRepository {
  FileProjectRecoveryCheckpointRepository({ProjectRecoveryStore? store})
      : _store = store ?? ProjectRecoveryStore();

  final ProjectRecoveryStore _store;

  @override
  Future<void> writeCheckpoint({
    required String projectName,
    required String json,
  }) async {
    await _store.write(projectName: projectName, json: json);
  }

  @override
  Future<void> deleteForProject(String projectName) =>
      _store.deleteForProject(projectName);
}
