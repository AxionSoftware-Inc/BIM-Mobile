// Legacy dialog widgets are kept temporarily for the level-line quick edit
// path.  The production Inspector is `PropertyEditor` + its controllers.
// ignore_for_file: unused_element, unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'authoring_command_service.dart';
import 'documentation/document_models.dart';
import 'documentation/documentation_workspace.dart';
import 'documentation/sheet_canvas.dart';
import 'documentation/sheet_workspace_controller.dart';
import 'inspector_controller.dart';
import 'material_layer_editor.dart';
import 'native_viewer_session_factory.dart';
import 'property_editor.dart';
import 'project_lifecycle_service.dart';
import 'project_persistence_service.dart';
import 'project_session_controller.dart';
import 'project_browser_panel.dart';
import 'render_scene_editor.dart';
import 'render_scene_estimator.dart';
import 'render_scene_models.dart';
import 'render_scene_repository.dart';
import 'scene_mutation_service.dart';
import 'scene_view_service.dart';
import 'selection_controller.dart';
import 'tbe_ffi.dart';
import 'tools/level_tool_controller.dart';
import 'tools/opening_tool_controller.dart';
import 'tools/plan_sketch_geometry.dart';
import 'tools/surface_tool_controller.dart';
import 'tools/stair_tool_controller.dart';
import 'tools/trim_extend_tool_controller.dart';
import 'tools/wall_tool_controller.dart';
import 'workspace_chrome.dart';
import 'render_scene_viewport.dart';
import 'render_scene_viewport_planar.dart';

enum _WallMoveMode {
  translate,
  startHandle,
  endHandle,
}

enum _ResidentialTemplateKind {
  tower9,
  campus6x9,
}

class ViewerApp extends StatelessWidget {
  const ViewerApp({
    super.key,
    this.source,
    this.preferEngineBackedBundledSample = false,
  });

  final RenderSceneSource? source;
  final bool preferEngineBackedBundledSample;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tablet BIM',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1F5D4E),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F6F4),
        useMaterial3: true,
        visualDensity: VisualDensity.standard,
      ),
      home: ViewerHomePage(
        source: source ?? const AssetRenderSceneSource(),
        preferEngineBackedBundledSample: preferEngineBackedBundledSample,
      ),
    );
  }
}

class ViewerHomePage extends StatefulWidget {
  const ViewerHomePage({
    super.key,
    required this.source,
    this.preferEngineBackedBundledSample = false,
  });

  final RenderSceneSource source;
  final bool preferEngineBackedBundledSample;

  @override
  State<ViewerHomePage> createState() => _ViewerHomePageState();
}

class _ViewerHomePageState extends State<ViewerHomePage> {
  static const double _defaultWallThicknessMeters =
      RenderSceneEditor.defaultWallThicknessMeters;
  static const double _defaultWallHeightMeters =
      RenderSceneEditor.defaultWallHeightMeters;
  static const Set<String> _coreKindOrder = <String>{
    'wall',
    'door',
    'window',
    'room',
    'slab',
    'floor',
    'ceiling',
    'roof',
    'column',
    'beam',
    'stair',
  };

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
  late final ProjectLifecycleService<ViewerRepository> _projectLifecycle;
  late final ProjectPersistenceService _projectPersistence;
  late final ProjectSessionController<ViewerRepository> _projectSession;
  late final SceneViewService _sceneViews;
  late final SheetWorkspaceController _sheetWorkspace;

  ViewerRepository? get _engineRepository => _projectSession.session;
  bool get _engineBackedMode => _projectSession.isEngineBacked;

