// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

/// Workspace composition, toolbar controls and panels.
extension _ViewerWorkspaceLayout on _ViewerHomePageState {
  Widget _buildWorkspace(BuildContext context) {
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
                if (_openedViewTabs.isNotEmpty)
                  OpenedViewTabBar(
                    tabs: List<OpenedViewTab>.unmodifiable(_openedViewTabs),
                    activeTabId: _activeViewTabId,
                    enabled: !_workspaceBusy,
                    onSelect: (tabId) => unawaited(
                      _selectOpenedViewTab(tabId),
                    ),
                    onClose: (tabId) => unawaited(
                      _closeOpenedViewTab(tabId),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      AuthoringToolPalette(
                        mode: _interactionMode,
                        enabled: scene != null &&
                            !_workspaceBusy &&
                            _sheetWorkspace.activeSheet == null,
                        onModeChanged: _setInteractionMode,
                      ),
                      Expanded(
                        child: _buildViewportPanel(context),
                      ),
                      if (_showSidePanel)
                        _buildWorkspaceSidePanel(
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
      busy: _workspaceBusy,
      engineBacked: _engineBackedMode,
      hasScene: fullScene != null,
      hasSelection: _viewportController.selectedElementId != null,
      browserVisible: _showSidePanel &&
          _sidePanelTab == WorkspaceSidePanelTab.projectBrowser,
      inspectorVisible:
          _showSidePanel && _sidePanelTab == WorkspaceSidePanelTab.inspector,
      activeSectionName: _activeSectionView?.name,
      onExitSection: _activeSectionView == null
          ? null
          : () => _setProjectionMode(RenderSceneProjectionMode.isometric),
      onSave: _saveCurrentProject,
      canUndo: _canUndo,
      canRedo: _canRedo,
      onUndo: () => unawaited(_undoProject()),
      onRedo: () => unawaited(_redoProject()),
      onDocumentation: _openDocumentationWorkspace,
      onImportIfc: _importIfc,
      onExportIfc: _exportIfc,
      onProjectUnits: _showProjectUnitsDialog,
      onCreateSection: _showSectionDialog,
      onReload: _reloadCurrentScene,
      onClearSelection: _clearSelection,
      onToggleBrowser: _toggleProjectBrowserPanel,
      onToggleInspector: _toggleInspectorPanel,
      onReturnToStart:
          widget.onReturnToStart == null ? null : _requestReturnToStart,
    );
  }

  void _toggleProjectBrowserPanel() {
    _updateViewportState(() {
      if (!_showSidePanel ||
          _sidePanelTab != WorkspaceSidePanelTab.projectBrowser) {
        _showSidePanel = true;
        _sidePanelTab = WorkspaceSidePanelTab.projectBrowser;
      } else {
        _showSidePanel = false;
      }
    });
  }

  void _toggleInspectorPanel() {
    _updateViewportState(() {
      if (!_showSidePanel || _sidePanelTab != WorkspaceSidePanelTab.inspector) {
        _showSidePanel = true;
        _sidePanelTab = WorkspaceSidePanelTab.inspector;
      } else {
        _showSidePanel = false;
      }
    });
  }

  void _selectSidePanelTab(WorkspaceSidePanelTab tab) {
    _updateViewportState(() {
      _showSidePanel = true;
      _sidePanelTab = tab;
    });
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
                    onPressed: scene == null || _workspaceBusy
                        ? null
                        : _showSectionBoxDialog,
                    icon: const Icon(Icons.crop_free_outlined, size: 18),
                    label: Text(_viewportController.hasSectionBox
                        ? 'Section Box on'
                        : 'Section Box'),
                  ),
                ],
                const SizedBox(width: 10),
                FilledButton.tonalIcon(
                  onPressed:
                      scene == null || _workspaceBusy ? null : _fitCamera,
                  icon: const Icon(Icons.fit_screen, size: 18),
                  label: const Text('Fit'),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: scene == null ||
                          _workspaceBusy ||
                          _viewportController.selectedElementIds.isEmpty
                      ? null
                      : _deleteSelectedObject,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(
                    _viewportController.selectedElementIds.length > 1
                        ? 'Delete (${_viewportController.selectedElementIds.length})'
                        : 'Delete',
                  ),
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
                          _updateViewportState(() {
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
    return Tooltip(
      message: label,
      child: ChoiceChip(
        avatar: Icon(_toolbarIcon(label), size: 17),
        label: Text(label),
        selected: selected,
        onSelected: onPressed == null ? null : (_) => onPressed(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildProjectBrowserPanel(
    BuildContext context,
    RenderScene? scene,
  ) {
    return ProjectBrowserPanel(
      scene: scene,
      availableKinds: _availableKinds(scene),
      visibleKinds: _visibleKinds,
      activeViewTabId: _activeViewTabId,
      sheets: _sheetWorkspace.sheets,
      activeSheetId: _sheetWorkspace.activeSheetId,
      onCreateSheet: _createSheet,
      onClose: () => _updateViewportState(() => _showSidePanel = false),
      onVisibleKindsChanged: _setVisibleKinds,
      onOpen3d: _open3dViewTab,
      onOpenFloorPlan: _openFloorPlanViewTab,
      onOpenElevation: _openElevationViewTab,
      onOpenSection: _openSectionViewTab,
      viewPresentationById:
          Map<String, OpenedViewTab>.unmodifiable(_viewPresentationById),
      onOpenSheet: _openSheetViewTab,
    );
  }

  Future<void> _openProjectSection(RenderSceneSection section) async {
    if (_engineRepository == null || !_engineBackedMode || !mounted) {
      throw StateError('Section view requires an active engine project.');
    }
    _updateViewportState(() {
      _isBusy = true;
      _statusMessage = 'Opening ${section.name}...';
      _loadError = null;
    });
    try {
      final result = await _sceneViews.setFullSceneRenderScope(true);
      await _activateSectionView(section, result);
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'Section failed.';
      });
      rethrow;
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
          color: Theme.of(context).colorScheme.surface,
          child: RenderSceneViewport(
            controller: _viewportController,
            interactionMode: _interactionMode,
            onSceneTap: _handleSceneTap,
            onSceneDragStart: _handleSceneDragStart,
            onSceneDragUpdate: _handleSceneDragUpdate,
            onSceneDragEnd: _handleSceneDragEnd,
            onSceneMultiTouchStart: _handleSceneMultiTouchStart,
            onSceneSecondaryTap: _handleSceneSecondaryTap,
            onSceneHover: _handleSceneHover,
            authoringPickKinds: _authoringPickKinds,
            directSurfaceDrag: _isSurfaceAuthoring &&
                (_surfaceDrawMode == RenderSceneSurfaceDrawMode.rectangle ||
                    _surfaceDrawMode == RenderSceneSurfaceDrawMode.polyline),
            planPickResolver: _engineBackedMode ? _resolvePlanPick : null,
            onLevelElevationSubmitted: _moveSelectedLevelElevation,
            draftSurfaceWallIds: _draftSurfaceWallIds,
            draftWallThicknessMeters:
                _ViewerHomePageState._defaultWallThicknessMeters,
            draftWallHeightMeters:
                _ViewerHomePageState._defaultWallHeightMeters,
            draftWallEditElementId: _draftMoveTarget?.kindKey == 'wall'
                ? _draftMoveTarget?.elementId
                : null,
            showDiagnostics: _showDiagnostics,
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
              enabled: _scene != null && !_workspaceBusy,
              canFinish: _draftCanConfirm,
              canUndo: _surfaceTool.canUndo,
              canCloseBoundary: _draftSurfacePoints.length >= 3,
              boundaryClosed: _surfaceTool.boundaryClosed,
              draftPointCount: _draftSurfacePoints.length,
              onDrawModeChanged: _setSurfaceDrawMode,
              onUndo: _undoSurfaceDraft,
              onToggleBoundaryClosed: _toggleBoundaryClosed,
              onRepairJoins: () => unawaited(_repairWallJoins()),
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
              enabled: _scene != null && !_workspaceBusy,
              hasDraft: _interactionMode == RenderSceneInteractionMode.addWall
                  ? _wallTool.hasStart
                  : _stairTool.hasStart,
              onDone: () => unawaited(
                _setInteractionMode(RenderSceneInteractionMode.select),
              ),
              onCancel: _cancelDraft,
            ),
          ),
        // The Section Box is drawn and manipulated in the native Filament
        // overlay so its border and clipping planes share one camera matrix.
        Positioned(
          right: 16,
          bottom: 16,
          child: ViewportControlDeck(
            hasScene: _scene != null && !_workspaceBusy,
            projectionMode: _projectionMode,
            displayStyle: _displayStyle,
            shadowsEnabled: _viewportController.shadowsEnabled,
            hdriVisible: _viewportController.hdriVisible,
            orbitStyle: _orbitProjectionStyle,
            onProjectionChanged: _setProjectionMode,
            onDisplayStyleChanged: _setDisplayStyle,
            onShadowsChanged: _setShadowsEnabled,
            onHdriChanged: _setHdriVisible,
            onOrbitStyleChanged: _setOrbitProjectionStyle,
            onFit: _fitCamera,
            hasSectionBox: _viewportController.hasSectionBox,
            onSectionBox: _showSectionBoxDialog,
          ),
        ),
        if (_workspaceBusy)
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

  Widget _buildWorkspaceSidePanel({
    required BuildContext context,
    required RenderScene? scene,
    required InspectorTarget inspectorTarget,
  }) {
    final theme = Theme.of(context);

    return SizedBox(
      width: 340,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            WorkspaceSidePanelTabs(
              activeTab: _sidePanelTab,
              onChanged: _selectSidePanelTab,
            ),
            const Divider(height: 1),
            Expanded(
              child: switch (_sidePanelTab) {
                WorkspaceSidePanelTab.projectBrowser =>
                  _buildProjectBrowserPanel(context, scene),
                WorkspaceSidePanelTab.inspector => _buildInspectorPanel(
                    context: context,
                    scene: scene,
                    inspectorTarget: inspectorTarget,
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorPanel({
    required BuildContext context,
    required RenderScene? scene,
    required InspectorTarget inspectorTarget,
  }) {
    final theme = Theme.of(context);
    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: scene == null
                ? const _EmptyPanelMessage(
                    icon: Icons.info_outline,
                    title: 'No scene',
                    message: 'Load a scene to inspect diagnostics.',
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: <Widget>[
                      if (_interactionMode != RenderSceneInteractionMode.select)
                        ExpansionTile(
                          key: PageStorageKey<String>(
                            'inspector-active-tool-${_interactionMode.name}',
                          ),
                          initiallyExpanded: _interactionMode ==
                                  RenderSceneInteractionMode.addDoor ||
                              _interactionMode ==
                                  RenderSceneInteractionMode.addWindow ||
                              _interactionMode ==
                                  RenderSceneInteractionMode.moveOpening,
                          backgroundColor: Colors.transparent,
                          collapsedBackgroundColor: Colors.transparent,
                          shape: const Border(),
                          collapsedShape: const Border(),
                          tilePadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          leading: const Icon(Icons.build_outlined),
                          title: const Text('Active tool'),
                          subtitle: Text(_interactionMode.authoringLabel),
                          children: <Widget>[
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
                              draftSurfacePointCount:
                                  _draftSurfacePoints.length,
                              draftSurfaceWallCount:
                                  _draftSurfaceWallIds.length,
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
                              openingKind: _interactionMode ==
                                          RenderSceneInteractionMode
                                              .addWindow ||
                                      (_interactionMode ==
                                              RenderSceneInteractionMode
                                                  .moveOpening &&
                                          _draftMoveTarget?.kindKey == 'window')
                                  ? 'window'
                                  : 'door',
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
                                _updateViewportState(() {
                                  _snapDraftToGrid = value;
                                });
                                if (_interactionMode ==
                                        RenderSceneInteractionMode.addDoor ||
                                    _interactionMode ==
                                        RenderSceneInteractionMode.addWindow ||
                                    _interactionMode ==
                                        RenderSceneInteractionMode
                                            .moveOpening) {
                                  _syncOpeningDraft();
                                } else {
                                  _syncSurfaceDraftPreview();
                                }
                              },
                              onOpeningPresetChanged: (preset) {
                                _updateViewportState(() {
                                  _draftOpeningWidthMeters = preset.widthMeters;
                                  _draftOpeningHeightMeters =
                                      preset.heightMeters;
                                  _draftOpeningSillHeightMeters =
                                      preset.sillHeightMeters;
                                });
                                _syncOpeningDraft();
                              },
                              onSurfaceThicknessChanged: (value) {
                                _updateViewportState(() {
                                  _draftSurfaceThicknessMeters = value;
                                });
                              },
                              onSurfaceHeightChanged: (value) {
                                _updateViewportState(() {
                                  if (_interactionMode ==
                                      RenderSceneInteractionMode.addCeiling) {
                                    _draftCeilingHeightOffsetMeters = value;
                                  } else {
                                    _draftSurfaceHeightMeters = value;
                                  }
                                });
                              },
                              onFloorTopElevationChanged: (value) {
                                _updateViewportState(() {
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
                          ],
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
}

IconData _toolbarIcon(String label) => switch (label) {
      '3D' || '3D View' => Icons.view_in_ar_outlined,
      'Shaded' => Icons.gradient_outlined,
      'Solid' => Icons.circle_outlined,
      'Wire' || 'Wireframe' => Icons.grid_4x4_outlined,
      'Ortho' => Icons.crop_square_outlined,
      'Persp' => Icons.threed_rotation,
      'Section Box' || 'Section Box on' => Icons.crop_free_outlined,
      'Fit' => Icons.fit_screen_outlined,
      'Delete' || 'Delete (2)' => Icons.delete_outline,
      'Select' => Icons.ads_click_outlined,
      'Wall' => Icons.architecture_outlined,
      'Level' || 'Move level' => Icons.height_outlined,
      'Move wall' => Icons.open_with_outlined,
      'Door' => Icons.door_front_door_outlined,
      'Window' => Icons.window_outlined,
      'Move opening' => Icons.compare_arrows_outlined,
      'Floor' => Icons.layers_outlined,
      'Ceiling' => Icons.space_dashboard_outlined,
      'Roof' => Icons.roofing_outlined,
      'Stair' => Icons.stairs_outlined,
      _ => Icons.tune_outlined,
    };
