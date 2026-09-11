/// Opaque recovery candidate exposed to the application start flow.
final class StartScreenRecoveryCandidate {
  const StartScreenRecoveryCandidate({
    required this.id,
    required this.projectName,
    required this.updatedAt,
  });

  final String id;
  final String projectName;
  final DateTime updatedAt;
}

/// Recovery operations required by the start flow.
///
/// Concrete file paths, metadata manifests and retention rules remain in the
/// projects infrastructure layer.
abstract interface class StartScreenRecoveryRepository {
  Future<List<StartScreenRecoveryCandidate>> list();

  Future<String> readJson(StartScreenRecoveryCandidate candidate);

  Future<void> delete(StartScreenRecoveryCandidate candidate);
}