  RenderScene? _scene;
  String? _statusMessage;
  String? _loadError;
  bool _isBusy = false;
  bool _showInspector = true;
  bool _showObjectList = false;
  bool _showDiagnostics = false;
  String? _engineLoadDiagnostic;
  int? _activeLevelId;
  RenderSceneSection? _activeSectionView;
  final Map<String, RenderScene> _sheetViewScenes = <String, RenderScene>{};
  RenderScene? _sheetSourceScene;
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
  _WallMoveMode _wallMoveMode = _WallMoveMode.translate;
  String? _editStatusMessage;
  bool _snapDraftToGrid = true;
  final List<String> _androidMutationTrace = <String>[];

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
            RenderSceneSurfaceDrawMode.autoRoom => const <String>{'room'},
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
    _selectionController = SelectionController(_viewportController);
    _inspectorController = InspectorController(_selectionController);
    _authoringCommands = AuthoringCommandService(
      repository: () => _engineRepository,
      engineEnabled: () => _engineBackedMode,
    );
    _projectSession = ProjectSessionController<ViewerRepository>();
    _projectLifecycle = ProjectLifecycleService<ViewerRepository>(
      sessionFactory: NativeViewerSessionFactory(),
    );
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
      _loadBundledSample();
    });
  }

  @override
  void dispose() {
    _sheetWorkspace.removeListener(_onSheetWorkspaceChanged);
    _sheetWorkspace.dispose();
    _viewportController.removeListener(_onViewportChanged);
    _viewportController.dispose();
    _wallTool.dispose();
    _levelTool.dispose();
    _openingTool.dispose();
    _surfaceTool.dispose();
    _stairTool.dispose();
    _trimTool.dispose();
    _inspectorController.dispose();
    _selectionController.dispose();
    _projectSession.dispose();
    super.dispose();
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

  void _onViewportChanged() {
    if (mounted) {
      setState(() {
        // Rebuild inspector/status when selection/highlight changes.
      });
    }
  }

  void _onSheetWorkspaceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _handleEscapePressed() async {
    if (_sheetWorkspace.activeSheet != null) {
      _closeActiveSheet();
      return;
    }
    final hasDraft = _wallTool.hasStart ||
        _levelTool.hasDraft ||
        _draftWallStart != null ||
        _draftWallEnd != null ||
        _draftSurfaceStart != null ||
        _draftSurfaceEnd != null ||
        _draftSurfaceWallIds.isNotEmpty ||
        _draftHostWall != null ||
        _viewportController.draftOpening != null ||
        _viewportController.draftSurface != null;

    if (hasDraft) {
      await _cancelDraft();
      return;
    }

    if (_interactionMode != RenderSceneInteractionMode.select) {
      await _setInteractionMode(RenderSceneInteractionMode.select);
      return;
    }

    if (_viewportController.selectedElementId != null) {
      await _clearSelection();
    }
  }

  Future<void> _loadBundledSample() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
      _loadError = null;
      _activeSectionView = null;
      _statusMessage = 'Loading bundled RenderScene sample...';
    });

    try {
      final engineLoaded = widget.preferEngineBackedBundledSample &&
          widget.source is AssetRenderSceneSource &&
          await _tryLoadBundledEngineSample();
      if (engineLoaded) {
        return;
      }
      if (kReleaseMode && widget.preferEngineBackedBundledSample) {
        throw StateError(
          'Production authoring requires the native C++ BIM engine. '
          'Fallback RenderScene is debug/demo only.',
        );
      }
      final result = await widget.source.loadBundledSample();
      await _applyLoadResult(
        result,
        sourceLabel: 'Sample model',
      );
      if (!_engineBackedMode) {
        setState(() {
          _engineLoadDiagnostic ??=
              'Engine-backed sample unavailable. Fallback render scene loaded.';
          _statusMessage = _engineLoadDiagnostic;
        });
      }
    } catch (error) {
      setState(() {
        _loadError = error.toString();
        _statusMessage = 'Failed to load bundled sample.';
        _isBusy = false;
      });
    }
  }

  Future<void> _createResidentialTemplate(
    _ResidentialTemplateKind template,
  ) async {
    if (_isBusy) return;
    final buildingCount = template == _ResidentialTemplateKind.tower9 ? 1 : 6;
    const storyCount = 9;
    final label = buildingCount == 1
        ? '9-qavatli turar-joy binosi'
        : '6 ta 9-qavatli turar-joy shaharchasi';
    setState(() {
      _isBusy = true;
      _loadError = null;
      _activeSectionView = null;
      _statusMessage = '$label engine’da yaratilmoqda...';
    });

    try {
      final previousRepository = _engineRepository;
      final launch = await _projectLifecycle.createResidentialTemplate(
        existingSession: previousRepository,
        buildingCount: buildingCount,
        storyCount: storyCount,
      );
      if (!mounted) {
        if (launch.createdSession) launch.session.dispose();
        return;
      }
      _projectSession.activate(launch.session);
      _engineLoadDiagnostic = null;
      await _applyLoadResult(
        launch.renderScene!,
        sourceLabel: '$label template',
      );
      if (buildingCount == 1) {
        // A tower is most useful as a whole-building visual test on first
        // open. Switching back to plan re-enables nearby-level streaming.
        await _setProjectionMode(RenderSceneProjectionMode.isometric);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _statusMessage = '$label yaratilmadi.';
        _isBusy = false;
      });
    }
  }

  Future<bool> _tryLoadBundledEngineSample() async {
    try {
      final launch = await _projectLifecycle.createResidentialTemplate(
        buildingCount: 1,
        storyCount: 3,
      );
      _projectSession.activate(launch.session);
      _engineLoadDiagnostic = null;
      await _applyLoadResult(
        launch.renderScene!,
        sourceLabel: 'Layered house',
      );
      // The bundled engine sample is the first visual proof of the complete
      // building path. Open it in 3D so the top-level roof and monolithic
      // stair are visible immediately instead of being hidden by the default
      // top-down level filter.
      await _setProjectionMode(RenderSceneProjectionMode.isometric);
      return true;
    } catch (error) {
      _projectSession.markUnavailable();
      _engineLoadDiagnostic = 'Engine-backed sample failed: $error';
      return false;
    }
  }

  Future<void> _reloadCurrentScene() async {
    if (_engineBackedMode && _engineRepository != null) {
      setState(() {
        _isBusy = true;
        _loadError = null;
        _statusMessage = _activeSectionView == null
            ? 'Refreshing engine-backed scene...'
            : 'Refreshing ${_activeSectionView!.name}...';
      });
      try {
        final activeSection = _activeSectionView;
        if (activeSection != null) {
          final result = await _sceneViews.setFullSceneRenderScope(true);
          await _activateSectionView(activeSection, result);
        } else {
          final result = await _sceneViews.refresh();
          await _applyLoadResult(
            result,
            sourceLabel: 'Current project',
          );
        }
      } catch (error) {
        setState(() {
          _loadError = error.toString();
          _statusMessage = 'Failed to refresh engine-backed scene.';
          _isBusy = false;
        });
      }
      return;
    }
    await _loadBundledSample();
  }

  Future<void> _saveCurrentProject() async {
    final repository = _engineRepository;
    if (!_engineBackedMode || repository == null || _isBusy) {
      setState(() {
        _statusMessage = 'Save uchun native engine session kerak.';
      });
      return;
    }
    setState(() {
      _isBusy = true;
      _loadError = null;
      _statusMessage = 'Saving project...';
    });
    try {
      final file = await _projectPersistence.saveToDefaultLocation();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _statusMessage = 'Saved: ${file.path}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'Project save failed.';
      });
    }
  }

  Future<void> _openDocumentationWorkspace() async {
    final scene = _scene;
    if (scene == null || !mounted) return;
    final composedSheet = _sheetWorkspace.activeSheet;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => DocumentationWorkspacePage(
          scene: _sheetSourceScene ?? scene,
          activeLevelId: _activeLevelId,
          initialProjectName: 'Tablet BIM Project',
          composedSheet: composedSheet,
          composedScenes: Map<String, RenderScene>.unmodifiable(
            _sheetViewScenes,
          ),
        ),
      ),
    );
  }

  void _createSheet() {
    final sheet = _sheetWorkspace.createSheet();
    setState(() {
      _showObjectList = true;
      _showInspector = false;
      _statusMessage = '${sheet.number} sheet ochildi.';
    });
  }

  void _openSheet(String sheetId) {
    _sheetWorkspace.openSheet(sheetId);
    final sheet = _sheetWorkspace.activeSheet;
    setState(() {
      _showObjectList = true;
      _showInspector = false;
      _statusMessage =
          sheet == null ? _statusMessage : '${sheet.number} · ${sheet.title}';
    });
  }

  void _closeActiveSheet() {
    final closed = _sheetWorkspace.activeSheet;
    _sheetWorkspace.closeSheet();
    setState(() {
      _statusMessage = closed == null
          ? _statusMessage
          : '${closed.number} yopildi · model view';
    });
    if (_engineBackedMode) {
      final needsFullScene = _projectionMode.isElevation;
      unawaited(_sceneViews.setFullSceneRenderScope(needsFullScene));
    }
  }

  Future<bool> _placeSheetView(
    SheetViewReference view,
    double normalizedX,
    double normalizedY,
  ) async {
    final currentScene = _scene;
    if (currentScene == null || _sheetWorkspace.activeSheet == null) {
      return false;
    }
    if (_sheetWorkspace.activeSheet!.placements
        .any((placement) => placement.view.id == view.id)) {
      return false;
    }

    setState(() {
      _statusMessage = '${view.label} sheet uchun tayyorlanmoqda...';
    });
    try {
      RenderScene resolvedScene;
      if (view.kind == SheetViewKind.section &&
          view.section != null &&
          _engineBackedMode) {
        final result = await _sceneViews.section(
          view.section!.start,
          view.section!.end,
        );
        resolvedScene = result.scene ?? currentScene;
      } else {
        var source = _sheetSourceScene;
        if (source == null) {
          if (_engineBackedMode) {
            final result = await _sceneViews.setFullSceneRenderScope(true);
            source = result.scene ?? currentScene;
          } else {
            source = currentScene;
          }
          _sheetSourceScene = source;
        }
        resolvedScene = view.kind == SheetViewKind.floorPlan
            ? source.filteredByLevel(view.levelId)
            : source;
      }

      _sheetViewScenes[view.id] = resolvedScene;
      final placed = _sheetWorkspace.placeView(
        view: view,
        centerX: normalizedX,
        centerY: normalizedY,
      );
      if (mounted) {
        setState(() {
          _statusMessage = placed
              ? '${view.label} sheetga joylashtirildi.'
              : '${view.label} bu sheetda allaqachon bor.';
        });
      }
      return placed;
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = '${view.label} sheetga qo‘yilmadi.';
          _loadError = error.toString();
        });
      }
      return false;
    }
  }

  Future<void> _toggleAndroidRenderer() async {
    final next =
        _viewportController.backend == RenderSceneViewportBackend.native
            ? RenderSceneViewportBackend.fallback
            : RenderSceneViewportBackend.native;
    await _viewportController.setBackend(next);
    if (!mounted) return;
    setState(() {
      _statusMessage = next == RenderSceneViewportBackend.native
          ? 'Filament renderer enabled. Interaction stays Flutter-owned.'
          : 'Flutter fallback renderer enabled.';
    });
  }

  Future<void> _applyLoadResult(
    RenderSceneLoadResult result, {
    required String sourceLabel,
  }) async {
    final rawScene = result.scene;
    final scene = rawScene == null
        ? null
        : RenderSceneEditor.normalizeSceneGeometry(rawScene);
    _sheetSourceScene = null;
    _sheetViewScenes.clear();

    setState(() {
      _scene = scene;
      _loadError = result.errors.isNotEmpty ? result.errors.join('\n') : null;
      _statusMessage = scene == null
          ? 'RenderScene load failed.'
          : '$sourceLabel · ${scene.objectCount} objects';
      _isBusy = false;

      if (scene != null) {
        if (_usesProjectionDefaultDisplayStyle) {
          _displayStyle = _defaultDisplayStyleForProjection();
        }
        _activeLevelId =
            _resolveInitialLevelId(scene, preferred: _activeLevelId);
        final activeLevel = scene.levelById(_activeLevelId) ??
            (scene.levels.isNotEmpty ? scene.levels.first : null);
        _draftFloorTopElevationMeters = activeLevel?.elevationMeters ?? 0.0;
        _draftSurfaceHeightMeters =
            activeLevel?.defaultWallHeightMeters ?? _defaultWallHeightMeters;
        if (_usesProjectionDefaultVisibility || _visibleKinds.isEmpty) {
          _visibleKinds = _defaultVisibleKindsForProjection(scene);
          _usesProjectionDefaultVisibility = true;
        } else {
          _visibleKinds = _sanitizeVisibleKinds(
            visibleKinds: _visibleKinds,
            scene: _sceneForViewport(scene),
          );
        }
        _visibleKinds = _ensurePlanCoreVisibility(_visibleKinds, scene);
      }
    });

    if (scene == null) {
      await _viewportController.clearScene();
      return;
    }

    await _viewportController.loadRenderScene(_sceneForViewport(scene));
    await _viewportController.setVisibleKinds(_visibleKinds);
    await _viewportController.setProjectionMode(_projectionMode);
    await _viewportController.setOrbitProjectionStyle(_orbitProjectionStyle);
    await _viewportController.setDisplayStyle(_displayStyle);
    _interactionMode = RenderSceneInteractionMode.select;
    await _viewportController.setInteractionMode(_interactionMode);
    _viewportController.clearDraft();
    await _viewportController.fitCamera();
    if (kDebugMode &&
        _viewportController.backend == RenderSceneViewportBackend.native) {
      final diagnostics = await _viewportController.nativeDiagnostics();
      if (diagnostics != null && mounted) {
        final input = diagnostics['inputObjects'] ?? 0;
        final renderables = diagnostics['renderables'] ?? 0;
        final faceBatches = diagnostics['faceBatches'] ?? renderables;
        final instanceGroups = diagnostics['instanceGroups'] ?? 0;
        final instancedObjects = diagnostics['instancedObjects'] ?? 0;
        final edgeBatches = diagnostics['edgeBatches'] ?? 0;
        final drawCalls = diagnostics['estimatedDrawCalls'] ?? renderables;
        final frames = diagnostics['renderedFrames'] ?? 0;
        final materialReady = diagnostics['materialReady'] == true;
        setState(() {
          _statusMessage =
              'Filament: input=$input · renderables=$renderables · '
              'face batches=$faceBatches · instances=$instancedObjects/$instanceGroups · '
              'edge batches=$edgeBatches · '
              'draws=$drawCalls · frames=$frames · '
              'material=${materialReady ? 'ready' : 'FAILED'}';
        });
      }
    }
  }

  Set<String> _sanitizeVisibleKinds({
    required Set<String> visibleKinds,
    required RenderScene scene,
  }) {
    if (visibleKinds.isEmpty) {
      return <String>{};
    }

    final available = scene.kindCounts.keys.toSet();
    return visibleKinds.intersection(available);
  }

  int? _resolveInitialLevelId(RenderScene scene, {int? preferred}) {
    final levels = scene.levels;
    if (levels.isEmpty) {
      return preferred;
    }
    if (preferred != null && scene.levelById(preferred) != null) {
      return preferred;
    }
    return levels.first.levelId;
  }

  RenderScene _sceneForViewport(RenderScene scene) {
    if (_projectionMode == RenderSceneProjectionMode.topDown) {
      final activeLevel = _activeLevel(scene);
      if (activeLevel != null) {
        return scene.filteredByVerticalRange(
          activeLevelId: activeLevel.levelId,
          bottomMeters: activeLevel.elevationMeters,
          topMeters: activeLevel.elevationMeters + _planViewRangeMeters,
        );
      }
    }
    return scene;
  }

  Set<String> _defaultVisibleKindsForProjection(RenderScene scene) {
    final available = scene.kindCounts.keys.toSet();
    if (_projectionMode == RenderSceneProjectionMode.topDown) {
      const preferred = <String>{
        'wall',
        'door',
        'window',
        'room',
        'column',
        'beam',
        'stair',
      };
      final visible = preferred.intersection(available);
      if (visible.isNotEmpty) {
        return visible;
      }
    }
    return <String>{};
  }

  Set<String> _ensurePlanCoreVisibility(
    Set<String> kinds,
    RenderScene scene,
  ) {
    if (_projectionMode != RenderSceneProjectionMode.topDown || kinds.isEmpty) {
      return kinds;
    }
    final available = scene.kindCounts.keys.toSet();
    return <String>{
      ...kinds,
      for (final kind in <String>{'wall', 'door', 'window'})
        if (available.contains(kind)) kind,
    };
  }

  RenderSceneDisplayStyle _defaultDisplayStyleForProjection() {
    if (_projectionMode == RenderSceneProjectionMode.topDown ||
        _projectionMode.isElevation) {
      return RenderSceneDisplayStyle.solid;
    }
    return RenderSceneDisplayStyle.solid;
  }

  RenderSceneLevel? _activeLevel(RenderScene? scene) {
    if (scene == null) {
      return null;
    }
    return scene.levelById(_activeLevelId) ??
        (scene.levels.isNotEmpty ? scene.levels.first : null);
  }

  double _activeLevelElevation(RenderScene? scene) {
    return _activeLevel(scene)?.elevationMeters ?? 0.0;
  }

  double _activeLevelDefaultWallHeight(RenderScene? scene) {
    return _activeLevel(scene)?.defaultWallHeightMeters ??
        _defaultWallHeightMeters;
  }

  int? _metadataInt(RenderSceneObject object, String key) {
    final value = object.metadata[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  double? _metadataDouble(RenderSceneObject object, String key) {
    final value = object.metadata[key];
    if (value is double) {
      return value;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  RenderSceneLevel? _pickLevelAtElevation(
    RenderScene scene,
    RenderScenePoint? modelPoint, {
    double toleranceMeters = 1.4,
  }) {
    if (modelPoint == null ||
        !(_projectionMode.isElevation ||
            _projectionMode.supportsPlanFootprintEditing)) {
      return null;
    }
    RenderSceneLevel? bestLevel;
    var bestDistance = toleranceMeters;
    for (final level in scene.levels) {
      final distance = (modelPoint.z - level.elevationMeters).abs();
      if (distance <= bestDistance) {
        bestDistance = distance;
        bestLevel = level;
      }
    }
    return bestLevel;
  }

  RenderSceneLevel? _nextHigherLevel(RenderScene scene, int baseLevelId) {
    final base = scene.levelById(baseLevelId);
    if (base == null) {
      return null;
    }
    final sorted = [...scene.levels]
      ..sort((a, b) => a.elevationMeters.compareTo(b.elevationMeters));
    for (final level in sorted) {
      if (level.elevationMeters > base.elevationMeters + 1e-6) {
        return level;
      }
    }
    return null;
  }

  Future<void> _attachWallToActiveLevel(
    RenderSceneObject object, {
    required bool constrainToNextLevel,
  }) async {
    final scene = _scene;
    final repository = _engineRepository;
    final wallId = object.elementId;
    final activeLevelId = _activeLevelId;
    if (scene == null ||
        repository == null ||
        !_engineBackedMode ||
        wallId == null ||
        activeLevelId == null ||
        object.kindKey != 'wall') {
      setState(() {
        _editStatusMessage =
            'Wallni levelga biriktirish uchun engine mode va active level kerak.';
      });
      return;
    }

    final nextLevel =
        constrainToNextLevel ? _nextHigherLevel(scene, activeLevelId) : null;
    if (constrainToNextLevel && nextLevel == null) {
      setState(() {
        _editStatusMessage =
            'Top constraint uchun active leveldan yuqori level topilmadi.';
      });
      return;
    }

    final result = await repository.setWallLevelConstraints(
      wallId: wallId,
      baseLevelId: activeLevelId,
      topLevelId: nextLevel?.levelId ?? 0,
      baseOffsetMeters: _metadataDouble(object, 'base_offset_meters') ?? 0.0,
      topOffsetMeters: _metadataDouble(object, 'top_offset_meters') ?? 0.0,
      heightMode: constrainToNextLevel ? 1 : 0,
    );
    await _applyEngineSceneResult(
      result,
      message: constrainToNextLevel
          ? 'Wall active levelga biriktirildi, top ${nextLevel?.name}ga constraint qilindi.'
          : 'Wall active levelga biriktirildi.',
    );
  }

  Future<void> _setActiveLevel(int? levelId) async {
    var scene = _scene;
    final wasGeneratedSection = _activeSectionView != null;
    if (scene == null ||
        levelId == null ||
        (_activeLevelId == levelId && !wasGeneratedSection)) {
      return;
    }
    if (wasGeneratedSection) {
      // Selecting a plan level is an explicit navigation away from the
      // generated cut scene. The engine call below reloads the authoritative
      // model snapshot for that level.
      setState(() => _activeSectionView = null);
    }
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final result = await _sceneViews.activateLevel(levelId);
      if (!mounted) {
        return;
      }
      scene = result.scene ?? scene;
    }
    final activeScene = scene;
    final level = activeScene.levelById(levelId);
    setState(() {
      _scene = activeScene;
      _activeLevelId = levelId;
      _draftFloorTopElevationMeters = level?.elevationMeters ?? 0.0;
      _draftSurfaceHeightMeters =
          level?.defaultWallHeightMeters ?? _defaultWallHeightMeters;
      _statusMessage = 'Active level changed.';
      if (_usesProjectionDefaultVisibility) {
        _visibleKinds = _defaultVisibleKindsForProjection(activeScene);
      } else {
        _visibleKinds = _sanitizeVisibleKinds(
          visibleKinds: _visibleKinds,
          scene: _sceneForViewport(activeScene),
        );
      }
      if (_usesProjectionDefaultDisplayStyle) {
        _displayStyle = _defaultDisplayStyleForProjection();
      }
    });
    await _viewportController.loadRenderScene(_sceneForViewport(activeScene));
    await _viewportController.setVisibleKinds(_visibleKinds);
    await _viewportController.setProjectionMode(_projectionMode);
    await _viewportController.setOrbitProjectionStyle(_orbitProjectionStyle);
    await _viewportController.setDisplayStyle(_displayStyle);
    await _viewportController.selectElement(null);
    await _viewportController.highlightElement(null);
    await _viewportController.fitCamera();
  }

  Future<void> _fitCamera() async {
    setState(() {
      _statusMessage = _projectionMode.fitLabel;
    });

    await _viewportController.fitCamera();
  }

  Future<void> _setProjectionMode(RenderSceneProjectionMode mode) async {
    final wasGeneratedSection = _activeSectionView != null;
    if (wasGeneratedSection) {
      await _viewportController.setSectionView(null);
    }
    if (_projectionMode == mode && !wasGeneratedSection) {
      // Project Browser can be used after a renderer reload. Reassert the
      // controller state even when the Flutter state already has this mode.
      await _viewportController.setProjectionMode(mode);
      return;
    }

    final scene = _scene;
    setState(() {
      // A normal plan, elevation, or 3D navigation intentionally leaves the
      // generated section snapshot and reloads the authoritative model view.
      _activeSectionView = null;
      _projectionMode = mode;
      _statusMessage = mode.statusLabel;
      if (scene != null && _usesProjectionDefaultVisibility) {
        _visibleKinds = _defaultVisibleKindsForProjection(scene);
      } else if (scene != null) {
        _visibleKinds = _sanitizeVisibleKinds(
          visibleKinds: _visibleKinds,
          scene: _sceneForViewport(scene),
        );
      }
      if (scene != null) {
        _visibleKinds = _ensurePlanCoreVisibility(_visibleKinds, scene);
      }
      if (_usesProjectionDefaultDisplayStyle) {
        _displayStyle = _defaultDisplayStyleForProjection();
      }
    });

    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      // Elevations must frame every storey of the building. Plan views retain
      // nearby-level streaming, and a large 3D campus keeps its streamed
      // scope so ordinary navigation remains smooth on a tablet.
      final is3d = mode == RenderSceneProjectionMode.isometric;
      final isLargeScene = (scene?.objectCount ?? 0) > 120;
      final useFullScene =
          mode.isElevation || (is3d && !isLargeScene && !wasGeneratedSection);
      final result = await _sceneViews.setFullSceneRenderScope(useFullScene);
      await _applyLoadResult(
        result,
        sourceLabel: useFullScene
            ? (mode.isElevation ? 'Full building elevation' : 'Full tower 3D')
            : 'Nearby levels',
      );
      return;
    }

    if (scene != null) {
      await _viewportController.updateRenderScene(_sceneForViewport(scene));
      await _viewportController.setVisibleKinds(_visibleKinds);
    }
    await _viewportController.setProjectionMode(mode);
    await _viewportController.setDisplayStyle(_displayStyle);
    await _viewportController.fitCamera();
  }

  Future<void> _activateSectionView(
    RenderSceneSection section,
    RenderSceneLoadResult result,
  ) async {
    if (result.scene == null) {
      setState(() {
        _activeSectionView = null;
      });
      await _applyLoadResult(result, sourceLabel: section.name);
      return;
    }

    // A section snapshot has its own X/Z coordinate system. Set the
    // projection first, then apply the scene once; calling the normal
    // elevation navigation here would reload and overwrite this cut view.
    setState(() {
      _activeSectionView = section;
      _projectionMode = RenderSceneProjectionMode.northElevation;
      _statusMessage = 'Opening ${section.name} cut...';
      if (_usesProjectionDefaultDisplayStyle) {
        _displayStyle = _defaultDisplayStyleForProjection();
      }
    });
    await _applyLoadResult(result, sourceLabel: '${section.name} cut');
    await _viewportController.setSectionView(section);
  }

  Future<void> _setOrbitProjectionStyle(
    RenderSceneOrbitProjectionStyle style,
  ) async {
    if (_orbitProjectionStyle == style) {
      return;
    }

    setState(() {
      _orbitProjectionStyle = style;
      _statusMessage = style == RenderSceneOrbitProjectionStyle.perspective
          ? '3D perspective view'
          : '3D orthographic view';
    });

    await _viewportController.setOrbitProjectionStyle(style);
    await _viewportController.fitCamera();
  }

  Future<void> _setDisplayStyle(RenderSceneDisplayStyle style) async {
    if (_displayStyle == style) {
      return;
    }

    setState(() {
      _displayStyle = style;
      _usesProjectionDefaultDisplayStyle = false;
      _statusMessage = switch (style) {
        RenderSceneDisplayStyle.shaded => 'Shaded display',
        RenderSceneDisplayStyle.solid => 'Solid display',
        RenderSceneDisplayStyle.wireframe => 'Wireframe display',
      };
    });

    await _viewportController.setDisplayStyle(style);
  }

  Future<void> _showSectionBoxDialog() async {
    final bounds = _viewportController.sceneBounds;
    if (!bounds.isFinite || _projectionMode.is3D == false) return;
    // Keep the box visibly outside the model, like Revit's Section Box, while
    // padding each axis independently so a tall building does not make the
    // whole cube unnecessarily huge in orbit.
    const marginX = 5.0;
    const marginY = 5.0;
    const marginZ = 5.0;
    final next = _viewportController.hasSectionBox
        ? null
        : RenderSceneBounds(
            min: RenderScenePoint(
              x: bounds.min.x - marginX,
              y: bounds.min.y - marginY,
              z: bounds.min.z - marginZ,
            ),
            max: RenderScenePoint(
              x: bounds.max.x + marginX,
              y: bounds.max.y + marginY,
              z: bounds.max.z + marginZ,
            ),
          );
    await _viewportController.setSectionBox(next);
    if (mounted) {
      setState(() => _statusMessage = next == null
          ? '3D Section Box cleared'
          : '3D Section Box active — drag viewport handles');
    }
  }

  Future<void> _showCreateLevelDialog() async {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    final suggestedIndex = scene.levels.length + 1;
    final currentLevel = _activeLevel(scene);
    final defaultElevation = currentLevel == null
        ? 0.0
        : currentLevel.elevationMeters + currentLevel.defaultWallHeightMeters;
    final nameController = TextEditingController(text: 'Level $suggestedIndex');
    final elevationController =
        TextEditingController(text: defaultElevation.toStringAsFixed(2));
    final heightController = TextEditingController(
      text: (currentLevel?.defaultWallHeightMeters ?? _defaultWallHeightMeters)
          .toStringAsFixed(2),
    );

    final payload =
        await showDialog<({String name, double elevation, double wallHeight})>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Create level'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                _NumericField(
                  label: 'Elevation (m)',
                  controller: elevationController,
                  onChanged: (_) {},
                ),
                _NumericField(
                  label: 'Default wall height (m)',
                  controller: heightController,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final elevation =
                    double.tryParse(elevationController.text.trim());
                final wallHeight =
                    double.tryParse(heightController.text.trim());
                if (name.isEmpty ||
                    elevation == null ||
                    wallHeight == null ||
                    wallHeight <= 0) {
                  return;
                }
                Navigator.of(context).pop((
                  name: name,
                  elevation: elevation,
                  wallHeight: wallHeight,
                ));
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (!mounted || payload == null) {
      return;
    }

    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final result = await repository.createLevel(
        name: payload.name,
        elevationMeters: payload.elevation,
        defaultWallHeightMeters: payload.wallHeight,
      );
      await _applyEngineSceneResult(result, message: 'Level created.');
      return;
    }
    final nextScene = RenderSceneEditor.createLevel(
      scene: scene,
      name: payload.name,
      elevationMeters: payload.elevation,
      defaultWallHeightMeters: payload.wallHeight,
    );
    await _applySceneChange(nextScene, message: 'Level created.');
  }

  Future<void> _showWallLevelConstraintsDialog(RenderSceneObject object) async {
    final repository = _engineRepository;
    final scene = _scene;
    final wallId = object.elementId;
    if (!_engineBackedMode ||
        repository == null ||
        scene == null ||
        wallId == null) {
      setState(() {
        _editStatusMessage =
            'Wall level constraints engine-backed mode talab qiladi.';
      });
      return;
    }
    final levels = scene.levels;
    if (levels.isEmpty) {
      return;
    }

    int baseLevelId = _metadataInt(object, 'base_level_id') ??
        object.levelId ??
        levels.first.levelId;
    int topLevelId = _metadataInt(object, 'top_level_id') ?? 0;
    int heightMode =
        ((object.metadata['height_mode']?.toString() ?? 'Unconnected') ==
                'TopLevel')
            ? 1
            : 0;
    final baseOffsetController = TextEditingController(
      text: (_metadataDouble(object, 'base_offset_meters') ?? 0.0)
          .toStringAsFixed(2),
    );
    final topOffsetController = TextEditingController(
      text: (_metadataDouble(object, 'top_offset_meters') ?? 0.0)
          .toStringAsFixed(2),
    );

    final payload = await showDialog<
        ({
          int baseLevelId,
          int topLevelId,
          int heightMode,
          double baseOffset,
          double topOffset
        })>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Wall #$wallId levels'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    DropdownButtonFormField<int>(
                      initialValue: baseLevelId,
                      decoration: const InputDecoration(
                        labelText: 'Base level',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: levels
                          .map((level) => DropdownMenuItem<int>(
                                value: level.levelId,
                                child: Text(level.name),
                              ))
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() {
                            baseLevelId = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: heightMode,
                      decoration: const InputDecoration(
                        labelText: 'Height mode',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const <DropdownMenuItem<int>>[
                        DropdownMenuItem(value: 0, child: Text('Unconnected')),
                        DropdownMenuItem(value: 1, child: Text('Top level')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setLocalState(() {
                            heightMode = value;
                            if (heightMode == 0) {
                              topLevelId = 0;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      initialValue: topLevelId == 0 ? null : topLevelId,
                      decoration: const InputDecoration(
                        labelText: 'Top level',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: levels
                          .map((level) => DropdownMenuItem<int>(
                                value: level.levelId,
                                child: Text(level.name),
                              ))
                          .toList(growable: false),
                      onChanged: heightMode == 0
                          ? null
                          : (value) {
                              setLocalState(() {
                                topLevelId = value ?? 0;
                              });
                            },
                    ),
                    const SizedBox(height: 8),
                    _NumericField(
                      label: 'Base offset (m)',
                      controller: baseOffsetController,
                      onChanged: (_) {},
                    ),
                    _NumericField(
                      label: 'Top offset (m)',
                      controller: topOffsetController,
                      onChanged: (_) {},
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final baseOffset =
                        double.tryParse(baseOffsetController.text.trim());
                    final topOffset =
                        double.tryParse(topOffsetController.text.trim());
                    if (baseOffset == null ||
                        topOffset == null ||
                        (heightMode == 1 && topLevelId == 0)) {
                      return;
                    }
                    Navigator.of(context).pop((
                      baseLevelId: baseLevelId,
                      topLevelId: topLevelId,
                      heightMode: heightMode,
                      baseOffset: baseOffset,
                      topOffset: topOffset,
                    ));
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || payload == null) {
      return;
    }

    final result = await repository.setWallLevelConstraints(
      wallId: wallId,
      baseLevelId: payload.baseLevelId,
      topLevelId: payload.topLevelId,
      baseOffsetMeters: payload.baseOffset,
      topOffsetMeters: payload.topOffset,
      heightMode: payload.heightMode,
    );
    await _applyEngineSceneResult(result,
        message: 'Wall level constraints updated.');
  }

  Future<void> _showOpeningLevelDialog(RenderSceneObject object) async {
    final scene = _scene;
    final repository = _engineRepository;
    final openingId = object.elementId;
    if (scene == null ||
        repository == null ||
        !_engineBackedMode ||
        openingId == null ||
        (object.kindKey != 'door' && object.kindKey != 'window')) {
      setState(() {
        _editStatusMessage =
            'Opening level move engine-backed mode talab qiladi.';
      });
      return;
    }
    final levels = scene.levels;
    if (levels.isEmpty) {
      return;
    }
    int selectedLevelId =
        object.levelId ?? _activeLevelId ?? levels.first.levelId;
    final levelOffsetController = TextEditingController(
      text: (_metadataDouble(object, 'level_offset_meters') ?? 0.0)
          .toStringAsFixed(2),
    );
    final resultConstraint = await showDialog<({int levelId, double offset})>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: Text('Move ${prettySceneKind(object.kind)} to level'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<int>(
                    initialValue: selectedLevelId,
                    decoration: const InputDecoration(
                      labelText: 'Base level',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: levels
                        .map((level) => DropdownMenuItem<int>(
                              value: level.levelId,
                              child: Text(
                                '${level.name} (${level.elevationMeters.toStringAsFixed(2)} m)',
                              ),
                            ))
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value != null) {
                        setLocalState(() {
                          selectedLevelId = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: levelOffsetController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Offset from level (m)',
                      helperText: 'Masalan 0.30 = leveldan 30 sm yuqori',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final offset = double.tryParse(levelOffsetController.text);
                    if (offset == null) {
                      return;
                    }
                    Navigator.of(context).pop(
                      (levelId: selectedLevelId, offset: offset),
                    );
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );

    levelOffsetController.dispose();
    if (!mounted || resultConstraint == null) {
      return;
    }

    final result = await repository.setOpeningLevelConstraint(
      openingId: openingId,
      levelId: resultConstraint.levelId,
      levelOffsetMeters: resultConstraint.offset,
    );
    await _applyEngineSceneResult(
      result,
      message:
          '${prettySceneKind(object.kind)} ${scene.levelById(resultConstraint.levelId)?.name ?? 'level'} + ${resultConstraint.offset.toStringAsFixed(2)} m ga biriktirildi.',
    );
  }

  Future<void> _showEditLevelDialog(RenderSceneLevel level) async {
    final scene = _scene;
    final repository = _engineRepository;
    if (scene == null || !_engineBackedMode || repository == null) {
      setState(() {
        _editStatusMessage = 'Level edit engine-backed mode talab qiladi.';
      });
      return;
    }

    final nameController = TextEditingController(text: level.name);
    final elevationController =
        TextEditingController(text: level.elevationMeters.toStringAsFixed(2));
    final heightController = TextEditingController(
      text: level.defaultWallHeightMeters.toStringAsFixed(2),
    );

    final payload =
        await showDialog<({String name, double elevation, double wallHeight})>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit ${level.name}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                _NumericField(
                  label: 'Elevation (m)',
                  controller: elevationController,
                  onChanged: (_) {},
                ),
                _NumericField(
                  label: 'Default wall height (m)',
                  controller: heightController,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final elevation =
                    double.tryParse(elevationController.text.trim());
                final wallHeight =
                    double.tryParse(heightController.text.trim());
                if (name.isEmpty ||
                    elevation == null ||
                    wallHeight == null ||
                    wallHeight <= 0) {
                  return;
                }
                Navigator.of(context).pop((
                  name: name,
                  elevation: elevation,
                  wallHeight: wallHeight,
                ));
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );

    if (!mounted || payload == null) {
      return;
    }

    final result = await repository.updateLevel(
      levelId: level.levelId,
      name: payload.name,
      elevationMeters: payload.elevation,
      defaultWallHeightMeters: payload.wallHeight,
    );
    await _applyEngineSceneResult(
      result,
      message: '${payload.name} updated.',
    );
  }

  Future<void> _moveSelectedLevelElevation(
    RenderSceneLevel level,
    String value,
  ) async {
    final elevation = double.tryParse(value.trim());
    if (elevation == null) {
      setState(() {
        _editStatusMessage = 'Balandlik raqamini to‘g‘ri kiriting.';
      });
      return;
    }
    if ((elevation - level.elevationMeters).abs() < 0.0001) {
      return;
    }
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final result = await repository.moveLevelElevation(
        levelId: level.levelId,
        elevationMeters: elevation,
      );
      final updated = result.scene?.levelById(level.levelId);
      if (updated == null ||
          (updated.elevationMeters - elevation).abs() > 0.0001) {
        setState(() {
          _editStatusMessage =
              'Engine level elevation qaytarmadi: ${result.errors.join(' ')}';
        });
        return;
      }
      await _applyEngineSceneResult(
        result,
        message: '${level.name} elevation: ${elevation.toStringAsFixed(2)} m.',
      );
      return;
    }

    // Mac development fallback must remain editable when the native dylib is
    // unavailable; otherwise the UI accepts input but the scene can never move.
    final scene = _scene;
    if (scene == null) {
      return;
    }
    final nextScene = RenderSceneEditor.setLevelElevation(
      scene: scene,
      levelId: level.levelId,
      elevationMeters: elevation,
    );
    await _applySceneChange(
      nextScene,
      message: '${level.name} elevation: ${elevation.toStringAsFixed(2)} m.',
      authoritative: true,
    );
  }

  Future<void> _setSelectedObjectLevelLock(
    RenderSceneObject object,
    bool locked,
  ) async {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    final repository = _engineRepository;
    final elementId = object.elementId;
    if (_engineBackedMode &&
        repository != null &&
        elementId != null &&
        (object.kindKey == 'door' || object.kindKey == 'window')) {
      final result = await repository.setOpeningLevelLock(
        openingId: elementId,
        locked: locked,
      );
      await _applyEngineSceneResult(
        result,
        message: locked
            ? '${prettySceneKind(object.kind)} levelga lock qilindi.'
            : '${prettySceneKind(object.kind)} leveldan unlock qilindi.',
      );
      return;
    }
    if (_engineBackedMode && repository != null && object.kindKey == 'wall') {
      setState(() {
        _editStatusMessage =
            'Wall level lock engine mode uchun constraint inspector keyingi bosqichda ulanadi.';
      });
      return;
    }
    final nextScene = RenderSceneEditor.setElementLevelLock(
      scene: scene,
      object: object,
      locked: locked,
    );
    await _applySceneChange(
      nextScene,
      message: locked
          ? '${prettySceneKind(object.kind)} levelga lock qilindi.'
          : '${prettySceneKind(object.kind)} leveldan unlock qilindi.',
    );
  }

  Future<void> _setVisibleKinds(Set<String> kinds) async {
    setState(() {
      _visibleKinds = kinds;
      _usesProjectionDefaultVisibility = false;
      _statusMessage =
          kinds.isEmpty ? 'Showing all categories' : 'Updated category filter';
    });

    await _viewportController.setVisibleKinds(kinds);
  }

  Future<void> _selectObject(RenderSceneObject object) async {
    final id = object.elementId?.toString();

    setState(() {
      _statusMessage = id == null
          ? 'Selected ${prettySceneKind(object.kind)}'
          : 'Selected ${prettySceneKind(object.kind)} #$id';
    });

    // The interaction module may already have created a multi-selection. Keep
    // it intact while making the clicked item the active Inspector object.
    if (id == null || !_viewportController.selectedElementIds.contains(id)) {
      await _selectionController.selectObject(object);
    } else {
      await _viewportController.highlightElement(id);
    }
  }

  Future<void> _clearSelection() async {
    setState(() {
      _statusMessage = 'Selection cleared';
    });

    await _selectionController.clear();
  }

  Future<void> _selectLevel(RenderSceneLevel level) async {
    await _setActiveLevel(level.levelId);
    if (!mounted) {
      return;
    }
    setState(() {
      _statusMessage = 'Selected ${level.name}';
      _editStatusMessage =
          '${level.name}: ${level.elevationMeters.toStringAsFixed(2)} m. Inspector orqali tahrir qiling yoki level line’ni torting.';
    });
    await _selectionController.selectLevel(level.levelId);
  }

  Future<void> _setInteractionMode(RenderSceneInteractionMode mode) async {
    if (_interactionMode == mode) {
      return;
    }

    // A projection switch reloads the engine scene and intentionally resets
    // transient authoring state. Do that first, then activate the requested
    // tool so Floor/Ceiling/Roof stays active when it brings the user to plan.
    if (mode.requiresPlanProjection &&
        _projectionMode != kDefaultPlanProjectionMode) {
      await _setProjectionMode(kDefaultPlanProjectionMode);
    }

    if (mode.prefersElevationProjection &&
        _projectionMode == RenderSceneProjectionMode.isometric) {
      await _setProjectionMode(kDefaultElevationProjectionMode);
    }

    final selected = _selectedObject(_scene);

    setState(() {
      _interactionMode = mode;
      _editStatusMessage = mode == RenderSceneInteractionMode.select
          ? 'Selection mode'
          : 'Editing mode: ${mode.authoringLabel}';
      _statusMessage = _editStatusMessage;
    });

    await _viewportController.setInteractionMode(mode);
    await _clearDraft();

    if ((mode == RenderSceneInteractionMode.moveOpening ||
            mode == RenderSceneInteractionMode.addDoor ||
            mode == RenderSceneInteractionMode.addWindow) &&
        selected != null &&
        (selected.kindKey == 'door' || selected.kindKey == 'window')) {
      setState(() {
        _primeOpeningDraftFromObject(selected);
      });
    }

    if (mode == RenderSceneInteractionMode.addRoof) {
      await _prepareAutomaticFlatRoof();
    }
  }

  Future<void> _prepareAutomaticFlatRoof() async {
    final scene = _scene;
    final baseLevelId = _activeLevelId;
    if (scene == null || baseLevelId == null) {
      return;
    }
    final baseLevel = scene.levelById(baseLevelId);
    final candidates = scene.objects
        .where((object) => object.kindKey == 'wall')
        .where((object) =>
            (_metadataInt(object, 'base_level_id') ?? object.levelId) ==
            baseLevelId)
        .where((object) => object.elementId != null)
        .toList(growable: false);
    final topLevelIds = <int>{
      for (final wall in candidates)
        if ((_metadataInt(wall, 'top_level_id') ?? 0) > 0)
          _metadataInt(wall, 'top_level_id')!,
    };
    final roofLevelId = topLevelIds.isNotEmpty
        ? (topLevelIds.toList()
              ..sort((left, right) =>
                  (scene.levelById(left)?.elevationMeters ?? 0)
                      .compareTo(scene.levelById(right)?.elevationMeters ?? 0)))
            .last
        : (scene.levels
                .where((level) =>
                    baseLevel != null &&
                    level.elevationMeters > baseLevel.elevationMeters + 1e-6)
                .toList()
              ..sort((left, right) =>
                  left.elevationMeters.compareTo(right.elevationMeters)))
            .firstOrNull
            ?.levelId;
    if (roofLevelId == null) {
      setState(() {
        _editStatusMessage =
            'Automatic roof uchun wall top level yoki undan yuqori level kerak.';
      });
      return;
    }
    final boundWalls = candidates
        .where(
            (wall) => (_metadataInt(wall, 'top_level_id') ?? 0) == roofLevelId)
        .toList(growable: false);
    final polygon = RenderSceneEditor.surfacePolygonForWalls(boundWalls);
    if (polygon == null || polygon.length < 3) {
      setState(() {
        _editStatusMessage =
            'Automatic roof faqat bitta yopiq outer wall loop topilganda yaratiladi. Murakkab plan uchun wall loop tanlang yoki footprint chizing.';
      });
      return;
    }
    final existingRoof = scene.objects.any(
      (object) => object.kindKey == 'roof' && object.levelId == roofLevelId,
    );
    if (existingRoof) {
      setState(() {
        _editStatusMessage =
            'Bu roof levelda roof bor. Duplicate yaratilmadi; avval mavjud roofni tahrir qiling.';
      });
      return;
    }
    _surfaceTool
      ..drawMode = RenderSceneSurfaceDrawMode.pickWalls
      ..replaceWallIds(
        boundWalls.map((wall) => wall.elementId!).toList(growable: false),
      )
      ..replacePoints(polygon);
    setState(() {
      _activeLevelId = roofLevelId;
      _editStatusMessage =
          'Automatic roof footprint ready: ${boundWalls.length} wall, ${scene.levelById(roofLevelId)?.name ?? 'Level'}. Confirm bosing.';
    });
    _viewportController.setSurfaceDraft(
      RenderSceneSurfaceDraft(kind: 'roof', points: polygon, closed: true),
    );
  }

  void _setSurfaceDrawMode(RenderSceneSurfaceDrawMode value) {
    if (_surfaceDrawMode == value) {
      return;
    }
    setState(() {
      _surfaceDrawMode = value;
      _draftSurfaceStart = null;
      _draftSurfaceEnd = null;
      _draftSurfacePoints.clear();
      _draftSurfaceWallIds.clear();
      _editStatusMessage = switch (value) {
        RenderSceneSurfaceDrawMode.polyline =>
          'Boundary sketch: tap each corner, then Finish.',
        RenderSceneSurfaceDrawMode.rectangle =>
          'Rectangle sketch: tap two opposite corners.',
        RenderSceneSurfaceDrawMode.pickWalls =>
          'Pick Walls: tap enclosing walls, then Finish.',
        RenderSceneSurfaceDrawMode.autoRoom =>
          'Auto Room: tap a room to create the system.',
      };
    });
    _viewportController.setSurfaceDraft(null);
  }

  void _undoSurfaceDraft() {
    final scene = _scene;
    if (!_surfaceTool.undoLast()) return;
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls &&
        scene != null) {
      _syncSurfaceDraftFromWalls(scene);
    } else {
      _syncSurfaceDraftPreview();
    }
    setState(() {
      _editStatusMessage = switch (_surfaceDrawMode) {
        RenderSceneSurfaceDrawMode.polyline =>
          '${_draftSurfacePoints.length} boundary points remain.',
        RenderSceneSurfaceDrawMode.pickWalls =>
          '${_draftSurfaceWallIds.length} picked walls remain.',
        RenderSceneSurfaceDrawMode.rectangle =>
          'Rectangle cleared. Drag again to draw.',
        RenderSceneSurfaceDrawMode.autoRoom => 'Tap a room.',
      };
    });
  }

  Future<void> _clearDraft() async {
    final activeLevel = _activeLevel(_scene);
    _wallTool.reset();
    _levelTool.reset();
    _openingTool.reset();
    _surfaceTool.reset(
      levelElevation: activeLevel?.elevationMeters ?? 0.0,
      defaultHeight:
          activeLevel?.defaultWallHeightMeters ?? _defaultWallHeightMeters,
    );
    _stairTool.reset();
    _trimTool.reset();
    setState(() {
      _draftWallStart = null;
      _draftWallEnd = null;
      _draftMoveTarget = null;
      _moveAnchorPoint = null;
      _moveWallOriginalStart = null;
      _moveWallOriginalEnd = null;
      _draftMoveLevelId = null;
      _moveLevelOriginalElevation = null;
      _wallMoveMode = _WallMoveMode.translate;
    });

    _viewportController.clearDraft();
  }

  Future<void> _handleSceneTap(RenderSceneTapDetails details) async {
    final scene = _scene;
    final tappedObject = details.pickedObject;
    final pickedLevel = details.pickedLevel;
    final modelPoint = details.modelPoint;

    if (scene == null) {
      return;
    }

    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        if (pickedLevel != null && _projectionMode.isElevation) {
          await _selectLevel(pickedLevel);
          return;
        }
        if (tappedObject != null) {
          final tappedId = tappedObject.elementId?.toString();
          // Modifier selection is already resolved by ViewportInteractionController.
          // A Ctrl-click may have removed this object, so never re-add it here.
          if (tappedId != null &&
              !_viewportController.selectedElementIds.contains(tappedId)) {
            if (_viewportController.selectedElementIds.isEmpty) {
              await _clearSelection();
            } else {
              setState(() {
                _statusMessage =
                    '${_viewportController.selectedElementIds.length} objects selected';
              });
            }
            return;
          }
          if (_projectionMode.isElevation && tappedObject.levelId != null) {
            await _setActiveLevel(tappedObject.levelId);
            setState(() {
              _editStatusMessage =
                  '${prettySceneKind(tappedObject.kind)} leveli active qilindi.';
              _statusMessage = _editStatusMessage;
            });
          }
          await _selectObject(tappedObject);
          return;
        }
        if (_projectionMode.isElevation) {
          final pickedLevel = _pickLevelAtElevation(scene, modelPoint);
          if (pickedLevel != null) {
            await _selectLevel(pickedLevel);
            return;
          }
        }
        await _clearSelection();
        return;
      case RenderSceneInteractionMode.addWall:
        await _handleAddWallTap(modelPoint);
        return;
      case RenderSceneInteractionMode.addLevel:
        await _handleAddLevelTap(modelPoint);
        return;
      case RenderSceneInteractionMode.moveLevel:
        _handleMoveLevelStart(
          scene,
          modelPoint,
          pickedLevel: pickedLevel,
        );
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        await _handleOpeningTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.moveWall:
        await _handleMoveWallTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.moveOpening:
        await _handleMoveOpeningTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.trimExtend:
        await _handleTrimExtendTap(tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        await _handleSurfaceTap(scene, tappedObject, modelPoint);
        return;
      case RenderSceneInteractionMode.addStair:
        await _handleAddStairTap(modelPoint);
        return;
    }
  }

  void _handleSceneHover(RenderSceneTapDetails details) {
    final modelPoint = details.modelPoint;
    if (modelPoint == null) {
      return;
    }

    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        return;
      case RenderSceneInteractionMode.addWall:
        final start = _wallTool.start;
        if (start == null) {
          return;
        }
        final snappedPoint = _draftLinePoint(
          rawPoint: modelPoint,
          referenceStart: start,
        );
        if (_wallTool.end == snappedPoint) {
          return;
        }
        _wallTool.preview(snappedPoint);
        setState(() {
          _editStatusMessage =
              'Wall draft: ${start.distanceTo(snappedPoint).toStringAsFixed(2)} m';
        });
        _viewportController.setWallDraft(start, snappedPoint);
        return;
      case RenderSceneInteractionMode.addLevel:
        final start = _levelTool.start;
        if (start == null) {
          return;
        }
        final snappedPoint = _draftLinePoint(
          rawPoint: modelPoint,
          referenceStart: start,
        );
        if (_levelTool.end == snappedPoint) {
          return;
        }
        _levelTool.preview(snappedPoint);
        setState(() {
          _editStatusMessage =
              'Level draft: ${snappedPoint.z.toStringAsFixed(2)} m';
        });
        _viewportController.setWallDraft(start, snappedPoint);
        return;
      case RenderSceneInteractionMode.moveLevel:
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        final scene = _scene;
        if (scene == null) {
          return;
        }
        final hostWall = _resolveHostWall(scene, details.pickedObject);
        if (hostWall == null) {
          return;
        }
        _updateOpeningDraftPreview(
          scene: scene,
          hostWall: hostWall,
          point: modelPoint,
          announce: false,
        );
        return;
      case RenderSceneInteractionMode.moveWall:
        final scene = _scene;
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (scene == null ||
            target == null ||
            target.kindKey != 'wall' ||
            _moveAnchorPoint == null ||
            _moveWallOriginalStart == null ||
            _moveWallOriginalEnd == null) {
          return;
        }
        _updateMoveWallPreview(
          scene: scene,
          wall: target,
          point: modelPoint,
        );
        return;
      case RenderSceneInteractionMode.moveOpening:
        final scene = _scene;
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (scene == null ||
            target == null ||
            (target.kindKey != 'door' && target.kindKey != 'window') ||
            _moveAnchorPoint == null) {
          return;
        }
        _updateMoveOpeningPreview(
          scene: scene,
          opening: target,
          point: modelPoint,
        );
        return;
      case RenderSceneInteractionMode.trimExtend:
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls) {
          final candidate = details.pickedObject;
          if (candidate?.kindKey == 'wall' && candidate?.elementId != null) {
            unawaited(_viewportController
                .highlightElement(candidate!.elementId.toString()));
          }
          return;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom) {
          final candidate = details.pickedObject;
          if (candidate?.kindKey == 'room' && candidate?.elementId != null) {
            unawaited(_viewportController
                .highlightElement(candidate!.elementId.toString()));
          }
          return;
        }
        if (_surfaceDrawMode != RenderSceneSurfaceDrawMode.rectangle) {
          return;
        }
        final start = _draftSurfaceStart;
        if (start == null || _draftSurfaceWallIds.isNotEmpty) {
          return;
        }
        final snapped = _snapDraftToGrid ? _snapPoint(modelPoint) : modelPoint;
        if (_draftSurfaceEnd == snapped) {
          return;
        }
        setState(() {
          _draftSurfaceEnd = snapped;
          if (_draftSurfacePoints.length == 1) {
            _draftSurfacePoints.add(snapped);
          } else if (_draftSurfacePoints.length >= 2) {
            _draftSurfacePoints[1] = snapped;
          }
        });
        _syncSurfaceDraftPreview();
        return;
      case RenderSceneInteractionMode.addStair:
        final start = _stairTool.start;
        if (start == null) {
          return;
        }
        final snapped =
            _draftLinePoint(rawPoint: modelPoint, referenceStart: start);
        _stairTool.preview(snapped);
        _viewportController.setWallDraft(start, snapped);
        setState(() {
          _editStatusMessage =
              'Stair run: ${start.distanceTo(snapped).toStringAsFixed(2)} m';
        });
        return;
    }
  }

  Future<void> _handleAddWallTap(RenderScenePoint? modelPoint) async {
    if (modelPoint == null) {
      setState(() {
        _editStatusMessage = 'Tap the 2D plan to place wall endpoints.';
      });
      return;
    }

    final snappedPoint = _draftLinePoint(
      rawPoint: modelPoint,
      referenceStart: _wallTool.start,
    );

    if (!_wallTool.hasStart) {
      _wallTool.begin(snappedPoint);
      setState(() {
        _editStatusMessage =
            'Wall start set. Tap again for the end point. Ortho/snap is active.';
      });
      _viewportController.setWallDraft(snappedPoint, snappedPoint);
      return;
    }

    _wallTool.preview(snappedPoint);
    setState(() {
      _editStatusMessage =
          'Wall segment: ${_wallTool.start!.distanceTo(snappedPoint).toStringAsFixed(2)} m. Creating...';
    });
    _viewportController.setWallDraft(_wallTool.start, snappedPoint);
    await _commitWallDraft(autoContinue: true);
  }

  Future<void> _handleAddStairTap(RenderScenePoint? modelPoint) async {
    final scene = _scene;
    if (scene == null || modelPoint == null) {
      setState(() =>
          _editStatusMessage = 'Stair uchun 2D plan’da ikki nuqta qo‘ying.');
      return;
    }
    final active = _activeLevel(scene);
    final top = active == null ? null : _nextHigherLevel(scene, active.levelId);
    if (active == null || top == null) {
      setState(() => _editStatusMessage =
          'Stair uchun Base Level va undan yuqori Top Level kerak.');
      return;
    }
    final point =
        _draftLinePoint(rawPoint: modelPoint, referenceStart: _stairTool.start);
    if (!_stairTool.hasStart) {
      _stairTool.begin(point);
      _viewportController.setWallDraft(point, point);
      setState(() => _editStatusMessage =
          'Stair start set. Ikkinchi nuqta run/directionni belgilaydi.');
      return;
    }
    _stairTool.preview(point);
    _viewportController.setWallDraft(_stairTool.start, point);
    await _commitStairDraft();
  }

  Future<void> _commitStairDraft() async {
    final scene = _scene;
    final start = _stairTool.start;
    final end = _stairTool.end;
    final repository = _engineRepository;
    final base = scene == null ? null : _activeLevel(scene);
    final top = base == null || scene == null
        ? null
        : _nextHigherLevel(scene, base.levelId);
    if (scene == null ||
        start == null ||
        end == null ||
        base == null ||
        top == null) {
      return;
    }
    final run = start.distanceTo(end);
    if (run < 0.8) {
      setState(
          () => _editStatusMessage = 'Stair run kamida 0.80 m bo‘lishi kerak.');
      return;
    }
    if (!_engineBackedMode || repository == null) {
      setState(() => _editStatusMessage =
          'Stair productionda engine-backed mode talab qiladi.');
      return;
    }
    final rise = top.elevationMeters - base.elevationMeters;
    if (rise <= 0.1) {
      setState(() => _editStatusMessage =
          'Top Level Base Leveldan yuqorida bo‘lishi kerak.');
      return;
    }
    final risers = (rise / 0.175).round().clamp(1, 60);
    final result = await repository.createStair(
      baseLevelId: base.levelId,
      topLevelId: top.levelId,
      start: RenderScenePoint(x: start.x, y: start.y, z: base.elevationMeters),
      direction: RenderScenePoint(x: end.x - start.x, y: end.y - start.y, z: 0),
      widthMeters: _stairTool.widthMeters,
      totalRiseMeters: rise,
      totalRunMeters: run,
      riserCount: risers,
      treadCount: risers,
    );
    await _applyEngineSceneResult(result,
        message: 'Stair created: ${base.name} → ${top.name}.');
    final id = repository.lastCreatedElementId;
    await _clearDraft();
    if (id != null) {
      await _viewportController.selectElement(id.toString());
    }
  }

  Future<void> _handleAddLevelTap(RenderScenePoint? modelPoint) async {
    if (modelPoint == null) {
      setState(() {
        _editStatusMessage = 'Tap the elevation view to place a level line.';
      });
      return;
    }

    final snappedPoint = _draftLinePoint(
      rawPoint: modelPoint,
      referenceStart: _levelTool.start,
    );

    if (!_levelTool.hasDraft) {
      _levelTool.begin(snappedPoint);
      setState(() {
        _editStatusMessage =
            'Level elevation set. Tap again to define the line length.';
      });
      _viewportController.setWallDraft(snappedPoint, snappedPoint);
      return;
    }

    _levelTool.preview(snappedPoint);
    setState(() {
      _editStatusMessage =
          'Level line ready at ${snappedPoint.z.toStringAsFixed(2)} m. Creating level...';
    });
    _viewportController.setWallDraft(_levelTool.start, snappedPoint);
    await _commitLevelDraft();
  }

  Future<void> _commitWallDraft({required bool autoContinue}) async {
    final scene = _scene;
    final start = _wallTool.start;
    final end = _wallTool.end;
    if (scene == null || start == null || end == null) {
      return;
    }

    final length = start.distanceTo(end);
    if (length < 0.1) {
      setState(() {
        _editStatusMessage = 'Wall is too short.';
      });
      return;
    }

    final activeLevelId = _activeLevel(scene)?.levelId;
    final baseElevation = _activeLevelElevation(scene);
    final wallHeight = _activeLevelDefaultWallHeight(scene);
    final topLevel =
        activeLevelId == null ? null : _nextHigherLevel(scene, activeLevelId);
    _traceAndroidMutation(
      'wall commit: start=${start.x.toStringAsFixed(2)},${start.y.toStringAsFixed(2)} '
      'end=${end.x.toStringAsFixed(2)},${end.y.toStringAsFixed(2)} '
      'base=$activeLevelId top=${topLevel?.levelId} sceneWalls=${scene.kindCounts['wall'] ?? 0}',
    );
    if (activeLevelId == null || topLevel == null) {
      setState(() {
        _editStatusMessage = activeLevelId == null
            ? 'Wall chizish uchun Base Level tanlang.'
            : 'Wall chizish uchun ${_activeLevel(scene)?.name}dan yuqori Top Level kerak.';
      });
      return;
    }
    final mutation = SceneMutationService(
      engineRepository: _engineBackedMode ? _engineRepository : null,
    );
    final outcome = await mutation.createWall(
      CreateWallRequest(
        scene: scene,
        start: RenderScenePoint(x: start.x, y: start.y, z: baseElevation),
        end: RenderScenePoint(x: end.x, y: end.y, z: baseElevation),
        baseLevelId: activeLevelId,
        topLevelId: topLevel.levelId,
        heightMeters: wallHeight,
        thicknessMeters: _defaultWallThicknessMeters,
      ),
    );
    for (final entry in outcome.trace) {
      _traceAndroidMutation(entry);
    }
    if (!outcome.success || outcome.scene == null) {
      setState(() {
        _editStatusMessage = outcome.error ?? 'Wall yaratilmadi.';
      });
      return;
    }
    await _applySceneChange(
      outcome.scene!,
      message: 'Wall created and constrained to ${topLevel.name}.',
      authoritative: true,
    );
    if (outcome.createdElementId != null) {
      await _viewportController
          .selectElement(outcome.createdElementId.toString());
      await _viewportController
          .highlightElement(outcome.createdElementId.toString());
    }

    if (autoContinue) {
      _wallTool.continueFrom(end);
      setState(() {
        _editStatusMessage =
            'Wall created. Tap next point to continue, or Cancel to stop.';
      });
      _viewportController.setWallDraft(end, end);
    } else {
      await _clearDraft();
      setState(() {
        _editStatusMessage = 'Wall created.';
      });
    }
  }

  Future<void> _commitLevelDraft() async {
    final scene = _scene;
    final start = _levelTool.start;
    final end = _levelTool.end;
    if (scene == null || start == null || end == null) {
      return;
    }

    final elevation = end.z;
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final result = await repository.createLevel(
        name: 'Level ${scene.levels.length + 1}',
        elevationMeters: elevation,
        defaultWallHeightMeters: _activeLevelDefaultWallHeight(scene),
      );
      await _applyEngineSceneResult(
        result,
        message: 'Level created at ${elevation.toStringAsFixed(2)} m.',
      );
      await _clearDraft();
      return;
    }
    final nextIndex = scene.levels.length + 1;
    final nextScene = RenderSceneEditor.createLevel(
      scene: scene,
      name: 'Level $nextIndex',
      elevationMeters: elevation,
      defaultWallHeightMeters: _activeLevelDefaultWallHeight(scene),
    );
    await _applySceneChange(
      nextScene,
      message: 'Level created at ${elevation.toStringAsFixed(2)} m.',
    );
    await _clearDraft();
  }

  Future<void> _handleOpeningTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    final hostWall = _resolveHostWall(scene, tappedObject);
    if (hostWall == null) {
      setState(() {
        _editStatusMessage = 'Click a wall to place opening.';
        _draftHostWall = null;
      });
      return;
    }

    final point = modelPoint ?? RenderSceneEditor.wallCenterPoint(hostWall);
    if (point == null) {
      setState(() {
        _editStatusMessage = 'Unable to resolve opening offset on this wall.';
      });
      return;
    }
    _updateOpeningDraftPreview(
      scene: scene,
      hostWall: hostWall,
      point: point,
      announce: true,
    );

    final openingDraft = _viewportController.draftOpening;
    if (openingDraft != null && openingDraft.valid) {
      await _commitOpeningDraft(scene, hostWall);
    }
  }

  Future<void> _handleMoveWallTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    final selected = _selectedObject(scene);
    final wall = tappedObject?.kindKey == 'wall'
        ? tappedObject
        : (selected?.kindKey == 'wall' ? selected : null);
    if (wall == null) {
      setState(() {
        _editStatusMessage = 'Move wall uchun avval devorni tanlang.';
      });
      return;
    }
    if (_draftMoveTarget?.elementId != wall.elementId) {
      await _selectObject(wall);
    }
    if (_moveAnchorPoint == null) {
      final start = RenderSceneEditor.wallStartPoint(wall);
      final end = RenderSceneEditor.wallEndPoint(wall);
      final anchor = modelPoint ?? RenderSceneEditor.wallCenterPoint(wall);
      if (start == null || end == null || anchor == null) {
        return;
      }
      final startDistance = anchor.distanceTo(start);
      final endDistance = anchor.distanceTo(end);
      var moveMode = _WallMoveMode.translate;
      if (startDistance <= 0.45 && startDistance <= endDistance) {
        moveMode = _WallMoveMode.startHandle;
      } else if (endDistance <= 0.45 && endDistance < startDistance) {
        moveMode = _WallMoveMode.endHandle;
      }
      setState(() {
        _draftMoveTarget = wall;
        _moveAnchorPoint = moveMode == _WallMoveMode.translate
            ? anchor
            : (moveMode == _WallMoveMode.startHandle ? start : end);
        _moveWallOriginalStart = start;
        _moveWallOriginalEnd = end;
        _wallMoveMode = moveMode;
        _draftWallStart = start;
        _draftWallEnd = end;
        _editStatusMessage = moveMode == _WallMoveMode.translate
            ? 'Wall move preview boshlandi. Devorni torting.'
            : 'Wall endpoint preview boshlandi. Uchini torting.';
      });
      _viewportController.setWallDraft(start, end);
      return;
    }

    if (_draftCanConfirm) {
      await _confirmDraft();
    }
  }

  void _handleMoveLevelStart(
    RenderScene scene,
    RenderScenePoint? modelPoint, {
    RenderSceneLevel? pickedLevel,
  }) {
    if (!_projectionMode.isElevation) {
      setState(() {
        _editStatusMessage = 'Move level faqat elevation view’da ishlaydi.';
      });
      return;
    }
    final level = pickedLevel ??
        _pickLevelAtElevation(scene, modelPoint) ??
        _activeLevel(scene);
    if (level == null || modelPoint == null) {
      return;
    }
    if (pickedLevel == null &&
        (modelPoint.z - level.elevationMeters).abs() > 0.8) {
      setState(() {
        _editStatusMessage =
            'Level line yaqinidan ushlab suring. Active level: ${level.name}.';
      });
      return;
    }
    final preview =
        _levelDraftEndpointsForElevation(scene, level.elevationMeters);
    setState(() {
      _draftMoveLevelId = level.levelId;
      _moveLevelOriginalElevation = level.elevationMeters;
      _moveAnchorPoint = modelPoint;
      _draftWallStart = preview.$1;
      _draftWallEnd = preview.$2;
      _editStatusMessage =
          '${level.name} move preview boshlandi (${level.elevationMeters.toStringAsFixed(2)} m).';
    });
    _viewportController.setWallDraft(preview.$1, preview.$2);
  }

  (RenderScenePoint, RenderScenePoint) _levelDraftEndpointsForElevation(
    RenderScene scene,
    double elevation,
  ) {
    final bounds = scene.bounds;
    final descriptor = _projectionMode.planarDescriptor;
    if (descriptor == null || !descriptor.isElevation) {
      return (
        RenderScenePoint(
            x: bounds.min.x - 1.0, y: bounds.center.y, z: elevation),
        RenderScenePoint(
            x: bounds.max.x + 1.0, y: bounds.center.y, z: elevation),
      );
    }
    final horizontalMin =
        descriptor.minAxis(bounds, descriptor.horizontalAxis) - 1.0;
    final horizontalMax =
        descriptor.maxAxis(bounds, descriptor.horizontalAxis) + 1.0;
    return (
      descriptor.pointOnPlane(
        bounds: bounds,
        horizontalValue: horizontalMin,
        verticalValue: elevation,
      ),
      descriptor.pointOnPlane(
        bounds: bounds,
        horizontalValue: horizontalMax,
        verticalValue: elevation,
      ),
    );
  }

  void _updateMoveLevelPreview({
    required RenderScene scene,
    required RenderScenePoint point,
  }) {
    final levelId = _draftMoveLevelId;
    final originalElevation = _moveLevelOriginalElevation;
    if (levelId == null || originalElevation == null) {
      return;
    }
    final nextElevation = _snapDouble(point.z, 0.1);
    final preview = _levelDraftEndpointsForElevation(scene, nextElevation);
    setState(() {
      _draftWallStart = preview.$1;
      _draftWallEnd = preview.$2;
      _editStatusMessage =
          'Level move preview: ${nextElevation.toStringAsFixed(2)} m';
    });
    _viewportController.setWallDraft(preview.$1, preview.$2);
  }

  Future<void> _handleMoveOpeningTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    final selected = _selectedObject(scene);
    final opening = (tappedObject != null &&
            (tappedObject.kindKey == 'door' ||
                tappedObject.kindKey == 'window'))
        ? tappedObject
        : ((selected != null &&
                (selected.kindKey == 'door' || selected.kindKey == 'window'))
            ? selected
            : null);
    if (opening == null) {
      setState(() {
        _editStatusMessage = 'Move opening uchun door yoki window tanlang.';
      });
      return;
    }
    if (_draftMoveTarget?.elementId != opening.elementId) {
      await _selectObject(opening);
    }
    final hostWallId = _metadataInt(opening, 'host_wall_id');
    final hostWall = hostWallId == null ? null : scene.objectById(hostWallId);
    if (hostWall == null || hostWall.kindKey != 'wall') {
      setState(() {
        _editStatusMessage = 'Opening host wall topilmadi.';
      });
      return;
    }

    if (_moveAnchorPoint == null) {
      _primeOpeningDraftFromObject(opening);
      final anchor = modelPoint ??
          RenderSceneEditor.openingCenterPoint(
            hostWall: hostWall,
            offsetMeters: _draftOpeningOffsetMeters,
          );
      if (anchor == null) {
        return;
      }
      setState(() {
        _draftMoveTarget = opening;
        _draftHostWall = hostWall;
        _moveAnchorPoint = anchor;
        _editStatusMessage =
            'Opening move preview boshlandi. Kursorni devor bo‘ylab suring va Confirm bosing.';
      });
      _syncOpeningDraft();
      return;
    }

    if (_draftCanConfirm) {
      await _confirmDraft();
    }
  }

  void _updateMoveWallPreview({
    required RenderScene scene,
    required RenderSceneObject wall,
    required RenderScenePoint point,
  }) {
    final anchor = _moveAnchorPoint;
    final originalStart = _moveWallOriginalStart;
    final originalEnd = _moveWallOriginalEnd;
    if (anchor == null || originalStart == null || originalEnd == null) {
      return;
    }
    RenderScenePoint nextStart;
    RenderScenePoint nextEnd;
    if (_wallMoveMode == _WallMoveMode.translate) {
      final delta = point - anchor;
      nextStart = RenderScenePoint(
        x: originalStart.x + delta.x,
        y: originalStart.y + delta.y,
        z: originalStart.z,
      );
      nextEnd = RenderScenePoint(
        x: originalEnd.x + delta.x,
        y: originalEnd.y + delta.y,
        z: originalEnd.z,
      );
      nextStart = _snapMovedWallPoint(scene, wall, nextStart, originalStart);
      nextEnd = _snapMovedWallPoint(scene, wall, nextEnd, originalEnd);
    } else if (_wallMoveMode == _WallMoveMode.startHandle) {
      nextStart = _draftLinePoint(rawPoint: point, referenceStart: originalEnd);
      nextStart = _snapMovedWallPoint(scene, wall, nextStart, originalStart);
      nextEnd = originalEnd;
    } else {
      nextStart = originalStart;
      nextEnd = _draftLinePoint(rawPoint: point, referenceStart: originalStart);
      nextEnd = _snapMovedWallPoint(scene, wall, nextEnd, originalEnd);
    }
    setState(() {
      _draftWallStart = nextStart;
      _draftWallEnd = nextEnd;
      _editStatusMessage = _wallMoveMode == _WallMoveMode.translate
          ? 'Wall move preview: ${(nextEnd - nextStart).distanceTo(const RenderScenePoint(x: 0, y: 0, z: 0)).toStringAsFixed(2)} m'
          : 'Wall reshape preview: ${(nextEnd - nextStart).distanceTo(const RenderScenePoint(x: 0, y: 0, z: 0)).toStringAsFixed(2)} m';
    });
    _viewportController.setWallDraft(nextStart, nextEnd);
  }

  void _updateMoveOpeningPreview({
    required RenderScene scene,
    required RenderSceneObject opening,
    required RenderScenePoint point,
  }) {
    final hostWall = _draftHostWall;
    if (hostWall == null) {
      return;
    }
    _updateOpeningDraftPreview(
      scene: scene,
      hostWall: hostWall,
      point: point,
      announce: false,
    );
    setState(() {
      _editStatusMessage = 'Opening move preview tayyor.';
    });
  }

  void _updateOpeningDraftPreview({
    required RenderScene scene,
    required RenderSceneObject hostWall,
    required RenderScenePoint point,
    required bool announce,
  }) {
    final snappedPoint = _snapDraftToGrid ? _snapPoint(point) : point;
    final offset = RenderSceneEditor.wallOffsetMeters(hostWall, snappedPoint);
    if (offset == null) {
      if (announce) {
        setState(() {
          _editStatusMessage = 'Unable to compute wall-local offset.';
        });
      }
      return;
    }

    final wallLength = RenderSceneEditor.wallLength(hostWall) ?? 0.0;
    final halfWidth = _openingWidthHalf;
    final valid = offset >= halfWidth && offset <= wallLength - halfWidth;
    final kind = _interactionMode == RenderSceneInteractionMode.addDoor
        ? 'Door'
        : 'Window';
    final snappedOffset = _snapDraftToGrid ? _snapDouble(offset, 0.25) : offset;
    final sameWall = _draftHostWall?.elementId == hostWall.elementId;
    final sameOffset = (_draftOpeningOffsetMeters - snappedOffset).abs() < 1e-6;
    if (!announce && sameWall && sameOffset) {
      return;
    }

    setState(() {
      _draftHostWall = hostWall;
      _draftOpeningOffsetMeters = snappedOffset;
      if (announce) {
        _editStatusMessage = valid
            ? '$kind preview on wall #${hostWall.elementId}'
            : '$kind is near wall edge.';
      }
    });

    _viewportController.setOpeningDraft(
      RenderSceneOpeningDraft(
        kind: kind,
        hostWallId: hostWall.elementId,
        offsetMeters: snappedOffset,
        widthMeters: _draftOpeningWidthMeters,
        heightMeters: _draftOpeningHeightMeters,
        sillHeightMeters: _draftOpeningSillHeightMeters,
        valid: valid,
        message:
            valid ? 'Ready to create $kind.' : 'Adjust the offset or width.',
      ),
    );
  }

  Future<void> _handleTrimExtendTap(
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    if (tappedObject == null || tappedObject.kindKey != 'wall') {
      setState(() {
        _editStatusMessage =
            'Trim / Extend uchun wallni, o‘zgartirmoqchi bo‘lgan uchiga yaqin joyidan bosing.';
      });
      return;
    }
    final start = RenderSceneEditor.wallStartPoint(tappedObject);
    final end = RenderSceneEditor.wallEndPoint(tappedObject);
    if (start == null || end == null || tappedObject.elementId == null) {
      setState(() {
        _editStatusMessage =
            'Tanlangan wallning tahrir qilinadigan axis geometriyasi yo‘q.';
      });
      return;
    }
    final touchPoint =
        modelPoint ?? RenderSceneEditor.wallCenterPoint(tappedObject) ?? start;
    _trimTool.selectWall(
      wall: tappedObject,
      axis: PlanSketchLine(start: start, end: end),
      touchPoint: touchPoint,
    );
    await _selectObject(tappedObject);
    await _viewportController
        .highlightElement(tappedObject.elementId!.toString());
    if (!mounted) return;
    setState(() {
      _editStatusMessage = _trimTool.message;
      _statusMessage = _trimTool.message;
    });
  }

  Future<void> _commitTrimExtend() async {
    final first = _trimTool.first;
    final second = _trimTool.second;
    final preview = _trimTool.preview;
    final firstId = first?.wall.elementId;
    final secondId = second?.wall.elementId;
    if (first == null ||
        second == null ||
        preview == null ||
        firstId == null ||
        secondId == null) {
      setState(() {
        _editStatusMessage =
            'Avval ikkita wallni ularning trim/extend qilinadigan uchidan tanlang.';
      });
      return;
    }
    if (!_engineBackedMode || _engineRepository == null) {
      setState(() {
        _editStatusMessage =
            'Trim / Extend productionda engine-backed transaction talab qiladi.';
      });
      return;
    }
    try {
      final result = await _authoringCommands.trimExtendWalls(
        firstWallId: firstId,
        firstUsesStart: first.endpoint == PlanSketchEndpoint.start,
        secondWallId: secondId,
        secondUsesStart: second.endpoint == PlanSketchEndpoint.start,
      );
      await _applyEngineSceneResult(
        result,
        message: 'Walls trimmed/extended and auto-joined.',
      );
      await _clearDraft();
      await _viewportController.selectElement(firstId.toString());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _editStatusMessage = 'Trim / Extend failed: $error';
      });
    }
  }

  Future<void> _handleSurfaceTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom &&
        tappedObject?.kindKey == 'room' &&
        _surfaceSupportsRoomAutoPick) {
      final room = tappedObject!;
      final repository = _engineRepository;
      if (_engineBackedMode &&
          repository != null &&
          room.elementId != null &&
          _activeLevelId != null) {
        final assemblyId = repository.defaultAssemblyId(
          _interactionMode == RenderSceneInteractionMode.addFloor
              ? 'Floor'
              : 'Ceiling',
        );
        if (assemblyId == null) {
          setState(() {
            _editStatusMessage =
                'Engine project assembly topilmadi for ${_surfaceKindLabel()}.';
          });
          return;
        }
        final result = _interactionMode == RenderSceneInteractionMode.addFloor
            ? await repository.createFloorSystemForRoom(
                roomId: room.elementId!,
                assemblyId: assemblyId,
              )
            : await repository.createCeilingSystemForRoom(
                roomId: room.elementId!,
                assemblyId: assemblyId,
                heightOffsetMeters: _draftCeilingHeightOffsetMeters,
              );
        await _applyEngineSceneResult(
          result,
          message:
              '${_surfaceKindLabel()} created for room #${room.elementId}.',
        );
      } else {
        final nextScene =
            _interactionMode == RenderSceneInteractionMode.addFloor
                ? RenderSceneEditor.addFloorForRoom(
                    scene: scene,
                    room: room,
                    thicknessMeters: _draftSurfaceThicknessMeters,
                    topElevationMeters: _draftFloorTopElevationMeters,
                    levelId: room.levelId ?? _activeLevelId,
                  )
                : RenderSceneEditor.addCeilingForRoom(
                    scene: scene,
                    room: room,
                    thicknessMeters: _draftSurfaceThicknessMeters,
                    heightMeters: _draftCeilingHeightOffsetMeters,
                    levelId: room.levelId ?? _activeLevelId,
                  );
        await _applySceneChange(
          nextScene,
          message:
              '${_surfaceKindLabel()} created for room #${room.elementId}.',
        );
        final created =
            nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
        if (created != null) {
          await _viewportController
              .selectElement(created.elementId?.toString());
          await _viewportController.highlightElement(
            created.elementId?.toString(),
          );
        }
      }
      await _clearDraft();
      return;
    }

    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls &&
        tappedObject != null &&
        tappedObject.kindKey == 'wall') {
      final wallId = tappedObject.elementId;
      if (wallId != null) {
        setState(() {
          if (_draftSurfaceWallIds.contains(wallId)) {
            _draftSurfaceWallIds.remove(wallId);
          } else {
            _draftSurfaceWallIds.add(wallId);
          }
          _draftSurfacePoints.clear();
          _editStatusMessage =
              '${_draftSurfaceWallIds.length} wall selected for ${_surfaceKindLabel()} boundary.';
        });
        await _selectObject(tappedObject);
        _syncSurfaceDraftFromWalls(scene);
        return;
      }
    }

    if (modelPoint == null) {
      setState(() {
        _editStatusMessage =
            'Tap plan area to draw ${_surfaceKindLabel()} boundary.';
      });
      return;
    }

    final snapped = _surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline
        ? _draftLinePoint(
            rawPoint: modelPoint,
            referenceStart: _draftSurfacePoints.lastOrNull,
          )
        : (_snapDraftToGrid ? _snapPoint(modelPoint) : modelPoint);
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
      final first = _draftSurfacePoints.firstOrNull;
      if (first != null &&
          _draftSurfacePoints.length >= 3 &&
          PlanSketchGeometry.planDistance(first, snapped) <=
              PlanSketchGeometry.defaultEndpointToleranceMeters) {
        setState(() {
          _draftSurfaceEnd = first;
          _editStatusMessage = 'Boundary closed. Creating...';
        });
        _syncSurfaceDraftPreview();
        await _confirmDraft();
        return;
      }
      final previous = _draftSurfacePoints.lastOrNull;
      if (previous != null &&
          PlanSketchGeometry.planDistance(previous, snapped) <
              PlanSketchGeometry.minimumSegmentMeters) {
        return;
      }
      setState(() {
        _draftSurfaceWallIds.clear();
        _draftSurfacePoints.add(snapped);
        _draftSurfaceStart ??= snapped;
        _draftSurfaceEnd = snapped;
        _editStatusMessage = _draftSurfacePoints.length < 3
            ? 'Polyline draft point ${_draftSurfacePoints.length} added. Add more points.'
            : 'Polyline draft ready. Confirm to create ${_surfaceKindLabel()}.';
      });
      _syncSurfaceDraftPreview();
      return;
    }

    if (_draftSurfaceStart == null) {
      setState(() {
        _draftSurfaceStart = snapped;
        _draftSurfaceEnd = snapped;
        _draftSurfacePoints
          ..clear()
          ..add(snapped);
        _draftSurfaceWallIds.clear();
        _editStatusMessage =
            '${_surfaceKindLabel()} draft start set. Tap opposite corner to finish rectangle.';
      });
      _syncSurfaceDraftPreview();
      return;
    }

    setState(() {
      _draftSurfaceEnd = snapped;
      if (_draftSurfacePoints.length == 1) {
        _draftSurfacePoints.add(snapped);
      } else {
        _draftSurfacePoints[1] = snapped;
      }
      _editStatusMessage = '${_surfaceKindLabel()} rectangle ready.';
    });
    _syncSurfaceDraftPreview();
    await _confirmDraft();
  }

  double get _openingWidthHalf => _draftOpeningWidthMeters * 0.5;

  String _surfaceKindKey() {
    return switch (_interactionMode) {
      RenderSceneInteractionMode.addFloor => 'floor',
      RenderSceneInteractionMode.addCeiling => 'ceiling',
      RenderSceneInteractionMode.addRoof => 'roof',
      _ => 'surface',
    };
  }

  String _surfaceKindLabel() {
    return switch (_interactionMode) {
      RenderSceneInteractionMode.addFloor => 'floor',
      RenderSceneInteractionMode.addCeiling => 'ceiling',
      RenderSceneInteractionMode.addRoof => 'roof',
      _ => 'surface',
    };
  }

  int _surfaceTargetKind() {
    return switch (_interactionMode) {
      RenderSceneInteractionMode.addFloor => 1,
      RenderSceneInteractionMode.addCeiling => 2,
      RenderSceneInteractionMode.addRoof => 3,
      _ => 1,
    };
  }

  bool get _surfaceSupportsRoomAutoPick =>
      _interactionMode == RenderSceneInteractionMode.addFloor ||
      _interactionMode == RenderSceneInteractionMode.addCeiling;

  void _syncSurfaceDraftPreview() {
    final kind = _surfaceKindKey();
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls &&
        _draftSurfaceStart != null &&
        _draftSurfaceEnd != null) {
      _viewportController.setSurfaceDraft(
        RenderSceneSurfaceDraft(
          kind: kind,
          points: PlanSketchGeometry.rectangle(
            _draftSurfaceStart!,
            _draftSurfaceEnd!,
          ),
        ),
      );
      return;
    }
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.rectangle &&
        _draftSurfaceStart != null &&
        _draftSurfaceEnd != null) {
      _viewportController.setSurfaceDraft(
        RenderSceneSurfaceDraft(
          kind: kind,
          points: PlanSketchGeometry.rectangle(
            _draftSurfaceStart!,
            _draftSurfaceEnd!,
          ),
        ),
      );
      return;
    }
    if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline &&
        _draftSurfacePoints.isNotEmpty) {
      _viewportController.setSurfaceDraft(
        RenderSceneSurfaceDraft(
          kind: kind,
          points: List<RenderScenePoint>.from(_draftSurfacePoints),
          closed: _draftSurfacePoints.length >= 3,
        ),
      );
      return;
    }
    _viewportController.setSurfaceDraft(null);
  }

  List<RenderScenePoint> _surfaceProfilePointsForCommit() {
    switch (_surfaceDrawMode) {
      case RenderSceneSurfaceDrawMode.rectangle:
        final start = _draftSurfaceStart;
        final end = _draftSurfaceEnd;
        if (start == null || end == null) {
          return const <RenderScenePoint>[];
        }
        return <RenderScenePoint>[start, end];
      case RenderSceneSurfaceDrawMode.polyline:
        return List<RenderScenePoint>.from(_draftSurfacePoints);
      case RenderSceneSurfaceDrawMode.pickWalls:
      case RenderSceneSurfaceDrawMode.autoRoom:
        return const <RenderScenePoint>[];
    }
  }

  RenderSceneObject? _resolveHostWall(
    RenderScene scene,
    RenderSceneObject? tappedObject,
  ) {
    if (tappedObject != null && tappedObject.kindKey == 'wall') {
      return tappedObject;
    }

    final selected = _selectedObject(scene);
    if (selected != null && selected.kindKey == 'wall') {
      return selected;
    }

    return _draftHostWall;
  }

  RenderScenePoint _snapPoint(RenderScenePoint point, [double step = 0.25]) {
    if (!_snapDraftToGrid || step <= 0) {
      return point;
    }
    return PlanSketchGeometry.snapToGrid(point, stepMeters: step);
  }

  RenderScenePoint _draftLinePoint({
    required RenderScenePoint rawPoint,
    required RenderScenePoint? referenceStart,
  }) {
    final scene = _scene;
    return PlanSketchGeometry.resolveLineEndpoint(
      rawPoint: rawPoint,
      referenceStart: referenceStart,
      candidatePoints: scene == null
          ? const <RenderScenePoint>[]
          : RenderSceneEditor.wallSnapPoints(scene),
      useGridSnap: _snapDraftToGrid,
      lockElevationAxis: _projectionMode.isElevation,
      snapVertical: _projectionMode.isElevation,
    );
  }

  RenderScenePoint _snapMovedWallPoint(
    RenderScene scene,
    RenderSceneObject wall,
    RenderScenePoint point,
    RenderScenePoint originalPoint, {
    double toleranceMeters = 0.45,
  }) {
    if (!_snapDraftToGrid) {
      return point;
    }
    RenderScenePoint bestPoint = _snapPoint(point);
    var bestDistance = toleranceMeters;
    for (final object in scene.objects) {
      if (object.kindKey != 'wall' || object.elementId == wall.elementId) {
        continue;
      }
      for (final candidate in <RenderScenePoint?>[
        RenderSceneEditor.wallStartPoint(object),
        RenderSceneEditor.wallEndPoint(object),
      ]) {
        if (candidate == null) {
          continue;
        }
        final distance = candidate.distanceTo(point);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestPoint = candidate;
        }
      }
    }
    return RenderScenePoint(x: bestPoint.x, y: bestPoint.y, z: originalPoint.z);
  }

  double _snapDouble(double value, double step) {
    if (!_snapDraftToGrid || step <= 0) {
      return value;
    }
    return (value / step).roundToDouble() * step;
  }

  bool get _draftCanConfirm {
    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        return false;
      case RenderSceneInteractionMode.addWall:
        return _wallTool.hasStart;
      case RenderSceneInteractionMode.addLevel:
        return _levelTool.hasDraft;
      case RenderSceneInteractionMode.moveLevel:
        return _draftMoveLevelId != null &&
            _draftWallStart != null &&
            _draftWallEnd != null;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
      case RenderSceneInteractionMode.moveOpening:
        final openingDraft = _viewportController.draftOpening;
        final selectedWall = _selectedObject(_scene)?.kindKey == 'wall';
        final selectedOpening = _selectedObject(_scene)?.kindKey == 'door' ||
            _selectedObject(_scene)?.kindKey == 'window';
        return openingDraft != null &&
            openingDraft.valid &&
            (_draftHostWall != null || selectedWall || selectedOpening);
      case RenderSceneInteractionMode.moveWall:
        final start = _draftWallStart;
        final end = _draftWallEnd;
        final target = _draftMoveTarget ?? _selectedObject(_scene);
        return target?.kindKey == 'wall' && start != null && end != null;
      case RenderSceneInteractionMode.trimExtend:
        return _trimTool.isReady;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.pickWalls) {
          return _draftSurfaceWallIds.length >= 3;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline) {
          return _draftSurfacePoints.length >= 3;
        }
        if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom) {
          return false;
        }
        if (_draftSurfaceWallIds.length >= 3) {
          return true;
        }
        final start = _draftSurfaceStart;
        final end = _draftSurfaceEnd;
        if (start == null || end == null) {
          return false;
        }
        final width = (end.x - start.x).abs();
        final depth = (end.y - start.y).abs();
        return width >= 0.1 && depth >= 0.1;
      case RenderSceneInteractionMode.addStair:
        return _stairTool.hasRun;
    }
  }

  Future<void> _confirmDraft() async {
    final scene = _scene;
    if (scene == null) {
      return;
    }

    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        return;
      case RenderSceneInteractionMode.addWall:
        await _clearDraft();
        await _setInteractionMode(RenderSceneInteractionMode.select);
        setState(() {
          _editStatusMessage = 'Wall chizish tugatildi.';
        });
        return;
      case RenderSceneInteractionMode.addLevel:
        await _commitLevelDraft();
        return;
      case RenderSceneInteractionMode.addStair:
        await _commitStairDraft();
        return;
      case RenderSceneInteractionMode.moveLevel:
        final sceneLevel = _scene;
        final levelId = _draftMoveLevelId;
        final end = _draftWallEnd;
        if (sceneLevel == null || levelId == null || end == null) {
          setState(() {
            _editStatusMessage = 'Move level preview tayyor emas.';
          });
          return;
        }
        final repository = _engineRepository;
        if (_engineBackedMode && repository != null) {
          final result = await repository.moveLevelElevation(
            levelId: levelId,
            elevationMeters: end.z,
          );
          await _applyEngineSceneResult(
            result,
            message:
                'Level elevation updated to ${end.z.toStringAsFixed(2)} m.',
          );
        } else {
          final nextScene = RenderSceneEditor.setLevelElevation(
            scene: sceneLevel,
            levelId: levelId,
            elevationMeters: end.z,
          );
          await _applySceneChange(
            nextScene,
            message:
                'Level elevation updated to ${end.z.toStringAsFixed(2)} m.',
          );
        }
        await _clearDraft();
        return;
      case RenderSceneInteractionMode.addDoor:
      case RenderSceneInteractionMode.addWindow:
        final hostWall = _draftHostWall ?? _selectedObject(scene);
        if (hostWall == null || hostWall.kindKey != 'wall') {
          setState(() {
            _editStatusMessage = 'Select a wall first.';
          });
          return;
        }
        await _commitOpeningDraft(scene, hostWall);
        return;
      case RenderSceneInteractionMode.moveWall:
        final wall = _draftMoveTarget ?? _selectedObject(scene);
        final start = _draftWallStart;
        final end = _draftWallEnd;
        if (wall == null ||
            wall.kindKey != 'wall' ||
            start == null ||
            end == null) {
          setState(() {
            _editStatusMessage = 'Move wall preview tayyor emas.';
          });
          return;
        }
        final repository = _engineRepository;
        if (_engineBackedMode && repository != null && wall.elementId != null) {
          final result = await repository.setWallAxis(
            wallId: wall.elementId!,
            start: start,
            end: end,
          );
          await _applyEngineSceneResult(result, message: 'Wall moved.');
        } else {
          final nextScene = RenderSceneEditor.setWallAxis(
            scene: scene,
            wall: wall,
            start: start,
            end: end,
          );
          await _applySceneChange(nextScene, message: 'Wall moved.');
        }
        await _clearDraft();
        return;
      case RenderSceneInteractionMode.moveOpening:
        final opening = _draftMoveTarget ?? _selectedObject(scene);
        if (opening == null ||
            (opening.kindKey != 'door' && opening.kindKey != 'window')) {
          setState(() {
            _editStatusMessage = 'Move opening preview tayyor emas.';
          });
          return;
        }
        final repository = _engineRepository;
        if (_engineBackedMode &&
            repository != null &&
            opening.elementId != null) {
          var result = await repository.moveHostedOpening(
            openingId: opening.elementId!,
            offsetMeters: _draftOpeningOffsetMeters,
          );
          result = await repository.resizeOpening(
            openingId: opening.elementId!,
            kind: opening.kindKey,
            widthMeters: _draftOpeningWidthMeters,
            heightMeters: _draftOpeningHeightMeters,
            sillHeightMeters: _draftOpeningSillHeightMeters,
          );
          await _applyEngineSceneResult(
            result,
            message: '${prettySceneKind(opening.kind)} moved.',
          );
        } else {
          final nextScene = RenderSceneEditor.moveOpening(
            scene: scene,
            opening: opening,
            offsetMeters: _draftOpeningOffsetMeters,
          );
          await _applySceneChange(
            nextScene,
            message: '${prettySceneKind(opening.kind)} moved.',
          );
        }
        await _clearDraft();
        return;
      case RenderSceneInteractionMode.trimExtend:
        await _commitTrimExtend();
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        final repository = _engineRepository;
        if (_engineBackedMode && repository != null && _activeLevelId != null) {
          final targetKind = _surfaceTargetKind();
          final assemblyId =
              _interactionMode == RenderSceneInteractionMode.addRoof
                  ? 0
                  : repository.defaultAssemblyId(
                      _interactionMode == RenderSceneInteractionMode.addFloor
                          ? 'Floor'
                          : 'Ceiling',
                    );
          if (_interactionMode != RenderSceneInteractionMode.addRoof &&
              assemblyId == null) {
            setState(() {
              _editStatusMessage =
                  'Engine project assembly topilmadi for ${_surfaceKindLabel()}.';
            });
            return;
          }
          if (_surfaceDrawMode == RenderSceneSurfaceDrawMode.autoRoom) {
            setState(() {
              _editStatusMessage =
                  'Tap a room to create ${_surfaceKindLabel()} automatically.';
            });
            return;
          }
          final result = _surfaceDrawMode ==
                  RenderSceneSurfaceDrawMode.pickWalls
              ? await repository.createProfile(
                  targetKind: targetKind,
                  draftMode: 2,
                  levelId: _activeLevelId!,
                  points: const <RenderScenePoint>[],
                  wallIds: _draftSurfaceWallIds.toList(growable: false),
                  closed: true,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  heightMeters: _draftSurfaceHeightMeters,
                  verticalOffsetMeters:
                      _interactionMode == RenderSceneInteractionMode.addFloor
                          ? _draftFloorTopElevationMeters
                          : _interactionMode ==
                                  RenderSceneInteractionMode.addCeiling
                              ? _draftCeilingHeightOffsetMeters
                              : 0.0,
                  assemblyId: assemblyId ?? 0,
                )
              : await repository.createProfile(
                  targetKind: targetKind,
                  draftMode:
                      _surfaceDrawMode == RenderSceneSurfaceDrawMode.rectangle
                          ? 1
                          : 0,
                  levelId: _activeLevelId!,
                  points: _surfaceProfilePointsForCommit(),
                  closed: true,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  heightMeters: _draftSurfaceHeightMeters,
                  verticalOffsetMeters:
                      _interactionMode == RenderSceneInteractionMode.addFloor
                          ? _draftFloorTopElevationMeters
                          : _interactionMode ==
                                  RenderSceneInteractionMode.addCeiling
                              ? _draftCeilingHeightOffsetMeters
                              : 0.0,
                  assemblyId: assemblyId ?? 0,
                );
          await _applyEngineSceneResult(
            result,
            message: '${_surfaceKindLabel()} created.',
          );
          await _clearDraft();
          return;
        }
        if (_interactionMode == RenderSceneInteractionMode.addRoof) {
          setState(() {
            _editStatusMessage =
                'Roof creation hozircha engine-backed mode talab qiladi.';
          });
          return;
        }
        RenderScene nextScene;
        if (_draftSurfaceWallIds.length >= 2) {
          final walls = scene.objects
              .where(
                  (object) => _draftSurfaceWallIds.contains(object.elementId))
              .where((object) => object.kindKey == 'wall')
              .toList(growable: false);
          nextScene = _interactionMode == RenderSceneInteractionMode.addFloor
              ? RenderSceneEditor.addFloorFromWalls(
                  scene: scene,
                  walls: walls,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  topElevationMeters: _draftFloorTopElevationMeters,
                  levelId: _activeLevelId,
                )
              : RenderSceneEditor.addCeilingFromWalls(
                  scene: scene,
                  walls: walls,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  heightMeters: _draftCeilingHeightOffsetMeters,
                  levelId: _activeLevelId,
                );
          if (identical(nextScene, scene)) {
            setState(() {
              _editStatusMessage =
                  'At least 2 valid walls are required for wall-bound floor/ceiling.';
            });
            return;
          }
        } else {
          final start = _draftSurfaceStart;
          final end = _draftSurfaceEnd;
          if (start == null || end == null) {
            setState(() {
              _editStatusMessage =
                  'Draw a rectangle first, or multi-select walls.';
            });
            return;
          }
          final bounds = RenderSceneBounds.normalized(
            min: RenderScenePoint(
              x: math.min(start.x, end.x),
              y: math.min(start.y, end.y),
              z: 0,
            ),
            max: RenderScenePoint(
              x: math.max(start.x, end.x),
              y: math.max(start.y, end.y),
              z: 0,
            ),
          );
          nextScene = _interactionMode == RenderSceneInteractionMode.addFloor
              ? RenderSceneEditor.addFloorFromBounds(
                  scene: scene,
                  bounds: bounds,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  topElevationMeters: _draftFloorTopElevationMeters,
                  levelId: _activeLevelId,
                )
              : RenderSceneEditor.addCeilingFromBounds(
                  scene: scene,
                  bounds: bounds,
                  thicknessMeters: _draftSurfaceThicknessMeters,
                  heightMeters: _draftCeilingHeightOffsetMeters,
                  levelId: _activeLevelId,
                );
        }
        await _applySceneChange(
          nextScene,
          message: '${_surfaceKindLabel()} created.',
        );
        final created =
            nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
        if (created != null) {
          await _viewportController
              .selectElement(created.elementId?.toString());
          await _viewportController
              .highlightElement(created.elementId?.toString());
        }
        await _clearDraft();
        return;
    }
  }

  Future<void> _cancelDraft() async {
    await _clearDraft();
    setState(() {
      _editStatusMessage = 'Draft canceled.';
      _statusMessage = _editStatusMessage;
    });
  }

  Future<void> _commitOpeningDraft(
    RenderScene scene,
    RenderSceneObject hostWall,
  ) async {
    final openingDraft = _viewportController.draftOpening;
    if (openingDraft != null && !openingDraft.valid) {
      setState(() {
        _editStatusMessage = openingDraft.message;
      });
      return;
    }

    final offset = _draftOpeningOffsetMeters;
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null && hostWall.elementId != null) {
      final result = _interactionMode == RenderSceneInteractionMode.addDoor
          ? await repository.createDoor(
              name: 'Door',
              hostWallId: hostWall.elementId!,
              offsetMeters: offset,
              widthMeters: _draftOpeningWidthMeters,
              heightMeters: _draftOpeningHeightMeters,
            )
          : await repository.createWindow(
              name: 'Window',
              hostWallId: hostWall.elementId!,
              offsetMeters: offset,
              widthMeters: _draftOpeningWidthMeters,
              heightMeters: _draftOpeningHeightMeters,
              sillHeightMeters: _draftOpeningSillHeightMeters,
            );
      await _applyEngineSceneResult(
        result,
        message:
            '${_interactionMode == RenderSceneInteractionMode.addDoor ? 'Door' : 'Window'} created.',
      );
      await _clearDraft();
      return;
    }
    final nextScene = _interactionMode == RenderSceneInteractionMode.addDoor
        ? RenderSceneEditor.addDoor(
            scene: scene,
            hostWall: hostWall,
            offsetMeters: offset,
            widthMeters: _draftOpeningWidthMeters,
            heightMeters: _draftOpeningHeightMeters,
            levelId: hostWall.levelId ?? _activeLevelId,
          )
        : RenderSceneEditor.addWindow(
            scene: scene,
            hostWall: hostWall,
            offsetMeters: offset,
            widthMeters: _draftOpeningWidthMeters,
            heightMeters: _draftOpeningHeightMeters,
            sillHeightMeters: _draftOpeningSillHeightMeters,
            levelId: hostWall.levelId ?? _activeLevelId,
          );
    await _applySceneChange(
      nextScene,
      message:
          '${_interactionMode == RenderSceneInteractionMode.addDoor ? 'Door' : 'Window'} created.',
    );
    final created =
        nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
    if (created != null) {
      await _viewportController.selectElement(created.elementId?.toString());
      await _viewportController.highlightElement(created.elementId?.toString());
    }
    await _clearDraft();
  }

  void _syncOpeningDraft() {
    final hostWall = _draftHostWall;
    if (hostWall == null) {
      _viewportController.setOpeningDraft(null);
      return;
    }

    final wallLength = RenderSceneEditor.wallLength(hostWall) ?? 0.0;
    final offset = _draftOpeningOffsetMeters;
    final valid =
        offset >= _openingWidthHalf && offset <= wallLength - _openingWidthHalf;
    final kind = _interactionMode == RenderSceneInteractionMode.addDoor
        ? 'Door'
        : 'Window';

    _viewportController.setOpeningDraft(
      RenderSceneOpeningDraft(
        kind: kind,
        hostWallId: hostWall.elementId,
        offsetMeters: offset,
        widthMeters: _draftOpeningWidthMeters,
        heightMeters: _draftOpeningHeightMeters,
        sillHeightMeters: _draftOpeningSillHeightMeters,
        valid: valid,
        message: valid
            ? 'Ready to create $kind.'
            : 'Opening overlaps wall edge or is too wide.',
      ),
    );
  }

  void _syncSurfaceDraftFromWalls(RenderScene scene) {
    final walls = scene.objects
        .where((object) => _draftSurfaceWallIds.contains(object.elementId))
        .where((object) => object.kindKey == 'wall')
        .toList(growable: false);
    final polygon = RenderSceneEditor.surfacePolygonForWalls(walls);
    if (polygon != null && polygon.length >= 3) {
      _viewportController.setSurfaceDraft(
        RenderSceneSurfaceDraft(
          kind: _surfaceKindKey(),
          points: polygon,
          closed: true,
        ),
      );
      return;
    }
    final bounds = RenderSceneEditor.surfaceBoundsForWalls(walls);
    if (bounds == null) {
      _viewportController.setSurfaceDraft(null);
      return;
    }
    _draftSurfaceStart = RenderScenePoint(
      x: bounds.min.x,
      y: bounds.min.y,
      z: bounds.min.z,
    );
    _draftSurfaceEnd = RenderScenePoint(
      x: bounds.max.x,
      y: bounds.max.y,
      z: bounds.max.z,
    );
    _syncSurfaceDraftPreview();
  }

  Future<void> _deleteSelectedObject() async {
    final scene = _scene;
    final selected = _selectedObject(scene);
    if (scene == null || selected == null) {
      setState(() {
        _editStatusMessage = 'Delete uchun avval obyektni tanlang.';
      });
      return;
    }

    final repository = _engineRepository;
    if (_engineBackedMode && repository != null && selected.elementId != null) {
      final result = await repository.deleteElement(
        elementId: selected.elementId!,
      );
      await _applyEngineSceneResult(
        result,
        message: '${prettySceneKind(selected.kind)} o‘chirildi.',
      );
      return;
    }

    final nextScene = RenderSceneEditor.deleteObject(
      scene: scene,
      target: selected,
    );
    await _applySceneChange(
      nextScene,
      message: '${prettySceneKind(selected.kind)} o‘chirildi.',
    );
  }

  Future<void> _applySceneChange(
    RenderScene nextScene, {
    required String message,
    bool authoritative = false,
  }) async {
    if (!authoritative) {
      setState(() {
        _editStatusMessage =
            'Engine ulanmagan: preview ko‘rsatilyapti, lekin model o‘zgartirilmaydi.';
      });
      return;
    }
    final previousSelectedId = _viewportController.selectedElementId;
    final previousSelectedLevelId = _viewportController.selectedLevelId;
    final previousHighlightedId = _viewportController.highlightedElementId;
    final selectedBefore = _selectedObject(nextScene);
    final nextSelected = previousSelectedId != null
        ? nextScene.objectByStableId(previousSelectedId)
        : null;
    final resolvedLevelId =
        _resolveInitialLevelId(nextScene, preferred: _activeLevelId);
    _sheetSourceScene = null;
    _sheetViewScenes.clear();

    setState(() {
      _scene = nextScene;
      _activeLevelId = resolvedLevelId;
      _activeSectionView = null;
      _statusMessage = message;
      _editStatusMessage = message;
      _loadError = null;
    });

    final nextViewportScene = _sceneForViewport(nextScene);

    setState(() {
      if (_usesProjectionDefaultVisibility) {
        _visibleKinds = _defaultVisibleKindsForProjection(nextScene);
      } else {
        _visibleKinds = _sanitizeVisibleKinds(
          visibleKinds: _visibleKinds,
          scene: nextViewportScene,
        );
      }
      _visibleKinds = _ensurePlanCoreVisibility(_visibleKinds, nextScene);
    });

    // A delete can remove the active renderable. Clear its native selection
    // before rebuilding Filament so a frame never tries to tint/highlight an
    // entity that has just been destroyed, which showed up as a tablet flash.
    if (previousSelectedId != null && nextSelected == null) {
      await _viewportController.selectElement(null);
      await _viewportController.highlightElement(null);
    }

    await _viewportController.updateRenderScene(nextViewportScene);
    await _viewportController.setVisibleKinds(_visibleKinds);

    if (previousSelectedLevelId != null &&
        nextScene.levelById(previousSelectedLevelId) != null) {
      await _viewportController.selectLevel(previousSelectedLevelId);
      return;
    }

    if (nextSelected != null) {
      await _viewportController
          .selectElement(nextSelected.elementId?.toString());
      await _viewportController
          .highlightElement(nextSelected.elementId?.toString());
    } else if (previousSelectedId != null) {
      await _viewportController.selectElement(null);
      await _viewportController.highlightElement(null);
    } else if (selectedBefore != null) {
      await _viewportController
          .selectElement(selectedBefore.elementId?.toString());
      await _viewportController
          .highlightElement(selectedBefore.elementId?.toString());
    } else {
      await _viewportController.highlightElement(previousHighlightedId);
    }
  }

  Future<void> _applyEngineSceneResult(
    RenderSceneLoadResult result, {
    required String message,
  }) async {
    if (result.scene == null) {
      setState(() {
        _editStatusMessage = result.errors.isNotEmpty
            ? result.errors.join('\n')
            : 'Engine update failed.';
      });
      return;
    }
    await _applySceneChange(
      result.scene!,
      message: message,
      authoritative: true,
    );
  }

  RenderSceneObject? _selectedObject(RenderScene? scene) {
    if (scene == null) {
      return null;
    }

    final selectedId = _viewportController.selectedElementId;
    if (selectedId == null) {
      return null;
    }

    final parsedId = int.tryParse(selectedId);
    return scene.objectById(parsedId);
  }

  void _primeOpeningDraftFromObject(RenderSceneObject object) {
    _openingTool.loadFromMetadata(object.metadata);
  }

  List<String> _availableKinds(RenderScene? scene) {
    if (scene == null) {
      return <String>[];
    }

    final available = scene.kindCounts.keys.toSet();
    final ordered = <String>[
      for (final kind in _coreKindOrder)
        if (available.contains(kind)) kind,
      for (final kind in available)
        if (!_coreKindOrder.contains(kind)) kind,
    ];

    return ordered;
  }

  @override
  Widget build(BuildContext context) {
    final fullScene = _scene;
    final scene = fullScene == null ? null : _sceneForViewport(fullScene);
    final inspectorTarget = _inspectorController.targetFor(fullScene);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (DismissIntent intent) {
              _handleEscapePressed();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: _buildAppBar(context, fullScene, scene),
            body: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: <Widget>[
                      _buildLeftRail(context, scene),
                      AuthoringToolPalette(
                        mode: _interactionMode,
                        enabled: scene != null &&
                            !_isBusy &&
                            _sheetWorkspace.activeSheet == null,
                        onModeChanged: _setInteractionMode,
                      ),
                      Expanded(
                        child: _buildViewportPanel(context),
                      ),
                      if (_showInspector)
                        _buildRightPanel(
                          context: context,
                          scene: fullScene,
                          inspectorTarget: inspectorTarget,
                        ),
                    ],
                  ),
                ),
                if (_loadError != null) _buildErrorBanner(context, _loadError!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    RenderScene? fullScene,
    RenderScene? viewportScene,
  ) {
    return WorkspaceAppBar(
      statusMessage: _statusMessage,
      busy: _isBusy,
      engineBacked: _engineBackedMode,
      hasScene: fullScene != null,
      hasSelection: _viewportController.selectedElementId != null,
      browserVisible: _showObjectList,
      inspectorVisible: _showInspector,
      activeSectionName: _activeSectionView?.name,
      onExitSection: _activeSectionView == null
          ? null
          : () => _setProjectionMode(RenderSceneProjectionMode.isometric),
      onCreateTemplate: (template) => _createResidentialTemplate(
        template == WorkspaceTemplate.tower9
            ? _ResidentialTemplateKind.tower9
            : _ResidentialTemplateKind.campus6x9,
      ),
      onSave: _saveCurrentProject,
      onDocumentation: _openDocumentationWorkspace,
      onOpenMaterials: _showMaterialLayerEditor,
      onCreateSection: _showSectionDialog,
      onReload: _reloadCurrentScene,
      onClearSelection: _clearSelection,
      onToggleBrowser: () => setState(() {
        _showObjectList = !_showObjectList;
      }),
      onToggleInspector: () => setState(() {
        _showInspector = !_showInspector;
      }),
      rendererToggleVisible: defaultTargetPlatform == TargetPlatform.android,
      rendererIsNative:
          _viewportController.backend == RenderSceneViewportBackend.native,
      onToggleRenderer: _toggleAndroidRenderer,
    );
  }

  Widget _buildToolbar(BuildContext context, RenderScene? scene) {
    final is3D = _projectionMode.is3D;
    final selectedWall = scene == null
        ? null
        : (() {
            final selected = _selectedObject(_scene);
            if (selected == null || selected.kindKey != 'wall') {
              return null;
            }
            return selected;
          })();

    return Container(
      height: 126,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                ..._buildProjectionModeButtons(scene),
                _toolbarChoiceButton(
                  label: '3D',
                  selected:
                      _projectionMode == RenderSceneProjectionMode.isometric,
                  onPressed: scene == null
                      ? null
                      : () => _setProjectionMode(
                          RenderSceneProjectionMode.isometric),
                ),
                const SizedBox(width: 10),
                _toolbarChoiceButton(
                  label: 'Shaded',
                  selected: _displayStyle == RenderSceneDisplayStyle.shaded,
                  onPressed: scene == null
                      ? null
                      : () => _setDisplayStyle(RenderSceneDisplayStyle.shaded),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Solid',
                  selected: _displayStyle == RenderSceneDisplayStyle.solid,
                  onPressed: scene == null
                      ? null
                      : () => _setDisplayStyle(RenderSceneDisplayStyle.solid),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Wire',
                  selected: _displayStyle == RenderSceneDisplayStyle.wireframe,
                  onPressed: scene == null
                      ? null
                      : () =>
                          _setDisplayStyle(RenderSceneDisplayStyle.wireframe),
                ),
                if (is3D) ...<Widget>[
                  const SizedBox(width: 10),
                  _toolbarChoiceButton(
                    label: 'Ortho',
                    selected: _orbitProjectionStyle ==
                        RenderSceneOrbitProjectionStyle.orthographic,
                    onPressed: scene == null
                        ? null
                        : () => _setOrbitProjectionStyle(
                              RenderSceneOrbitProjectionStyle.orthographic,
                            ),
                  ),
                  const SizedBox(width: 6),
                  _toolbarChoiceButton(
                    label: 'Persp',
                    selected: _orbitProjectionStyle ==
                        RenderSceneOrbitProjectionStyle.perspective,
                    onPressed: scene == null
                        ? null
                        : () => _setOrbitProjectionStyle(
                              RenderSceneOrbitProjectionStyle.perspective,
                            ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed:
                        scene == null || _isBusy ? null : _showSectionBoxDialog,
                    icon: const Icon(Icons.crop_free_outlined, size: 18),
                    label: Text(_viewportController.hasSectionBox
                        ? 'Section Box on'
                        : 'Section Box'),
                  ),
                ],
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed: scene == null || _isBusy ? null : _fitCamera,
                  icon: const Icon(Icons.fit_screen, size: 18),
                  label: const Text('Fit'),
                ),
                if (scene != null) ...<Widget>[
                  const SizedBox(width: 10),
                  _LevelToolbarControl(
                    levels: scene.levels,
                    activeLevelId: _activeLevelId,
                    onChanged: (levelId) => _setActiveLevel(levelId),
                    onAddLevel: _showCreateLevelDialog,
                  ),
                ],
                const SizedBox(width: 8),
                IconButton(
                  tooltip:
                      _showDiagnostics ? 'Hide diagnostics' : 'Diagnostics',
                  onPressed: scene == null
                      ? null
                      : () {
                          setState(() {
                            _showDiagnostics = !_showDiagnostics;
                          });
                        },
                  icon: const Icon(Icons.analytics_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _toolbarChoiceButton(
                  label: 'Select',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.select,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.select),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Wall',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addWall,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.addWall),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Level',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addLevel,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                            RenderSceneInteractionMode.addLevel,
                          ),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Move level',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.moveLevel,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                            RenderSceneInteractionMode.moveLevel,
                          ),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Move wall',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.moveWall,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.moveWall),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Door',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addDoor,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.addDoor),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Window',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addWindow,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.addWindow),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Move opening',
                  selected: _interactionMode ==
                      RenderSceneInteractionMode.moveOpening,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                            RenderSceneInteractionMode.moveOpening,
                          ),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Floor',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addFloor,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.addFloor),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Ceiling',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addCeiling,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                            RenderSceneInteractionMode.addCeiling,
                          ),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Roof',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addRoof,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.addRoof),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Stair',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.addStair,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.addStair),
                ),
                if (scene != null && selectedWall != null) ...<Widget>[
                  const SizedBox(width: 12),
                  _SelectedWallLevelToolbarControl(
                    wall: selectedWall,
                    scene: scene,
                    activeLevelId: _activeLevelId,
                    onAttachBaseToActive: () => _attachWallToActiveLevel(
                      selectedWall,
                      constrainToNextLevel: false,
                    ),
                    onAttachTopToNext: () => _attachWallToActiveLevel(
                      selectedWall,
                      constrainToNextLevel: true,
                    ),
                    onAdvanced: () => _showWallLevelConstraintsDialog(
                      selectedWall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildProjectionModeButtons(RenderScene? scene) {
    return <Widget>[
      for (var index = 0;
          index < kOrthographicProjectionModes.length;
          index++) ...[
        _toolbarChoiceButton(
          label: kOrthographicProjectionModes[index].shortLabel,
          selected: _projectionMode == kOrthographicProjectionModes[index],
          onPressed: scene == null
              ? null
              : () => _setProjectionMode(kOrthographicProjectionModes[index]),
        ),
        const SizedBox(width: 6),
      ],
    ];
  }

  Widget _toolbarChoiceButton({
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onPressed == null ? null : (_) => onPressed(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildLeftRail(BuildContext context, RenderScene? scene) {
    final theme = Theme.of(context);

    return Container(
      width: _showObjectList ? 280 : 72,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: _showObjectList
          ? _buildObjectListPanel(context, scene)
          : _buildCollapsedRail(context),
    );
  }

  Widget _buildCollapsedRail(BuildContext context) {
    return Column(
      children: <Widget>[
        const SizedBox(height: 8),
        IconButton(
          tooltip: 'Show project browser',
          onPressed: () {
            setState(() {
              _showObjectList = true;
            });
          },
          icon: const Icon(Icons.view_list),
        ),
      ],
    );
  }

  Widget _buildObjectListPanel(BuildContext context, RenderScene? scene) {
    return ProjectBrowserPanel(
      scene: scene,
      availableKinds: _availableKinds(scene),
      visibleKinds: _visibleKinds,
      selectedElementId: _viewportController.selectedElementId,
      projectionMode: _projectionMode,
      activeLevelId: _activeLevelId,
      activeSectionName: _activeSectionView?.name,
      sheets: _sheetWorkspace.sheets,
      activeSheetId: _sheetWorkspace.activeSheetId,
      onCreateSheet: _createSheet,
      onClose: () => setState(() => _showObjectList = false),
      onVisibleKindsChanged: _setVisibleKinds,
      onSelectObject: _selectObject,
      onOpen3d: () => _setProjectionMode(RenderSceneProjectionMode.isometric),
      onOpenFloorPlan: (levelId) async {
        await _setActiveLevel(levelId);
        await _setProjectionMode(RenderSceneProjectionMode.topDown);
      },
      onOpenElevation: _setProjectionMode,
      onOpenSection: _openProjectSection,
      onOpenSheet: _openSheet,
    );
  }

  Future<void> _openProjectSection(RenderSceneSection section) async {
    if (_engineRepository == null || !_engineBackedMode || !mounted) return;
    setState(() {
      _isBusy = true;
      _statusMessage = 'Opening ${section.name}...';
      _loadError = null;
    });
    try {
      final result = await _sceneViews.setFullSceneRenderScope(true);
      await _activateSectionView(section, result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'Section failed.';
      });
    }
  }

  Widget _buildViewportPanel(BuildContext context) {
    final sheet = _sheetWorkspace.activeSheet;
    final scene = _scene;
    if (sheet != null && scene != null) {
      return SheetCanvas(
        controller: _sheetWorkspace,
        fallbackScene: _sheetSourceScene ?? scene,
        resolvedScenes: _sheetViewScenes,
        onPlaceView: _placeSheetView,
        onClose: _closeActiveSheet,
        onOpenPdf: _openDocumentationWorkspace,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Container(
          color: const Color(0xFFF4F7F5),
          child: RenderSceneViewport(
            controller: _viewportController,
            interactionMode: _interactionMode,
            onSceneTap: _handleSceneTap,
            onSceneDragStart: _handleSceneDragStart,
            onSceneDragUpdate: _handleSceneDragUpdate,
            onSceneDragEnd: _handleSceneDragEnd,
            onSceneSecondaryTap: _handleSceneSecondaryTap,
            onSceneHover: _handleSceneHover,
            authoringPickKinds: _authoringPickKinds,
            directSurfaceDrag: _isSurfaceAuthoring &&
                _surfaceDrawMode == RenderSceneSurfaceDrawMode.rectangle,
            planPickResolver: _engineBackedMode ? _resolvePlanPick : null,
            onLevelElevationSubmitted: _moveSelectedLevelElevation,
            draftWallThicknessMeters: _defaultWallThicknessMeters,
            draftWallHeightMeters: _defaultWallHeightMeters,
          ),
        ),
        if (_isSurfaceAuthoring)
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: SurfaceDrawingContextBar(
              mode: _interactionMode,
              drawMode: _surfaceDrawMode,
              enabled: _scene != null && !_isBusy,
              canFinish: _draftCanConfirm,
              canUndo: _surfaceTool.canUndo,
              onDrawModeChanged: _setSurfaceDrawMode,
              onUndo: _undoSurfaceDraft,
              onTrimExtend: () {
                _setInteractionMode(RenderSceneInteractionMode.trimExtend);
              },
              onFinish: _confirmDraft,
              onCancel: _cancelDraft,
            ),
          ),
        if (_interactionMode == RenderSceneInteractionMode.addWall ||
            _interactionMode == RenderSceneInteractionMode.addStair)
          Positioned(
            left: 16,
            top: 16,
            child: LineDrawingContextBar(
              mode: _interactionMode,
              enabled: _scene != null && !_isBusy,
              hasDraft: _interactionMode == RenderSceneInteractionMode.addWall
                  ? _wallTool.hasStart
                  : _stairTool.hasStart,
              onDone: () => unawaited(
                _setInteractionMode(RenderSceneInteractionMode.select),
              ),
              onCancel: _cancelDraft,
            ),
          ),
        if (kDebugMode && _androidMutationTrace.isNotEmpty)
          Positioned(
            left: 8,
            right: 8,
            top: 8,
            child: _AndroidMutationTrace(entries: _androidMutationTrace),
          ),
        // The Section Box is drawn and manipulated in the native Filament
        // overlay so its border and clipping planes share one camera matrix.
        Positioned(
          right: 16,
          bottom: 16,
          child: ViewportControlDeck(
            hasScene: _scene != null && !_isBusy,
            projectionMode: _projectionMode,
            displayStyle: _displayStyle,
            orbitStyle: _orbitProjectionStyle,
            onProjectionChanged: _setProjectionMode,
            onDisplayStyleChanged: _setDisplayStyle,
            onOrbitStyleChanged: _setOrbitProjectionStyle,
            onFit: _fitCamera,
            hasSectionBox: _viewportController.hasSectionBox,
            onSectionBox: _showSectionBoxDialog,
          ),
        ),
        if (_isBusy)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.08),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        SizedBox(height: 14),
                        Text('Loading scene...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRightPanel({
    required BuildContext context,
    required RenderScene? scene,
    required InspectorTarget inspectorTarget,
  }) {
    final theme = Theme.of(context);

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Inspector',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: scene == null
                ? const _EmptyPanelMessage(
                    icon: Icons.info_outline,
                    title: 'No scene',
                    message: 'Load a scene to inspect diagnostics.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (_interactionMode != RenderSceneInteractionMode.select)
                        _DraftEditorCard(
                          interactionMode: _interactionMode,
                          draftWallStart: _interactionMode ==
                                  RenderSceneInteractionMode.addWall
                              ? _wallTool.start
                              : _interactionMode ==
                                      RenderSceneInteractionMode.addLevel
                                  ? _levelTool.start
                                  : _draftWallStart,
                          draftWallEnd: _interactionMode ==
                                  RenderSceneInteractionMode.addWall
                              ? _wallTool.end
                              : _interactionMode ==
                                      RenderSceneInteractionMode.addLevel
                                  ? _levelTool.end
                                  : _draftWallEnd,
                          draftSurfaceStart: _draftSurfaceStart,
                          draftSurfaceEnd: _draftSurfaceEnd,
                          draftSurfacePointCount: _draftSurfacePoints.length,
                          draftSurfaceWallCount: _draftSurfaceWallIds.length,
                          draftSurfaceThicknessMeters:
                              _draftSurfaceThicknessMeters,
                          draftSurfaceHeightMeters: _interactionMode ==
                                  RenderSceneInteractionMode.addCeiling
                              ? _draftCeilingHeightOffsetMeters
                              : _draftSurfaceHeightMeters,
                          draftStairWidthMeters: _stairTool.widthMeters,
                          draftFloorTopElevationMeters:
                              _draftFloorTopElevationMeters,
                          surfaceDrawMode: _surfaceDrawMode,
                          draftHostWall: _draftHostWall,
                          openingOffsetMeters: _draftOpeningOffsetMeters,
                          openingWidthMeters: _draftOpeningWidthMeters,
                          openingHeightMeters: _draftOpeningHeightMeters,
                          openingSillHeightMeters:
                              _draftOpeningSillHeightMeters,
                          trimFirstWall: _trimTool.first,
                          trimSecondWall: _trimTool.second,
                          trimPreview: _trimTool.preview,
                          editStatusMessage: _editStatusMessage,
                          snapEnabled: _snapDraftToGrid,
                          canConfirm: _draftCanConfirm,
                          onSnapToggled: (value) {
                            setState(() {
                              _snapDraftToGrid = value;
                            });
                            if (_interactionMode ==
                                    RenderSceneInteractionMode.addDoor ||
                                _interactionMode ==
                                    RenderSceneInteractionMode.addWindow ||
                                _interactionMode ==
                                    RenderSceneInteractionMode.moveOpening) {
                              _syncOpeningDraft();
                            } else {
                              _syncSurfaceDraftPreview();
                            }
                          },
                          onOpeningOffsetChanged: (value) {
                            setState(() {
                              _draftOpeningOffsetMeters = value;
                            });
                            _syncOpeningDraft();
                          },
                          onOpeningWidthChanged: (value) {
                            setState(() {
                              _draftOpeningWidthMeters = value;
                            });
                            _syncOpeningDraft();
                          },
                          onOpeningHeightChanged: (value) {
                            setState(() {
                              _draftOpeningHeightMeters = value;
                            });
                            _syncOpeningDraft();
                          },
                          onOpeningSillHeightChanged: (value) {
                            setState(() {
                              _draftOpeningSillHeightMeters = value;
                            });
                            _syncOpeningDraft();
                          },
                          onSurfaceThicknessChanged: (value) {
                            setState(() {
                              _draftSurfaceThicknessMeters = value;
                            });
                          },
                          onSurfaceHeightChanged: (value) {
                            setState(() {
                              if (_interactionMode ==
                                  RenderSceneInteractionMode.addCeiling) {
                                _draftCeilingHeightOffsetMeters = value;
                              } else {
                                _draftSurfaceHeightMeters = value;
                              }
                            });
                          },
                          onFloorTopElevationChanged: (value) {
                            setState(() {
                              _draftFloorTopElevationMeters = value;
                            });
                          },
                          onStairWidthChanged: _stairTool.setWidth,
                          onConfirm: _confirmDraft,
                          onCancel: _cancelDraft,
                          onClearSelection: _clearSelection,
                          onResetMode: () => _setInteractionMode(
                            RenderSceneInteractionMode.select,
                          ),
                        ),
                      if (_interactionMode != RenderSceneInteractionMode.select)
                        const SizedBox(height: 16),
                      PropertyEditor(
                        scene: scene,
                        target: inspectorTarget,
                        commands: _authoringCommands,
                        viewRangeMeters: _planViewRangeMeters,
                        onViewRangeChanged: _setPlanViewRangeMeters,
                        showPlanViewRange: _projectionMode ==
                            RenderSceneProjectionMode.topDown,
                        activePlanLevel: _activeLevel(scene),
                        onApplied: (result, message) =>
                            _applyEngineSceneResult(result, message: message),
                        onClearSelection: _clearSelection,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _setPlanViewRangeMeters(double value) async {
    if (!value.isFinite || value <= 0.05) {
      return;
    }
    setState(() {
      _planViewRangeMeters = value.clamp(0.1, 20.0);
      _statusMessage =
          'Plan view range: ${_planViewRangeMeters.toStringAsFixed(2)} m';
    });
    final scene = _scene;
    if (scene != null && _projectionMode == RenderSceneProjectionMode.topDown) {
      await _viewportController.updateRenderScene(_sceneForViewport(scene));
      await _viewportController.setVisibleKinds(_visibleKinds);
    }
  }

  Future<void> _showMaterialLayerEditor() async {
    final repository = _engineRepository;
    if (repository == null || !_engineBackedMode || !mounted) return;
    try {
      final json = await _projectPersistence.exportJson();
      final decoded = jsonDecode(json);
      if (decoded is! Map) return;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => MaterialLayerEditor(
          projectJson: decoded.cast<String, dynamic>(),
          onApply: (updatedProject) async {
            final updatedJson = jsonEncode(updatedProject);
            await _projectPersistence.replaceFromJson(
              projectName: 'Material Layer Project',
              json: updatedJson,
            );
            final result = await _sceneViews.refresh();
            if (mounted) {
              await _applyLoadResult(result, sourceLabel: 'Material layers');
            }
          },
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _editStatusMessage = 'Material editor failed: $error');
      }
    }
  }

  Future<void> _showSectionDialog() async {
    final scene = _scene;
    if (_engineRepository == null ||
        scene == null ||
        !_engineBackedMode ||
        !mounted) {
      return;
    }
    // Section placement is a plan-view command: create the default section
    // through the building centre without exposing coordinate fields. The
    // Project Browser still owns Section A/B, while this command gives the
    // same predictable horizontal cut as Revit's first section marker.
    final margin =
        math.max(scene.bounds.width, scene.bounds.depth) * 0.08 + 0.5;
    final section = RenderSceneSection(
      name: 'Section',
      start: RenderScenePoint(
        x: scene.bounds.min.x - margin,
        y: (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
        z: 0,
      ),
      end: RenderScenePoint(
        x: scene.bounds.max.x + margin,
        y: (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
        z: 0,
      ),
    );
    setState(() {
      _isBusy = true;
      _statusMessage = 'Creating section...';
      _loadError = null;
    });
    try {
      final result = await _sceneViews.setFullSceneRenderScope(true);
      await _activateSectionView(section, result);
    } catch (error) {
      if (mounted) {
        setState(() {
          _isBusy = false;
          _loadError = error.toString();
          _statusMessage = 'Section failed.';
        });
      }
    }
    return;
  }

  Future<void> _handleSceneSecondaryTap(RenderSceneTapDetails details) async {
    if (!mounted) {
      return;
    }

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    final pickedLevel = details.pickedLevel;
    final tappedObject = details.pickedObject;
    if (pickedLevel != null && _projectionMode.isElevation) {
      await _selectLevel(pickedLevel);
      if (!mounted) {
        return;
      }
      final action = await showMenu<String>(
        context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(
            details.globalPosition.dx,
            details.globalPosition.dy,
            1,
            1,
          ),
          Offset.zero & (overlay?.size ?? const Size(1, 1)),
        ),
        items: const <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'edit_level',
            child: Text('Edit level'),
          ),
        ],
      );
      if (!mounted) {
        return;
      }
      if (action == 'edit_level') {
        await _showEditLevelDialog(pickedLevel);
      }
      return;
    }
    if (tappedObject != null) {
      await _selectObject(tappedObject);
    }
    if (tappedObject == null && _projectionMode.isElevation) {
      final scene = _scene;
      final pickedLevel = scene == null
          ? null
          : _pickLevelAtElevation(scene, details.modelPoint);
      if (pickedLevel != null) {
        await _setActiveLevel(pickedLevel.levelId);
        if (!mounted) {
          return;
        }
        final action = await showMenu<String>(
          context: context,
          position: RelativeRect.fromRect(
            Rect.fromLTWH(
              details.globalPosition.dx,
              details.globalPosition.dy,
              1,
              1,
            ),
            Offset.zero & (overlay?.size ?? const Size(1, 1)),
          ),
          items: const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(
              value: 'edit_level',
              child: Text('Edit level'),
            ),
          ],
        );
        if (!mounted) {
          return;
        }
        if (action == 'edit_level') {
          await _showEditLevelDialog(pickedLevel);
        }
        return;
      }
    }
    if (!mounted) {
      return;
    }

    final selected = tappedObject ?? _selectedObject(_scene);
    if (selected == null || overlay == null) {
      return;
    }

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(
          details.globalPosition.dx,
          details.globalPosition.dy,
          1,
          1,
        ),
        Offset.zero & overlay.size,
      ),
      items: const <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'delete',
          child: Text('Delete'),
        ),
      ],
    );

    if (!mounted) {
      return;
    }
    if (action == 'delete') {
      await _deleteSelectedObject();
    }
  }

  void _handleSceneDragStart(RenderSceneTapDetails details) {
    final scene = _scene;
    if (scene == null) {
      return;
    }
    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        final level = details.pickedLevel;
        if (level != null) {
          unawaited(_selectLevel(level));
          _handleMoveLevelStart(
            scene,
            details.modelPoint,
            pickedLevel: level,
          );
          return;
        }
        if (details.pickedObject != null) {
          final object = details.pickedObject!;
          if (object.kindKey == 'wall') {
            unawaited(_handleMoveWallTap(scene, object, details.modelPoint));
          } else if (object.kindKey == 'door' || object.kindKey == 'window') {
            unawaited(_handleMoveOpeningTap(scene, object, details.modelPoint));
          } else {
            unawaited(_selectObject(object));
          }
        }
        return;
      case RenderSceneInteractionMode.addWall:
        final point = details.modelPoint;
        if (point == null) return;
        final snapped = _draftLinePoint(
          rawPoint: point,
          referenceStart: _wallTool.start,
        );
        if (!_wallTool.hasStart) {
          _wallTool.begin(snapped);
        } else {
          _wallTool.preview(snapped);
        }
        _viewportController.setWallDraft(_wallTool.start, _wallTool.end);
        setState(() {
          _editStatusMessage = _wallTool.hasSegment
              ? 'Release to create this wall.'
              : 'Drag to draw, or tap the next wall corner.';
        });
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        if (_surfaceDrawMode != RenderSceneSurfaceDrawMode.rectangle) return;
        final point = details.modelPoint;
        if (point == null) return;
        final snapped = _snapDraftToGrid ? _snapPoint(point) : point;
        setState(() {
          if (_draftSurfaceStart == null) {
            _draftSurfaceStart = snapped;
            _draftSurfaceEnd = snapped;
            _draftSurfacePoints
              ..clear()
              ..add(snapped);
          } else {
            _draftSurfaceEnd = snapped;
            if (_draftSurfacePoints.length == 1) {
              _draftSurfacePoints.add(snapped);
            } else {
              _draftSurfacePoints[1] = snapped;
            }
          }
          _editStatusMessage = 'Drag and release to create rectangle.';
        });
        _syncSurfaceDraftPreview();
        return;
      case RenderSceneInteractionMode.addStair:
        final point = details.modelPoint;
        if (point == null) return;
        final snapped = _draftLinePoint(
          rawPoint: point,
          referenceStart: _stairTool.start,
        );
        if (!_stairTool.hasStart) {
          _stairTool.begin(snapped);
        } else {
          _stairTool.preview(snapped);
        }
        _viewportController.setWallDraft(_stairTool.start, _stairTool.end);
        return;
      case RenderSceneInteractionMode.moveWall:
        _handleMoveWallTap(scene, details.pickedObject, details.modelPoint);
        return;
      case RenderSceneInteractionMode.moveLevel:
        _handleMoveLevelStart(
          scene,
          details.modelPoint,
          pickedLevel: details.pickedLevel,
        );
        return;
      case RenderSceneInteractionMode.moveOpening:
        _handleMoveOpeningTap(scene, details.pickedObject, details.modelPoint);
        return;
      default:
        return;
    }
  }

  void _handleSceneDragUpdate(RenderSceneTapDetails details) {
    final scene = _scene;
    final point = details.modelPoint;
    if (scene == null || point == null) {
      return;
    }
    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        if (_draftMoveLevelId != null) {
          _updateMoveLevelPreview(scene: scene, point: point);
        } else {
          final target = _draftMoveTarget;
          if (target?.kindKey == 'wall') {
            _updateMoveWallPreview(scene: scene, wall: target!, point: point);
          } else if (target?.kindKey == 'door' || target?.kindKey == 'window') {
            _updateMoveOpeningPreview(
                scene: scene, opening: target!, point: point);
          }
        }
        return;
      case RenderSceneInteractionMode.moveWall:
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (target != null && target.kindKey == 'wall') {
          _updateMoveWallPreview(scene: scene, wall: target, point: point);
        }
        return;
      case RenderSceneInteractionMode.moveLevel:
        _updateMoveLevelPreview(scene: scene, point: point);
        return;
      case RenderSceneInteractionMode.moveOpening:
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (target != null &&
            (target.kindKey == 'door' || target.kindKey == 'window')) {
          _updateMoveOpeningPreview(
              scene: scene, opening: target, point: point);
        }
        return;
      case RenderSceneInteractionMode.addWall:
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
      case RenderSceneInteractionMode.addStair:
        _handleSceneHover(details);
        return;
      default:
        return;
    }
  }

  Future<void> _handleSceneDragEnd(RenderSceneTapDetails details) async {
    switch (_interactionMode) {
      case RenderSceneInteractionMode.addWall:
        _handleSceneHover(details);
        if (_wallTool.hasSegment) {
          await _commitWallDraft(autoContinue: true);
        }
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
      case RenderSceneInteractionMode.addRoof:
        if (_surfaceDrawMode != RenderSceneSurfaceDrawMode.rectangle) return;
        _handleSceneHover(details);
        if (PlanSketchGeometry.isUsableRectangle(
          _draftSurfaceStart,
          _draftSurfaceEnd,
        )) {
          await _confirmDraft();
        }
        return;
      case RenderSceneInteractionMode.addStair:
        _handleSceneHover(details);
        if (_stairTool.hasRun) {
          await _commitStairDraft();
        }
        return;
      case RenderSceneInteractionMode.select:
        if (_draftMoveLevelId != null && _draftWallEnd != null) {
          final repository = _engineRepository;
          final levelId = _draftMoveLevelId!;
          final elevation = _draftWallEnd!.z;
          if (_engineBackedMode && repository != null) {
            final result = await repository.moveLevelElevation(
              levelId: levelId,
              elevationMeters: elevation,
            );
            await _applyEngineSceneResult(
              result,
              message:
                  'Level elevation updated to ${elevation.toStringAsFixed(2)} m.',
            );
          }
          await _clearDraft();
        } else if (_draftMoveTarget?.kindKey == 'wall' &&
            _draftWallStart != null &&
            _draftWallEnd != null) {
          final wall = _draftMoveTarget!;
          final repository = _engineRepository;
          if (_engineBackedMode &&
              repository != null &&
              wall.elementId != null) {
            final result = await repository.setWallAxis(
                wallId: wall.elementId!,
                start: _draftWallStart!,
                end: _draftWallEnd!);
            await _applyEngineSceneResult(result, message: 'Wall moved.');
          }
          await _clearDraft();
        } else if ((_draftMoveTarget?.kindKey == 'door' ||
                _draftMoveTarget?.kindKey == 'window') &&
            _draftMoveTarget?.elementId != null) {
          final opening = _draftMoveTarget!;
          final repository = _engineRepository;
          if (_engineBackedMode && repository != null) {
            final result = await repository.moveHostedOpening(
              openingId: opening.elementId!,
              offsetMeters: _draftOpeningOffsetMeters,
            );
            await _applyEngineSceneResult(
              result,
              message: '${prettySceneKind(opening.kind)} moved.',
            );
          }
          await _clearDraft();
        }
        return;
      case RenderSceneInteractionMode.moveWall:
      case RenderSceneInteractionMode.moveOpening:
      case RenderSceneInteractionMode.moveLevel:
        if (_draftCanConfirm) {
          await _confirmDraft();
        }
        return;
      default:
        return;
    }
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFEE2E2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, color: Color(0xFF991B1B)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF991B1B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelToolbarControl extends StatelessWidget {
  const _LevelToolbarControl({
    required this.levels,
    required this.activeLevelId,
    required this.onChanged,
    required this.onAddLevel,
  });

  final List<RenderSceneLevel> levels;
  final int? activeLevelId;
  final ValueChanged<int?> onChanged;
  final VoidCallback onAddLevel;

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) {
      return FilledButton.tonalIcon(
        onPressed: onAddLevel,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Level'),
      );
    }

    final selectedLevelId =
        levels.any((level) => level.levelId == activeLevelId)
            ? activeLevelId
            : levels.first.levelId;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.layers_outlined, size: 18),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: selectedLevelId,
              isDense: true,
              items: <DropdownMenuItem<int>>[
                for (final level in levels)
                  DropdownMenuItem<int>(
                    value: level.levelId,
                    child: Text(
                      '${level.name} (${level.elevationMeters.toStringAsFixed(2)}m)',
                    ),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Add level',
            onPressed: onAddLevel,
            icon: const Icon(Icons.add),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _SelectedWallLevelToolbarControl extends StatelessWidget {
  const _SelectedWallLevelToolbarControl({
    required this.wall,
    required this.scene,
    required this.activeLevelId,
    required this.onAttachBaseToActive,
    required this.onAttachTopToNext,
    required this.onAdvanced,
  });

  final RenderSceneObject wall;
  final RenderScene scene;
  final int? activeLevelId;
  final VoidCallback onAttachBaseToActive;
  final VoidCallback onAttachTopToNext;
  final VoidCallback onAdvanced;

  @override
  Widget build(BuildContext context) {
    final baseLevelId =
        _objectMetadataInt(wall, 'base_level_id') ?? wall.levelId;
    final topLevelId = _objectMetadataInt(wall, 'top_level_id');
    final baseLabel = scene.levelById(baseLevelId)?.name ?? 'None';
    final topLabel = (topLevelId == null || topLevelId == 0)
        ? 'Unconnected'
        : (scene.levelById(topLevelId)?.name ?? 'Level $topLevelId');
    final activeLabel = activeLevelId == null
        ? 'No active'
        : (scene.levelById(activeLevelId)?.name ?? 'Level $activeLevelId');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: <Widget>[
          Text(
            'Wall levels',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text('Base: $baseLabel'),
          Text('Top: $topLabel'),
          Text('Active: $activeLabel'),
          ActionChip(
            label: const Text('Base -> active'),
            onPressed: onAttachBaseToActive,
          ),
          ActionChip(
            label: const Text('Top -> next'),
            onPressed: onAttachTopToNext,
          ),
          ActionChip(
            label: const Text('Advanced'),
            onPressed: onAdvanced,
          ),
        ],
      ),
    );
  }
}

class _DraftEditorCard extends StatefulWidget {
  const _DraftEditorCard({
    required this.interactionMode,
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.draftSurfaceStart,
    required this.draftSurfaceEnd,
    required this.draftSurfacePointCount,
    required this.draftSurfaceWallCount,
    required this.draftSurfaceThicknessMeters,
    required this.draftSurfaceHeightMeters,
    required this.draftStairWidthMeters,
    required this.draftFloorTopElevationMeters,
    required this.surfaceDrawMode,
    required this.draftHostWall,
    required this.openingOffsetMeters,
    required this.openingWidthMeters,
    required this.openingHeightMeters,
    required this.openingSillHeightMeters,
    required this.trimFirstWall,
    required this.trimSecondWall,
    required this.trimPreview,
    required this.editStatusMessage,
    required this.snapEnabled,
    required this.canConfirm,
    required this.onSnapToggled,
    required this.onOpeningOffsetChanged,
    required this.onOpeningWidthChanged,
    required this.onOpeningHeightChanged,
    required this.onOpeningSillHeightChanged,
    required this.onSurfaceThicknessChanged,
    required this.onSurfaceHeightChanged,
    required this.onFloorTopElevationChanged,
    required this.onStairWidthChanged,
    required this.onConfirm,
    required this.onCancel,
    required this.onClearSelection,
    required this.onResetMode,
  });

  final RenderSceneInteractionMode interactionMode;
  final RenderScenePoint? draftWallStart;
  final RenderScenePoint? draftWallEnd;
  final RenderScenePoint? draftSurfaceStart;
  final RenderScenePoint? draftSurfaceEnd;
  final int draftSurfacePointCount;
  final int draftSurfaceWallCount;
  final double draftSurfaceThicknessMeters;
  final double draftSurfaceHeightMeters;
  final double draftStairWidthMeters;
  final double draftFloorTopElevationMeters;
  final RenderSceneSurfaceDrawMode surfaceDrawMode;
  final RenderSceneObject? draftHostWall;
  final double openingOffsetMeters;
  final double openingWidthMeters;
  final double openingHeightMeters;
  final double openingSillHeightMeters;
  final TrimExtendWallSelection? trimFirstWall;
  final TrimExtendWallSelection? trimSecondWall;
  final PlanSketchTrimResult? trimPreview;
  final String? editStatusMessage;
  final bool snapEnabled;
  final bool canConfirm;
  final ValueChanged<bool> onSnapToggled;
  final ValueChanged<double> onOpeningOffsetChanged;
  final ValueChanged<double> onOpeningWidthChanged;
  final ValueChanged<double> onOpeningHeightChanged;
  final ValueChanged<double> onOpeningSillHeightChanged;
  final ValueChanged<double> onSurfaceThicknessChanged;
  final ValueChanged<double> onSurfaceHeightChanged;
  final ValueChanged<double> onFloorTopElevationChanged;
  final ValueChanged<double> onStairWidthChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onClearSelection;
  final VoidCallback onResetMode;

  @override
  State<_DraftEditorCard> createState() => _DraftEditorCardState();
}

class _DraftEditorCardState extends State<_DraftEditorCard> {
  TextEditingController? _offsetController;
  TextEditingController? _widthController;
  TextEditingController? _heightController;
  TextEditingController? _sillController;
  TextEditingController? _surfaceThicknessController;
  TextEditingController? _surfaceHeightController;
  TextEditingController? _floorTopController;
  TextEditingController? _stairWidthController;

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void didUpdateWidget(covariant _DraftEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_offsetController, widget.openingOffsetMeters,
        oldWidget.openingOffsetMeters);
    _syncController(_widthController, widget.openingWidthMeters,
        oldWidget.openingWidthMeters);
    _syncController(_heightController, widget.openingHeightMeters,
        oldWidget.openingHeightMeters);
    _syncController(_sillController, widget.openingSillHeightMeters,
        oldWidget.openingSillHeightMeters);
    _syncController(
        _surfaceThicknessController,
        widget.draftSurfaceThicknessMeters,
        oldWidget.draftSurfaceThicknessMeters);
    _syncController(_surfaceHeightController, widget.draftSurfaceHeightMeters,
        oldWidget.draftSurfaceHeightMeters);
    _syncController(_floorTopController, widget.draftFloorTopElevationMeters,
        oldWidget.draftFloorTopElevationMeters);
    _syncController(_stairWidthController, widget.draftStairWidthMeters,
        oldWidget.draftStairWidthMeters);
  }

  @override
  void dispose() {
    _offsetController?.dispose();
    _widthController?.dispose();
    _heightController?.dispose();
    _sillController?.dispose();
    _surfaceThicknessController?.dispose();
    _surfaceHeightController?.dispose();
    _floorTopController?.dispose();
    _stairWidthController?.dispose();
    super.dispose();
  }

  void _syncController(
    TextEditingController? controller,
    double next,
    double previous,
  ) {
    if (controller == null) {
      return;
    }
    if ((next - previous).abs() < 1e-9) {
      return;
    }
    controller.text = _format(next);
  }

  void _ensureControllers() {
    _offsetController ??=
        TextEditingController(text: _format(widget.openingOffsetMeters));
    _widthController ??=
        TextEditingController(text: _format(widget.openingWidthMeters));
    _heightController ??=
        TextEditingController(text: _format(widget.openingHeightMeters));
    _sillController ??=
        TextEditingController(text: _format(widget.openingSillHeightMeters));
    _surfaceThicknessController ??= TextEditingController(
      text: _format(widget.draftSurfaceThicknessMeters),
    );
    _surfaceHeightController ??=
        TextEditingController(text: _format(widget.draftSurfaceHeightMeters));
    _floorTopController ??= TextEditingController(
        text: _format(widget.draftFloorTopElevationMeters));
    _stairWidthController ??=
        TextEditingController(text: _format(widget.draftStairWidthMeters));
  }

  String _format(double value) {
    return value.toStringAsFixed(2);
  }

  double? _parse(String text) {
    return double.tryParse(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final theme = Theme.of(context);
    final mode = widget.interactionMode;
    final wall = widget.draftHostWall;

    return _InfoCard(
      title: 'Edit',
      icon: Icons.build_outlined,
      children: <Widget>[
        _InfoRow(label: 'Mode', value: mode.authoringLabel),
        if (mode != RenderSceneInteractionMode.trimExtend)
          _InfoRow(
            label: 'Snap',
            value: widget.snapEnabled ? 'On' : 'Off',
            trailing: Switch.adaptive(
              value: widget.snapEnabled,
              onChanged: widget.onSnapToggled,
            ),
          ),
        if (widget.editStatusMessage != null)
          Text(
            widget.editStatusMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        if (mode == RenderSceneInteractionMode.select)
          const Text('Select mode: tap objects to inspect them.')
        else if (mode == RenderSceneInteractionMode.addLevel)
          _LevelDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.moveLevel)
          _LevelDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.addWall)
          _WallDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.addStair)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                  'Ikki nuqta bilan straight stair run chizing. Rise Base/Top Leveldan olinadi.'),
              const SizedBox(height: 8),
              _WallDraftSummary(
                start: widget.draftWallStart,
                end: widget.draftWallEnd,
              ),
              const SizedBox(height: 8),
              _NumericField(
                label: 'Width (m)',
                controller: _stairWidthController!,
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) widget.onStairWidthChanged(parsed);
                },
              ),
            ],
          )
        else if (mode == RenderSceneInteractionMode.moveWall)
          _WallDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.trimExtend)
          _TrimExtendDraftSummary(
            first: widget.trimFirstWall,
            second: widget.trimSecondWall,
            preview: widget.trimPreview,
          )
        else if (mode == RenderSceneInteractionMode.addFloor ||
            mode == RenderSceneInteractionMode.addCeiling ||
            mode == RenderSceneInteractionMode.addRoof)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SurfaceDraftSummary(
                mode: mode,
                start: widget.draftSurfaceStart,
                end: widget.draftSurfaceEnd,
                pointCount: widget.draftSurfacePointCount,
                wallCount: widget.draftSurfaceWallCount,
                drawMode: widget.surfaceDrawMode,
              ),
              const SizedBox(height: 8),
              _NumericField(
                label: 'Thickness (m)',
                controller: _surfaceThicknessController!,
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) {
                    widget.onSurfaceThicknessChanged(parsed);
                  }
                },
              ),
              if (mode == RenderSceneInteractionMode.addFloor)
                _NumericField(
                  label: 'Top elevation (m)',
                  controller: _floorTopController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) {
                      widget.onFloorTopElevationChanged(parsed);
                    }
                  },
                )
              else if (mode == RenderSceneInteractionMode.addCeiling)
                _NumericField(
                  label: 'Height offset (m)',
                  controller: _surfaceHeightController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) {
                      widget.onSurfaceHeightChanged(parsed);
                    }
                  },
                )
              else
                const Text(
                  'Roof uses the same boundary sketch. Shape, slope and overhang stay editable in Properties.',
                ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _InfoRow(
                label: 'Host wall',
                value: wall?.elementId?.toString() ?? 'Select a wall',
              ),
              const SizedBox(height: 8),
              _NumericField(
                label: 'Offset (m)',
                controller: _offsetController!,
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) {
                    widget.onOpeningOffsetChanged(parsed);
                  }
                },
              ),
              _NumericField(
                label: 'Width (m)',
                controller: _widthController!,
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) {
                    widget.onOpeningWidthChanged(parsed);
                  }
                },
              ),
              _NumericField(
                label: 'Height (m)',
                controller: _heightController!,
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) {
                    widget.onOpeningHeightChanged(parsed);
                  }
                },
              ),
              if (mode == RenderSceneInteractionMode.addWindow)
                _NumericField(
                  label: 'Sill height (m)',
                  controller: _sillController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) {
                      widget.onOpeningSillHeightChanged(parsed);
                    }
                  },
                ),
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Preview',
                value: wall == null ? 'No wall selected' : 'Ready',
              ),
            ],
          ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: widget.canConfirm ? widget.onConfirm : null,
                child: Text(
                  mode == RenderSceneInteractionMode.trimExtend
                      ? 'Trim / Extend'
                      : 'Confirm',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onResetMode,
          child: const Text('Back to Select'),
        ),
        TextButton(
          onPressed: widget.onClearSelection,
          child: const Text('Clear selection'),
        ),
      ],
    );
  }
}

