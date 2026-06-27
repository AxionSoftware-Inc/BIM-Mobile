import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'render_scene_editor.dart';
import 'render_scene_estimator.dart';
import 'render_scene_models.dart';
import 'render_scene_repository.dart';
import 'render_scene_viewport.dart';

class _DeleteSelectionIntent extends Intent {
  const _DeleteSelectionIntent();
}

enum _WallMoveMode {
  translate,
  startHandle,
  endHandle,
}

class ViewerApp extends StatelessWidget {
  const ViewerApp({
    super.key,
    this.source,
  });

  final RenderSceneSource? source;

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
      ),
    );
  }
}

class ViewerHomePage extends StatefulWidget {
  const ViewerHomePage({
    super.key,
    required this.source,
  });

  final RenderSceneSource source;

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

  RenderScene? _scene;
  String? _statusMessage;
  String? _loadError;
  bool _isBusy = false;
  bool _showInspector = true;
  bool _showObjectList = false;
  bool _showDiagnostics = false;
  bool _autoRoomSurfacesEnabled = true;
  RenderSceneEstimateCatalog _estimateCatalog =
      const RenderSceneEstimateCatalog();
  int? _activeLevelId;

  RenderSceneProjectionMode _projectionMode = RenderSceneProjectionMode.topDown;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.perspective;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;
  RenderSceneInteractionMode _interactionMode =
      RenderSceneInteractionMode.select;
  RenderScenePoint? _draftWallStart;
  RenderScenePoint? _draftWallEnd;
  RenderScenePoint? _draftSurfaceStart;
  RenderScenePoint? _draftSurfaceEnd;
  final Set<int> _draftSurfaceWallIds = <int>{};
  RenderSceneObject? _draftHostWall;
  RenderSceneObject? _draftMoveTarget;
  RenderScenePoint? _moveAnchorPoint;
  RenderScenePoint? _moveWallOriginalStart;
  RenderScenePoint? _moveWallOriginalEnd;
  _WallMoveMode _wallMoveMode = _WallMoveMode.translate;
  double _draftOpeningOffsetMeters = 1.0;
  double _draftOpeningWidthMeters = 0.9;
  double _draftOpeningHeightMeters = 2.1;
  double _draftOpeningSillHeightMeters = 0.9;
  double _draftSurfaceThicknessMeters = 0.18;
  double _draftSurfaceHeightMeters = _defaultWallHeightMeters;
  double _draftFloorTopElevationMeters = 0.0;
  String? _editStatusMessage;
  bool _snapDraftToGrid = true;

  /// Empty means “show all” in RenderSceneViewportController.
  Set<String> _visibleKinds = <String>{};

  @override
  void initState() {
    super.initState();
    _viewportController.addListener(_onViewportChanged);
    _loadBundledSample();
  }

