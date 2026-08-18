// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

extension _ViewerProjectLifecycle on _ViewerHomePageState {
  Future<void> _createBlankProject() async {
    if (_isBusy) return;
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
      );
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'New project yaratilmadi.';
        _isBusy = false;
      });
    }
  }

  void _onViewportChanged() {
    if (mounted) {
      _updateViewportState(() {
        // Rebuild inspector/status when selection/highlight changes.
      });
    }
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
      final result = await _sceneViews.refresh();
      await _applyLoadResult(result, sourceLabel: projectName);
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'Projectni ochib bo‘lmadi.';
        _isBusy = false;
      });
    }
  }

  Future<void> _createResidentialTemplate(
    _ResidentialTemplateKind template,
  ) async {
    if (_isBusy) return;
    final buildingCount =
        template == _ResidentialTemplateKind.campus6x9 ? 6 : 1;
    final storyCount = template == _ResidentialTemplateKind.default3 ? 3 : 9;
    final label = switch (template) {
      _ResidentialTemplateKind.default3 => '3-qavatli oddiy bino',
      _ResidentialTemplateKind.tower9 => '9-qavatli turar-joy binosi',
      _ResidentialTemplateKind.campus6x9 =>
        '6 ta 9-qavatli turar-joy shaharchasi',
    };
    _updateViewportState(() {
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
      _updateViewportState(() {
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
    final repository = _engineRepository;
    if (!_engineBackedMode || repository == null || _isBusy) {
      _updateViewportState(() {
        _statusMessage = 'Save uchun native engine session kerak.';
      });
      return;
    }
    _updateViewportState(() {
      _isBusy = true;
      _loadError = null;
      _statusMessage = 'Saving project...';
    });
    try {
      final file = await _projectPersistence.saveToDefaultLocation();
      if (!mounted) return;
      _updateViewportState(() {
        _isBusy = false;
        _statusMessage = 'Saved: ${file.path}';
      });
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
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

  Future<void> _openViewTab(OpenedViewTab tab) async {
    if (_isBusy || !mounted) return;
    _saveActiveViewPresentation();
    final requested = _tabWithSavedPresentation(tab);
    final existing = _openedViewTabById(requested.id);
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
        _loadError = error.toString();
        _statusMessage = '${target.label} ochilmadi.';
        _isBusy = false;
      });
    }
  }

  Future<void> _activateViewTab(OpenedViewTab tab) async {
    if (tab.kind != OpenedViewKind.sheet &&
        _sheetWorkspace.activeSheet != null) {
      _sheetWorkspace.closeSheet();
    }
    switch (tab.kind) {
      case OpenedViewKind.threeD:
        await _setProjectionMode(
          tab.projectionMode ?? RenderSceneProjectionMode.isometric,
        );
      case OpenedViewKind.floorPlan:
        if (tab.levelId != null) {
          await _setActiveLevel(tab.levelId);
        }
        await _setProjectionMode(
          tab.projectionMode ?? RenderSceneProjectionMode.topDown,
        );
      case OpenedViewKind.elevation:
        await _setProjectionMode(
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
      id: 'view-3d-default',
      label: '3D View',
      kind: OpenedViewKind.threeD,
      projectionMode: RenderSceneProjectionMode.isometric,
    ));
  }

  Future<void> _openFloorPlanViewTab(int levelId) async {
    final level = _scene?.levelById(levelId);
    if (level == null) return;
    await _openViewTab(OpenedViewTab(
      id: 'floor-plan-$levelId',
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
      projectionMode: RenderSceneProjectionMode.northElevation,
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

  Future<void> _selectOpenedViewTab(String tabId) async {
    final tab = _openedViewTabById(tabId);
    if (tab == null || _activeViewTabId == tabId) return;
    _saveActiveViewPresentation();
    _updateViewportState(() => _activeViewTabId = tabId);
    await _activateViewTab(tab);
  }

  Future<void> _closeOpenedViewTab(String tabId) async {
    if (_openedViewTabs.length <= 1) return;
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
      _showObjectList = true;
      _showInspector = false;
      _statusMessage = '${sheet.number} sheet ochildi.';
    });
  }

  void _openSheet(String sheetId) {
    _sheetWorkspace.openSheet(sheetId);
    final sheet = _sheetWorkspace.activeSheet;
    _updateViewportState(() {
      _showObjectList = true;
      _showInspector = false;
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
              ? '${view.label} sheetga joylashtirildi.'
              : '${view.label} bu sheetda allaqachon bor.';
        });
      }
      return placed;
    } catch (error) {
      if (mounted) {
        _updateViewportState(() {
          _statusMessage = '${view.label} sheetga qo‘yilmadi.';
          _loadError = error.toString();
        });
      }
      return false;
    }
  }

  Future<void> _applyLoadResult(
    RenderSceneLoadResult result, {
    required String sourceLabel,
  }) async {
    final rawScene = result.scene;
    final scene = rawScene == null
        ? null
        : RenderSceneEditor.normalizeSceneGeometry(rawScene);
    _viewWorkspace.clearSheetCache();

    _updateViewportState(() {
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
  }
}