class _WallDraftSummary extends StatelessWidget {
  const _WallDraftSummary({
    required this.start,
    required this.end,
  });

  final RenderScenePoint? start;
  final RenderScenePoint? end;

  @override
  Widget build(BuildContext context) {
    if (start == null || end == null) {
      return const Text('Tap once to set the wall start point.');
    }

    final length = start!.distanceTo(end!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InfoRow(
          label: 'Start',
          value:
              '(${start!.x.toStringAsFixed(2)}, ${start!.y.toStringAsFixed(2)})',
        ),
        _InfoRow(
          label: 'End',
          value: '(${end!.x.toStringAsFixed(2)}, ${end!.y.toStringAsFixed(2)})',
        ),
        _InfoRow(
          label: 'Length',
          value: '${length.toStringAsFixed(2)} m',
        ),
      ],
    );
  }
}

class _TrimExtendDraftSummary extends StatelessWidget {
  const _TrimExtendDraftSummary({
    required this.first,
    required this.second,
    required this.preview,
  });

  final TrimExtendWallSelection? first;
  final TrimExtendWallSelection? second;
  final PlanSketchTrimResult? preview;

  String _endpointLabel(PlanSketchEndpoint endpoint) =>
      endpoint == PlanSketchEndpoint.start ? 'Start' : 'End';

