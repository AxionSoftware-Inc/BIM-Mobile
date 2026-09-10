/// Semantic project templates exposed by the application start flow.
enum ProjectTemplate {
  default3,
  tower9,
  campus6x9,
  town9,
  modern3,
  glassTower9,
  glassCampus6x9,
  professionalHouse,
}

/// Presentation-safe recovery metadata.
///
/// Reading/deleting recovery files remains an infrastructure responsibility;
/// the start screen only needs a project label plus callbacks supplied by
/// composition.
final class ProjectRecoverySummary {
  const ProjectRecoverySummary({required this.projectName});

  final String projectName;
}
