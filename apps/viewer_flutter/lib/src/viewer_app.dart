import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'tbe_ffi.dart';

class ViewerApp extends StatelessWidget {
  const ViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TBE Viewer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1F5D4E)),
        useMaterial3: true,
      ),
      home: const ViewerHomePage(),
    );
  }
}

class ViewerHomePage extends StatefulWidget {
  const ViewerHomePage({super.key});

  @override
  State<ViewerHomePage> createState() => _ViewerHomePageState();
}

class _ViewerHomePageState extends State<ViewerHomePage> {
  ViewerRepository? _repository;
  ViewerSnapshot? _snapshot;
  Rect? _viewBox;
  HitCandidateView? _selectedHit;
  final List<HitCandidateView> _hitResults = <HitCandidateView>[];
  Offset? _lastTapPosition;
  String? _statusMessage;
  String? _libraryError;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    try {
      _repository = ViewerRepository(TbeViewerApi.load());
      _loadBundledSample();
    } catch (error) {
      _libraryError = error.toString();
    }
  }

  Future<void> _loadBundledSample() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    setState(() {
      _isBusy = true;
      _libraryError = null;
    });
    try {
      final json = await rootBundle.loadString('assets/sample_project.json');
      final loadResult = await repository.loadFromJson(
          projectName: 'Bundled Sample', json: json);
      final viewBox = _parseViewBox(loadResult.snapshot.svgPath);
      setState(() {
        _snapshot = loadResult.snapshot;
        _viewBox = viewBox;
        _selectedHit = null;
        _lastTapPosition = null;
        _hitResults
          ..clear()
          ..addAll(loadResult.hitCandidates);
        _statusMessage = 'Bundled sample loaded';
        _isBusy = false;
      });
    } catch (error) {
      setState(() {
        _statusMessage = error.toString();
        _isBusy = false;
      });
    }
  }

  Future<void> _openJson() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final path = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        const XTypeGroup(label: 'Project JSON', extensions: <String>['json']),
      ],
    );
    if (path == null) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      final json = await File(path.path).readAsString();
      final loadResult = await repository.loadFromJson(
        projectName: path.name,
        json: json,
        sourcePath: path.path,
      );
      final viewBox = _parseViewBox(loadResult.snapshot.svgPath);
      setState(() {
        _snapshot = loadResult.snapshot;
        _viewBox = viewBox;
        _selectedHit = null;
        _lastTapPosition = null;
        _hitResults
          ..clear()
          ..addAll(loadResult.hitCandidates);
        _statusMessage = 'Loaded ${path.name}';
        _isBusy = false;
      });
    } catch (error) {
      setState(() {
        _statusMessage = error.toString();
        _isBusy = false;
      });
    }
  }

  Future<void> _openPackage() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final directory =
        await getDirectoryPath(confirmButtonText: 'Open .tbeproj');
    if (directory == null) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      final loadResult =
          await repository.loadFromPackage(packagePath: directory);
      final viewBox = _parseViewBox(loadResult.snapshot.svgPath);
      setState(() {
        _snapshot = loadResult.snapshot;
        _viewBox = viewBox;
        _selectedHit = null;
        _lastTapPosition = null;
        _hitResults
          ..clear()
          ..addAll(loadResult.hitCandidates);
        _statusMessage = 'Loaded package $directory';
        _isBusy = false;
      });
    } catch (error) {
      setState(() {
        _statusMessage = error.toString();
        _isBusy = false;
      });
    }
  }

  Future<void> _reloadCurrentProject() async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      final loadResult = await repository.reloadCurrent();
      final viewBox = _parseViewBox(loadResult.snapshot.svgPath);
      setState(() {
        _snapshot = loadResult.snapshot;
        _viewBox = viewBox;
        _selectedHit = null;
        _lastTapPosition = null;
        _hitResults
          ..clear()
          ..addAll(loadResult.hitCandidates);
        _statusMessage = 'Reloaded current project';
        _isBusy = false;
      });
    } catch (error) {
      setState(() {
        _statusMessage = error.toString();
        _isBusy = false;
      });
    }
  }

  Rect _parseViewBox(String svgPath) {
    final text = File(svgPath).readAsStringSync();
    final match = RegExp(r'viewBox="([^"]+)"').firstMatch(text);
    if (match == null) {
      return const Rect.fromLTWH(0, 0, 10, 10);
    }
    final parts =
        match.group(1)!.split(RegExp(r'\s+')).map(double.parse).toList();
    if (parts.length != 4) {
      return const Rect.fromLTWH(0, 0, 10, 10);
    }
    return Rect.fromLTWH(parts[0], parts[1], parts[2], parts[3]);
  }

  Offset _screenToModel(Offset localPosition, Size size) {
    final viewBox = _viewBox ?? const Rect.fromLTWH(0, 0, 10, 10);
    final x = viewBox.left + (localPosition.dx / size.width) * viewBox.width;
    final y = viewBox.top + (localPosition.dy / size.height) * viewBox.height;
    return Offset(x, y);
  }

  Future<void> _handleTap(
      TapDownDetails details, BoxConstraints constraints) async {
    if (_snapshot == null || _repository == null) {
      return;
    }
    final modelPoint = _screenToModel(
      details.localPosition,
      Size(constraints.maxWidth, constraints.maxHeight),
    );
    try {
      final hits = _repository!.hitTest(modelPoint.dx, modelPoint.dy);
      setState(() {
        _selectedHit = hits.isEmpty ? null : hits.first;
        _lastTapPosition = details.localPosition;
        _hitResults
          ..clear()
          ..addAll(hits);
        _statusMessage =
            'Hit-test at (${modelPoint.dx.toStringAsFixed(2)}, ${modelPoint.dy.toStringAsFixed(2)}) returned ${hits.length} candidate(s)';
      });
    } catch (error) {
      setState(() {
        _statusMessage = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('TabletBimEngine Viewer'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: snapshot == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: <Widget>[
                      Text('Engine ${snapshot.engineVersion}'),
                      const SizedBox(width: 16),
                      Text('API ${snapshot.apiVersion}'),
                      const SizedBox(width: 16),
                      Text('Schema ${snapshot.schemaVersion}'),
                      const SizedBox(width: 16),
                      Text(
                          'Validation errors ${snapshot.validation.errorCount}'),
                    ],
                  ),
                ),
        ),
      ),
      body: Row(
        children: <Widget>[
          SizedBox(
            width: 260,
            child: _LeftPanel(
              snapshot: snapshot,
              statusMessage: _statusMessage,
              libraryError: _libraryError,
              isBusy: _isBusy,
              onOpenSample: _loadBundledSample,
              onOpenJson: _openJson,
              onOpenPackage: _openPackage,
              onReload: _reloadCurrentProject,
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Container(
                  color: const Color(0xFFF1F5F2),
                  child: _buildCenterPanel(constraints, snapshot),
                );
              },
            ),
          ),
          SizedBox(
            width: 320,
            child: _RightPanel(
              selectedHit: _selectedHit,
              hitResults: _hitResults,
              validationMessages:
                  snapshot?.validationMessages ?? const <String>[],
              levelId: snapshot?.levelId,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCenterPanel(
      BoxConstraints constraints, ViewerSnapshot? snapshot) {
    if (_libraryError != null) {
      return _CenterMessageCard(
        title: 'Native library not loaded',
        message: _libraryError!,
      );
    }
    if (_isBusy && snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot == null) {
      return const _CenterMessageCard(
        title: 'No project loaded',
        message: 'Open the bundled sample or choose a JSON / .tbeproj package.',
      );
    }
    return GestureDetector(
      onTapDown: (details) => _handleTap(details, constraints),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          InteractiveViewer(
            minScale: 0.5,
            maxScale: 8.0,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                SvgPicture.file(
                  File(snapshot.svgPath),
                  fit: BoxFit.contain,
                ),
                const Positioned(
                  left: 12,
                  bottom: 12,
                  child: Card(
                    color: Colors.black87,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Approximate screen-to-model mapping via SVG viewBox',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_lastTapPosition != null)
            Positioned(
              left: _lastTapPosition!.dx - 10,
              top: _lastTapPosition!.dy - 10,
              child: IgnorePointer(
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border:
                        Border.all(color: const Color(0xFFB42318), width: 2),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          if (_isBusy)
            const Align(
              alignment: Alignment.topCenter,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }
}

class _LeftPanel extends StatelessWidget {
  const _LeftPanel({
    required this.snapshot,
    required this.statusMessage,
    required this.libraryError,
    required this.isBusy,
    required this.onOpenSample,
    required this.onOpenJson,
    required this.onOpenPackage,
    required this.onReload,
  });

  final ViewerSnapshot? snapshot;
  final String? statusMessage;
  final String? libraryError;
  final bool isBusy;
  final Future<void> Function() onOpenSample;
  final Future<void> Function() onOpenJson;
  final Future<void> Function() onOpenPackage;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    final schedule = snapshot?.schedule;
    return Material(
      color: const Color(0xFFF7FAF8),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          FilledButton(
            onPressed: isBusy ? null : onOpenSample,
            child: const Text('Open Sample'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: isBusy ? null : onOpenJson,
            child: const Text('Open JSON'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: isBusy ? null : onOpenPackage,
            child: const Text('Open Package'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: isBusy ? null : onReload,
            child: const Text('Reload'),
          ),
          const SizedBox(height: 16),
          Text('Project', style: Theme.of(context).textTheme.titleMedium),
          Text(snapshot?.projectName ?? 'No project loaded'),
          const SizedBox(height: 16),
          Text('Schedule Summary',
              style: Theme.of(context).textTheme.titleMedium),
          _kv('Walls', '${schedule?.wallRows ?? 0}'),
          _kv('Openings', '${schedule?.openingRows ?? 0}'),
          _kv('Rooms', '${schedule?.roomRows ?? 0}'),
          _kv('Slabs', '${schedule?.slabRows ?? 0}'),
          _kv('Roofs', '${schedule?.roofRows ?? 0}'),
          _kv('Columns', '${schedule?.columnRows ?? 0}'),
          _kv('Beams', '${schedule?.beamRows ?? 0}'),
          _kv('Stairs', '${schedule?.stairRows ?? 0}'),
          _kv('Floor systems', '${schedule?.floorRows ?? 0}'),
          _kv('Ceiling systems', '${schedule?.ceilingRows ?? 0}'),
          _kv('Takeoff rows', '${schedule?.materialTakeoffRows ?? 0}'),
          const SizedBox(height: 16),
          Text('Package', style: Theme.of(context).textTheme.titleMedium),
          SelectableText(snapshot?.packagePath ?? 'No package exported yet'),
          const SizedBox(height: 16),
          Text('Status', style: Theme.of(context).textTheme.titleMedium),
          Text(libraryError ?? statusMessage ?? 'Ready'),
        ],
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(key)),
          Text(value),
        ],
      ),
    );
  }
}

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.selectedHit,
    required this.hitResults,
    required this.validationMessages,
    required this.levelId,
  });

  final HitCandidateView? selectedHit;
  final List<HitCandidateView> hitResults;
  final List<String> validationMessages;
  final int? levelId;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFCFCFA),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('Selected Element',
              style: Theme.of(context).textTheme.titleMedium),
          if (selectedHit == null)
            const Text('Tap the floorplan to run hit-test.')
          else ...<Widget>[
            Text('Element id: ${selectedHit!.elementId}'),
            Text('Element kind: ${selectedHit!.elementKind}'),
            Text('Hit kind: ${selectedHit!.hitKind}'),
            Text('Distance: ${selectedHit!.distanceMeters.toStringAsFixed(3)}'),
            Text('Priority: ${selectedHit!.priority}'),
            if (levelId != null) Text('Level id: $levelId'),
          ],
          const SizedBox(height: 16),
          Text('Hit Results', style: Theme.of(context).textTheme.titleMedium),
          if (hitResults.isEmpty)
            const Text('No hit results yet.')
          else
            for (final hit in hitResults)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('Element ${hit.elementId}'),
                subtitle: Text(
                  'kind=${hit.elementKind} hit=${hit.hitKind} '
                  'distance=${hit.distanceMeters.toStringAsFixed(3)} priority=${hit.priority}',
                ),
              ),
          const SizedBox(height: 16),
          Text('Validation Messages',
              style: Theme.of(context).textTheme.titleMedium),
          if (validationMessages.isEmpty)
            const Text('No validation messages.')
          else
            for (final message in validationMessages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(message),
              ),
        ],
      ),
    );
  }
}

class _CenterMessageCard extends StatelessWidget {
  const _CenterMessageCard({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                SelectableText(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
