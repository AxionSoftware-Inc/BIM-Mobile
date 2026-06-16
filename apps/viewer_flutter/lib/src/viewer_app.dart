import 'package:flutter/material.dart';

import 'render_scene_models.dart';
import 'render_scene_repository.dart';
import 'render_scene_viewport.dart';

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
  final RenderSceneViewportController _viewportController =
      RenderSceneViewportController();

  RenderScene? _scene;
  String? _statusMessage;
  String? _loadError;
  bool _isBusy = false;
  RenderSceneProjectionMode _projectionMode = RenderSceneProjectionMode.topDown;
  RenderSceneOrbitProjectionStyle _orbitProjectionStyle =
      RenderSceneOrbitProjectionStyle.perspective;
  RenderSceneDisplayStyle _displayStyle = RenderSceneDisplayStyle.solid;

  @override
  void initState() {
    super.initState();
    _loadBundledSample();
  }

  @override
  void dispose() {
    _viewportController.dispose();
    super.dispose();
  }

  Future<void> _loadBundledSample() async {
    setState(() {
      _isBusy = true;
      _loadError = null;
      _statusMessage = 'Loading bundled RenderScene sample...';
    });
    try {
      final result = await widget.source.loadBundledSample();
      await _applyLoadResult(result, sourceLabel: 'assets/render_scene.json');
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
    final scene = result.scene;
    setState(() {
      _scene = scene;
      _loadError = result.errors.isNotEmpty ? result.errors.join('\n') : null;
      _statusMessage = scene == null
          ? 'RenderScene load failed.'
          : 'Loaded ${scene.objectCount} objects from $sourceLabel';
      _isBusy = false;
    });
    if (scene != null) {
      await _viewportController.loadRenderScene(scene);
      await _viewportController.setProjectionMode(_projectionMode);
      await _viewportController.fitCamera();
    } else {
      await _viewportController.clearScene();
    }
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
              child: RenderSceneViewport(controller: _viewportController),
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
