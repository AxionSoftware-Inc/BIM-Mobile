/// Application boundary for workspace crash-recovery checkpoints.
///
/// Presentation decides *when* a checkpoint is needed. Infrastructure owns
/// durable paths, manifests, retention and atomic file writes.
abstract interface class ProjectRecoveryCheckpointRepository {
  Future<void> writeCheckpoint({
    required String projectName,
    required String json,
  });

  Future<void> deleteForProject(String projectName);
}
