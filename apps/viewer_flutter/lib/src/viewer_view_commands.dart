// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

extension _ViewerViewCommands on _ViewerHomePageState {
  void _ensureNavigationScene(
    RenderSceneLoadResult result, {
    required String label,
  }) {
    if (result.scene != null) return;
    final detail = result.errors.isEmpty
        ? 'The engine returned an empty RenderScene.'
        : result.errors.join('\n');
    throw StateError('$label failed: $detail');
  }

  Future<void> _fitCamera() async {
    final requestedMode = _projectionMode;
    _updateViewportState(() {
      _statusMessage = requestedMode.fitLabel;
    });

    await _viewportController.fitCamera();
    if (!mounted || _projectionMode != requestedMode) return;
    _updateViewportState(() {
      _statusMessage = requestedMode.statusLabel;
    });
  }

  Future<void> _loadFamilyIntoProject() async {
    final session = _engineRepository;
    final scene = _scene;
    if (!_engineBackedMode ||
        session == null ||
        scene == null ||
        _workspaceBusy) {
      return;
    }

    try {
      await FamilyFileStore.ensureBuiltInFamilies();
      final storedFamilies = await FamilyFileStore.listStored();
      final asset = await _chooseFamilyAsset(storedFamilies);
      if (!mounted || asset == null) return;
      final selected = _selectedObject(scene);
      final hostWall = selected?.kindKey == 'wall' ? selected : null;
      final placement = await _chooseFamilyPlacement(
        asset.document,
        scene,
        hostWall: hostWall,
      );
      if (!mounted || placement == null) return;
      _updateViewportState(() {
        _isBusy = true;
        _loadError = null;
        _statusMessage = 'Placing ${asset.document.name}...';
      });
      final result = await FamilyInstanceAdapter.place(
        family: asset.document,
        type: placement.type,
        familyAssetPath: asset.path,
        levelId: placement.levelId,
        position: RenderScenePoint(x: placement.x, y: placement.y, z: 0.0),
        offsetMeters: placement.offsetMeters,
        creationGateway: session,
        authoringGateway: session,
        hostWallId: hostWall?.elementId,
      );
      await _applyEngineSceneResult(
        result.scene,
        message: '${asset.document.name} · ${result.type.name} placed.',
        revealElementId: result.elementId,
        selectElementId: result.elementId,
      );
    } catch (error) {
      if (!mounted) return;
      _updateViewportState(() {
        _loadError = error.toString();
        _statusMessage = 'Family placement failed.';
      });
    } finally {
      if (mounted) _updateViewportState(() => _isBusy = false);
    }
  }