  @override
  Widget build(BuildContext context) {
    if (first == null) {
      return const Text(
        'Birinchi wallni o‘zgartirmoqchi bo‘lgan uchiga yaqin joyidan bosing.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InfoRow(
          label: 'First wall',
          value:
              '#${first!.wall.elementId} · ${_endpointLabel(first!.endpoint)}',
        ),
        if (second == null)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Endi ikkinchi wallni uning trim/extend qilinadigan uchiga yaqin joyidan bosing.',
            ),
          )
        else ...<Widget>[
          _InfoRow(
            label: 'Second wall',
            value:
                '#${second!.wall.elementId} · ${_endpointLabel(second!.endpoint)}',
          ),
          if (preview != null)
            _InfoRow(
              label: 'Join point',
              value:
                  '(${preview!.intersection.x.toStringAsFixed(2)}, ${preview!.intersection.y.toStringAsFixed(2)})',
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Bu uchlar parallel yoki juda qisqa natija beradi. Boshqa uchni tanlang.',
              ),
            ),
        ],
      ],
    );
  }
}

class _LevelDraftSummary extends StatelessWidget {
  const _LevelDraftSummary({
    required this.start,
    required this.end,
  });

  final RenderScenePoint? start;
  final RenderScenePoint? end;

  @override
  Widget build(BuildContext context) {
    if (start == null || end == null) {
      return const Text(
        'Elevation view’da 2 marta bosing: birinchi bosish balandlikni, ikkinchisi level line uzunligini beradi.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InfoRow(
          label: 'Elevation',
          value: '${end!.z.toStringAsFixed(2)} m',
        ),
        _InfoRow(
          label: 'Line',
          value:
              '(${start!.x.toStringAsFixed(2)}, ${start!.z.toStringAsFixed(2)}) → (${end!.x.toStringAsFixed(2)}, ${end!.z.toStringAsFixed(2)})',
        ),
      ],
    );
  }
}

