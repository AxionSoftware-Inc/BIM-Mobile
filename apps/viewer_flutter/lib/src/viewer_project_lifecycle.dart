// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

enum _WorkspaceExitChoice { save, discard }

// Above this size, an IFC is opened through the cache's native-first path.
// The threshold only chooses a transfer strategy: IFC source geometry remains
// authoritative and is never simplified or rewritten.
const int _nativeFirstIfcThresholdBytes = 8 * 1024 * 1024;

extension _IfcImportCache on _ViewerHomePageState {
  Future<Directory> _ifcCacheDirectory() async {
    final projectDirectory = await AppProjectStorage.projectDirectory();
    final directory = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}ifc-cache',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  String _ifcCacheKey(String path) {
    var hash = 2166136261;
    for (final codeUnit in path.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
    }
    final baseName = path
        .split(Platform.pathSeparator)
        .last
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${baseName}_$hash';
  }

  Future<({String json, String path})?> _readIfcImportCache(
      String ifcPath) async {
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;
      final directory = await _ifcCacheDirectory();
      final key = _ifcCacheKey(ifcPath);
      final cached = File(
        '${directory.path}${Platform.pathSeparator}$key.json',
      );
      final signatureFile = File(
        '${directory.path}${Platform.pathSeparator}$key.sig',
      );
      if (!await cached.exists() || await cached.length() <= 0) return null;
      if (!await signatureFile.exists() ||
          await signatureFile.readAsString() !=
              _ifcCacheSignature(ifcPath, stat)) {
        return null;
      }
      final json = await cached.readAsString();
      // Validate the cache before handing it to the native loader. A partial
      // file from a killed tablet session must never hide the original IFC.
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic> ||
          decoded['schema_version'] == null) {
        return null;
      }
      return (json: json, path: cached.path);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeIfcImportCache(String ifcPath, String json) async {
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file ||
          stat.size <= 0 ||
          json.isEmpty) {
        return;
      }
      final directory = await _ifcCacheDirectory();
      final key = _ifcCacheKey(ifcPath);
      final cached = File(
        '${directory.path}${Platform.pathSeparator}$key.json',
      );
      final signatureFile = File(
        '${directory.path}${Platform.pathSeparator}$key.sig',
      );
      if (await cached.exists() &&
          await cached.length() > 0 &&
          await signatureFile.exists() &&
          await signatureFile.readAsString() ==
              _ifcCacheSignature(ifcPath, stat)) {
        return;
      }
      await atomicWriteString(cached, json);
      await atomicWriteString(
        signatureFile,
        _ifcCacheSignature(ifcPath, stat),
      );
    } catch (_) {
      // The IFC itself remains the source of truth. Cache storage is best
      // effort because external/document-provider paths can be read-only.
    }
  }

  Future<({String cachePath, String signaturePath})> _nativeBimCachePaths(
    String ifcPath,
  ) async {
    final directory = await _ifcCacheDirectory();
    final key = _ifcCacheKey(ifcPath);
    final basePath = '${directory.path}${Platform.pathSeparator}$key.bimcache';
    return (
      cachePath: basePath,
      signaturePath: '$basePath.sig',
    );
  }

  /// Cache generation stays at the optional native-renderer boundary. Mock,
  /// cloud and fallback project sessions remain valid, while the real IFC is
  /// always retained as source of truth if this acceleration step fails.
  Future<String?> _ensureNativeBimCache(String ifcPath) async {
    final session = _engineRepository;
    if (session is! ViewerBimRuntimeCacheGateway) return null;
    final cacheSession = session as ViewerBimRuntimeCacheGateway;
    try {
      final source = File(ifcPath);
      final stat = await source.stat();
      if (stat.type != FileSystemEntityType.file || stat.size <= 0) return null;
      final paths = await _nativeBimCachePaths(ifcPath);
      final cacheFile = File(paths.cachePath);
      final signatureFile = File(paths.signaturePath);
      final signature = _nativeBimCacheSignature(ifcPath, stat);
      if (await cacheFile.exists() &&
          await cacheFile.length() > 0 &&
          await signatureFile.exists() &&
          await signatureFile.readAsString() == signature) {
        return paths.cachePath;
      }

      if (mounted) {
        _updateViewportState(() {
          _statusMessage = 'Preparing native 3D cache...';
        });
      }
      final result = await cacheSession.compileBimRuntimeCache(
        sourceIfcPath: ifcPath,
        cachePath: paths.cachePath,
      );
      if (!result.sourceValid || result.chunkCount == 0) return null;
      await atomicWriteString(signatureFile, signature);
      return paths.cachePath;
    } catch (_) {
      // Cache failures must not hide a valid IFC/project JSON import.
      return null;
    }
  }

  String _ifcCacheSignature(String path, FileStat stat) =>
      'tbe-ifc-cache-v2|$path|${stat.size}|'
      '${stat.modified.millisecondsSinceEpoch}';

  String _nativeBimCacheSignature(String path, FileStat stat) =>
      'tbe-bimcache-v4-simple-box-window|${_ifcCacheSignature(path, stat)}';
}

