// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

/// Start screen and project/template entry flow.
enum _ResidentialTemplateKind {
  default3,
  tower9,
  campus6x9,
  town9,
  modern3,
  glassTower9,
  glassCampus6x9,
  professionalHouse,
}

class ViewerApp extends StatefulWidget {
  const ViewerApp({
    super.key,
    this.source,
    this.startDependencies,
    this.preferEngineBackedBundledSample = false,
  });

  final RenderSceneSource? source;
  final ViewerStartDependencies? startDependencies;
  final bool preferEngineBackedBundledSample;

  @override
  State<ViewerApp> createState() => _ViewerAppState();
}

class _ViewerAppState extends State<ViewerApp> {
  ViewerAppSettings _settings = const ViewerAppSettings.defaults();
  late final ViewerStartDependencies _startDependencies;

  @override
  void initState() {
    super.initState();
    _startDependencies = widget.startDependencies ??
        ViewerStartDependencies.production(
          projectLabel: '${ArvelaBrand.name} projects',
        );
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await ViewerAppSettingsStore.load();
    if (!mounted) return;
    setState(() => _settings = settings);
  }

  void _updateSettings(ViewerAppSettings settings) {
    setState(() => _settings = settings);
    unawaited(ViewerAppSettingsStore.save(settings));
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = viewerThemeFor(_settings.appTheme);
    return MaterialApp(
      title: ArvelaBrand.name,
      debugShowCheckedModeBanner: false,
      theme: viewerAccessibilityTheme(
        baseTheme,
        largeTouchTargets: _settings.largeTouchTargets,
        highContrast: _settings.highContrast,
      ),
      themeMode: ThemeMode.light,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(_settings.textScale),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: widget.source == null
          ? _settings.onboardingComplete
              ? _StartScreenGate(
                  dependencies: _startDependencies,
                  preferEngineBackedBundledSample:
                      widget.preferEngineBackedBundledSample,
                  appTheme: _settings.appTheme,
                  viewportTheme: _settings.viewportTheme,
                  largeTouchTargets: _settings.largeTouchTargets,
                  highContrast: _settings.highContrast,
                  textScale: _settings.textScale,
                  onAppThemeChanged: (theme) => _updateSettings(
                    _settings.copyWith(appTheme: theme),
                  ),
                  onViewportThemeChanged: (theme) => _updateSettings(
                    _settings.copyWith(viewportTheme: theme),
                  ),
                  onLargeTouchTargetsChanged: (value) => _updateSettings(
                    _settings.copyWith(largeTouchTargets: value),
                  ),
                  onHighContrastChanged: (value) => _updateSettings(
                    _settings.copyWith(highContrast: value),
                  ),
                  onTextScaleChanged: (value) => _updateSettings(
                    _settings.copyWith(textScale: value),
                  ),
                )
              : OnboardingPage(
                  onComplete: () => _updateSettings(
                    _settings.copyWith(onboardingComplete: true),
                  ),
                )
          : ViewerHomePage(
              source: widget.source!,
              preferEngineBackedBundledSample:
                  widget.preferEngineBackedBundledSample,
              viewportTheme: _settings.viewportTheme.renderSceneTheme,
            ),
    );
  }
}

class _StartScreenGate extends StatefulWidget {
  const _StartScreenGate({
    required this.dependencies,
    required this.preferEngineBackedBundledSample,
    required this.appTheme,
    required this.viewportTheme,
    required this.largeTouchTargets,
    required this.highContrast,
    required this.textScale,
    required this.onAppThemeChanged,
    required this.onViewportThemeChanged,
    required this.onLargeTouchTargetsChanged,
    required this.onHighContrastChanged,
    required this.onTextScaleChanged,
  });

  final ViewerStartDependencies dependencies;
  final bool preferEngineBackedBundledSample;
  final AppThemeMode appTheme;
  final AppViewportTheme viewportTheme;
  final bool largeTouchTargets;
  final bool highContrast;
  final double textScale;
  final ValueChanged<AppThemeMode> onAppThemeChanged;
  final ValueChanged<AppViewportTheme> onViewportThemeChanged;
  final ValueChanged<bool> onLargeTouchTargetsChanged;
  final ValueChanged<bool> onHighContrastChanged;
  final ValueChanged<double> onTextScaleChanged;

  @override
  State<_StartScreenGate> createState() => _StartScreenGateState();
}

class _StartScreenGateState extends State<_StartScreenGate> {
  late final ProjectLaunchController _launch;
  late final StartScreenRecoveryRepository _recoveryRepository;
  late final ProjectOpenDocumentPicker _projectPicker;
  StartScreenRecoveryCandidate? _recoveryEntry;

  @override
  void initState() {
    super.initState();
    _launch = ProjectLaunchController()..addListener(_handleLaunchChanged);
    _recoveryRepository = widget.dependencies.recovery;
    _projectPicker = widget.dependencies.projectPicker;
    unawaited(_loadRecoveryEntry());
  }

