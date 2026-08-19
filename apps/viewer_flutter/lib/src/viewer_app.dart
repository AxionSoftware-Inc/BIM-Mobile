import 'package:flutter/material.dart';

import 'drawing_kernel.dart';
import 'drawing_layer.dart';
import 'render_scene_models.dart';
import 'render_scene_repository.dart';
import 'render_scene_viewport.dart';
import 'viewer_document_controller.dart';

class ViewerApp extends StatelessWidget {
  const ViewerApp({
    super.key,
    this.source,
  });

  final RenderSceneSource? source;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BIM Viewer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F5D4E)),
        useMaterial3: true,
      ),
      home: ViewerHomePage(
        source: source ?? EngineRenderSceneSource(),
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
  final RenderSceneViewportController _viewportController =
      RenderSceneViewportController();
  final DrawingInteractionController _drawingController =
      DrawingInteractionController();
  late final ViewerDocumentController _documentController;

  String? _statusMessage;
  RenderSceneProjectionMode _projectionMode = RenderSceneProjectionMode.topDown;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.perspective;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;

  @override
  void initState() {
    super.initState();
    _documentController = ViewerDocumentController(source: widget.source)
      ..addListener(_handleDocumentChanged);
    _drawingController.addListener(_handleDrawingChanged);
    _loadBundledSample();
  }

  RenderScene? get _scene => _documentController.scene;
  String? get _loadError => _documentController.errorMessage;
  bool get _isBusy => _documentController.isBusy;
  bool get _canEdit => widget.source is EngineRenderSceneSource;

  void _handleDocumentChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleDrawingChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _documentController.removeListener(_handleDocumentChanged);
    _drawingController.removeListener(_handleDrawingChanged);
    _documentController.dispose();
    _drawingController.dispose();
    _viewportController.dispose();
    super.dispose();
  }

  Future<void> _loadBundledSample() async {
    _statusMessage = 'Loading bundled project through the engine...';
    final result = await _documentController.loadBundledSample();
    await _applyLoadResult(result, sourceLabel: 'engine project');
  }

  Future<void> _reloadCurrentScene() async {
    await _loadBundledSample();
  }

  Future<void> _fitCamera() async {
    setState(() {
      _statusMessage = 'Fitting scene to view...';
    });
    await _viewportController.fitCamera();
  }

  Future<void> _applyLoadResult(
    RenderSceneLoadResult result, {
    required String sourceLabel,
  }) async {
    if (!mounted) {
      return;
    }
    final scene = result.scene;
    setState(() {
      _statusMessage = scene == null
          ? 'RenderScene load failed.'
          : 'Loaded ${scene.objectCount} objects from $sourceLabel';
    });
    if (scene != null) {
      _drawingController.setScene(scene);
      await _viewportController.loadRenderScene(scene);
      await _viewportController.setProjectionMode(_projectionMode);
      await _viewportController.fitCamera();
    } else {
      _drawingController.setScene(null);
      await _viewportController.clearScene();
    }
  }

  int _activeLevelId(RenderScene? scene) {
    for (final object in scene?.objects ?? const <RenderSceneObject>[]) {
      if (object.levelId != null && object.kindKey == 'wall') {
        return object.levelId!;
      }
    }
    return 0;
  }

  Future<bool> _commitWall(DrawingSegment segment) async {
    final source = widget.source;
    if (source is! EngineRenderSceneSource) {
      setState(() => _statusMessage = 'Engine editing is unavailable for this source');
      return false;
    }
    try {
      await source.createWall(
        name: 'Wall',
        levelId: _activeLevelId(_scene),
        startX: segment.start.x,
        startY: segment.start.y,
        endX: segment.end.x,
        endY: segment.end.y,
        thicknessMeters: segment.thickness,
        heightMeters: 3.0,
      );
      final refreshed = await source.refreshFromEngine();
      await _applyLoadResult(refreshed, sourceLabel: 'engine current model');
      return true;
    } catch (error) {
      if (mounted) {
        setState(() => _statusMessage = 'Wall was rejected: $error');
      }
      return false;
    }
  }

  Future<bool> _commitPolygon(
    DrawingToolKind tool,
    List<RenderScenePoint> polygon,
  ) async {
    if (mounted) {
      setState(() {
        _statusMessage =
            '${tool == DrawingToolKind.floor ? 'Floor' : 'Ceiling'} outline captured; semantic commit adapter is next.';
      });
    }
    return false;
  }

  Future<void> _setProjectionMode(RenderSceneProjectionMode mode) async {
    setState(() {
      _projectionMode = mode;
      _statusMessage = mode == RenderSceneProjectionMode.topDown
          ? '2D plan view'
          : '3D isometric view';
    });
    await _viewportController.setProjectionMode(mode);
  }

  Future<void> _setOrbitProjectionStyle(
    RenderSceneOrbitProjectionStyle style,
  ) async {
    setState(() {
      _orbitProjectionStyle = style;
      _statusMessage = style == RenderSceneOrbitProjectionStyle.perspective
          ? '3D perspective view'
          : '3D orthographic view';
    });
    await _viewportController.setOrbitProjectionStyle(style);
  }

  Future<void> _setDisplayStyle(RenderSceneDisplayStyle style) async {
    setState(() {
      _displayStyle = style;
      _statusMessage = style == RenderSceneDisplayStyle.solid
          ? 'Solid view'
          : 'Wireframe view';
    });
    await _viewportController.setDisplayStyle(style);
  }

  String _topBarText(RenderScene? scene) {
    if (scene == null) {
      return 'No RenderScene loaded';
    }
    final wallCount = scene.kindCounts['wall'] ?? 0;
    return '${scene.objectCount} objects · $wallCount walls · ${scene.vertexCount} vertices · ${scene.triangleCount} triangles';
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BIM Viewer'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Reload sample',
              onPressed: _isBusy ? null : _reloadCurrentScene,
              icon: const Icon(Icons.refresh),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Fit scene',
              onPressed: _isBusy ? null : _fitCamera,
              icon: const Icon(Icons.center_focus_strong),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<RenderSceneProjectionMode>(
              segments: const <ButtonSegment<RenderSceneProjectionMode>>[
                ButtonSegment<RenderSceneProjectionMode>(
                  value: RenderSceneProjectionMode.topDown,
                  label: Text('2D'),
                ),
                ButtonSegment<RenderSceneProjectionMode>(
                  value: RenderSceneProjectionMode.isometric,
                  label: Text('3D'),
                ),
              ],
              selected: <RenderSceneProjectionMode>{_projectionMode},
              onSelectionChanged: (Set<RenderSceneProjectionMode> selection) {
                if (selection.isNotEmpty) {
                  _setProjectionMode(selection.first);
                }
              },
            ),
          ),
          if (_projectionMode == RenderSceneProjectionMode.isometric)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SegmentedButton<RenderSceneOrbitProjectionStyle>(
                segments: const <ButtonSegment<
                    RenderSceneOrbitProjectionStyle>>[
                  ButtonSegment<RenderSceneOrbitProjectionStyle>(
                    value: RenderSceneOrbitProjectionStyle.perspective,
                    label: Text('Perspective'),
                  ),
                  ButtonSegment<RenderSceneOrbitProjectionStyle>(
                    value: RenderSceneOrbitProjectionStyle.orthographic,
                    label: Text('Ortho'),
                  ),
                ],
                selected: <RenderSceneOrbitProjectionStyle>{
                  _orbitProjectionStyle,
                },
                onSelectionChanged:
                    (Set<RenderSceneOrbitProjectionStyle> selection) {
                  if (selection.isNotEmpty) {
                    _setOrbitProjectionStyle(selection.first);
                  }
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<RenderSceneDisplayStyle>(
              segments: const <ButtonSegment<RenderSceneDisplayStyle>>[
                ButtonSegment<RenderSceneDisplayStyle>(
                  value: RenderSceneDisplayStyle.solid,
                  label: Text('Solid'),
                ),
                ButtonSegment<RenderSceneDisplayStyle>(
                  value: RenderSceneDisplayStyle.wireframe,
                  label: Text('Wire'),
                ),
              ],
              selected: <RenderSceneDisplayStyle>{_displayStyle},
              onSelectionChanged: (Set<RenderSceneDisplayStyle> selection) {
                if (selection.isNotEmpty) {
                  _setDisplayStyle(selection.first);
                }
              },
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _topBarText(scene),
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              color: const Color(0xFFF4F7F5),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  RenderSceneViewport(controller: _viewportController),
                  if (_canEdit)
                    DrawingLayer(
                      controller: _drawingController,
                      viewport: _viewportController,
                      onWallCommit: _commitWall,
                      onPolygonCommit: _commitPolygon,
                    ),
                  if (_canEdit)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Wrap(
                            spacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: <Widget>[
                              IconButton(
                                tooltip: 'Drawing mode',
                                onPressed: _drawingController.toggle,
                                color: _drawingController.enabled
                                    ? Theme.of(context).colorScheme.primary
                                    : null,
                                icon: const Icon(Icons.edit_road),
                              ),
                              if (_drawingController.enabled)
                                SegmentedButton<DrawingToolKind>(
                                  segments: const <ButtonSegment<DrawingToolKind>>[
                                    ButtonSegment<DrawingToolKind>(
                                      value: DrawingToolKind.wall,
                                      label: Text('Wall'),
                                      icon: Icon(Icons.straighten),
                                    ),
                                    ButtonSegment<DrawingToolKind>(
                                      value: DrawingToolKind.floor,
                                      label: Text('Floor'),
                                      icon: Icon(Icons.crop_square),
                                    ),
                                    ButtonSegment<DrawingToolKind>(
                                      value: DrawingToolKind.ceiling,
                                      label: Text('Ceiling'),
                                      icon: Icon(Icons.grid_on),
                                    ),
                                  ],
                                  selected: <DrawingToolKind>{
                                    _drawingController.tool,
                                  },
                                  onSelectionChanged:
                                      (Set<DrawingToolKind> selection) {
                                    if (selection.isNotEmpty) {
                                      _drawingController.setTool(selection.first);
                                    }
                                  },
                                ),
                              if (_drawingController.enabled)
                                IconButton(
                                  tooltip: 'Cancel drawing',
                                  onPressed: _drawingController.cancel,
                                  icon: const Icon(Icons.close),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Container(
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
                    Text(
                      _statusMessage ??
                          (_isBusy ? 'Loading scene...' : 'Ready'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 16),
                    Text('Objects: ${scene?.objectCount ?? 0}'),
                    const SizedBox(width: 12),
                    Text('Walls: ${scene?.kindCounts['wall'] ?? 0}'),
                    const SizedBox(width: 12),
                    Text(
                        'Mode: ${_projectionMode == RenderSceneProjectionMode.topDown ? '2D' : '3D'}'),
                    const SizedBox(width: 12),
                    Text(
                      'View: ${_orbitProjectionStyle == RenderSceneOrbitProjectionStyle.perspective ? 'Persp' : 'Ortho'}',
                    ),
                    const SizedBox(width: 12),
                    Text(
                        'Selected: ${_viewportController.selectedElementId ?? '-'}'),
                    const SizedBox(width: 12),
                    Text(
                        'Style: ${_displayStyle == RenderSceneDisplayStyle.solid ? 'Solid' : 'Wire'}'),
                  ],
                ),
              ),
            ),
          ),
          if (_loadError != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFFEE2E2),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _loadError!,
                style: const TextStyle(color: Color(0xFF991B1B)),
              ),
            ),
        ],
      ),
    );
  }
}