class _SurfaceDraftSummary extends StatelessWidget {
  const _SurfaceDraftSummary({
    required this.mode,
    required this.start,
    required this.end,
    required this.pointCount,
    required this.wallCount,
    required this.drawMode,
  });

  final RenderSceneInteractionMode mode;
  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final int pointCount;
  final int wallCount;
  final RenderSceneSurfaceDrawMode drawMode;

  @override
  Widget build(BuildContext context) {
    final label = switch (mode) {
      RenderSceneInteractionMode.addFloor => 'floor',
      RenderSceneInteractionMode.addCeiling => 'ceiling',
      RenderSceneInteractionMode.addRoof => 'roof',
      _ => 'surface',
    };
    if (drawMode == RenderSceneSurfaceDrawMode.pickWalls && wallCount >= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '$wallCount ta devor tanlangan. Confirm bossangiz $label devorlar chegarasidan hosil qilinadi.',
          ),
          if (start != null && end != null) ...<Widget>[
            const SizedBox(height: 8),
            _InfoRow(
              label: 'Bounds',
              value:
                  '${(end!.x - start!.x).abs().toStringAsFixed(2)} × ${(end!.y - start!.y).abs().toStringAsFixed(2)} m',
            ),
          ],
        ],
      );
    }

    if (drawMode == RenderSceneSurfaceDrawMode.polyline) {
      return Text(
        pointCount < 3
            ? '$pointCount nuqta qo‘yildi. Yana nuqta qo‘shing.'
            : 'Polyline boundary tayyor. Confirm bossangiz $label yaratiladi.',
      );
    }

    if (drawMode == RenderSceneSurfaceDrawMode.autoRoom) {
      return Text(
        mode == RenderSceneInteractionMode.addRoof
            ? 'Roof uchun AutoRoom hozircha yo‘q. Rectangle, Polyline yoki Pick Walls ishlating.'
            : 'Room ustiga bossangiz $label yaratiladi.',
      );
    }

    if (start == null || end == null) {
      return Text(
        'Bo‘sh joyga chizing yoki devorlarni tanlang. Shu kernel $label uchun ishlaydi.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Rectangle draft tayyor. Confirm bossangiz $label yaratiladi.'),
        const SizedBox(height: 8),
        _InfoRow(
          label: 'Start',
          value:
              '(${start!.x.toStringAsFixed(2)}, ${start!.y.toStringAsFixed(2)})',
        ),
        _InfoRow(
          label: 'End',
          value: '(${end!.x.toStringAsFixed(2)}, ${end!.y.toStringAsFixed(2)})',
        ),
        _InfoRow(
          label: 'Size',
          value:
              '${(end!.x - start!.x).abs().toStringAsFixed(2)} × ${(end!.y - start!.y).abs().toStringAsFixed(2)} m',
        ),
      ],
    );
  }
}

