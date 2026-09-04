// Legacy dialog widgets are kept temporarily for the level-line quick edit
// path.  The production Inspector is `PropertyEditor` + its controllers.
// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'authoring_command_service.dart';
import 'app_project_storage.dart';
import 'app_settings.dart';
import 'atomic_file_writer.dart';
import 'onboarding_page.dart';
import 'telemetry_service.dart';
import 'documentation/document_models.dart';
import 'documentation/documentation_workspace.dart';
import 'documentation/sheet_canvas.dart';
import 'documentation/sheet_workspace_controller.dart';
import 'family_authoring/family_authoring_module.dart';
import 'family_instance_adapter.dart';
import 'elements/bim_element_registry.dart';
import 'elements/floor_type_catalog.dart';
import 'elements/opening_parameters.dart';
import 'elements/opening_type_catalog.dart';
import 'elements/wall_parameters.dart';
import 'elements/wall_type_catalog.dart';
import 'inspector_controller.dart';
import 'ifc_template_catalog.dart';
import 'property_editor.dart';
import 'project_lifecycle_service.dart';
import 'project_persistence_service.dart';
import 'project_recovery_store.dart';
import 'project_unit_settings.dart';
import 'project_session_controller.dart';
import 'project_browser_panel.dart';
import 'render_scene_editor.dart';
import 'render_scene_estimator.dart';
import 'render_scene_models.dart';
import 'render_scene_repository.dart';
import 'scene_mutation_service.dart';
import 'scene_view_service.dart';
import 'selection_controller.dart';
import 'start_screen.dart';
import 'tools/level_tool_controller.dart';
import 'tools/opening_authoring_geometry.dart';
import 'tools/opening_tool_controller.dart';
import 'tools/plan_sketch_geometry.dart';
import 'tools/stair_authoring_geometry.dart';
import 'tools/surface_authoring_geometry.dart';
import 'tools/surface_tool_controller.dart';
import 'tools/stair_tool_controller.dart';
import 'tools/trim_extend_tool_controller.dart';
import 'tools/wall_tool_controller.dart';
import 'tools/wall_authoring_geometry.dart';
import 'tools/wall_repair_geometry.dart';
import 'view_tabs.dart';
import 'view_navigation_coordinator.dart';
import 'view_navigation_policy.dart';
import 'view_workspace_store.dart';
import 'viewer_app_dependencies.dart';
import 'viewer_bim_cache_gateway.dart';
import 'viewer_project_session.dart';
import 'workspace_chrome.dart';
import 'render_scene_viewport.dart';
import 'render_scene_viewport_planar.dart';
import 'async_serial_queue.dart';
import 'viewer_viewport_scene_policy.dart';

part 'viewer_viewport_input.dart';
part 'viewer_viewport_stair_editing.dart';
part 'viewer_form_widgets.dart';
part 'viewer_viewport_wall_editing.dart';
part 'viewer_viewport_surface_editing.dart';
part 'viewer_inspector_draft_widgets.dart';
part 'viewer_inspector_estimate_widgets.dart';
part 'viewer_inspector_info_widgets.dart';
part 'viewer_workspace_ui_layout.dart';
part 'viewer_workspace_ui_interactions.dart';
part 'viewer_start_screen.dart';
part 'viewer_project_lifecycle.dart';
part 'viewer_view_state.dart';
part 'viewer_view_commands.dart';
part 'viewer_authoring_state.dart';

