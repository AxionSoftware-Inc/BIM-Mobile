import '../../../../core/application/signals/application_notifier.dart';
import 'start_screen_models.dart';

/// Framework-neutral state for the start-screen project launch flow.
///
/// File picking, recovery storage and Flutter navigation remain outside this
/// controller. The controller owns only the semantic launch selection so the
/// shell cannot maintain competing template/project/blank flags.
final class ProjectLaunchController extends ApplicationChangeNotifier {
  ProjectLaunchState _state = const ProjectLaunchState();

  ProjectLaunchState get state => _state;

  void openProject({
    required String json,
    required String projectName,
    String? projectPath,
  }) {
    _setState(
      ProjectLaunchState(
        projectJson: json,
        projectName: projectName,
        projectPath: projectPath,
      ),
    );
  }

  void recoverProject({
    required String json,
    required String projectName,
  }) {
    openProject(json: json, projectName: projectName);
  }

  void createBlankProject() {
    _setState(const ProjectLaunchState(createBlank: true));
  }

  void selectTemplate(ProjectTemplate template) {
    _setState(ProjectLaunchState(selectedTemplate: template, busy: true));
  }

  void finishTemplateSelection() {
    if (!_state.busy) return;
    _setState(_state.copyWith(busy: false));
  }

  void fail(String message) {
    _setState(_state.copyWith(errorMessage: message, busy: false));
  }

  void clearError() {
    if (_state.errorMessage == null) return;
    _setState(_state.copyWith(clearError: true));
  }

  void returnToStart() {
    _setState(const ProjectLaunchState());
  }

  void _setState(ProjectLaunchState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }
}

final class ProjectLaunchState {
  const ProjectLaunchState({
    this.selectedTemplate,
    this.projectJson,
    this.projectName,
    this.projectPath,
    this.createBlank = false,
    this.busy = false,
    this.errorMessage,
  });

  final ProjectTemplate? selectedTemplate;
  final String? projectJson;
  final String? projectName;
  final String? projectPath;
  final bool createBlank;
  final bool busy;
  final String? errorMessage;

  bool get hasLaunchTarget =>
      selectedTemplate != null || projectJson != null || createBlank;

  ProjectLaunchState copyWith({
    ProjectTemplate? selectedTemplate,
    String? projectJson,
    String? projectName,
    String? projectPath,
    bool? createBlank,
    bool? busy,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProjectLaunchState(
      selectedTemplate: selectedTemplate ?? this.selectedTemplate,
      projectJson: projectJson ?? this.projectJson,
      projectName: projectName ?? this.projectName,
      projectPath: projectPath ?? this.projectPath,
      createBlank: createBlank ?? this.createBlank,
      busy: busy ?? this.busy,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectLaunchState &&
          other.selectedTemplate == selectedTemplate &&
          other.projectJson == projectJson &&
          other.projectName == projectName &&
          other.projectPath == projectPath &&
          other.createBlank == createBlank &&
          other.busy == busy &&
          other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(
        selectedTemplate,
        projectJson,
        projectName,
        projectPath,
        createBlank,
        busy,
        errorMessage,
      );
}