class _NumericField extends StatelessWidget {
  const _NumericField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _SelectedObjectCard extends StatelessWidget {
  const _SelectedObjectCard({
    required this.object,
    required this.sceneLevels,
    required this.onLevelLockChanged,
    this.onEditWallLevels,
    this.onMoveOpeningLevel,
    this.onAssignLevel,
    this.onAttachWallToActiveLevel,
    this.onAttachWallTopToNextLevel,
    this.onMoveOpeningToActiveLevel,
    this.onApplyWallLevels,
    this.onEditOpeningPlacement,
    this.onDelete,
  });

  final RenderSceneObject object;
  final List<RenderSceneLevel> sceneLevels;
  final ValueChanged<bool> onLevelLockChanged;
  final VoidCallback? onEditWallLevels;
  final VoidCallback? onMoveOpeningLevel;
  final VoidCallback? onAssignLevel;
  final VoidCallback? onAttachWallToActiveLevel;
  final VoidCallback? onAttachWallTopToNextLevel;
  final VoidCallback? onMoveOpeningToActiveLevel;
  final Future<void> Function({
    required int baseLevelId,
    required int topLevelId,
    required int heightMode,
  })? onApplyWallLevels;
  final Future<void> Function()? onEditOpeningPlacement;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = prettySceneKind(object.kind);
    final area = _objectMetadataDouble(object, 'area_m2');
    final perimeter = _objectMetadataDouble(object, 'perimeter_m');
    final wallThickness = _objectMetadataDouble(object, 'thickness_meters');
    final wallHeight = _objectMetadataDouble(object, 'height_meters');
    final wallStart = _wallPointSummary(
      object,
      xKey: 'start_x',
      yKey: 'start_y',
      legacyKey: 'axis_start',
    );
    final wallEnd = _wallPointSummary(
      object,
      xKey: 'end_x',
      yKey: 'end_y',
      legacyKey: 'axis_end',
    );
    final baseLevelId = object.metadata['base_level_id'];
    final topLevelId = object.metadata['top_level_id'];
    final heightMode = object.metadata['height_mode']?.toString();
    final levelLocked = RenderSceneEditor.isElementLevelLocked(object);
    final canToggleLevelLock =
        object.kindKey == 'door' || object.kindKey == 'window';

    return _InfoCard(
      title: 'Selected object',
      icon: _kindIcon(object.kindKey),
      children: <Widget>[
        _InfoRow(label: 'Kind', value: kind),
        _InfoRow(
            label: 'Element ID', value: object.elementId?.toString() ?? '-'),
        _InfoRow(label: 'Level ID', value: object.levelId?.toString() ?? '-'),
        if (canToggleLevelLock)
          _InfoRow(
            label: 'Level lock',
            value: levelLocked ? 'On' : 'Off',
            trailing: Switch.adaptive(
              value: levelLocked,
              onChanged: onLevelLockChanged,
            ),
          ),
        if (wallThickness != null)
          _InfoRow(
            label: 'Thickness',
            value: '${wallThickness.toStringAsFixed(2)} m',
          ),
        if (wallHeight != null)
          _InfoRow(
            label: 'Height',
            value: '${wallHeight.toStringAsFixed(2)} m',
          ),
        if (object.kindKey == 'wall')
          _InfoRow(label: 'Base level', value: '${baseLevelId ?? '-'}'),
        if (object.kindKey == 'wall')
          _InfoRow(
            label: 'Top constraint',
            value: '${topLevelId ?? '-'} (${heightMode ?? 'Unconnected'})',
          ),
        if (object.kindKey == 'stair') ...<Widget>[
          _InfoRow(label: 'Base level', value: '${baseLevelId ?? '-'}'),
          _InfoRow(label: 'Top level', value: '${topLevelId ?? '-'}'),
          _InfoRow(
            label: 'Run / rise',
            value:
                '${object.metadata['total_run_meters'] ?? '-'} m / ${object.metadata['total_rise_meters'] ?? '-'} m',
          ),
          _InfoRow(
            label: 'Treads / risers',
            value:
                '${object.metadata['tread_count'] ?? '-'} / ${object.metadata['riser_count'] ?? '-'}',
          ),
        ],
        if (object.kindKey == 'wall' &&
            sceneLevels.isNotEmpty &&
            onApplyWallLevels != null)
          _WallLevelInlineEditor(
            object: object,
            levels: sceneLevels,
            onApply: onApplyWallLevels!,
          ),
        if (object.kindKey == 'wall' && onEditWallLevels != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onAttachWallToActiveLevel,
                  icon: const Icon(Icons.vertical_align_bottom),
                  label: const Text('Base -> active'),
                ),
                OutlinedButton.icon(
                  onPressed: onAttachWallTopToNextLevel,
                  icon: const Icon(Icons.unfold_more),
                  label: const Text('Top -> next'),
                ),
                OutlinedButton.icon(
                  onPressed: onEditWallLevels,
                  icon: const Icon(Icons.tune),
                  label: const Text('Advanced'),
                ),
              ],
            ),
          ),
        if ((object.kindKey == 'door' || object.kindKey == 'window') &&
            onMoveOpeningLevel != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onMoveOpeningToActiveLevel,
                  icon: const Icon(Icons.layers_outlined),
                  label: const Text('Move -> active'),
                ),
                OutlinedButton.icon(
                  onPressed: onMoveOpeningLevel,
                  icon: const Icon(Icons.vertical_align_center),
                  label: const Text('Choose level'),
                ),
              ],
            ),
          ),
        if (onAssignLevel != null &&
            object.kindKey != 'wall' &&
            object.kindKey != 'door' &&
            object.kindKey != 'window')
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAssignLevel,
              icon: const Icon(Icons.layers),
              label: const Text('Assign level'),
            ),
          ),
        if (onEditOpeningPlacement != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onEditOpeningPlacement,
              icon: const Icon(Icons.open_with),
              label: const Text('Edit placement and size'),
            ),
          ),
        if (wallStart != null && wallEnd != null) ...<Widget>[
          _InfoRow(label: 'Axis start', value: wallStart),
          _InfoRow(label: 'Axis end', value: wallEnd),
        ],
        if (area != null)
          _InfoRow(
            label: 'Area',
            value: '${area.toStringAsFixed(2)} m²',
          ),
        if (perimeter != null)
          _InfoRow(
            label: 'Perimeter',
            value: '${perimeter.toStringAsFixed(2)} m',
          ),
        _InfoRow(label: 'Material', value: object.materialCategory),
        if (onDelete != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete element'),
            ),
          ),
      ],
    );
  }
}