class _ViewerHomePageState extends State<ViewerHomePage>
    with WidgetsBindingObserver {
  static const double _defaultWallThicknessMeters =
      RenderSceneEditor.defaultWallThicknessMeters;
  static const double _defaultWallHeightMeters =
      RenderSceneEditor.defaultWallHeightMeters;
  static final List<String> _coreKindOrder =
      BimElementRegistry.standard.coreKindOrder;

  final RenderSceneViewportController _viewportController =
      RenderSceneViewportController();
  final WallToolController _wallTool = WallToolController();
  final LevelToolController _levelTool = LevelToolController();
  final OpeningToolController _openingTool = OpeningToolController();
  final SurfaceToolController _surfaceTool = SurfaceToolController();
  final StairToolController _stairTool = StairToolController();
  final TrimExtendToolController _trimTool = TrimExtendToolController();
  late final SelectionController _selectionController;
  late final InspectorController _inspectorController;
  late final AuthoringCommandService _authoringCommands;
  late final ViewerAppDependencies _dependencies;
  late final ProjectLifecycleService<ViewerEngineSession> _projectLifecycle;
  late final ProjectPersistenceService _projectPersistence;
  late final ProjectSessionController<ViewerEngineSession> _projectSession;
  late final SceneViewService _sceneViews;
  late final SheetWorkspaceController _sheetWorkspace;

  ViewerEngineSession? get _engineRepository => _projectSession.session;
  bool get _engineBackedMode => _projectSession.isEngineBacked;

  RenderScene? _scene;
  ProjectUnitSettings _projectUnitSettings =
      const ProjectUnitSettings.defaults();
  String? _statusMessage;
  String? _loadError;
  bool _isBusy = false;
  int _sceneLoadGeneration = 0;
  // Monotonic presentation token for the authoritative document snapshot.
  // Deferred reads must never be allowed to commit after an edit, undo or
  // reload has advanced this token.
  int _sceneDataRevision = 0;
  bool _isViewNavigationBusy = false;
  bool _projectHasChanges = false;
  bool _canUndo = false;
  bool _canRedo = false;
  String _currentProjectName = 'Tablet BIM Project';
  final ProjectRecoveryStore _recoveryStore = ProjectRecoveryStore();
  Timer? _recoveryAutosaveTimer;
  bool _recoveryWriteInFlight = false;
  bool _showSidePanel = true;
  WorkspaceSidePanelTab _sidePanelTab = WorkspaceSidePanelTab.projectBrowser;
  bool _showDiagnostics = false;
  String? _engineLoadDiagnostic;
  // Camera deltas are emitted for every gesture sample. Keep the workspace
  // rebuild reserved for semantic viewport changes such as selection and
  // level highlighting; pan/zoom is painted by the viewport itself.
  String? _lastViewportUiSignature;
  int? _activeLevelId;
  RenderSceneSection? _activeSectionView;
  final ViewWorkspaceStore _viewWorkspace = ViewWorkspaceStore.standard();
  final ViewNavigationCoordinator _viewNavigation = ViewNavigationCoordinator();
  // Every authoritative mutation uses this lane before presenting a scene in
  // the viewport. Domain mutations stay independent; presentation ordering is
  // centralized here so a late door/wall result cannot overwrite a newer one.
  final AsyncSerialQueue _sceneCommitQueue = AsyncSerialQueue();

  List<OpenedViewTab> get _openedViewTabs => _viewWorkspace.tabs;
  String? get _activeViewTabId => _viewWorkspace.activeTabId;
  set _activeViewTabId(String? value) => _viewWorkspace.setActiveTab(value);
  Map<String, OpenedViewTab> get _viewPresentationById =>
      _viewWorkspace.savedPresentations;
  Map<String, RenderScene> get _sheetViewScenes => _viewWorkspace.sheetScenes;
  RenderScene? get _sheetSourceScene => _viewWorkspace.sheetSourceScene;
  set _sheetSourceScene(RenderScene? value) =>
      _viewWorkspace.cacheSheetSource(value);
  bool get _workspaceBusy => _isBusy || _isViewNavigationBusy;
  double _planViewRangeMeters = 2.0;

  RenderSceneProjectionMode _projectionMode = kDefaultPlanProjectionMode;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.perspective;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;
  RenderSceneInteractionMode _interactionMode =
      RenderSceneInteractionMode.select;
  RenderScenePoint? _draftWallStart;
  RenderScenePoint? _draftWallEnd;
  RenderSceneObject? _draftMoveTarget;
  RenderScenePoint? _moveAnchorPoint;
  RenderScenePoint? _moveWallOriginalStart;
  RenderScenePoint? _moveWallOriginalEnd;
  int? _draftMoveLevelId;
  double? _moveLevelOriginalElevation;
  WallMoveMode _wallMoveMode = WallMoveMode.translate;
  String? _editStatusMessage;
  final bool _snapDraftToGrid = true;
  bool _surfaceBoundaryMultiTouch = false;
  // A hosted opening belongs to the wall touched at gesture start.  Keeping
  // this separate from the hover preview prevents a release hit-test on a
  // neighbouring/overlapping wall from changing the host or mirroring the
  // wall-local offset just before commit.
  bool _openingGestureActive = false;
  final List<String> _androidMutationTrace = <String>[];
  // Wall gestures can arrive before the previous engine mutation has
  // finished. Keep the commits ordered instead of dropping the next segment.
  Future<void> _wallCommitTail = Future<void>.value();
  RenderScene? _wallSnapIndexScene;
  WallSnapIndex? _wallSnapIndex;
  int? _wallSnapIndexLevelId;
  int? _wallSnapIndexExcludeWallId;

  RenderSceneObject? get _draftHostWall => _openingTool.hostWall;
  set _draftHostWall(RenderSceneObject? value) =>
      _openingTool.setHostWall(value);
  double get _draftOpeningOffsetMeters => _openingTool.offsetMeters;
  set _draftOpeningOffsetMeters(double value) => _openingTool.setOffset(value);
  double get _draftOpeningWidthMeters => _openingTool.widthMeters;
  set _draftOpeningWidthMeters(double value) => _openingTool.setWidth(value);
  double get _draftOpeningHeightMeters => _openingTool.heightMeters;
  set _draftOpeningHeightMeters(double value) => _openingTool.setHeight(value);
  double get _draftOpeningSillHeightMeters => _openingTool.sillHeightMeters;
  set _draftOpeningSillHeightMeters(double value) =>
      _openingTool.setSillHeight(value);

  RenderScenePoint? get _draftSurfaceStart => _surfaceTool.start;
  set _draftSurfaceStart(RenderScenePoint? value) => _surfaceTool.start = value;
  RenderScenePoint? get _draftSurfaceEnd => _surfaceTool.end;
  set _draftSurfaceEnd(RenderScenePoint? value) => _surfaceTool.end = value;
  List<RenderScenePoint> get _draftSurfacePoints => _surfaceTool.points;
  Set<int> get _draftSurfaceWallIds => _surfaceTool.wallIds;
  RenderSceneSurfaceDrawMode get _surfaceDrawMode => _surfaceTool.drawMode;
  set _surfaceDrawMode(RenderSceneSurfaceDrawMode value) =>
      _surfaceTool.drawMode = value;
  double get _draftSurfaceThicknessMeters => _surfaceTool.thicknessMeters;
  set _draftSurfaceThicknessMeters(double value) =>
      _surfaceTool.thicknessMeters = value;
  double get _draftSurfaceHeightMeters => _surfaceTool.heightMeters;
  set _draftSurfaceHeightMeters(double value) =>
      _surfaceTool.heightMeters = value;
  double get _draftFloorTopElevationMeters => _surfaceTool.floorTopMeters;
  set _draftFloorTopElevationMeters(double value) =>
      _surfaceTool.floorTopMeters = value;
  double get _draftCeilingHeightOffsetMeters =>
      _surfaceTool.ceilingOffsetMeters;
  set _draftCeilingHeightOffsetMeters(double value) =>
      _surfaceTool.ceilingOffsetMeters = value;

  bool get _isSurfaceAuthoring =>
      _interactionMode == RenderSceneInteractionMode.addFloor ||
      _interactionMode == RenderSceneInteractionMode.addCeiling ||
      _interactionMode == RenderSceneInteractionMode.addRoof;

  Set<String> get _authoringPickKinds => switch (_interactionMode) {
        RenderSceneInteractionMode.addDoor ||
        RenderSceneInteractionMode.addWindow ||
        RenderSceneInteractionMode.trimExtend =>
          const <String>{'wall'},
        RenderSceneInteractionMode.addFloor ||
        RenderSceneInteractionMode.addCeiling ||
        RenderSceneInteractionMode.addRoof =>
          switch (_surfaceDrawMode) {
            RenderSceneSurfaceDrawMode.pickWalls => const <String>{'wall'},
            // Room previews are generated client-side and are not guaranteed
            // to exist in the native pick index. Keep the plan point available
            // so Auto Room can resolve the enclosure under the user's finger.
            RenderSceneSurfaceDrawMode.autoRoom => const <String>{},
            _ => const <String>{},
          },
        _ => const <String>{},
      };

  RenderSceneObject? _resolvePlanPick(
    RenderScenePoint point,
    Set<String> allowedKinds,
    double toleranceMeters,
  ) {
    final repository = _engineRepository;
    final scene = _scene;
    if (!_engineBackedMode || repository == null || scene == null) return null;
    try {
      // Plan symbols extend beyond the small opening mesh. Resolve them
      // before the native wall-body candidate so tapping a door swing or
      // window glazing line selects the hosted opening itself.
      if (allowedKinds.isEmpty) {
        final opening = RenderSceneQueries.openingAtPlanPoint(
          scene,
          point,
          toleranceMeters: toleranceMeters,
        );
        if (opening != null) return opening;
      }
      final candidates = repository.hitTest(
        point.x,
        point.y,
        toleranceMeters: toleranceMeters,
      );
      for (final candidate in candidates) {
        final object = scene.objectById(candidate.elementId);
        if (object == null) continue;
        if (_visibleKinds.isNotEmpty &&
            !_visibleKinds.contains(object.kindKey)) {
          continue;
        }
        if (allowedKinds.isNotEmpty && !allowedKinds.contains(object.kindKey)) {
          continue;
        }
        return object;
      }
    } catch (_) {
      // The mesh picker remains a safe fallback while a project is loading or
      // when a legacy engine does not expose the spatial query.
    }
    return null;
  }

  RenderSceneObject? _findWallNearPlanPoint(
    RenderScene scene,
    RenderScenePoint point, {
    double toleranceMeters = 0.45,
  }) {
    RenderSceneObject? best;
    var bestDistance = double.infinity;
    for (final wall in scene.objects) {
      if (wall.kindKey != 'wall' ||
          (_activeLevelId != null && wall.levelId != _activeLevelId)) {
        continue;
      }
      final start = RenderSceneEditor.wallStartPoint(wall);
      final end = RenderSceneEditor.wallEndPoint(wall);
      if (start == null || end == null) continue;
      final axis = end - start;
      final lengthSquared = axis.x * axis.x + axis.y * axis.y;
      if (lengthSquared <= 1e-9) continue;
      final rawT =
          ((point.x - start.x) * axis.x + (point.y - start.y) * axis.y) /
              lengthSquared;
      final t = rawT.clamp(0.0, 1.0);
      final projected = RenderScenePoint(
        x: start.x + axis.x * t,
        y: start.y + axis.y * t,
        z: point.z,
      );
      final dx = projected.x - point.x;
      final dy = projected.y - point.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      final wallTolerance = math.max(
        toleranceMeters,
        (RenderSceneEditor.wallThickness(wall) ?? 0.30) * 0.5 + 0.12,
      );
      if (distance <= wallTolerance && distance < bestDistance) {
        best = wall;
        bestDistance = distance;
      }
    }
    return best;
  }

  void _traceAndroidMutation(String message) {
    if (!kDebugMode) return;
    final timestamp = DateTime.now().toIso8601String().split('T').last;
    setState(() {
      _androidMutationTrace.insert(0, '$timestamp  $message');
      if (_androidMutationTrace.length > 8) {
        _androidMutationTrace.removeRange(8, _androidMutationTrace.length);
      }
    });
  }

  /// Empty means “show all” in RenderSceneViewportController.
  Set<String> _visibleKinds = <String>{};
  bool _usesProjectionDefaultVisibility = true;
  bool _usesProjectionDefaultDisplayStyle = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentProjectName = widget.initialProjectName ?? _currentProjectName;
    unawaited(_viewportController.setViewportTheme(widget.viewportTheme));
    _selectionController = SelectionController(_viewportController);
    _selectionController.addListener(_onSelectionChangedForWorkspace);
    _inspectorController = InspectorController(_selectionController);
    _authoringCommands = AuthoringCommandService(
      repository: () => _engineRepository,
      creationGateway: () => _engineRepository,
      engineEnabled: () => _engineBackedMode,
    );
    _dependencies = widget.dependencies ?? ViewerAppDependencies.production();
    _projectSession = _dependencies.projectSession;
    _projectLifecycle = _dependencies.projectLifecycle;
    _projectPersistence = ProjectPersistenceService(
      repository: () => _engineRepository,
      engineEnabled: () => _engineBackedMode,
    );
    _sceneViews = SceneViewService(
      repository: () => _engineRepository,
      engineEnabled: () => _engineBackedMode,
    );
    _sheetWorkspace = SheetWorkspaceController();
    _sheetWorkspace.addListener(_onSheetWorkspaceChanged);
    _viewportController.addListener(_onViewportChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final initialTemplate = widget.initialTemplate;
      final initialIfcPath = widget.initialIfcPath;
      final initialProjectJson = widget.initialProjectJson;
      if (widget.initialBlankProject) {
        _createBlankProject();
      } else if (initialTemplate != null) {
        _createResidentialTemplate(_residentialTemplateKind(initialTemplate));
      } else if (initialIfcPath != null) {
        unawaited(() async {
          await _loadIfcPath(
            initialIfcPath,
            projectName: widget.initialProjectName ?? 'IFC sample project',
          );
        }());
      } else if (initialProjectJson != null) {
        _loadProjectJson(
          initialProjectJson,
          projectName: widget.initialProjectName ?? 'Opened project',
          sourcePath: widget.initialProjectPath,
        );
      } else {
        _loadBundledSample();
      }
    });
  }

  _ResidentialTemplateKind _residentialTemplateKind(
    WorkspaceTemplate template,
  ) {
    switch (template) {
      case WorkspaceTemplate.default3:
        return _ResidentialTemplateKind.default3;
      case WorkspaceTemplate.tower9:
        return _ResidentialTemplateKind.tower9;
      case WorkspaceTemplate.campus6x9:
        return _ResidentialTemplateKind.campus6x9;
      case WorkspaceTemplate.modern3:
        return _ResidentialTemplateKind.modern3;
      case WorkspaceTemplate.glassTower9:
        return _ResidentialTemplateKind.glassTower9;
      case WorkspaceTemplate.glassCampus6x9:
        return _ResidentialTemplateKind.glassCampus6x9;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recoveryAutosaveTimer?.cancel();
    _sheetWorkspace.removeListener(_onSheetWorkspaceChanged);
    _sheetWorkspace.dispose();
    _viewportController.removeListener(_onViewportChanged);
    _selectionController.removeListener(_onSelectionChangedForWorkspace);
    _viewportController.dispose();
    _wallTool.dispose();
    _levelTool.dispose();
    _openingTool.dispose();
    _surfaceTool.dispose();
    _stairTool.dispose();
    _trimTool.dispose();
    _inspectorController.dispose();
    _selectionController.dispose();
    if (widget.dependencies == null) {
      _dependencies.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ViewerHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewportTheme != widget.viewportTheme) {
      unawaited(_viewportController.setViewportTheme(widget.viewportTheme));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_writeRecoveryAutosave());
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isBusy) {
        _reloadCurrentScene();
      }
    });
  }

  void _updateViewportState(VoidCallback callback) {
    if (mounted) setState(callback);
  }

  Future<void> _runViewNavigation(Future<void> Function() operation) {
    return _viewNavigation.run(() async {
      if (mounted) {
        _updateViewportState(() => _isViewNavigationBusy = true);
      }
      try {
        await operation();
      } finally {
        if (mounted) {
          _updateViewportState(() => _isViewNavigationBusy = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // A project session is hosted by the start screen. Intercept Android
    // back here so the app-level navigator is never popped while a model is
    // open; the existing save/discard flow owns the return to Start screen.
    final canLeaveWorkspace = widget.onReturnToStart == null;
    return PopScope<void>(
      canPop: canLeaveWorkspace,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !canLeaveWorkspace) {
          unawaited(_requestReturnToStart());
        }
      },
      child: _buildWorkspace(context),
    );
  }
}