  Future<
      ({
        FamilyTypeDefinition type,
        int levelId,
        double x,
        double y,
        double offsetMeters,
      })?> _chooseFamilyPlacement(
    FamilyDocument family,
    RenderScene scene, {
    RenderSceneObject? hostWall,
  }) async {
    final levels = scene.levels;
    if (levels.isEmpty || family.types.isEmpty) return null;
    final isHostedOpening = family.category == FamilyCategory.door ||
        family.category == FamilyCategory.window;
    var selectedType = family.types.first;
    var selectedLevelId = hostWall?.levelId ??
        scene.levelById(_activeLevelId)?.levelId ??
        levels.first.levelId;
    final bounds =
        scene.bounds.isFinite ? scene.bounds : RenderSceneBounds.zero();
    final hostWallCenter =
        hostWall == null ? null : RenderSceneQueries.wallCenterPoint(hostWall);
    final hostWallLength =
        hostWall == null ? null : RenderSceneQueries.wallLength(hostWall);
    final initialPoint = hostWallCenter ?? bounds.center;
    final initialOffset = hostWallLength != null && hostWallLength.isFinite
        ? hostWallLength * 0.5
        : 0.0;
    final hostedPlacementAvailable = !isHostedOpening ||
        (hostWall != null &&
            hostWallLength != null &&
            hostWallLength.isFinite &&
            hostWallLength > 0.0);
    final xController = TextEditingController(
      text: initialPoint.x.toStringAsFixed(2),
    );
    final yController = TextEditingController(
      text: initialPoint.y.toStringAsFixed(2),
    );
    final result = await showDialog<
        ({
          FamilyTypeDefinition type,
          int levelId,
          double x,
          double y,
          double offsetMeters,
        })>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: Text('Place ${family.name}'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${family.category.name} family',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<FamilyTypeDefinition>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'Family type',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: family.types
                      .map((item) => DropdownMenuItem<FamilyTypeDefinition>(
                            value: item,
                            child: Text(item.name),
                          ))
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) {
                      setLocalState(() => selectedType = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  initialValue: selectedLevelId,
                  decoration: const InputDecoration(
                    labelText: 'Level',
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
                      setLocalState(() => selectedLevelId = value);
                    }
                  },
                ),
                const SizedBox(height: 8),
                if (isHostedOpening)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hostWall == null
                            ? 'Select a host wall in the viewport before placing this family.'
                            : 'Host wall #${hostWall.elementId ?? '-'} · center placement · ${initialOffset.toStringAsFixed(2)} m',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  )
                else
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _NumericField(
                          label: 'X (m)',
                          controller: xController,
                          onChanged: (_) {},
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _NumericField(
                          label: 'Y (m)',
                          controller: yController,
                          onChanged: (_) {},
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: hostedPlacementAvailable
                  ? () {
                      final x = double.tryParse(xController.text.trim());
                      final y = double.tryParse(yController.text.trim());
                      if (!isHostedOpening &&
                          (x == null ||
                              y == null ||
                              !x.isFinite ||
                              !y.isFinite)) {
                        return;
                      }
                      Navigator.of(dialogContext).pop((
                        type: selectedType,
                        levelId: selectedLevelId,
                        x: x ?? initialPoint.x,
                        y: y ?? initialPoint.y,
                        offsetMeters: isHostedOpening ? initialOffset : 0.0,
                      ));
                    }
                  : null,
              child: const Text('Place'),
            ),
          ],
        ),
      ),
    );
    xController.dispose();
    yController.dispose();
    return result;
  }

  Future<FamilyAssetFile?> _chooseFamilyAsset(
    List<FamilyAssetFile> storedFamilies,
  ) async {
    if (storedFamilies.isEmpty) return FamilyFileStore.open();
    final choice = await FamilyLibraryDialog.show(
      context,
      assets: storedFamilies,
    );
    if (choice == null) return null;
    if (choice.browseFile) return FamilyFileStore.open();
    return choice.asset;
  }

  Future<void> _setProjectionMode(RenderSceneProjectionMode mode) {
    if (!mounted || _workspaceBusy) return Future<void>.value();
    return _runViewNavigation(() => _setProjectionModeNow(mode));
  }

  Future<void> _setProjectionModeNow(RenderSceneProjectionMode mode) async {
    final wasGeneratedSection = _activeSectionView != null;
    if (wasGeneratedSection) {
      await _viewportController.setSectionView(null);
    }
    final scene = _scene;
    final navigationScope = ViewNavigationPolicy.scopeFor(
      mode: mode,
      objectCount: scene?.objectCount ?? 0,
      generatedSection: wasGeneratedSection,
    );
    final standardTabId = _standardViewTabIdForProjection(mode);
    final shouldActivateStandardTab = standardTabId != null &&
        standardTabId != _activeViewTabId &&
        _viewWorkspace.tabById(standardTabId) != null;
    if (_projectionMode == mode && !wasGeneratedSection) {
      if (shouldActivateStandardTab) {
        _updateViewportState(() => _activeViewTabId = standardTabId);
      }
      // A nearby-level plan snapshot can still be active even though the
      // selected tab is already 3D/elevation. Re-fetch the intended scope so
      // the roof is not lost when the user returns to the same view tab.
      if (_viewportController.hasNativeGeometry) {
        await _viewportController.setVisibleKinds(_visibleKinds);
        await _viewportController.setProjectionMode(mode);
        await _viewportController.setDisplayStyle(_displayStyle);
        await _viewportController.fitCamera();
        return;
      }
      final repository = _engineRepository;
      if (_engineBackedMode &&
          repository != null &&
          scene != null &&
          navigationScope.refreshSceneScope) {
        final result = await _sceneViews.setFullSceneRenderScope(
          navigationScope.useFullScene,
        );
        await _applyLoadResult(
          result,
          sourceLabel: navigationScope.sourceLabel,
        );
        _ensureNavigationScene(result, label: navigationScope.sourceLabel);
      } else {
        // Project Browser can be used after a renderer reload. Reassert the
        // controller state even when the Flutter state already has this mode.
        await _viewportController.setProjectionMode(mode);
      }
      return;
    }

    _updateViewportState(() {
      // A normal plan, elevation, or 3D navigation intentionally leaves the
      // generated section snapshot and reloads the authoritative model view.
      _activeSectionView = null;
      _projectionMode = mode;
      if (shouldActivateStandardTab) {
        _activeViewTabId = standardTabId;
      }
      _statusMessage = mode.statusLabel;
      AppTelemetry.track(
        'view_changed',
        properties: <String, Object?>{'view': mode.name},
      );
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
    if (_viewportController.hasNativeGeometry) {
      // A plan scene intentionally strips family meshes before it reaches
      // Filament.  Therefore a 2D <-> 3D transition is also a geometry
      // boundary: rehydrate the authoritative scene once so 3D families are
      // visible again, and strip them again when returning to plan view.
      // Staying within the same projection still uses the resident native
      // geometry and keeps ordinary view changes cheap.
      if (scene != null) {
        await _viewportController.setVisibleKinds(_visibleKinds);
      }
      if (_viewportController.projectionMode != mode && scene != null) {
        await _viewportController.setProjectionMode(mode);
        await _viewportController.updateRenderScene(
          _sceneForViewport(scene),
          visibleKinds: _visibleKinds,
        );
      }
      if (_viewportController.projectionMode != mode) {
        await _viewportController.setProjectionMode(mode);
      }
      await _viewportController.setDisplayStyle(_displayStyle);
      await _viewportController.fitCamera();
      return;
    }
    if (_engineBackedMode && repository != null) {
      final scope = ViewNavigationPolicy.scopeFor(
        mode: mode,
        objectCount: scene?.objectCount ?? 0,
        generatedSection: wasGeneratedSection,
      );
      if (!scope.refreshSceneScope) {
        if (scene != null) {
          await _viewportController.updateRenderScene(_sceneForViewport(scene));
          await _viewportController.setVisibleKinds(_visibleKinds);
        }
        await _viewportController.setProjectionMode(mode);
        await _viewportController.setDisplayStyle(_displayStyle);
        await _viewportController.fitCamera();
        return;
      }
      final result = await _sceneViews.setFullSceneRenderScope(
        scope.useFullScene,
      );
      await _applyLoadResult(
        result,
        sourceLabel: scope.sourceLabel,
      );
      _ensureNavigationScene(result, label: scope.sourceLabel);
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

  String? _standardViewTabIdForProjection(RenderSceneProjectionMode mode) {
    switch (mode) {
      case RenderSceneProjectionMode.topDown:
        final levelId = _activeLevelId;
        return levelId == null ? null : ViewWorkspaceStore.floorPlanId(levelId);
      case RenderSceneProjectionMode.isometric:
        return ViewWorkspaceStore.threeDViewId;
      case RenderSceneProjectionMode.northElevation:
      case RenderSceneProjectionMode.southElevation:
      case RenderSceneProjectionMode.eastElevation:
      case RenderSceneProjectionMode.westElevation:
        return null;
    }
  }

  Future<void> _activateSectionView(
    RenderSceneSection section,
    RenderSceneLoadResult result,
  ) async {
    if (result.scene == null) {
      _updateViewportState(() {
        _activeSectionView = null;
      });
      await _applyLoadResult(result, sourceLabel: section.name);
      _ensureNavigationScene(result, label: section.name);
      return;
    }

    // A section keeps the authoritative full scene and selects its planar
    // descriptor from the authored line. Set that projection first, then
    // apply the scene once; normal elevation navigation would reload and
    // overwrite this cut view.
    final sectionProjection = projectionModeForSection(section);
    _updateViewportState(() {
      _activeSectionView = section;
      _projectionMode = sectionProjection;
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

    final viewId = _activeViewTabId;
    _updateViewportState(() {
      _orbitProjectionStyle = style;
      _statusMessage = style == RenderSceneOrbitProjectionStyle.perspective
          ? '3D perspective view'
          : '3D orthographic view';
    });

    await _viewportController.setOrbitProjectionStyle(style);
    if (viewId != null) {
      _updateViewPresentation(viewId, orbitProjectionStyle: style);
    }
    await _viewportController.fitCamera();
  }

  Future<void> _setDisplayStyle(RenderSceneDisplayStyle style) async {
    if (_displayStyle == style) {
      return;
    }

    final viewId = _activeViewTabId;
    _updateViewportState(() {
      _displayStyle = style;
      _usesProjectionDefaultDisplayStyle = false;
      _statusMessage = switch (style) {
        RenderSceneDisplayStyle.shaded => 'Shaded display',
        RenderSceneDisplayStyle.solid => 'Solid display',
        RenderSceneDisplayStyle.wireframe => 'Wireframe display',
      };
    });

    await _viewportController.setDisplayStyle(style);
    if (viewId != null) {
      _updateViewPresentation(viewId, displayStyle: style);
    }
  }

  Future<void> _setShadowsEnabled(bool enabled) async {
    final viewId = _activeViewTabId;
    await _viewportController.setShadowsEnabled(enabled);
    if (viewId != null) {
      _updateViewPresentation(viewId, shadowsEnabled: enabled);
    }
    if (!mounted) return;
    _updateViewportState(() {
      _statusMessage =
          enabled ? 'Real shadows enabled' : 'Real shadows disabled';
    });
  }

  Future<void> _setHdriVisible(bool visible) async {
    await _viewportController.setHdriVisible(visible);
    if (!mounted) return;
    _updateViewportState(() {
      _statusMessage = visible
          ? 'HDRI background visible'
          : 'HDRI background hidden; environment lighting remains active';
    });
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
      _updateViewportState(() => _statusMessage = next == null
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
    final elevationController = TextEditingController(
      text: _projectUnitSettings.formatLength(
        defaultElevation,
        withUnit: false,
      ),
    );
    final heightController = TextEditingController(
      text: _projectUnitSettings.formatLength(
        currentLevel?.defaultWallHeightMeters ??
            _ViewerHomePageState._defaultWallHeightMeters,
        withUnit: false,
      ),
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
                  label: 'Elevation (${_projectUnitSettings.lengthSymbol})',
                  controller: elevationController,
                  onChanged: (_) {},
                ),
                _NumericField(
                  label:
                      'Default wall height (${_projectUnitSettings.lengthSymbol})',
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
                final elevationDisplay =
                    double.tryParse(elevationController.text.trim());
                final wallHeightDisplay =
                    double.tryParse(heightController.text.trim());
                final elevation = elevationDisplay == null
                    ? null
                    : _projectUnitSettings.toMeters(elevationDisplay);
                final wallHeight = wallHeightDisplay == null
                    ? null
                    : _projectUnitSettings.toMeters(wallHeightDisplay);
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
      final result = await _authoringCommands.createLevel(
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
      _updateViewportState(() {
        _editStatusMessage =
            'Wall level constraints engine-backed mode talab qiladi.';
      });
      return;
    }
    final levels = scene.levels;
    if (levels.isEmpty) {
      return;
    }

    final wallParameters = WallElementParameters.fromObject(object);
    int baseLevelId =
        wallParameters.baseLevelId ?? object.levelId ?? levels.first.levelId;
    int topLevelId = wallParameters.topLevelId ?? 0;
    int heightMode = wallParameters.isTopConnected ? 1 : 0;
    final baseOffsetController = TextEditingController(
      text: _projectUnitSettings.formatLength(
        wallParameters.baseOffsetMeters,
        withUnit: false,
      ),
    );
    final topOffsetController = TextEditingController(
      text: _projectUnitSettings.formatLength(
        wallParameters.topOffsetMeters,
        withUnit: false,
      ),
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
                      label:
                          'Base offset (${_projectUnitSettings.lengthSymbol})',
                      controller: baseOffsetController,
                      onChanged: (_) {},
                    ),
                    _NumericField(
                      label:
                          'Top offset (${_projectUnitSettings.lengthSymbol})',
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
                    final baseOffsetDisplay =
                        double.tryParse(baseOffsetController.text.trim());
                    final topOffsetDisplay =
                        double.tryParse(topOffsetController.text.trim());
                    final baseOffset = baseOffsetDisplay == null
                        ? null
                        : _projectUnitSettings.toMeters(baseOffsetDisplay);
                    final topOffset = topOffsetDisplay == null
                        ? null
                        : _projectUnitSettings.toMeters(topOffsetDisplay);
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
      _updateViewportState(() {
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
      text: _projectUnitSettings.formatLength(
        OpeningElementParameters.fromObject(object).levelOffsetMeters,
        withUnit: false,
      ),
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
                                '${level.name} (${_projectUnitSettings.formatLength(level.elevationMeters)})',
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
                    decoration: InputDecoration(
                      labelText:
                          'Offset from level (${_projectUnitSettings.lengthSymbol})',
                      helperText:
                          'Enter the offset in ${_projectUnitSettings.lengthSymbol}.',
                      border: const OutlineInputBorder(),
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
                    final offsetDisplay =
                        double.tryParse(levelOffsetController.text);
                    if (offsetDisplay == null) {
                      return;
                    }
                    final offset = _projectUnitSettings.toMeters(offsetDisplay);
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
          '${prettySceneKind(object.kind)} ${scene.levelById(resultConstraint.levelId)?.name ?? 'level'} + ${_projectUnitSettings.formatLength(resultConstraint.offset)} ga biriktirildi.',
    );
  }

  Future<void> _showEditLevelDialog(RenderSceneLevel level) async {
    final scene = _scene;
    final repository = _engineRepository;
    if (scene == null || !_engineBackedMode || repository == null) {
      _updateViewportState(() {
        _editStatusMessage = 'Level edit engine-backed mode talab qiladi.';
      });
      return;
    }

    final nameController = TextEditingController(text: level.name);
    final elevationController = TextEditingController(
        text: _projectUnitSettings.formatLength(level.elevationMeters,
            withUnit: false));
    final heightController = TextEditingController(
      text: _projectUnitSettings.formatLength(
        level.defaultWallHeightMeters,
        withUnit: false,
      ),
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
                  label: 'Elevation (${_projectUnitSettings.lengthSymbol})',
                  controller: elevationController,
                  onChanged: (_) {},
                ),
                _NumericField(
                  label:
                      'Default wall height (${_projectUnitSettings.lengthSymbol})',
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
                final elevationDisplay =
                    double.tryParse(elevationController.text.trim());
                final wallHeightDisplay =
                    double.tryParse(heightController.text.trim());
                final elevation = elevationDisplay == null
                    ? null
                    : _projectUnitSettings.toMeters(elevationDisplay);
                final wallHeight = wallHeightDisplay == null
                    ? null
                    : _projectUnitSettings.toMeters(wallHeightDisplay);
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
      _updateViewportState(() {
        _editStatusMessage = 'Enter a valid elevation.';
      });
      return;
    }
    if ((elevation - level.elevationMeters).abs() < 0.0001) {
      return;
    }
    final repository = _engineRepository;
    if (_engineBackedMode && repository != null) {
      final result = await _authoringCommands.moveLevelElevation(
        levelId: level.levelId,
        elevationMeters: elevation,
      );
      final updated = result.scene?.levelById(level.levelId);
      if (updated == null ||
          (updated.elevationMeters - elevation).abs() > 0.0001) {
        _updateViewportState(() {
          _editStatusMessage =
              'The engine did not return the level elevation: ${result.errors.join(' ')}';
        });
        return;
      }
      await _applyEngineSceneResult(
        result,
        message:
            '${level.name} elevation: ${_projectUnitSettings.formatLength(elevation)}.',
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
      message:
          '${level.name} elevation: ${_projectUnitSettings.formatLength(elevation)}.',
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
      _updateViewportState(() {
        _editStatusMessage =
            'Wall level locking will be connected to the constraint Inspector in a later engine mode.';
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
}
