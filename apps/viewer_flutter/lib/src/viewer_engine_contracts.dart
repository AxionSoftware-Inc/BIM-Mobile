/// Stable Dart-side contract shared by feature/application code and the
/// native engine bridge. These types intentionally contain no FFI pointers or
/// platform-loading concerns.
final class TbeApiException implements Exception {
  TbeApiException(this.message);

  final String message;

  @override
  String toString() => 'TbeApiException: $message';
}

final class ViewerSnapshot {
  ViewerSnapshot({
    required this.projectName,
    required this.engineVersion,
    required this.apiVersion,
    required this.schemaVersion,
    required this.levelId,
    required this.validation,
    required this.schedule,
    required this.svgPath,
    required this.packagePath,
    required this.validationMessages,
  });

  final String projectName;
  final String engineVersion;
  final String apiVersion;
  final int schemaVersion;
  final int levelId;
  final ValidationSummary validation;
  final ScheduleSummary schedule;
  final String svgPath;
  final String packagePath;
  final List<String> validationMessages;
}

final class ScheduleSummary {
  ScheduleSummary({
    required this.wallRows,
    required this.openingRows,
    required this.roomRows,
    required this.slabRows,
    required this.roofRows,
    required this.columnRows,
    required this.beamRows,
    required this.stairRows,
    required this.floorRows,
    required this.ceilingRows,
    required this.materialTakeoffRows,
  });

  final int wallRows;
  final int openingRows;
  final int roomRows;
  final int slabRows;
  final int roofRows;
  final int columnRows;
  final int beamRows;
  final int stairRows;
  final int floorRows;
  final int ceilingRows;
  final int materialTakeoffRows;
}

final class ValidationSummary {
  ValidationSummary({
    required this.issueCount,
    required this.warningCount,
    required this.errorCount,
  });

  final int issueCount;
  final int warningCount;
  final int errorCount;
}

final class HitCandidateView {
  HitCandidateView({
    required this.elementId,
    required this.elementKind,
    required this.hitKind,
    required this.distanceMeters,
    required this.priority,
  });

  final int elementId;
  final int elementKind;
  final int hitKind;
  final double distanceMeters;
  final int priority;
}

final class ViewerLoadResult {
  ViewerLoadResult({
    required this.snapshot,
    required this.hitCandidates,
  });

  final ViewerSnapshot snapshot;
  final List<HitCandidateView> hitCandidates;
}