extension _ViewerProjectLifecycle on _ViewerHomePageState {
  Future<void> _createBlankProject() async {
    if (_isBusy) return;
    ++_sceneLoadGeneration;
    _currentProjectName = 'New Project';
    _updateViewportState(() {
      _isBusy = true;
      _loadError = null;
      _activeSectionView = null;
      _statusMessage = 'Creating a new project...';
    });
    try {
      final launch = await _projectLifecycle.createBlankProject(
        existingSession: _engineRepository,
        projectName: 'New Project',
      );
      if (!mounted) {
        if (launch.createdSession) launch.session.dispose();
        return;
      }
      _projectSession.activate(launch.session);
      _engineLoadDiagnostic = null;
      await _applyLoadResult(
        launch.renderScene!,
        sourceLabel: 'New Project',
        resetProjectChanges: true,
      );
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'New project could not be created.';
        _isBusy = false;
      });
    }
  }

  void _onViewportChanged() {
    final selectedIds = _viewportController.selectedElementIds.toList()..sort();
    final nextSignature = <String>[
      selectedIds.join(','),
      _viewportController.activeElementId ?? '',
      _viewportController.selectedLevelId?.toString() ?? '',
      _viewportController.highlightedElementId ?? '',
      _viewportController.nativeBridgeError ?? '',
    ].join('\u001f');
    if (_lastViewportUiSignature == nextSignature) return;
    _lastViewportUiSignature = nextSignature;
    if (mounted) {
      _updateViewportState(() {
        final bridgeError = _viewportController.nativeBridgeError;
        if (bridgeError != null) {
          _engineLoadDiagnostic = bridgeError;
          _statusMessage = 'Flutter viewport fallback is active.';
        }
      });
    }
  }

  void _onSelectionChangedForWorkspace() {
    if (!mounted || _selectionController.isEmpty) return;
    if (_showSidePanel && _sidePanelTab == WorkspaceSidePanelTab.inspector) {
      return;
    }

    // Native object taps update the shared SelectionController directly. Keep
    // the Revit-style workflow consistent with Flutter-side level/object taps:
    // a new selection opens Properties, while the user can still switch back
    // to Project Browser afterward without being pulled away on rebuilds.
    _updateViewportState(() {
      _showSidePanel = true;
      _sidePanelTab = WorkspaceSidePanelTab.inspector;
    });
  }

  void _onSheetWorkspaceChanged() {
    if (mounted) _updateViewportState(() {});
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
    ++_sceneLoadGeneration;

    _updateViewportState(() {
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
        resetProjectChanges: true,
      );
      if (!_engineBackedMode) {
        _updateViewportState(() {
          _engineLoadDiagnostic ??=
              'Engine-backed sample unavailable. Fallback render scene loaded.';
          _statusMessage = _engineLoadDiagnostic;
        });
      }
    } catch (error) {
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'Failed to load bundled sample.';
        _isBusy = false;
      });
    }
  }

  Future<void> _loadProjectJson(
    String json, {
    required String projectName,
    String? sourcePath,
  }) async {
    if (_isBusy) return;
    final generation = ++_sceneLoadGeneration;
    _currentProjectName = projectName;
    _updateViewportState(() {
      _isBusy = true;
      _loadError = null;
      _activeSectionView = null;
      _statusMessage = 'Opening $projectName...';
    });

    try {
      final launch = await _projectLifecycle.loadJson(
        projectName: projectName,
        json: json,
        sourcePath: sourcePath,
      );
      if (!mounted) {
        launch.session.dispose();
        return;
      }
      _projectSession.activate(launch.session);
      _engineLoadDiagnostic = null;
      final result = await _sceneViews.refreshPrimary();
      await _applyLoadResult(
        result,
        sourceLabel: projectName,
        resetProjectChanges: true,
      );
      _hydrateSecondaryScene(
        session: launch.session,
        generation: generation,
        sourceLabel: projectName,
      );
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'Could not open the project.';
        _isBusy = false;
      });
    }
  }

  void _hydrateSecondaryScene({
    required ViewerEngineSession session,
    required int generation,
    required String sourceLabel,
  }) {
    final expectedSceneDataRevision = _sceneDataRevision;
    unawaited(() async {
      // Give the platform view one event turn to paint the primary scene
      // before serializing the heavier secondary scene.
      await Future<void>.delayed(Duration.zero);
      if (!mounted ||
          generation != _sceneLoadGeneration ||
          !identical(_projectSession.session, session) ||
          expectedSceneDataRevision != _sceneDataRevision) {
        return;
      }
      _updateViewportState(() {
        _statusMessage = '$sourceLabel · loading details...';
      });
      try {
        final result = await _sceneViews.refresh();
        if (!mounted ||
            generation != _sceneLoadGeneration ||
            !identical(_projectSession.session, session) ||
            expectedSceneDataRevision != _sceneDataRevision) {
          return;
        }
        // Detail hydration shares the same presentation lane as authoring
        // commits. A late read may finish after a wall/opening edit, but it
        // can no longer overwrite the newer scene or viewport state.
        await _sceneCommitQueue.run(
          () => _applyLoadResult(
            result,
            sourceLabel: '$sourceLabel · details',
            preserveViewport: true,
            expectedSceneDataRevision: expectedSceneDataRevision,
          ),
        );
      } catch (error) {
        if (!mounted ||
            generation != _sceneLoadGeneration ||
            !identical(_projectSession.session, session)) {
          return;
        }
        _updateViewportState(() {
          _engineLoadDiagnostic = 'Secondary details deferred: $error';
          _statusMessage = '$sourceLabel · core scene ready';
        });
      }
    }());
  }

  Future<void> _createResidentialTemplate(
    _ResidentialTemplateKind template,
  ) async {
    if (_isBusy) return;
    ++_sceneLoadGeneration;
    final showcaseKind = switch (template) {
      _ResidentialTemplateKind.modern3 => 0,
      _ResidentialTemplateKind.glassTower9 => 1,
      _ResidentialTemplateKind.glassCampus6x9 => 2,
      _ => null,
    };
    final buildingCount =
        template == _ResidentialTemplateKind.campus6x9 ? 6 : 1;
    final storyCount = template == _ResidentialTemplateKind.default3 ? 3 : 9;
    final label = switch (template) {
      _ResidentialTemplateKind.default3 => '3-storey starter building',
      _ResidentialTemplateKind.tower9 => '9-storey residential building',
      _ResidentialTemplateKind.campus6x9 =>
        'Residential campus with six 9-storey buildings',
      _ResidentialTemplateKind.modern3 =>
        'Modern glass courtyard house with site landscape',
      _ResidentialTemplateKind.glassTower9 =>
        'Modern glass residential tower with central core',
      _ResidentialTemplateKind.glassCampus6x9 =>
        'Modern glass campus with six ordered buildings',
    };
    _currentProjectName = label;
    _updateViewportState(() {
      _isBusy = true;
      _loadError = null;
      _activeSectionView = null;
      _statusMessage = 'Creating $label in the engine...';
    });

    try {
      final previousRepository = _engineRepository;
      final launch = showcaseKind == null
          ? await _projectLifecycle.createResidentialTemplate(
              existingSession: previousRepository,
              buildingCount: buildingCount,
              storyCount: storyCount,
            )
          : await _projectLifecycle.createShowcaseTemplate(
              existingSession: previousRepository,
              templateKind: showcaseKind,
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
        resetProjectChanges: true,
      );
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = '$label could not be created.';
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
        resetProjectChanges: true,
      );
      return true;
    } catch (error) {
      _projectSession.markUnavailable();
      _engineLoadDiagnostic = 'Engine-backed sample failed: $error';
      return false;
    }
  }

  Future<void> _reloadCurrentScene() async {
    if (_engineBackedMode && _engineRepository != null) {
      ++_sceneLoadGeneration;
      _updateViewportState(() {
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
        _updateViewportState(() {
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
    await _saveProjectForExit();
  }

  Future<void> _importIfc() async {
    if (_isBusy || !_engineBackedMode || _engineRepository == null) return;
    try {
      const typeGroup = XTypeGroup(
        label: 'IFC models',
        extensions: <String>['ifc'],
      );
      final file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
      );
      if (file == null || !mounted) return;
      await _loadIfcPath(file.path, projectName: file.name);
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'IFC import failed.';
      });
    }
  }

  Future<void> _loadIfcPath(
    String path, {
    required String projectName,
  }) async {
    if (_isBusy) return;
    final generation = ++_sceneLoadGeneration;
    try {
      _updateViewportState(() {
        _isBusy = true;
        _loadError = null;
        _activeSectionView = null;
        _statusMessage = 'Importing $projectName...';
      });
      _currentProjectName = projectName;
      final repository = _engineRepository;
      final sourceStat = await File(path).stat();
      final preferNativeFirst = sourceStat.type == FileSystemEntityType.file &&
          sourceStat.size >= _nativeFirstIfcThresholdBytes &&
          _viewportController.backend == RenderSceneViewportBackend.native;
      final nativeFirstReady = preferNativeFirst
          ? await _primeNativeViewportForIfc(projectName)
          : false;
      // A former JSON scene cache can be hundreds of MiB.  Never read or
      // build it for a large model when the native cache route is available.
      final cached = nativeFirstReady ? null : await _readIfcImportCache(path);
      if (cached != null) {
        _updateViewportState(() {
          _statusMessage = 'Opening cached IFC model...';
        });
        if (repository != null) {
          await repository.loadFromJson(
            projectName: projectName,
            json: cached.json,
            sourcePath: cached.path,
          );
        } else {
          final launch = await _projectLifecycle.loadJson(
            projectName: projectName,
            json: cached.json,
            sourcePath: cached.path,
          );
          if (!mounted) {
            launch.session.dispose();
            return;
          }
          _projectSession.activate(launch.session);
          _engineLoadDiagnostic = null;
        }
      } else if (repository == null) {
        final launch = await _projectLifecycle.loadIfc(
          projectName: projectName,
          ifcPath: path,
        );
        if (!mounted) {
          launch.session.dispose();
          return;
        }
        _projectSession.activate(launch.session);
        _engineLoadDiagnostic = null;
        if (!nativeFirstReady) {
          final exactProjectJson =
              await launch.session.snapshotImportedProjectJson();
          await _writeIfcImportCache(path, exactProjectJson);
        }
      } else {
        await repository.loadFromIfc(ifcPath: path);
        // Keep the exact semantic/project representation for the next open.
        // The runtime LOD is produced later by the render-scene query and is
        // never written into this cache.
        if (!nativeFirstReady) {
          final exactProjectJson =
              await repository.snapshotImportedProjectJson();
          await _writeIfcImportCache(path, exactProjectJson);
        }
      }
      if (nativeFirstReady) {
        final nativeResult = await _prepareNativeBimCacheScene(path);
        if (nativeResult != null) {
          await _applyLoadResult(
            nativeResult,
            sourceLabel: projectName,
            resetProjectChanges: true,
            nativeGeometryAlreadyLoaded: true,
          );
          return;
        }
      }
      final nativeBimCachePath = await _ensureNativeBimCache(path);
      final result = await _sceneViews.refreshPrimary();
      await _applyLoadResult(
        result,
        sourceLabel: projectName,
        resetProjectChanges: true,
      );
      if (nativeBimCachePath != null && mounted) {
        await _viewportController.loadNativeBimCache(
          sourceIfcPath: path,
          cachePath: nativeBimCachePath,
        );
      } else {
        final activeSession = _projectSession.session;
        if (activeSession != null) {
          _hydrateSecondaryScene(
            session: activeSession,
            generation: generation,
            sourceLabel: projectName,
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'IFC import failed.';
      });
    }
  }

  /// Mounts a tiny loading scene so Android can create its PlatformView and
  /// then waits for the per-view MethodChannel.  It deliberately contains no
  /// IFC mesh payload; the following native call replaces it with direct cache
  /// buffers on the renderer thread.
  Future<bool> _primeNativeViewportForIfc(String projectName) async {
    final placeholder = parseRenderSceneJson(
      jsonEncode(<String, Object?>{
        'scene_version': 1,
        'units': 'meters',
        'coordinate_system': 'X/Y plan, Z up',
        'objects': <Object?>[],
        'levels': <Object?>[],
        'materials': <Object?>[],
        'sections': <Object?>[],
      }),
      source: 'native cache loading placeholder',
    ).scene;
    if (placeholder == null || !mounted) return false;
    _updateViewportState(() {
      _scene = placeholder;
      _statusMessage = 'Preparing native viewport for $projectName...';
    });
    await _viewportController.loadRenderScene(placeholder);
    return _viewportController.waitForNativeBridge();
  }

  /// Receives only compact element bounds/metadata from Android.  Vertices and
  /// indices stay in the C++ cache and are streamed to Filament as direct
  /// buffers, avoiding the old JSON MethodChannel allocation path.
  Future<RenderSceneLoadResult?> _prepareNativeBimCacheScene(
    String ifcPath,
  ) async {
    try {
      final paths = await _nativeBimCachePaths(ifcPath);
      if (mounted) {
        _updateViewportState(() {
          _statusMessage = 'Opening native 3D cache...';
        });
      }
      final payload = await _viewportController.prepareNativeBimCache(
        sourceIfcPath: ifcPath,
        cachePath: paths.cachePath,
      );
      final rawScene = payload?['scene'];
      if (rawScene is! Map) return null;
      final result = parseRenderSceneJson(
        jsonEncode(rawScene),
        source: 'native BIM cache metadata',
      );
      return result.scene == null ? null : result;
    } catch (_) {
      // A cache failure is recoverable: the legacy JSON renderer remains the
      // migration fallback for the same IFC source.
      return null;
    }
  }

  Future<void> _exportIfc() async {
    if (_isBusy || !_engineBackedMode || _engineRepository == null) return;
    try {
      const typeGroup = XTypeGroup(
        label: 'IFC model',
        extensions: <String>['ifc'],
      );
      final location = await getSaveLocation(
        acceptedTypeGroups: <XTypeGroup>[typeGroup],
        suggestedName: 'project.ifc',
      );
      if (location == null || !mounted) return;
      _updateViewportState(() {
        _isBusy = true;
        _loadError = null;
        _statusMessage = 'Exporting IFC...';
      });
      await _projectPersistence.exportIfc(path: location.path);
      if (!mounted) return;
      _updateViewportState(() {
        _isBusy = false;
        _statusMessage = 'IFC exported: ${location.path}';
      });
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'IFC export failed.';
      });
    }
  }

  Future<void> _showProjectUnitsDialog() async {
    if (_isBusy || !_engineBackedMode || _engineRepository == null) return;
    try {
      final current = await _projectPersistence.getUnitSettings();
      if (!mounted) return;
      var system = (current['system'] as String?) ?? 'metric';
      var length = (current['length'] as String?) ?? 'meter';
      final saved = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Project units'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: system,
                    decoration: const InputDecoration(labelText: 'System'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'metric', child: Text('Metric')),
                      DropdownMenuItem(
                          value: 'imperial', child: Text('Imperial')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => system = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: length,
                    decoration: const InputDecoration(labelText: 'Length'),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                          value: 'millimeter', child: Text('Millimeter')),
                      DropdownMenuItem(
                          value: 'centimeter', child: Text('Centimeter')),
                      DropdownMenuItem(value: 'meter', child: Text('Meter')),
                      DropdownMenuItem(value: 'inch', child: Text('Inch')),
                      DropdownMenuItem(value: 'foot', child: Text('Foot')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => length = value);
                    },
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      );
      if (saved != true || !mounted) return;
      await _projectPersistence.setUnitSettings(
        system: system,
        length: length,
        angle: 'degrees',
      );
      final result = await _sceneViews.refresh();
      await _applyLoadResult(
        result,
        sourceLabel: 'Project units',
        preserveViewport: true,
      );
      _updateViewportState(() {
        _projectHasChanges = true;
        _statusMessage = 'Project units: ${_projectUnitSettings.lengthSymbol}';
      });
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'Project units could not be updated.';
      });
    }
  }

  Future<bool> _saveProjectForExit() async {
    final repository = _engineRepository;
    if (!_engineBackedMode || repository == null || _isBusy) {
      _updateViewportState(() {
        _statusMessage = 'Saving requires a native engine session.';
      });
      return false;
    }
    _updateViewportState(() {
      _isBusy = true;
      _loadError = null;
      _statusMessage = 'Saving project...';
    });
    try {
      final file = await _projectPersistence.saveToDefaultLocation();
      try {
        await _recoveryStore.deleteForProject(_currentProjectName);
      } catch (_) {
        // Explicit save is already durable; recovery cleanup is best-effort.
      }
      if (!mounted) return false;
      _updateViewportState(() {
        _isBusy = false;
        _projectHasChanges = false;
        _statusMessage = 'Saved: ${file.path}';
      });
      return true;
    } catch (error) {
      if (!mounted) return false;
      _updateViewportState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'Project save failed.';
      });
      return false;
    }
  }

  Future<void> _requestReturnToStart() async {
    final returnToStart = widget.onReturnToStart;
    if (returnToStart == null || !mounted || _isBusy || _scene == null) {
      return;
    }

    if (!_projectHasChanges) {
      try {
        await _recoveryStore.deleteForProject(_currentProjectName);
      } catch (_) {}
      await returnToStart();
      return;
    }

    final choice = await showDialog<_WorkspaceExitChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Close project?'),
        content: const Text(
          'Save the open project before leaving Tablet BIM?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              _WorkspaceExitChoice.discard,
            ),
            child: const Text("Don't save"),
          ),
          FilledButton(
            onPressed: _engineBackedMode
                ? () => Navigator.of(context).pop(
                      _WorkspaceExitChoice.save,
                    )
                : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted || choice == null) return;
    if (choice == _WorkspaceExitChoice.save) {
      final saved = await _saveProjectForExit();
      if (!saved || !mounted) return;
    }
    if (choice == _WorkspaceExitChoice.discard) {
      try {
        await _recoveryStore.deleteForProject(_currentProjectName);
      } catch (_) {}
    }
    await returnToStart();
  }

  void _scheduleRecoveryAutosave() {
    _recoveryAutosaveTimer?.cancel();
    if (!_projectHasChanges || !_engineBackedMode) return;
    _recoveryAutosaveTimer = Timer(const Duration(seconds: 2), () {
      unawaited(_writeRecoveryAutosave());
    });
  }

  Future<void> _writeRecoveryAutosave() async {
    if (!_projectHasChanges || !_engineBackedMode || _recoveryWriteInFlight) {
      return;
    }
    if (_isBusy) {
      _scheduleRecoveryAutosave();
      return;
    }
    final repository = _engineRepository;
    if (repository == null) return;
    _recoveryWriteInFlight = true;
    try {
      final json = await repository.snapshotProjectJson();
      await _recoveryStore.write(
        projectName: _currentProjectName,
        json: json,
      );
    } catch (_) {
      // Recovery must never interrupt authoring or explicit saving.
    } finally {
      _recoveryWriteInFlight = false;
    }
  }

  Future<void> _refreshHistoryState() async {
    final repository = _engineRepository;
    if (!_engineBackedMode || repository == null) {
      _updateViewportState(() {
        _canUndo = false;
        _canRedo = false;
      });
      return;
    }
    try {
      final counts = await repository.historyCounts();
      if (!mounted) return;
      _updateViewportState(() {
        _canUndo = counts.undoCount > 0;
        _canRedo = counts.redoCount > 0;
      });
    } catch (_) {
      if (mounted) {
        _updateViewportState(() {
          _canUndo = false;
          _canRedo = false;
        });
      }
    }
  }

  Future<void> _undoProject() async {
    final repository = _engineRepository;
    if (!_engineBackedMode || repository == null || _isBusy || !_canUndo) {
      return;
    }
    _updateViewportState(() {
      _isBusy = true;
      _statusMessage = 'Undoing...';
      _loadError = null;
    });
    try {
      final result = await repository.undo();
      await _applyLoadResult(result, sourceLabel: 'Undo');
      _updateViewportState(() {
        _projectHasChanges = true;
        _statusMessage = 'Undo applied.';
      });
      _scheduleRecoveryAutosave();
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'Undo failed.';
      });
      await _refreshHistoryState();
    }
  }

  Future<void> _redoProject() async {
    final repository = _engineRepository;
    if (!_engineBackedMode || repository == null || _isBusy || !_canRedo) {
      return;
    }
    _updateViewportState(() {
      _isBusy = true;
      _statusMessage = 'Redoing...';
      _loadError = null;
    });
    try {
      final result = await repository.redo();
      await _applyLoadResult(result, sourceLabel: 'Redo');
      _updateViewportState(() {
        _projectHasChanges = true;
        _statusMessage = 'Redo applied.';
      });
      _scheduleRecoveryAutosave();
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _isBusy = false;
        _loadError = error.toString();
        _statusMessage = 'Redo failed.';
      });
      await _refreshHistoryState();
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

  OpenedViewTab? _openedViewTabById(String id) {
    for (final tab in _openedViewTabs) {
      if (tab.id == id) return tab;
    }
    return null;
  }

  void _updateViewPresentation(
    String viewId, {
    RenderSceneDisplayStyle? displayStyle,
    bool? shadowsEnabled,
    RenderSceneOrbitProjectionStyle? orbitProjectionStyle,
  }) {
    if (!mounted) return;
    final index = _openedViewTabs.indexWhere((tab) => tab.id == viewId);
    if (index < 0) return;
    final current = _openedViewTabs[index];
    final updated = current.copyWith(
      displayStyle: displayStyle,
      shadowsEnabled: shadowsEnabled,
      orbitProjectionStyle: orbitProjectionStyle,
    );
    _viewWorkspace.savePresentation(
      viewId,
      displayStyle: updated.displayStyle,
      shadowsEnabled: updated.shadowsEnabled,
      orbitProjectionStyle: updated.orbitProjectionStyle,
    );
    _sheetWorkspace.updateViewPresentation(
      viewId,
      displayStyle: updated.displayStyle,
      shadowsEnabled: updated.shadowsEnabled,
      orbitProjectionStyle: updated.orbitProjectionStyle,
    );
    if (updated.displayStyle == current.displayStyle &&
        updated.shadowsEnabled == current.shadowsEnabled &&
        updated.orbitProjectionStyle == current.orbitProjectionStyle) {
      return;
    }
    _updateViewportState(() {});
  }

  void _updateActiveViewPresentation({
    RenderSceneDisplayStyle? displayStyle,
    bool? shadowsEnabled,
    RenderSceneOrbitProjectionStyle? orbitProjectionStyle,
  }) {
    final activeId = _activeViewTabId;
    if (activeId == null) return;
    _updateViewPresentation(
      activeId,
      displayStyle: displayStyle,
      shadowsEnabled: shadowsEnabled,
      orbitProjectionStyle: orbitProjectionStyle,
    );
  }

  void _saveActiveViewPresentation() {
    _updateActiveViewPresentation(
      displayStyle: _displayStyle,
      shadowsEnabled: _viewportController.shadowsEnabled,
      orbitProjectionStyle: _orbitProjectionStyle,
    );
  }

  Future<void> _restoreViewPresentation(OpenedViewTab tab) async {
    _updateViewportState(() {
      _displayStyle = tab.displayStyle;
      _usesProjectionDefaultDisplayStyle = false;
      _orbitProjectionStyle = tab.orbitProjectionStyle;
    });
    await _viewportController.setOrbitProjectionStyle(
      tab.orbitProjectionStyle,
    );
    await _viewportController.setDisplayStyle(tab.displayStyle);
    await _viewportController.setShadowsEnabled(tab.shadowsEnabled);
  }

  OpenedViewTab _tabWithSavedPresentation(OpenedViewTab tab) {
    return _viewWorkspace.withSavedPresentation(tab);
  }

  Future<void> _openViewTab(OpenedViewTab tab) {
    if (_workspaceBusy || !mounted) return Future<void>.value();
    return _runViewNavigation(() => _openViewTabNow(tab));
  }

  Future<void> _openViewTabNow(OpenedViewTab tab) async {
    _saveActiveViewPresentation();
    final requested = _tabWithSavedPresentation(tab);
    final existing = _openedViewTabById(requested.id);
    final previousTabId = _activeViewTabId;
    final previousTab =
        previousTabId == null ? null : _openedViewTabById(previousTabId);
    if (existing == null) {
      _viewWorkspace.addTab(requested);
    }
    _updateViewportState(() {
      _activeViewTabId = requested.id;
    });
    final target = existing ?? requested;
    try {
      await _activateViewTab(target);
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        if (existing == null) {
          _viewWorkspace.removeTab(requested.id);
        }
        _activeViewTabId = previousTabId;
        _loadError = error.toString();
        _statusMessage = '${target.label} could not be opened.';
      });
      if (previousTab != null) {
        try {
          await _activateViewTab(previousTab);
        } catch (_) {
          // Keep the failed navigation error visible if the previous view
          // also cannot be restored.
        }
      }
    }
  }

  Future<void> _activateViewTab(OpenedViewTab tab) async {
    if (tab.kind != OpenedViewKind.sheet &&
        _sheetWorkspace.activeSheet != null) {
      _sheetWorkspace.closeSheet();
    }
    switch (tab.kind) {
      case OpenedViewKind.threeD:
        await _setProjectionModeNow(
          tab.projectionMode ?? RenderSceneProjectionMode.isometric,
        );
      case OpenedViewKind.floorPlan:
        if (tab.levelId != null) {
          await _setActiveLevelNow(tab.levelId);
        }
        await _setProjectionModeNow(
          tab.projectionMode ?? RenderSceneProjectionMode.topDown,
        );
      case OpenedViewKind.elevation:
        await _setProjectionModeNow(
          tab.projectionMode ?? RenderSceneProjectionMode.northElevation,
        );
      case OpenedViewKind.section:
        final section = tab.section;
        if (section != null) await _openProjectSection(section);
      case OpenedViewKind.sheet:
        if (tab.sheetId != null) _openSheet(tab.sheetId!);
    }
    if (tab.kind != OpenedViewKind.sheet) {
      await _restoreViewPresentation(tab);
    }
  }

  Future<void> _open3dViewTab() {
    return _openViewTab(OpenedViewTab(
      id: ViewWorkspaceStore.threeDViewId,
      label: '3D View',
      kind: OpenedViewKind.threeD,
      projectionMode: RenderSceneProjectionMode.isometric,
    ));
  }

  Future<void> _openFloorPlanViewTab(int levelId) async {
    final level = _scene?.levelById(levelId);
    if (level == null) return;
    await _openViewTab(OpenedViewTab(
      id: ViewWorkspaceStore.floorPlanId(levelId),
      label: '${level.name} plan',
      kind: OpenedViewKind.floorPlan,
      projectionMode: RenderSceneProjectionMode.topDown,
      levelId: levelId,
    ));
  }

  Future<void> _openElevationViewTab(
    RenderSceneProjectionMode mode,
  ) {
    return _openViewTab(OpenedViewTab(
      id: 'elevation-${mode.name}',
      label: mode.shortLabel,
      kind: OpenedViewKind.elevation,
      projectionMode: mode,
    ));
  }

  Future<void> _openSectionViewTab(RenderSceneSection section) {
    return _openViewTab(OpenedViewTab(
      id: 'section-${section.name}',
      label: section.name,
      kind: OpenedViewKind.section,
      projectionMode: projectionModeForSection(section),
      section: section,
    ));
  }

  Future<void> _openSheetViewTab(String sheetId) {
    final sheet = _sheetWorkspace.sheets.firstWhere(
      (item) => item.id == sheetId,
      orElse: () => const ProjectSheet(id: '', number: '', title: ''),
    );
    if (sheet.id.isEmpty) return Future<void>.value();
    return _openViewTab(OpenedViewTab(
      id: 'sheet-${sheet.id}',
      label: '${sheet.number} - ${sheet.title}',
      kind: OpenedViewKind.sheet,
      sheetId: sheet.id,
    ));
  }

  Future<void> _selectOpenedViewTab(String tabId) {
    if (_workspaceBusy || !mounted) return Future<void>.value();
    return _runViewNavigation(() => _selectOpenedViewTabNow(tabId));
  }

  Future<void> _selectOpenedViewTabNow(String tabId) async {
    final tab = _openedViewTabById(tabId);
    if (tab == null || _activeViewTabId == tabId) return;
    final previousTabId = _activeViewTabId;
    _saveActiveViewPresentation();
    _updateViewportState(() => _activeViewTabId = tabId);
    try {
      await _activateViewTab(tab);
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _activeViewTabId = previousTabId;
        _loadError = error.toString();
        _statusMessage = '${tab.label} could not be opened.';
      });
      final previousTab =
          previousTabId == null ? null : _openedViewTabById(previousTabId);
      if (previousTab != null) {
        try {
          await _activateViewTab(previousTab);
        } catch (_) {
          // Preserve the original navigation error in the workspace.
        }
      }
    }
  }

  Future<void> _closeOpenedViewTab(String tabId) async {
    if (_openedViewTabs.length <= 1) {
      if (_openedViewTabs.any((tab) => tab.id == tabId)) {
        await _requestReturnToStart();
      }
      return;
    }
    _saveActiveViewPresentation();
    final index = _openedViewTabs.indexWhere((tab) => tab.id == tabId);
    if (index < 0) return;
    final closing = _openedViewTabs[index];
    final wasActive = _activeViewTabId == tabId;
    final nextIndex =
        index < _openedViewTabs.length - 1 ? index + 1 : index - 1;
    final nextTab = _openedViewTabs[nextIndex];
    _updateViewportState(() {
      _viewWorkspace.removeTab(tabId);
      if (wasActive) _activeViewTabId = nextTab.id;
    });
    if (closing.kind == OpenedViewKind.sheet &&
        _sheetWorkspace.activeSheetId == closing.sheetId) {
      _sheetWorkspace.closeSheet();
    }
    if (wasActive) await _activateViewTab(nextTab);
  }

  void _createSheet() {
    final sheet = _sheetWorkspace.createSheet();
    final tab = OpenedViewTab(
      id: 'sheet-${sheet.id}',
      label: '${sheet.number} - ${sheet.title}',
      kind: OpenedViewKind.sheet,
      sheetId: sheet.id,
    );
    _updateViewportState(() {
      _viewWorkspace.addTab(tab);
      _activeViewTabId = tab.id;
      _showSidePanel = true;
      _sidePanelTab = WorkspaceSidePanelTab.projectBrowser;
      _statusMessage = '${sheet.number} sheet opened.';
    });
  }

  void _openSheet(String sheetId) {
    _sheetWorkspace.openSheet(sheetId);
    final sheet = _sheetWorkspace.activeSheet;
    _updateViewportState(() {
      _showSidePanel = true;
      _sidePanelTab = WorkspaceSidePanelTab.projectBrowser;
      _statusMessage =
          sheet == null ? _statusMessage : '${sheet.number} · ${sheet.title}';
    });
  }

  void _closeActiveSheet() {
    final sheetId = _sheetWorkspace.activeSheetId;
    if (sheetId != null) unawaited(_closeOpenedViewTab('sheet-$sheetId'));
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

    _updateViewportState(() {
      _statusMessage = 'Preparing ${view.label} for the sheet...';
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
          _viewWorkspace.cacheSheetSource(source);
        }
        resolvedScene = view.kind == SheetViewKind.floorPlan
            ? source.filteredByLevel(view.levelId)
            : source;
      }

      _viewWorkspace.cacheSheetScene(view.id, resolvedScene);
      final placed = _sheetWorkspace.placeView(
        view: view,
        centerX: normalizedX,
        centerY: normalizedY,
      );
      if (mounted) {
        _updateViewportState(() {
          _statusMessage = placed
              ? '${view.label} placed on the sheet.'
              : '${view.label} bu sheetda allaqachon bor.';
        });
      }
      return placed;
    } catch (error) {
      if (mounted) {
        _updateViewportState(() {
          _statusMessage = '${view.label} could not be placed on the sheet.';
          _loadError = error.toString();
        });
      }
      return false;
    }
  }

  Future<void> _applyLoadResult(
    RenderSceneLoadResult result, {
    required String sourceLabel,
    bool resetProjectChanges = false,
    bool nativeGeometryAlreadyLoaded = false,
    bool preserveViewport = false,
    int? expectedSceneDataRevision,
  }) async {
    if (expectedSceneDataRevision != null &&
        expectedSceneDataRevision != _sceneDataRevision) {
      return;
    }
    if (!preserveViewport) {
      ++_sceneDataRevision;
    }
    final rawScene = result.scene;
    final scene = rawScene == null
        ? null
        : nativeGeometryAlreadyLoaded
            ? rawScene
            : RenderSceneEditor.normalizeSceneGeometry(rawScene);
    _viewWorkspace.clearSheetCache();
    final resetViewWorkspace = resetProjectChanges && !preserveViewport;

    _updateViewportState(() {
      // A deferred detail query is best-effort. If it fails, keep the
      // already interactive primary scene instead of blanking the viewport.
      if (scene != null || !preserveViewport) {
        _scene = scene;
      }
      if (resetProjectChanges) {
        _projectHasChanges = false;
      }
      if (scene == null && preserveViewport) {
        _engineLoadDiagnostic =
            result.errors.isNotEmpty ? result.errors.join('\n') : null;
        _loadError = null;
        _statusMessage = '$sourceLabel · core scene ready';
      } else {
        _loadError = result.errors.isNotEmpty ? result.errors.join('\n') : null;
        _statusMessage = scene == null
            ? 'RenderScene load failed.'
            : '$sourceLabel · ${scene.objectCount} objects';
      }
      _isBusy = false;

      if (scene != null) {
        if (resetViewWorkspace) {
          // Project entry is the single boundary that owns default view
          // state. Authoring refreshes, undo/redo, and detail hydration keep
          // the user's opened tabs and camera mode intact.
          _viewWorkspace.resetForScene(scene);
          _activeViewTabId = _viewWorkspace.activeTabId;
          _projectionMode =
              _openedViewTabById(_activeViewTabId ?? '')?.projectionMode ??
                  RenderSceneProjectionMode.topDown;
          _usesProjectionDefaultVisibility = true;
          _usesProjectionDefaultDisplayStyle = true;
        }
        if (_usesProjectionDefaultDisplayStyle) {
          _displayStyle = _defaultDisplayStyleForProjection();
        }
        _activeLevelId = _resolveInitialLevelId(
          scene,
          // A new project gets a clean view context. Existing scene refreshes
          // retain the user's current level, including after an edit or
          // undo/redo.
          preferred: resetViewWorkspace ? null : _activeLevelId,
        );
        final activeLevel = scene.levelById(_activeLevelId) ??
            (scene.levels.isNotEmpty ? scene.levels.first : null);
        _draftFloorTopElevationMeters = activeLevel?.elevationMeters ?? 0.0;
        _draftSurfaceHeightMeters = activeLevel?.defaultWallHeightMeters ??
            _ViewerHomePageState._defaultWallHeightMeters;
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
      if (!preserveViewport) {
        await _viewportController.clearScene();
      }
      await _refreshHistoryState();
      await _refreshProjectUnitSettings();
      return;
    }

    if (nativeGeometryAlreadyLoaded) {
      await _viewportController.loadNativeSceneSummary(
        _sceneForViewport(scene),
      );
    } else if (preserveViewport) {
      await _viewportController.updateRenderScene(
        _sceneForViewport(scene),
        resetView: false,
        preserveNativeGeometry: _viewportController.hasNativeGeometry,
      );
    } else {
      await _viewportController.loadRenderScene(_sceneForViewport(scene));
    }
    await _viewportController.setVisibleKinds(_visibleKinds);
    await _viewportController.setProjectionMode(_projectionMode);
    await _viewportController.setOrbitProjectionStyle(_orbitProjectionStyle);
    await _viewportController.setDisplayStyle(_displayStyle);
    if (!preserveViewport) {
      _interactionMode = RenderSceneInteractionMode.select;
      await _viewportController.setInteractionMode(_interactionMode);
      _viewportController.clearDraft();
      await _viewportController.fitCamera();
    }
    if (kDebugMode &&
        _viewportController.backend == RenderSceneViewportBackend.native) {
      final diagnostics = await _viewportController.nativeDiagnostics();
      if (diagnostics != null && mounted && _showDiagnostics) {
        final input = diagnostics['inputObjects'] ?? 0;
        final renderables = diagnostics['renderables'] ?? 0;
        final faceBatches = diagnostics['faceBatches'] ?? renderables;
        final instanceGroups = diagnostics['instanceGroups'] ?? 0;
        final instancedObjects = diagnostics['instancedObjects'] ?? 0;
        final edgeBatches = diagnostics['edgeBatches'] ?? 0;
        final drawCalls = diagnostics['estimatedDrawCalls'] ?? renderables;
        final frames = diagnostics['renderedFrames'] ?? 0;
        final materialReady = diagnostics['materialReady'] == true;
        _updateViewportState(() {
          _statusMessage =
              'Filament: input=$input · renderables=$renderables · '
              'face batches=$faceBatches · instances=$instancedObjects/$instanceGroups · '
              'edge batches=$edgeBatches · '
              'draws=$drawCalls · frames=$frames · '
              'material=${materialReady ? 'ready' : 'FAILED'}';
        });
      }
    }
    await _refreshHistoryState();
    await _refreshProjectUnitSettings();
  }

  Future<void> _refreshProjectUnitSettings() async {
    final repository = _engineRepository;
    if (!_engineBackedMode || repository == null) {
      if (mounted &&
          _projectUnitSettings != const ProjectUnitSettings.defaults()) {
        _updateViewportState(() {
          _projectUnitSettings = const ProjectUnitSettings.defaults();
        });
      }
      return;
    }
    try {
      final settings = ProjectUnitSettings.fromMap(
        await _projectPersistence.getUnitSettings(),
      );
      if (!mounted) return;
      if (_projectUnitSettings != settings) {
        _updateViewportState(() {
          _projectUnitSettings = settings;
        });
      }
    } catch (_) {
      // Unit display is a presentation preference. Keep the last known value
      // if an optional read fails; authoring remains in metres internally.
    }
  }
}