String? _wallPointSummary(
  RenderSceneObject object, {
  required String xKey,
  required String yKey,
  required String legacyKey,
}) {
  final x = _objectMetadataDouble(object, xKey);
  final y = _objectMetadataDouble(object, yKey);
  if (x != null && y != null) {
    return '${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}';
  }
  final legacy = object.metadata[legacyKey];
  if (legacy is Map && legacy['x'] != null && legacy['y'] != null) {
    return '${legacy['x']}, ${legacy['y']}';
  }
  return null;
}

double? _objectMetadataDouble(RenderSceneObject object, String key) {
  final value = object.metadata[key];
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _objectMetadataInt(RenderSceneObject object, String key) {
  final value = object.metadata[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

// Kept as a diagnostics building block for the optional diagnostics surface.
class _SceneSummaryCard extends StatelessWidget {
  const _SceneSummaryCard({
    required this.scene,
    required this.activeLevel,
  });

  final RenderScene scene;
  final RenderSceneLevel? activeLevel;

  @override
  Widget build(BuildContext context) {
    final bounds = scene.bounds;

    return _InfoCard(
      title: 'Scene summary',
      icon: Icons.analytics_outlined,
      children: <Widget>[
        _InfoRow(label: 'Source', value: scene.source),
        _InfoRow(label: 'Version', value: scene.sceneVersion.toString()),
        _InfoRow(label: 'Units', value: scene.units),
        _InfoRow(label: 'Coordinates', value: scene.coordinateSystem),
        _InfoRow(label: 'Levels', value: scene.levels.length.toString()),
        if (activeLevel != null)
          _InfoRow(
            label: 'Active level',
            value:
                '${activeLevel!.name} @ ${activeLevel!.elevationMeters.toStringAsFixed(2)} m',
          ),
        _InfoRow(label: 'Objects', value: scene.objectCount.toString()),
        _InfoRow(label: 'Vertices', value: scene.vertexCount.toString()),
        _InfoRow(label: 'Indices', value: scene.indexCount.toString()),
        _InfoRow(label: 'Triangles', value: scene.triangleCount.toString()),
        _InfoRow(
          label: 'Bounds',
          value:
              '${bounds.width.toStringAsFixed(2)} × ${bounds.depth.toStringAsFixed(2)} × ${bounds.height.toStringAsFixed(2)} m',
        ),
      ],
    );
  }
}

class _AndroidMutationTrace extends StatelessWidget {
  const _AndroidMutationTrace({required this.entries});

  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Card(
        color: const Color(0xED111827),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.25,
              fontFamily: 'monospace',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('ANDROID MUTATION TRACE',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                for (final entry in entries) Text(entry, maxLines: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedLevelCard extends StatelessWidget {
  const _SelectedLevelCard({
    required this.level,
    required this.onElevationSubmitted,
    required this.onEdit,
  });

  final RenderSceneLevel level;
  final Future<void> Function(String value) onElevationSubmitted;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Selected level',
      icon: Icons.straighten,
      children: <Widget>[
        _InfoRow(label: 'Name', value: level.name),
        _InfoRow(label: 'Level ID', value: level.levelId.toString()),
        TextFormField(
          initialValue: level.elevationMeters.toStringAsFixed(2),
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Elevation (m)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: onElevationSubmitted,
        ),
        _InfoRow(
          label: 'Default wall height',
          value: '${level.defaultWallHeightMeters.toStringAsFixed(2)} m',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit level properties'),
          ),
        ),
      ],
    );
  }
}

class _MultiSelectionInspectorCard extends StatelessWidget {
  const _MultiSelectionInspectorCard({
    required this.count,
    required this.onClear,
  });

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Multiple selection',
      icon: Icons.select_all,
      children: <Widget>[
        Text('$count ta obyekt tanlangan.'),
        const SizedBox(height: 6),
        const Text(
          'Faqat barcha tanlangan obyektlarga umumiy bo‘lgan xavfsiz propertylar keyinroq batch edit qilinadi. Hozir noto‘g‘ri qiymat o‘zgarmasligi uchun individual Inspector oching.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            label: const Text('Clear selection'),
          ),
        ),
      ],
    );
  }
}

class _ActiveLevelCard extends StatelessWidget {
  const _ActiveLevelCard({
    required this.level,
    required this.levels,
    required this.activeLevelId,
    required this.onSelectLevel,
  });

  final RenderSceneLevel? level;
  final List<RenderSceneLevel> levels;
  final int? activeLevelId;
  final Future<void> Function(int? levelId) onSelectLevel;

  @override
  Widget build(BuildContext context) {
    if (level == null) {
      return const _InfoCard(
        title: 'Active level',
        icon: Icons.straighten,
        children: <Widget>[
          Text('No active level selected.'),
        ],
      );
    }

    return _InfoCard(
      title: 'Active level',
      icon: Icons.straighten,
      children: <Widget>[
        _InfoRow(label: 'Name', value: level!.name),
        _InfoRow(label: 'Level ID', value: level!.levelId.toString()),
        _InfoRow(
          label: 'Elevation',
          value: '${level!.elevationMeters.toStringAsFixed(2)} m',
        ),
        _InfoRow(
          label: 'Default wall height',
          value: '${level!.defaultWallHeightMeters.toStringAsFixed(2)} m',
        ),
        if (levels.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          const Text(
            'Levels',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Column(
            children: levels
                .map<Widget>(
                  (entry) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        tileColor: entry.levelId == activeLevelId
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.55)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: Icon(
                          entry.levelId == activeLevelId
                              ? Icons.check_circle
                              : Icons.straighten,
                          size: 18,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                            '${entry.elevationMeters.toStringAsFixed(2)} m'),
                        onTap: () => onSelectLevel(entry.levelId),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 4),
          const Text('Tap row: select level.', style: TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}

class _WallLevelInlineEditor extends StatefulWidget {
  const _WallLevelInlineEditor({
    required this.object,
    required this.levels,
    required this.onApply,
  });

  final RenderSceneObject object;
  final List<RenderSceneLevel> levels;
  final Future<void> Function({
    required int baseLevelId,
    required int topLevelId,
    required int heightMode,
  }) onApply;

  @override
  State<_WallLevelInlineEditor> createState() => _WallLevelInlineEditorState();
}

class _WallLevelInlineEditorState extends State<_WallLevelInlineEditor> {
  late int _baseLevelId;
  late int _topLevelId;
  late int _heightMode;

  @override
  void initState() {
    super.initState();
    _syncFromObject();
  }

  @override
  void didUpdateWidget(covariant _WallLevelInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object != widget.object ||
        oldWidget.levels != widget.levels) {
      _syncFromObject();
    }
  }

  void _syncFromObject() {
    final firstLevelId =
        widget.levels.isNotEmpty ? widget.levels.first.levelId : 0;
    _baseLevelId = _objectInt(widget.object, 'base_level_id') ??
        widget.object.levelId ??
        firstLevelId;
    _topLevelId = _objectInt(widget.object, 'top_level_id') ?? 0;
    _heightMode =
        (widget.object.metadata['height_mode']?.toString() == 'TopLevel')
            ? 1
            : 0;
    if (_heightMode == 1 && _topLevelId == 0 && widget.levels.length > 1) {
      final sorted = [...widget.levels]
        ..sort((a, b) => a.elevationMeters.compareTo(b.elevationMeters));
      RenderSceneLevel? base;
      for (final level in sorted) {
        if (level.levelId == _baseLevelId) {
          base = level;
          break;
        }
      }
      if (base != null) {
        RenderSceneLevel? next;
        for (final level in sorted) {
          if (level.elevationMeters > base.elevationMeters + 1e-6) {
            next = level;
            break;
          }
        }
        _topLevelId = next?.levelId ?? 0;
      }
    }
  }

  int? _objectInt(RenderSceneObject object, String key) {
    final value = object.metadata[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final levels = widget.levels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        const Text(
          'Wall levels',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: levels.any((level) => level.levelId == _baseLevelId)
              ? _baseLevelId
              : levels.first.levelId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Base level',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: levels
              .map(
                (level) => DropdownMenuItem<int>(
                  value: level.levelId,
                  child: Text(
                    '${level.name} (${level.elevationMeters.toStringAsFixed(2)}m)',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _baseLevelId = value;
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _heightMode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Height mode',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const <DropdownMenuItem<int>>[
            DropdownMenuItem<int>(value: 0, child: Text('Unconnected')),
            DropdownMenuItem<int>(value: 1, child: Text('Top level')),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _heightMode = value;
              if (_heightMode == 0) {
                _topLevelId = 0;
              }
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _topLevelId == 0 ? null : _topLevelId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Top level',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: levels
              .map(
                (level) => DropdownMenuItem<int>(
                  value: level.levelId,
                  child: Text(
                    '${level.name} (${level.elevationMeters.toStringAsFixed(2)}m)',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _heightMode == 0
              ? null
              : (value) {
                  setState(() {
                    _topLevelId = value ?? 0;
                  });
                },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () {
              widget.onApply(
                baseLevelId: _baseLevelId,
                topLevelId: _topLevelId,
                heightMode: _heightMode,
              );
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Apply wall levels'),
          ),
        ),
      ],
    );
  }
}

class _EstimateSummaryCard extends StatelessWidget {
  const _EstimateSummaryCard({
    required this.summary,
    required this.catalog,
    required this.onCatalogChanged,
  });

  final RenderSceneEstimateSummary summary;
  final RenderSceneEstimateCatalog catalog;
  final ValueChanged<RenderSceneEstimateCatalog> onCatalogChanged;

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Estimate',
      icon: Icons.request_quote_outlined,
      children: <Widget>[
        _InfoRow(label: 'Rooms', value: summary.roomCount.toString()),
        _InfoRow(
          label: 'Room area',
          value: '${summary.totalRoomArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Room perimeter',
          value: '${summary.totalRoomPerimeter.toStringAsFixed(2)} m',
        ),
        _InfoRow(label: 'Walls', value: summary.wallCount.toString()),
        _InfoRow(
          label: 'Wall gross volume',
          value: '${summary.wallGrossVolume.toStringAsFixed(2)} m³',
        ),
        _InfoRow(
          label: 'Wall net volume',
          value: '${summary.wallNetVolume.toStringAsFixed(2)} m³',
        ),
        _InfoRow(
          label: 'Wall net area',
          value: '${summary.wallNetArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Brick count',
          value: summary.brickCount.toString(),
        ),
        _InfoRow(
          label: 'Floors',
          value:
              '${summary.floorCount} · ${summary.floorArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Concrete',
          value: '${summary.floorConcreteVolume.toStringAsFixed(2)} m³',
        ),
        _InfoRow(
          label: 'Floor finish',
          value: '${summary.floorArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Ceilings',
          value:
              '${summary.ceilingCount} · ${summary.ceilingArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Doors / Windows',
          value: '${summary.doorCount} / ${summary.windowCount}',
        ),
        _InfoRow(
          label: 'Opening area',
          value: '${summary.openingArea.toStringAsFixed(2)} m²',
        ),
        const SizedBox(height: 10),
        Text(
          'Cost lines',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final item in summary.lineItems)
          _InfoRow(
            label:
                '${item.label} (${item.quantity.toStringAsFixed(item.unit == 'pcs' ? 0 : 2)} ${item.unit})',
            value: '${_money(item.unitCost)} → ${_money(item.totalCost)}',
          ),
        const SizedBox(height: 8),
        _InfoRow(
          label: 'Estimated total',
          value: _money(summary.totalCost),
        ),
        const SizedBox(height: 12),
        _EstimateCatalogEditor(
          catalog: catalog,
          onChanged: onCatalogChanged,
        ),
      ],
    );
  }
}

class _EstimateCatalogEditor extends StatefulWidget {
  const _EstimateCatalogEditor({
    required this.catalog,
    required this.onChanged,
  });

  final RenderSceneEstimateCatalog catalog;
  final ValueChanged<RenderSceneEstimateCatalog> onChanged;

  @override
  State<_EstimateCatalogEditor> createState() => _EstimateCatalogEditorState();
}

class _EstimateCatalogEditorState extends State<_EstimateCatalogEditor> {
  late final TextEditingController _brickDensityController;
  late final TextEditingController _brickUnitCostController;
  late final TextEditingController _concreteController;
  late final TextEditingController _floorFinishController;
  late final TextEditingController _ceilingController;
  late final TextEditingController _doorController;
  late final TextEditingController _windowController;

  @override
  void initState() {
    super.initState();
    _brickDensityController = TextEditingController();
    _brickUnitCostController = TextEditingController();
    _concreteController = TextEditingController();
    _floorFinishController = TextEditingController();
    _ceilingController = TextEditingController();
    _doorController = TextEditingController();
    _windowController = TextEditingController();
    _syncFromCatalog(widget.catalog);
  }

  @override
  void didUpdateWidget(covariant _EstimateCatalogEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      _syncFromCatalog(widget.catalog);
    }
  }

  @override
  void dispose() {
    _brickDensityController.dispose();
    _brickUnitCostController.dispose();
    _concreteController.dispose();
    _floorFinishController.dispose();
    _ceilingController.dispose();
    _doorController.dispose();
    _windowController.dispose();
    super.dispose();
  }

  void _syncFromCatalog(RenderSceneEstimateCatalog catalog) {
    _brickDensityController.text = _format(catalog.bricksPerCubicMeter);
    _brickUnitCostController.text = _format(catalog.brickUnitCost);
    _concreteController.text = _format(catalog.concreteCostPerCubicMeter);
    _floorFinishController.text =
        _format(catalog.floorFinishCostPerSquareMeter);
    _ceilingController.text = _format(catalog.ceilingCostPerSquareMeter);
    _doorController.text = _format(catalog.doorUnitCost);
    _windowController.text = _format(catalog.windowUnitCost);
  }

  String _format(double value) => value.toStringAsFixed(2);

  void _updateCatalog({
    double? bricksPerCubicMeter,
    double? brickUnitCost,
    double? concreteCostPerCubicMeter,
    double? floorFinishCostPerSquareMeter,
    double? ceilingCostPerSquareMeter,
    double? doorUnitCost,
    double? windowUnitCost,
  }) {
    widget.onChanged(
      widget.catalog.copyWith(
        bricksPerCubicMeter: bricksPerCubicMeter,
        brickUnitCost: brickUnitCost,
        concreteCostPerCubicMeter: concreteCostPerCubicMeter,
        floorFinishCostPerSquareMeter: floorFinishCostPerSquareMeter,
        ceilingCostPerSquareMeter: ceilingCostPerSquareMeter,
        doorUnitCost: doorUnitCost,
        windowUnitCost: windowUnitCost,
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<double> onValue,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = double.tryParse(value.trim());
          if (parsed != null && parsed >= 0) {
            onValue(parsed);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        'Unit prices',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      subtitle: const Text('Live estimate shu qiymatlar bilan yangilanadi'),
      children: <Widget>[
        _buildField(
          label: 'Bricks per m³',
          controller: _brickDensityController,
          onValue: (value) => _updateCatalog(bricksPerCubicMeter: value),
        ),
        _buildField(
          label: 'Brick unit cost',
          controller: _brickUnitCostController,
          onValue: (value) => _updateCatalog(brickUnitCost: value),
        ),
        _buildField(
          label: 'Concrete cost per m³',
          controller: _concreteController,
          onValue: (value) => _updateCatalog(concreteCostPerCubicMeter: value),
        ),
        _buildField(
          label: 'Floor finish cost per m²',
          controller: _floorFinishController,
          onValue: (value) =>
              _updateCatalog(floorFinishCostPerSquareMeter: value),
        ),
        _buildField(
          label: 'Ceiling cost per m²',
          controller: _ceilingController,
          onValue: (value) => _updateCatalog(ceilingCostPerSquareMeter: value),
        ),
        _buildField(
          label: 'Door unit cost',
          controller: _doorController,
          onValue: (value) => _updateCatalog(doorUnitCost: value),
        ),
        _buildField(
          label: 'Window unit cost',
          controller: _windowController,
          onValue: (value) => _updateCatalog(windowUnitCost: value),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              const defaults = RenderSceneEstimateCatalog();
              _syncFromCatalog(defaults);
              widget.onChanged(defaults);
            },
            child: const Text('Reset defaults'),
          ),
        ),
      ],
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.scene,
  });

  final RenderScene scene;

  @override
  Widget build(BuildContext context) {
    final diagnostics = scene.diagnostics;

    return _InfoCard(
      title: 'Diagnostics',
      icon: Icons.bug_report_outlined,
      children: <Widget>[
        _InfoRow(label: 'Source', value: diagnostics.source),
        _InfoRow(
            label: 'Visible', value: diagnostics.visibleObjectCount.toString()),
        _InfoRow(
          label: 'Selectable',
          value: diagnostics.selectableObjectCount.toString(),
        ),
        _InfoRow(
          label: 'Missing geometry',
          value: diagnostics.missingGeometryCount.toString(),
        ),
        _InfoRow(
          label: 'Invalid bounds',
          value: diagnostics.invalidBoundsCount.toString(),
        ),
        _InfoRow(label: 'Levels', value: diagnostics.levelCount.toString()),
        const SizedBox(height: 8),
        Text(
          'Kinds',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final entry in diagnostics.kindCounts.entries)
          _InfoRow(
            label: prettySceneKind(entry.key),
            value: entry.value.toString(),
          ),
        if (diagnostics.warnings.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Warnings',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          for (final warning in diagnostics.warnings)
            _BulletText(text: warning),
        ],
        if (diagnostics.errors.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Errors',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: const Color(0xFF991B1B)),
          ),
          const SizedBox(height: 6),
          for (final error in diagnostics.errors)
            _BulletText(text: error, color: const Color(0xFF991B1B)),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.trailing,
  });

  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _BulletText extends StatelessWidget {
  const _BulletText({
    required this.text,
    this.color,
  });

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('• ', style: TextStyle(color: color)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPanelMessage extends StatelessWidget {
  const _EmptyPanelMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 38, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _kindIcon(String kind) {
  switch (kind) {
    case 'wall':
      return Icons.linear_scale;
    case 'door':
      return Icons.door_front_door_outlined;
    case 'window':
      return Icons.window_outlined;
    case 'room':
      return Icons.meeting_room_outlined;
    case 'slab':
    case 'floor':
      return Icons.layers_outlined;
    case 'ceiling':
      return Icons.flip_to_front_outlined;
    case 'roof':
      return Icons.roofing_outlined;
    case 'column':
      return Icons.view_column_outlined;
    case 'beam':
      return Icons.horizontal_rule;
    case 'stair':
      return Icons.stairs_outlined;
    default:
      return Icons.category_outlined;
  }
}

Color _kindUiColor(String kind) {
  switch (kind) {
    case 'wall':
      return const Color(0xFF1F5D4E);
    case 'door':
      return const Color(0xFFC2410C);
    case 'window':
      return const Color(0xFF0284C7);
    case 'room':
      return const Color(0xFF7C3AED);
    case 'slab':
    case 'floor':
      return const Color(0xFF475569);
    case 'ceiling':
      return const Color(0xFF64748B);
    case 'roof':
      return const Color(0xFFB91C1C);
    case 'column':
      return const Color(0xFF374151);
    case 'beam':
      return const Color(0xFF92400E);
    case 'stair':
      return const Color(0xFF4338CA);
    default:
      return const Color(0xFF6B7280);
  }
}