  @override
  void dispose() {
    _viewportController.removeListener(_onViewportChanged);
    _viewportController.dispose();
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

  Future<void> _handleEscapePressed() async {
    final hasDraft = _draftWallStart != null ||
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

  bool _isTextEditingFocused() {
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext == null) {
      return false;
    }
    return focusedContext.widget is EditableText;
  }

  Future<void> _loadBundledSample() async {
    if (_isBusy) {
      return;
    }

    setState(() {
      _isBusy = true;
      _loadError = null;
      _statusMessage = 'Loading bundled RenderScene sample...';
    });

    try {
      final result = await widget.source.loadBundledSample();
      await _applyLoadResult(
        result,
        sourceLabel: 'assets/render_scene.json',
      );
    } catch (error) {
      setState(() {
        _loadError = error.toString();
        _statusMessage = 'Failed to load bundled sample.';
        _isBusy = false;
      });
    }
  }

  Future<void> _reloadCurrentScene() async {
    await _loadBundledSample();
  }

  Future<void> _applyLoadResult(
    RenderSceneLoadResult result, {
    required String sourceLabel,
  }) async {
    final rawScene = result.scene;
    final scene =
        rawScene == null ? null : RenderSceneEditor.normalizeSceneGeometry(rawScene);

    setState(() {
      _scene = scene;
      _loadError = result.errors.isNotEmpty ? result.errors.join('\n') : null;
      _statusMessage = scene == null
          ? 'RenderScene load failed.'
          : 'Loaded ${scene.objectCount} objects from $sourceLabel';
      _isBusy = false;

      if (scene != null) {
        _activeLevelId = _resolveInitialLevelId(scene, preferred: _activeLevelId);
        final activeLevel = scene.levelById(_activeLevelId) ??
            (scene.levels.isNotEmpty ? scene.levels.first : null);
        _draftFloorTopElevationMeters = activeLevel?.elevationMeters ?? 0.0;
        _draftSurfaceHeightMeters =
            activeLevel?.defaultWallHeightMeters ?? _defaultWallHeightMeters;
        _visibleKinds = _sanitizeVisibleKinds(
          visibleKinds: _visibleKinds,
          scene: _sceneForViewport(scene),
        );
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
    return scene.filteredByLevel(_activeLevelId);
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

  Future<void> _setActiveLevel(int? levelId) async {
    final scene = _scene;
    if (scene == null || levelId == null || _activeLevelId == levelId) {
      return;
    }
    final level = scene.levelById(levelId);
    setState(() {
      _activeLevelId = levelId;
      _draftFloorTopElevationMeters = level?.elevationMeters ?? 0.0;
      _draftSurfaceHeightMeters =
          level?.defaultWallHeightMeters ?? _defaultWallHeightMeters;
      _statusMessage = 'Active level changed.';
      _visibleKinds = _sanitizeVisibleKinds(
        visibleKinds: _visibleKinds,
        scene: _sceneForViewport(scene),
      );
    });
    await _viewportController.loadRenderScene(_sceneForViewport(scene));
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
      _statusMessage = _projectionMode == RenderSceneProjectionMode.topDown
          ? 'Fitting 2D plan...'
          : 'Fitting 3D scene...';
    });

    await _viewportController.fitCamera();
  }

  Future<void> _setProjectionMode(RenderSceneProjectionMode mode) async {
    if (_projectionMode == mode) {
      return;
    }

    setState(() {
      _projectionMode = mode;
      _statusMessage = mode == RenderSceneProjectionMode.topDown
          ? '2D plan view'
          : '3D isometric view';
    });

    await _viewportController.setProjectionMode(mode);
    await _viewportController.fitCamera();
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
      _statusMessage = style == RenderSceneDisplayStyle.solid
          ? 'Solid display'
          : 'Wireframe display';
    });

    await _viewportController.setDisplayStyle(style);
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
    final nameController =
        TextEditingController(text: 'Level $suggestedIndex');
    final elevationController =
        TextEditingController(text: defaultElevation.toStringAsFixed(2));
    final heightController = TextEditingController(
      text: (currentLevel?.defaultWallHeightMeters ?? _defaultWallHeightMeters)
          .toStringAsFixed(2),
    );

    final payload = await showDialog<({String name, double elevation, double wallHeight})>(
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

    final previousLevelIds = scene.levels.map((level) => level.levelId).toSet();
    final nextScene = RenderSceneEditor.createLevel(
      scene: scene,
      name: payload.name,
      elevationMeters: payload.elevation,
      defaultWallHeightMeters: payload.wallHeight,
    );
    final createdLevel = nextScene.levels.firstWhere(
      (level) => !previousLevelIds.contains(level.levelId),
      orElse: () => nextScene.levels.last,
    );
    await _applySceneChange(nextScene, message: 'Level created.');
    await _setActiveLevel(createdLevel.levelId);
  }

  Future<void> _setVisibleKinds(Set<String> kinds) async {
    setState(() {
      _visibleKinds = kinds;
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

    await _viewportController.selectElement(id);
    await _viewportController.highlightElement(id);
  }

  Future<void> _clearSelection() async {
    setState(() {
      _statusMessage = 'Selection cleared';
    });

    await _viewportController.selectElement(null);
    await _viewportController.highlightElement(null);
  }

  Future<void> _setInteractionMode(RenderSceneInteractionMode mode) async {
    if (_interactionMode == mode) {
      return;
    }

    final selected = _selectedObject(_scene);

    setState(() {
      _interactionMode = mode;
      _editStatusMessage = mode == RenderSceneInteractionMode.select
          ? 'Selection mode'
          : 'Editing mode: ${mode.name}';
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

    if (mode != RenderSceneInteractionMode.select &&
        _projectionMode != RenderSceneProjectionMode.topDown) {
      await _setProjectionMode(RenderSceneProjectionMode.topDown);
    }
  }

  Future<void> _clearDraft() async {
    setState(() {
      _draftWallStart = null;
      _draftWallEnd = null;
      _draftSurfaceStart = null;
      _draftSurfaceEnd = null;
      _draftSurfaceWallIds.clear();
      _draftHostWall = null;
      _draftMoveTarget = null;
      _moveAnchorPoint = null;
      _moveWallOriginalStart = null;
      _moveWallOriginalEnd = null;
      _wallMoveMode = _WallMoveMode.translate;
      _draftOpeningOffsetMeters = 1.0;
      _draftOpeningWidthMeters = 0.9;
      _draftOpeningHeightMeters = 2.1;
      _draftOpeningSillHeightMeters = 0.9;
      _draftSurfaceThicknessMeters = 0.18;
      _draftSurfaceHeightMeters = _defaultWallHeightMeters;
      _draftFloorTopElevationMeters = 0.0;
    });

    _viewportController.clearDraft();
  }

  Future<void> _handleSceneTap(RenderSceneTapDetails details) async {
    final scene = _scene;
    final tappedObject = details.pickedObject;
    final modelPoint = details.modelPoint;

    if (scene == null) {
      return;
    }

    switch (_interactionMode) {
      case RenderSceneInteractionMode.select:
        return;
      case RenderSceneInteractionMode.addWall:
        await _handleAddWallTap(modelPoint);
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
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
        await _handleSurfaceTap(scene, tappedObject, modelPoint);
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
        final start = _draftWallStart;
        if (start == null) {
          return;
        }
        final snappedPoint = _wallDraftPoint(
          rawPoint: modelPoint,
          referenceStart: start,
        );
        if (_draftWallEnd == snappedPoint) {
          return;
        }
        setState(() {
          _draftWallEnd = snappedPoint;
          _editStatusMessage =
              'Wall draft: ${start.distanceTo(snappedPoint).toStringAsFixed(2)} m';
        });
        _viewportController.setWallDraft(start, snappedPoint);
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
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
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
        });
        _viewportController.setSurfaceDraft(
          RenderSceneSurfaceDraft(
            kind: _interactionMode == RenderSceneInteractionMode.addFloor
                ? 'floor'
                : 'ceiling',
            start: start,
            end: snapped,
          ),
        );
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

    final snappedPoint = _wallDraftPoint(
      rawPoint: modelPoint,
      referenceStart: _draftWallStart,
    );

    if (_draftWallStart == null) {
      setState(() {
        _draftWallStart = snappedPoint;
        _draftWallEnd = snappedPoint;
        _editStatusMessage =
            'Wall start set. Tap again for the end point. Ortho/snap is active.';
      });
      _viewportController.setWallDraft(snappedPoint, snappedPoint);
      return;
    }

    setState(() {
      _draftWallEnd = snappedPoint;
      _editStatusMessage =
          'Wall endpoint set. Creating ${_draftWallStart!.distanceTo(snappedPoint).toStringAsFixed(2)} m wall...';
    });
    _viewportController.setWallDraft(_draftWallStart, snappedPoint);
    await _commitWallDraft(autoContinue: true);
  }

  Future<void> _commitWallDraft({required bool autoContinue}) async {
    final scene = _scene;
    final start = _draftWallStart;
    final end = _draftWallEnd;
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
    final nextScene = RenderSceneEditor.addWall(
      scene: scene,
      start: RenderScenePoint(x: start.x, y: start.y, z: baseElevation),
      end: RenderScenePoint(x: end.x, y: end.y, z: baseElevation),
      heightMeters: wallHeight,
      thicknessMeters: _defaultWallThicknessMeters,
      levelId: activeLevelId,
    );
    await _applySceneChange(nextScene, message: 'Wall created.');
    final created = nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
    if (created != null) {
      await _viewportController.selectElement(created.elementId?.toString());
      await _viewportController.highlightElement(created.elementId?.toString());
    }

    if (autoContinue) {
      setState(() {
        _draftWallStart = end;
        _draftWallEnd = end;
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

  Future<void> _handleMoveOpeningTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    final selected = _selectedObject(scene);
    final opening = (tappedObject != null &&
            (tappedObject.kindKey == 'door' || tappedObject.kindKey == 'window'))
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
    final hostWallId =
        (opening.metadata['host_wall_id'] as num?)?.toInt();
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
      nextStart = _wallDraftPoint(rawPoint: point, referenceStart: originalEnd);
      nextStart = _snapMovedWallPoint(scene, wall, nextStart, originalStart);
      nextEnd = originalEnd;
    } else {
      nextStart = originalStart;
      nextEnd = _wallDraftPoint(rawPoint: point, referenceStart: originalStart);
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

  Future<void> _handleSurfaceTap(
    RenderScene scene,
    RenderSceneObject? tappedObject,
    RenderScenePoint? modelPoint,
  ) async {
    if (tappedObject?.kindKey == 'room') {
      final room = tappedObject!;
      final nextScene = _interactionMode == RenderSceneInteractionMode.addFloor
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
              heightMeters: _draftSurfaceHeightMeters,
              levelId: room.levelId ?? _activeLevelId,
            );
      await _applySceneChange(
        nextScene,
        message:
            '${_interactionMode == RenderSceneInteractionMode.addFloor ? 'Floor' : 'Ceiling'} created for room #${room.elementId}.',
      );
      final created =
          nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
      if (created != null) {
        await _viewportController.selectElement(created.elementId?.toString());
        await _viewportController.highlightElement(
          created.elementId?.toString(),
        );
      }
      await _clearDraft();
      return;
    }

    if (tappedObject != null && tappedObject.kindKey == 'wall') {
      final wallId = tappedObject.elementId;
      if (wallId != null) {
        setState(() {
          if (_draftSurfaceWallIds.contains(wallId)) {
            _draftSurfaceWallIds.remove(wallId);
          } else {
            _draftSurfaceWallIds.add(wallId);
          }
          _editStatusMessage =
              '${_draftSurfaceWallIds.length} wall selected for ${_interactionMode == RenderSceneInteractionMode.addFloor ? 'floor' : 'ceiling'} boundary.';
        });
        await _selectObject(tappedObject);
        _syncSurfaceDraftFromWalls(scene);
        return;
      }
    }

    if (modelPoint == null) {
      setState(() {
        _editStatusMessage =
            'Tap empty plan area to draw rectangle, or tap walls to multi-select boundary.';
      });
      return;
    }

    final snapped = _snapDraftToGrid ? _snapPoint(modelPoint) : modelPoint;
    if (_draftSurfaceStart == null) {
      setState(() {
        _draftSurfaceStart = snapped;
        _draftSurfaceEnd = snapped;
        _draftSurfaceWallIds.clear();
        _editStatusMessage =
            'Surface draft start set. Tap opposite corner to finish rectangle.';
      });
      _viewportController.setSurfaceDraft(
        RenderSceneSurfaceDraft(
          kind: _interactionMode == RenderSceneInteractionMode.addFloor
              ? 'floor'
              : 'ceiling',
          start: snapped,
          end: snapped,
        ),
      );
      return;
    }

    setState(() {
      _draftSurfaceEnd = snapped;
      _editStatusMessage =
          '${_interactionMode == RenderSceneInteractionMode.addFloor ? 'Floor' : 'Ceiling'} rectangle ready.';
    });
    _viewportController.setSurfaceDraft(
      RenderSceneSurfaceDraft(
        kind: _interactionMode == RenderSceneInteractionMode.addFloor
            ? 'floor'
            : 'ceiling',
        start: _draftSurfaceStart!,
        end: snapped,
      ),
    );
  }

  double get _openingWidthHalf => _draftOpeningWidthMeters * 0.5;

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

    double snap(double value) => (value / step).roundToDouble() * step;
    return RenderScenePoint(
      x: snap(point.x),
      y: snap(point.y),
      z: snap(point.z),
    );
  }

  RenderScenePoint _wallDraftPoint({
    required RenderScenePoint rawPoint,
    required RenderScenePoint? referenceStart,
  }) {
    final nearScenePoint = _snapToNearbyScenePoint(rawPoint);
    var point = _snapDraftToGrid ? _snapPoint(nearScenePoint) : nearScenePoint;
    final start = referenceStart;
    if (start == null) {
      return point;
    }

    final dx = point.x - start.x;
    final dy = point.y - start.y;
    if (dx.abs() < 1e-6 && dy.abs() < 1e-6) {
      return point;
    }

    if (dx.abs() > dy.abs() * 1.35) {
      point = RenderScenePoint(x: point.x, y: start.y, z: point.z);
    } else if (dy.abs() > dx.abs() * 1.35) {
      point = RenderScenePoint(x: start.x, y: point.y, z: point.z);
    }
    return point;
  }

  RenderScenePoint _snapToNearbyScenePoint(
    RenderScenePoint point, {
    double toleranceMeters = 0.45,
  }) {
    final scene = _scene;
    if (scene == null) {
      return point;
    }

    RenderScenePoint bestPoint = point;
    var bestDistance = toleranceMeters;
    for (final candidate in RenderSceneEditor.wallSnapPoints(scene)) {
      final distance = candidate.distanceTo(point);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestPoint = candidate;
      }
    }
    return bestPoint;
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
        final start = _draftWallStart;
        final end = _draftWallEnd;
        if (start == null || end == null) {
          return false;
        }
        return start.distanceTo(end) >= 0.1;
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
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
        if (_draftSurfaceWallIds.length >= 2) {
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
        await _commitWallDraft(autoContinue: true);
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
        if (wall == null || wall.kindKey != 'wall' || start == null || end == null) {
          setState(() {
            _editStatusMessage = 'Move wall preview tayyor emas.';
          });
          return;
        }
        final nextScene = RenderSceneEditor.setWallAxis(
          scene: scene,
          wall: wall,
          start: start,
          end: end,
        );
        await _applySceneChange(nextScene, message: 'Wall moved.');
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
        final nextScene = RenderSceneEditor.moveOpening(
          scene: scene,
          opening: opening,
          offsetMeters: _draftOpeningOffsetMeters,
        );
        await _applySceneChange(nextScene, message: '${prettySceneKind(opening.kind)} moved.');
        await _clearDraft();
        return;
      case RenderSceneInteractionMode.addFloor:
      case RenderSceneInteractionMode.addCeiling:
        RenderScene nextScene;
        if (_draftSurfaceWallIds.length >= 2) {
          final walls = scene.objects
              .where((object) => _draftSurfaceWallIds.contains(object.elementId))
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
                  heightMeters: _draftSurfaceHeightMeters,
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
                  heightMeters: _draftSurfaceHeightMeters,
                  levelId: _activeLevelId,
                );
        }
        await _applySceneChange(
          nextScene,
          message:
              '${_interactionMode == RenderSceneInteractionMode.addFloor ? 'Floor' : 'Ceiling'} created.',
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
    final created = nextScene.objects.isNotEmpty ? nextScene.objects.last : null;
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
    _viewportController.setSurfaceDraft(
      RenderSceneSurfaceDraft(
        kind: _interactionMode == RenderSceneInteractionMode.addFloor
            ? 'floor'
            : 'ceiling',
        start: _draftSurfaceStart!,
        end: _draftSurfaceEnd!,
      ),
    );
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
  }) async {
    if (_autoRoomSurfacesEnabled) {
      nextScene = RenderSceneEditor.synchronizeAutoRoomSurfaces(
        scene: nextScene,
        includeFloors: true,
        includeCeilings: true,
        floorThicknessMeters: _draftSurfaceThicknessMeters,
        floorTopElevationMeters: 0.0,
        ceilingThicknessMeters: _draftSurfaceThicknessMeters.clamp(0.02, 1.0),
        ceilingHeightMeters: _draftSurfaceHeightMeters,
      );
    }
    final previousSelectedId = _viewportController.selectedElementId;
    final previousHighlightedId = _viewportController.highlightedElementId;
    final selectedBefore = _selectedObject(nextScene);
    final nextSelected = previousSelectedId != null
        ? nextScene.objectByStableId(previousSelectedId)
        : null;
    final resolvedLevelId =
        _resolveInitialLevelId(nextScene, preferred: _activeLevelId);
    final nextViewportScene = nextScene.filteredByLevel(resolvedLevelId);

    setState(() {
      _scene = nextScene;
      _activeLevelId = resolvedLevelId;
      _statusMessage = message;
      _editStatusMessage = message;
      _loadError = null;
      _visibleKinds = _sanitizeVisibleKinds(
        visibleKinds: _visibleKinds,
        scene: nextViewportScene,
      );
    });

    await _viewportController.updateRenderScene(nextViewportScene);
    await _viewportController.setVisibleKinds(_visibleKinds);

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

  String _topBarText(RenderScene? scene) {
    if (scene == null) {
      return 'No RenderScene loaded';
    }

    final wallCount = scene.kindCounts['wall'] ?? 0;
    final doorCount = scene.kindCounts['door'] ?? 0;
    final windowCount = scene.kindCounts['window'] ?? 0;

    final activeLevel = _activeLevel(_scene);
    final levelLabel = activeLevel == null
        ? 'No level'
        : '${activeLevel.name} @ ${activeLevel.elevationMeters.toStringAsFixed(2)}m';

    return '$levelLabel · ${scene.objectCount} objects · '
        '$wallCount walls · '
        '$doorCount doors · '
        '$windowCount windows · '
        '${scene.vertexCount} vertices · '
        '${scene.triangleCount} triangles';
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
    final metadata = object.metadata;
    _draftOpeningOffsetMeters =
        (metadata['offset_meters'] as num?)?.toDouble() ?? _draftOpeningOffsetMeters;
    _draftOpeningWidthMeters =
        (metadata['width_meters'] as num?)?.toDouble() ?? _draftOpeningWidthMeters;
    _draftOpeningHeightMeters =
        (metadata['height_meters'] as num?)?.toDouble() ?? _draftOpeningHeightMeters;
    _draftOpeningSillHeightMeters =
        (metadata['sill_height_meters'] as num?)?.toDouble() ?? _draftOpeningSillHeightMeters;
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
    final selectedObject = _selectedObject(fullScene);

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        SingleActivator(LogicalKeyboardKey.delete): _DeleteSelectionIntent(),
        SingleActivator(LogicalKeyboardKey.backspace): _DeleteSelectionIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (DismissIntent intent) {
              _handleEscapePressed();
              return null;
            },
          ),
          _DeleteSelectionIntent: CallbackAction<_DeleteSelectionIntent>(
            onInvoke: (_DeleteSelectionIntent intent) {
              if (_isTextEditingFocused()) {
                return null;
              }
              _deleteSelectedObject();
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
                      Expanded(
                        child: _buildViewportPanel(context),
                      ),
                      if (_showInspector)
                        _buildRightPanel(
                          context: context,
                          scene: fullScene,
                          selectedObject: selectedObject,
                        ),
                    ],
                  ),
                ),
                _buildStatusBar(context, scene),
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
    final theme = Theme.of(context);

    return AppBar(
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('Tablet BIM'),
          Text(
            _topBarText(viewportScene),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        IconButton(
          tooltip: 'Reload bundled RenderScene',
          onPressed: _isBusy ? null : _reloadCurrentScene,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Fit view',
          onPressed: viewportScene == null || _isBusy ? null : _fitCamera,
          icon: const Icon(Icons.center_focus_strong),
        ),
        IconButton(
          tooltip: 'Clear selection',
          onPressed: _viewportController.selectedElementId == null
              ? null
              : _clearSelection,
          icon: const Icon(Icons.deselect),
        ),
        IconButton(
          tooltip: _showObjectList ? 'Hide object list' : 'Show object list',
          onPressed: () {
            setState(() {
              _showObjectList = !_showObjectList;
            });
          },
          icon: Icon(
            _showObjectList ? Icons.view_list : Icons.view_list_outlined,
          ),
        ),
        IconButton(
          tooltip: _showInspector ? 'Hide inspector' : 'Show inspector',
          onPressed: () {
            setState(() {
              _showInspector = !_showInspector;
            });
          },
          icon: Icon(
            _showInspector
                ? Icons.keyboard_double_arrow_right
                : Icons.keyboard_double_arrow_left,
          ),
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(108),
        child: _buildToolbar(context, fullScene),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, RenderScene? scene) {
    final is3D = _projectionMode == RenderSceneProjectionMode.isometric;

    return Container(
      height: 108,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _toolbarChoiceButton(
                  label: '2D',
                  selected: _projectionMode == RenderSceneProjectionMode.topDown,
                  onPressed: scene == null
                      ? null
                      : () => _setProjectionMode(RenderSceneProjectionMode.topDown),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: '3D',
                  selected: _projectionMode == RenderSceneProjectionMode.isometric,
                  onPressed: scene == null
                      ? null
                      : () => _setProjectionMode(RenderSceneProjectionMode.isometric),
                ),
                const SizedBox(width: 10),
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
                      : () => _setDisplayStyle(RenderSceneDisplayStyle.wireframe),
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
                _toolbarChoiceButton(
                  label: _autoRoomSurfacesEnabled
                      ? 'Auto surfaces'
                      : 'Manual surfaces',
                  selected: _autoRoomSurfacesEnabled,
                  onPressed: scene == null
                      ? null
                      : () async {
                          final nextEnabled = !_autoRoomSurfacesEnabled;
                          setState(() {
                            _autoRoomSurfacesEnabled = nextEnabled;
                          });
                          if (nextEnabled && _scene != null) {
                            final synced =
                                RenderSceneEditor.synchronizeAutoRoomSurfaces(
                              scene: _scene!,
                              includeFloors: true,
                              includeCeilings: true,
                              floorThicknessMeters: _draftSurfaceThicknessMeters,
                              floorTopElevationMeters: 0.0,
                              ceilingThicknessMeters: _draftSurfaceThicknessMeters
                                  .clamp(0.02, 1.0)
                                  .toDouble(),
                              ceilingHeightMeters: _draftSurfaceHeightMeters,
                            );
                            await _applySceneChange(
                              synced,
                              message: 'Auto room surfaces synced.',
                            );
                          }
                        },
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _showDiagnostics ? 'Hide diagnostics' : 'Diagnostics',
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
                  selected: _interactionMode == RenderSceneInteractionMode.select,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(RenderSceneInteractionMode.select),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Wall',
                  selected: _interactionMode == RenderSceneInteractionMode.addWall,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(RenderSceneInteractionMode.addWall),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Move wall',
                  selected: _interactionMode == RenderSceneInteractionMode.moveWall,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(RenderSceneInteractionMode.moveWall),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Door',
                  selected: _interactionMode == RenderSceneInteractionMode.addDoor,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(RenderSceneInteractionMode.addDoor),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Window',
                  selected: _interactionMode == RenderSceneInteractionMode.addWindow,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(RenderSceneInteractionMode.addWindow),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Move opening',
                  selected:
                      _interactionMode == RenderSceneInteractionMode.moveOpening,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(
                          RenderSceneInteractionMode.moveOpening,
                        ),
                ),
                const SizedBox(width: 6),
                _toolbarChoiceButton(
                  label: 'Floor',
                  selected: _interactionMode == RenderSceneInteractionMode.addFloor,
                  onPressed: scene == null
                      ? null
                      : () => _setInteractionMode(RenderSceneInteractionMode.addFloor),
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
              ],
            ),
          ),
        ],
      ),
    );
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
          tooltip: 'Show object list',
          onPressed: () {
            setState(() {
              _showObjectList = true;
            });
          },
          icon: const Icon(Icons.view_list),
        ),
        IconButton(
          tooltip: 'Reload sample',
          onPressed: _isBusy ? null : _reloadCurrentScene,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Fit view',
          onPressed: _scene == null ? null : _fitCamera,
          icon: const Icon(Icons.center_focus_strong),
        ),
      ],
    );
  }

  Widget _buildObjectListPanel(BuildContext context, RenderScene? scene) {
    final theme = Theme.of(context);
    final availableKinds = _availableKinds(scene);
    final objects = scene == null
        ? <RenderSceneObject>[]
        : scene.objectsForKinds(_visibleKinds);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Objects',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Collapse object list',
                onPressed: () {
                  setState(() {
                    _showObjectList = false;
                  });
                },
                icon: const Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
        if (scene != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _KindFilterWrap(
              availableKinds: availableKinds,
              selectedKinds: _visibleKinds,
              kindCounts: scene.kindCounts,
              onChanged: _setVisibleKinds,
            ),
          ),
        const Divider(height: 20),
        Expanded(
          child: scene == null
              ? const _EmptyPanelMessage(
                  icon: Icons.data_object,
                  title: 'No scene loaded',
                  message: 'Load a RenderScene sample to inspect objects.',
                )
              : objects.isEmpty
                  ? const _EmptyPanelMessage(
                      icon: Icons.filter_alt_off,
                      title: 'No visible objects',
                      message: 'Change category filters to show objects.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      itemCount: objects.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (BuildContext context, int index) {
                        final object = objects[index];
                        return _ObjectListTile(
                          object: object,
                          selected: object.elementId?.toString() ==
                              _viewportController.selectedElementId,
                          onTap: () => _selectObject(object),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildViewportPanel(BuildContext context) {
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
            draftWallThicknessMeters: _defaultWallThicknessMeters,
            draftWallHeightMeters: _defaultWallHeightMeters,
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
    required RenderSceneObject? selectedObject,
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
                      _DraftEditorCard(
                        interactionMode: _interactionMode,
                        draftWallStart: _draftWallStart,
                        draftWallEnd: _draftWallEnd,
                        draftSurfaceStart: _draftSurfaceStart,
                        draftSurfaceEnd: _draftSurfaceEnd,
                        draftSurfaceWallCount: _draftSurfaceWallIds.length,
                        draftSurfaceThicknessMeters:
                            _draftSurfaceThicknessMeters,
                        draftSurfaceHeightMeters: _draftSurfaceHeightMeters,
                        draftFloorTopElevationMeters:
                            _draftFloorTopElevationMeters,
                        draftHostWall: _draftHostWall,
                        openingOffsetMeters: _draftOpeningOffsetMeters,
                        openingWidthMeters: _draftOpeningWidthMeters,
                        openingHeightMeters: _draftOpeningHeightMeters,
                        openingSillHeightMeters: _draftOpeningSillHeightMeters,
                        editStatusMessage: _editStatusMessage,
                        snapEnabled: _snapDraftToGrid,
                        canConfirm: _draftCanConfirm,
                        onSnapToggled: (value) {
                          setState(() {
                            _snapDraftToGrid = value;
                          });
                          _syncOpeningDraft();
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
                            _draftSurfaceHeightMeters = value;
                          });
                        },
                        onFloorTopElevationChanged: (value) {
                          setState(() {
                            _draftFloorTopElevationMeters = value;
                          });
                        },
                        onConfirm: _confirmDraft,
                        onCancel: _cancelDraft,
                        onClearSelection: _clearSelection,
                        onResetMode: () => _setInteractionMode(
                          RenderSceneInteractionMode.select,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (selectedObject == null)
                        const _EmptyPanelMessage(
                          icon: Icons.ads_click,
                          title: 'Nothing selected',
                          message:
                              'Tap an object in the model or choose one from the list.',
                        )
                      else
                        _SelectedObjectCard(object: selectedObject),
                      const SizedBox(height: 16),
                      _SceneSummaryCard(
                        scene: scene,
                        activeLevel: _activeLevel(scene),
                      ),
                      const SizedBox(height: 16),
                      _EstimateSummaryCard(
                        summary: RenderSceneEstimator.summarize(
                          scene,
                          catalog: _estimateCatalog,
                        ),
                        catalog: _estimateCatalog,
                        onCatalogChanged: (catalog) {
                          setState(() {
                            _estimateCatalog = catalog;
                          });
                        },
                      ),
                      if (_showDiagnostics) ...<Widget>[
                        const SizedBox(height: 16),
                        _DiagnosticsCard(scene: scene),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSceneSecondaryTap(RenderSceneTapDetails details) async {
    if (!mounted) {
      return;
    }

    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;

    final tappedObject = details.pickedObject;
    if (tappedObject != null) {
      await _selectObject(tappedObject);
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
      case RenderSceneInteractionMode.moveWall:
        _handleMoveWallTap(scene, details.pickedObject, details.modelPoint);
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
      case RenderSceneInteractionMode.moveWall:
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (target != null && target.kindKey == 'wall') {
          _updateMoveWallPreview(scene: scene, wall: target, point: point);
        }
        return;
      case RenderSceneInteractionMode.moveOpening:
        final target = _draftMoveTarget ?? _selectedObject(scene);
        if (target != null &&
            (target.kindKey == 'door' || target.kindKey == 'window')) {
          _updateMoveOpeningPreview(scene: scene, opening: target, point: point);
        }
        return;
      default:
        return;
    }
  }

  Future<void> _handleSceneDragEnd(RenderSceneTapDetails details) async {
    switch (_interactionMode) {
      case RenderSceneInteractionMode.moveWall:
      case RenderSceneInteractionMode.moveOpening:
        if (_draftCanConfirm) {
          await _confirmDraft();
        }
        return;
      default:
        return;
    }
  }

  Widget _buildStatusBar(BuildContext context, RenderScene? scene) {
    final theme = Theme.of(context);
    final selectedId = _viewportController.selectedElementId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF0F172A),
      child: DefaultTextStyle(
        style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
            ) ??
            const TextStyle(color: Colors.white),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              Icon(
                _loadError == null ? Icons.check_circle : Icons.error,
                size: 18,
                color: _loadError == null
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFFCA5A5),
              ),
              const SizedBox(width: 8),
              Text(
                _statusMessage ?? (_isBusy ? 'Loading scene...' : 'Ready'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(width: 18),
              Text('Objects: ${scene?.objectCount ?? 0}'),
              const SizedBox(width: 12),
              Text('Triangles: ${scene?.triangleCount ?? 0}'),
              const SizedBox(width: 12),
              Text(
                'Mode: ${_projectionMode == RenderSceneProjectionMode.topDown ? '2D' : '3D'}',
              ),
              const SizedBox(width: 12),
              Text(
                'Projection: ${_orbitProjectionStyle == RenderSceneOrbitProjectionStyle.perspective ? 'Perspective' : 'Orthographic'}',
              ),
              const SizedBox(width: 12),
              Text(
                'Style: ${_displayStyle == RenderSceneDisplayStyle.solid ? 'Solid' : 'Wire'}',
              ),
              const SizedBox(width: 12),
              Text(
                'Edit: ${_interactionMode.name}',
              ),
              const SizedBox(width: 12),
              Text('Selected: ${selectedId ?? '-'}'),
            ],
          ),
        ),
      ),
    );
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

class _KindFilterWrap extends StatelessWidget {
  const _KindFilterWrap({
    required this.availableKinds,
    required this.selectedKinds,
    required this.kindCounts,
    required this.onChanged,
  });

  final List<String> availableKinds;
  final Set<String> selectedKinds;
  final Map<String, int> kindCounts;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    if (availableKinds.isEmpty) {
      return const SizedBox.shrink();
    }

    final allSelected = selectedKinds.isEmpty;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilterChip(
          label: const Text('All'),
          selected: allSelected,
          onSelected: (_) {
            onChanged(<String>{});
          },
        ),
        for (final kind in availableKinds)
          FilterChip(
            label: Text('${prettySceneKind(kind)} ${kindCounts[kind] ?? 0}'),
            selected: allSelected || selectedKinds.contains(kind),
            onSelected: (bool selected) {
              final next =
                  allSelected ? availableKinds.toSet() : selectedKinds.toSet();

              if (selected) {
                next.add(kind);
              } else {
                next.remove(kind);
              }

              if (next.length == availableKinds.length) {
                onChanged(<String>{});
              } else {
                onChanged(next);
              }
            },
          ),
      ],
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

    final selectedLevelId = levels.any((level) => level.levelId == activeLevelId)
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

class _DraftEditorCard extends StatefulWidget {
  const _DraftEditorCard({
    required this.interactionMode,
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.draftSurfaceStart,
    required this.draftSurfaceEnd,
    required this.draftSurfaceWallCount,
    required this.draftSurfaceThicknessMeters,
    required this.draftSurfaceHeightMeters,
    required this.draftFloorTopElevationMeters,
    required this.draftHostWall,
    required this.openingOffsetMeters,
    required this.openingWidthMeters,
    required this.openingHeightMeters,
    required this.openingSillHeightMeters,
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
  final int draftSurfaceWallCount;
  final double draftSurfaceThicknessMeters;
  final double draftSurfaceHeightMeters;
  final double draftFloorTopElevationMeters;
  final RenderSceneObject? draftHostWall;
  final double openingOffsetMeters;
  final double openingWidthMeters;
  final double openingHeightMeters;
  final double openingSillHeightMeters;
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
    _syncController(_surfaceThicknessController, widget.draftSurfaceThicknessMeters,
        oldWidget.draftSurfaceThicknessMeters);
    _syncController(_surfaceHeightController, widget.draftSurfaceHeightMeters,
        oldWidget.draftSurfaceHeightMeters);
    _syncController(_floorTopController, widget.draftFloorTopElevationMeters,
        oldWidget.draftFloorTopElevationMeters);
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
    _floorTopController ??=
        TextEditingController(text: _format(widget.draftFloorTopElevationMeters));
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
        _InfoRow(label: 'Mode', value: mode.name),
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
        else if (mode == RenderSceneInteractionMode.addWall)
          _WallDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.moveWall)
          _WallDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.addFloor ||
            mode == RenderSceneInteractionMode.addCeiling)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SurfaceDraftSummary(
                mode: mode,
                start: widget.draftSurfaceStart,
                end: widget.draftSurfaceEnd,
                wallCount: widget.draftSurfaceWallCount,
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
              else
                _NumericField(
                  label: 'Height (m)',
                  controller: _surfaceHeightController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) {
                      widget.onSurfaceHeightChanged(parsed);
                    }
                  },
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
                child: const Text('Confirm'),
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

class _SurfaceDraftSummary extends StatelessWidget {
  const _SurfaceDraftSummary({
    required this.mode,
    required this.start,
    required this.end,
    required this.wallCount,
  });

  final RenderSceneInteractionMode mode;
  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final int wallCount;

  @override
  Widget build(BuildContext context) {
    final label =
        mode == RenderSceneInteractionMode.addFloor ? 'floor' : 'ceiling';
    if (wallCount >= 2) {
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

    if (start == null || end == null) {
      return Text(
        'Room ustiga bosing yoki bo‘sh joyga 2 marta bosib to‘rtburchak chizing, yoki 2+ devorni tanlab $label yarating.',
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

class _ObjectListTile extends StatelessWidget {
  const _ObjectListTile({
    required this.object,
    required this.selected,
    required this.onTap,
  });

  final RenderSceneObject object;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = prettySceneKind(object.kind);
    final id = object.elementId?.toString() ?? 'no-id';

    return Material(
      color: selected ? theme.colorScheme.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
        leading: CircleAvatar(
          radius: 17,
          backgroundColor: _kindUiColor(object.kindKey).withValues(alpha: 0.15),
          child: Icon(
            _kindIcon(object.kindKey),
            size: 18,
            color: _kindUiColor(object.kindKey),
          ),
        ),
        title: Text(
          '$kind #$id',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${object.mesh.positions.length} vertices · ${object.mesh.triangleCount} tris',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: selected ? const Icon(Icons.check_circle) : null,
      ),
    );
  }
}

class _SelectedObjectCard extends StatelessWidget {
  const _SelectedObjectCard({
    required this.object,
  });

  final RenderSceneObject object;

  @override
  Widget build(BuildContext context) {
    final kind = prettySceneKind(object.kind);
    final bounds = object.bounds;
    final area = (object.metadata['area_m2'] as num?)?.toDouble();
    final perimeter = (object.metadata['perimeter_m'] as num?)?.toDouble();
    final wallThickness =
        (object.metadata['thickness_meters'] as num?)?.toDouble();
    final wallHeight = (object.metadata['height_meters'] as num?)?.toDouble();
    final wallStart = object.metadata['axis_start'];
    final wallEnd = object.metadata['axis_end'];

    return _InfoCard(
      title: 'Selected object',
      icon: _kindIcon(object.kindKey),
      children: <Widget>[
        _InfoRow(label: 'Kind', value: kind),
        _InfoRow(
            label: 'Element ID', value: object.elementId?.toString() ?? '-'),
        _InfoRow(label: 'Level ID', value: object.levelId?.toString() ?? '-'),
        _InfoRow(label: 'Selectable', value: object.selectable ? 'Yes' : 'No'),
        _InfoRow(
          label: 'Visible',
          value: object.visibleByDefault ? 'Default' : 'Hidden',
        ),
        _InfoRow(label: 'Revision', value: object.revision.toString()),
        _InfoRow(
          label: 'Mesh',
          value:
              '${object.mesh.positions.length} vertices · ${object.mesh.triangleCount} triangles',
        ),
        _InfoRow(
          label: 'Bounds',
          value:
              '${bounds.width.toStringAsFixed(2)} × ${bounds.depth.toStringAsFixed(2)} × ${bounds.height.toStringAsFixed(2)} m',
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
        if (wallStart is Map && wallEnd is Map) ...<Widget>[
          _InfoRow(label: 'Axis start', value: '${wallStart['x']}, ${wallStart['y']}'),
          _InfoRow(label: 'Axis end', value: '${wallEnd['x']}, ${wallEnd['y']}'),
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
      ],
    );
  }
}

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
          onValue: (value) =>
              _updateCatalog(concreteCostPerCubicMeter: value),
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
          onValue: (value) =>
              _updateCatalog(ceilingCostPerSquareMeter: value),
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
