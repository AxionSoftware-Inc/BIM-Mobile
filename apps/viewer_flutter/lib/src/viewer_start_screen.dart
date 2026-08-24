// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

/// Start screen and project/template entry flow.
enum _ResidentialTemplateKind {
  default3,
  tower9,
  campus6x9,
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
    return MaterialApp(
      title: 'Tablet BIM',
      debugShowCheckedModeBanner: false,
      theme: viewerThemeFor(_settings.appTheme),
      themeMode: ThemeMode.light,
      home: widget.source == null
          ? _StartScreenGate(
              preferEngineBackedBundledSample:
                  widget.preferEngineBackedBundledSample,
              appTheme: _settings.appTheme,
              viewportTheme: _settings.viewportTheme,
              onAppThemeChanged: (theme) => _updateSettings(
                _settings.copyWith(appTheme: theme),
              ),
              onViewportThemeChanged: (theme) => _updateSettings(
                _settings.copyWith(viewportTheme: theme),
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
    required this.onAppThemeChanged,
    required this.onViewportThemeChanged,
  });

  final bool preferEngineBackedBundledSample;
  final AppThemeMode appTheme;
  final RenderSceneViewportTheme viewportTheme;
  final ValueChanged<AppThemeMode> onAppThemeChanged;
  final ValueChanged<RenderSceneViewportTheme> onViewportThemeChanged;

  @override
  State<_StartScreenGate> createState() => _StartScreenGateState();
}

class _StartScreenGateState extends State<_StartScreenGate> {
  WorkspaceTemplate? _selectedTemplate;
  String? _projectJson;
  String? _projectName;
  String? _projectPath;
  String? _errorMessage;
  bool _createBlank = false;
  bool _busy = false;

  Future<void> _openProject() async {
    if (_busy) return;
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
        _projectJson = json;
        _projectName = file.name;
        _projectPath = file.path;
        _selectedTemplate = null;
        _createBlank = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Projectni ochib bo‘lmadi: $error');
    }
  }

  Future<void> _createProject() async {
    if (_busy) return;
    setState(() {
      _errorMessage = null;
      _selectedTemplate = null;
      _projectJson = null;
      _projectName = null;
      _projectPath = null;
      _createBlank = true;
    });
  }

  void _selectTemplate(WorkspaceTemplate template) {
    if (_busy) return;
    setState(() {
      _errorMessage = null;
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

  @override
  Widget build(BuildContext context) {
    final template = _selectedTemplate;
    final json = _projectJson;
    if (template != null || json != null || _createBlank) {
      final Object gateKey = template ?? json ?? 'blank-project';
      return ViewerHomePage(
        key: ValueKey<Object>(gateKey),
        source: const AssetRenderSceneSource(),
        preferEngineBackedBundledSample: true,
        initialTemplate: template,
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
      onSettings: () => _showSettings(context),
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
        onAppThemeChanged: widget.onAppThemeChanged,
        onViewportThemeChanged: widget.onViewportThemeChanged,
      ),
    );
  }

  Future<void> _returnToStart() async {
    if (_busy) return;
    setState(() {
      _selectedTemplate = null;
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
  final String? initialProjectJson;
  final String? initialProjectName;
  final String? initialProjectPath;
  final bool initialBlankProject;
  final RenderSceneViewportTheme viewportTheme;
  final Future<void> Function()? onReturnToStart;

  @override
  State<ViewerHomePage> createState() => _ViewerHomePageState();
}