  @override
  void dispose() {
    _launch
      ..removeListener(_handleLaunchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleLaunchChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadRecoveryEntry() async {
    try {
      final entries = await _recoveryRepository.list();
      if (mounted && entries.isNotEmpty) {
        setState(() => _recoveryEntry = entries.first);
      }
    } catch (_) {}
  }

  Future<void> _recoverProject() async {
    final entry = _recoveryEntry;
    if (_launch.state.busy || entry == null) return;
    try {
      final json = await _recoveryRepository.readJson(entry);
      if (!mounted) return;
      _launch.recoverProject(json: json, projectName: entry.projectName);
    } catch (error) {
      if (!mounted) return;
      _launch.fail('Recovery file could not be opened: $error');
    }
  }

  Future<void> _dismissRecovery() async {
    final entry = _recoveryEntry;
    if (entry == null) return;
    await _recoveryRepository.delete(entry);
    if (mounted) setState(() => _recoveryEntry = null);
  }

  Future<void> _openProject() async {
    if (_launch.state.busy) return;
    AppTelemetry.track('project_open_started');
    try {
      final document = await _projectPicker.pick();
      if (document == null || !mounted) return;
      _launch.openProject(
        json: document.json,
        projectName: document.projectName,
        projectPath: document.projectPath,
      );
      AppTelemetry.track('project_opened');
    } catch (error) {
      if (!mounted) return;
      _launch.fail('Could not open the project: $error');
    }
  }

  Future<void> _createProject() async {
    if (_launch.state.busy) return;
    AppTelemetry.track('blank_project_started');
    _launch.createBlankProject();
  }

  Future<void> _createFamily() async {
    if (_launch.state.busy) return;
    AppTelemetry.track('family_create_started');
    await FamilyAuthoringModule.createFamily(context);
  }

  void _selectTemplate(ProjectTemplate template) {
    if (_launch.state.busy) return;
    AppTelemetry.track(
      'template_selected',
      properties: <String, Object?>{'template': template.name},
    );
    _launch.selectTemplate(template);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _launch.finishTemplateSelection();
    });
  }

  @override
  Widget build(BuildContext context) {
    final launch = _launch.state;
    final template = launch.selectedTemplate == null
        ? null
        : WorkspaceTemplate.values.byName(launch.selectedTemplate!.name);
    final json = launch.projectJson;
    if (launch.hasLaunchTarget) {
      final Object gateKey = template ?? json ?? 'blank-project';
      return ViewerHomePage(
        key: ValueKey<Object>(gateKey),
        source: const AssetRenderSceneSource(),
        preferEngineBackedBundledSample: true,
        initialTemplate: template,
        initialBlankProject: launch.createBlank,
        initialProjectJson: json,
        initialProjectName: launch.projectName,
        initialProjectPath: launch.projectPath,
        viewportTheme: widget.viewportTheme.renderSceneTheme,
        onReturnToStart: _returnToStart,
      );
    }
    final recoveryEntry = _recoveryEntry;
    return StartScreen(
      onOpen: _openProject,
      onCreate: _createProject,
      onCreateFamily: () => unawaited(_createFamily()),
      onSelectTemplate: _selectTemplate,
      onSettings: () => _showSettings(context),
      templatePreferencesRepository: widget.dependencies.templatePreferences,
      recoveryEntry: recoveryEntry == null
          ? null
          : ProjectRecoverySummary(projectName: recoveryEntry.projectName),
      onRecover: _recoverProject,
      onDismissRecovery: () => unawaited(_dismissRecovery()),
      busy: launch.busy,
      errorMessage: launch.errorMessage,
    );
  }

  Future<void> _showSettings(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => ViewerSettingsDialog(
        appTheme: widget.appTheme,
        viewportTheme: widget.viewportTheme,
        largeTouchTargets: widget.largeTouchTargets,
        highContrast: widget.highContrast,
        textScale: widget.textScale,
        onAppThemeChanged: widget.onAppThemeChanged,
        onViewportThemeChanged: widget.onViewportThemeChanged,
        onLargeTouchTargetsChanged: widget.onLargeTouchTargetsChanged,
        onHighContrastChanged: widget.onHighContrastChanged,
        onTextScaleChanged: widget.onTextScaleChanged,
      ),
    );
  }

  Future<void> _returnToStart() async {
    if (_launch.state.busy) return;
    _launch.returnToStart();
  }
}

class ViewerHomePage extends StatefulWidget {
  const ViewerHomePage({
    super.key,
    required this.source,
    this.dependencies,
    this.preferEngineBackedBundledSample = false,
    this.initialTemplate,
    this.initialIfcPath,
    this.initialProjectJson,
    this.initialProjectName,
    this.initialProjectPath,
    this.initialBlankProject = false,
    this.viewportTheme = RenderSceneViewportTheme.light,
    this.onReturnToStart,
  });

  final RenderSceneSource source;
  final ViewerAppDependencies? dependencies;
  final bool preferEngineBackedBundledSample;
  final WorkspaceTemplate? initialTemplate;
  final String? initialIfcPath;
  final String? initialProjectJson;
  final String? initialProjectName;
  final String? initialProjectPath;
  final bool initialBlankProject;
  final RenderSceneViewportTheme viewportTheme;
  final Future<void> Function()? onReturnToStart;

  @override
  State<ViewerHomePage> createState() => _ViewerHomePageState();
}
