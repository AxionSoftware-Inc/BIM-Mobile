// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

/// Start screen and project/template entry flow.
enum _ResidentialTemplateKind {
  default3,
  tower9,
  campus6x9,
  modern3,
  glassTower9,
  glassCampus6x9,
}

class ViewerApp extends StatefulWidget {
  const ViewerApp({
    super.key,
    this.source,
    this.preferEngineBackedBundledSample = false,
  });

  final RenderSceneSource? source;
  final bool preferEngineBackedBundledSample;

  @override
  State<ViewerApp> createState() => _ViewerAppState();
}

class _ViewerAppState extends State<ViewerApp> {
  ViewerAppSettings _settings = const ViewerAppSettings.defaults();

  @override
  void initState() {
    super.initState();
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
      title: 'Tablet BIM',
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
              viewportTheme: _settings.viewportTheme,
            ),
    );
  }
}

class _StartScreenGate extends StatefulWidget {
  const _StartScreenGate({
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

  final bool preferEngineBackedBundledSample;
  final AppThemeMode appTheme;
  final RenderSceneViewportTheme viewportTheme;
  final bool largeTouchTargets;
  final bool highContrast;
  final double textScale;
  final ValueChanged<AppThemeMode> onAppThemeChanged;
  final ValueChanged<RenderSceneViewportTheme> onViewportThemeChanged;
  final ValueChanged<bool> onLargeTouchTargetsChanged;
  final ValueChanged<bool> onHighContrastChanged;
  final ValueChanged<double> onTextScaleChanged;

  @override
  State<_StartScreenGate> createState() => _StartScreenGateState();
}

class _StartScreenGateState extends State<_StartScreenGate> {
  WorkspaceTemplate? _selectedTemplate;
  String? _ifcPath;
  String? _projectJson;
  String? _projectName;
  String? _projectPath;
  String? _errorMessage;
  bool _createBlank = false;
  bool _busy = false;
  ProjectRecoveryEntry? _recoveryEntry;
  final ProjectRecoveryStore _recoveryStore = ProjectRecoveryStore();
  final IfcTemplateDownloader _ifcDownloader = IfcTemplateDownloader();

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecoveryEntry());
  }

  Future<void> _loadRecoveryEntry() async {
    try {
      final entries = await _recoveryStore.list();
      if (mounted && entries.isNotEmpty) {
        setState(() => _recoveryEntry = entries.first);
      }
    } catch (_) {}
  }

  Future<void> _recoverProject() async {
    final entry = _recoveryEntry;
    if (_busy || entry == null) return;
    try {
      final json = await entry.readJson();
      if (!mounted) return;
      setState(() {
        _projectJson = json;
        _projectName = entry.projectName;
        _projectPath = null;
        _selectedTemplate = null;
        _createBlank = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(
          () => _errorMessage = 'Recovery file could not be opened: $error');
    }
  }

  Future<void> _dismissRecovery() async {
    final entry = _recoveryEntry;
    if (entry == null) return;
    await _recoveryStore.deleteEntry(entry);
    if (mounted) setState(() => _recoveryEntry = null);
  }

  Future<void> _openProject() async {
    if (_busy) return;
    AppTelemetry.track('project_open_started');
    try {
      const typeGroup = XTypeGroup(
        label: 'BIM projects',
        extensions: <String>['json', 'tbe.json'],
      );
      final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
      if (file == null) return;
      final json = await file.readAsString();
      if (!mounted) return;
      setState(() {
        _errorMessage = null;
        _ifcPath = null;
        _projectJson = json;
        _projectName = file.name;
        _projectPath = file.path;
        _selectedTemplate = null;
        _createBlank = false;
      });
      AppTelemetry.track('project_opened');
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Could not open the project: $error');
    }
  }

  Future<void> _createProject() async {
    if (_busy) return;
    AppTelemetry.track('blank_project_started');
    setState(() {
      _errorMessage = null;
      _ifcPath = null;
      _selectedTemplate = null;
      _projectJson = null;
      _projectName = null;
      _projectPath = null;
      _createBlank = true;
    });
  }

  void _selectTemplate(WorkspaceTemplate template) {
    if (_busy) return;
    AppTelemetry.track(
      'template_selected',
      properties: <String, Object?>{'template': template.name},
    );
    setState(() {
      _errorMessage = null;
      _ifcPath = null;
      _selectedTemplate = template;
      _projectJson = null;
      _projectName = null;
      _projectPath = null;
      _busy = true;
    });
    // Keep the loading state visible for the transition, then let the
    // workspace perform the authoritative native template creation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _busy = false);
    });
  }

  Future<void> _selectIfcTemplate(IfcTemplate template) async {
    if (_busy) return;
    AppTelemetry.track(
      'ifc_template_selected',
      properties: <String, Object?>{'template': template.id},
    );
    setState(() {
      _errorMessage = null;
      _busy = true;
    });
    try {
      final path = await _ifcDownloader.download(template);
      if (!mounted) return;
      setState(() {
        _ifcPath = path;
        _selectedTemplate = null;
        _projectJson = null;
        _projectName = template.title;
        _projectPath = path;
        _createBlank = false;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Could not download ${template.title}: $error';
      });
    }
  }

  @override
  void dispose() {
    _ifcDownloader.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final template = _selectedTemplate;
    final ifcPath = _ifcPath;
    final json = _projectJson;
    if (template != null || ifcPath != null || json != null || _createBlank) {
      final Object gateKey = template ?? ifcPath ?? json ?? 'blank-project';
      return ViewerHomePage(
        key: ValueKey<Object>(gateKey),
        source: const AssetRenderSceneSource(),
        preferEngineBackedBundledSample: true,
        initialTemplate: template,
        initialIfcPath: ifcPath,
        initialBlankProject: _createBlank,
        initialProjectJson: json,
        initialProjectName: _projectName,
        initialProjectPath: _projectPath,
        viewportTheme: widget.viewportTheme,
        onReturnToStart: _returnToStart,
      );
    }
    return StartScreen(
      onOpen: _openProject,
      onCreate: _createProject,
      onSelectTemplate: _selectTemplate,
      onSelectIfcTemplate: _selectIfcTemplate,
      onSettings: () => _showSettings(context),
      recoveryEntry: _recoveryEntry,
      onRecover: _recoverProject,
      onDismissRecovery: () => unawaited(_dismissRecovery()),
      busy: _busy,
      errorMessage: _errorMessage,
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
    if (_busy) return;
    setState(() {
      _selectedTemplate = null;
      _ifcPath = null;
      _projectJson = null;
      _projectName = null;
      _projectPath = null;
      _errorMessage = null;
      _createBlank = false;
    });
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
