// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

class _LevelToolbarControl extends StatelessWidget {
  const _LevelToolbarControl({
    required this.levels,
    required this.activeLevelId,
    required this.onChanged,
    required this.onAddLevel,
    required this.units,
  });

  final List<RenderSceneLevel> levels;
  final int? activeLevelId;
  final ValueChanged<int?> onChanged;
  final VoidCallback onAddLevel;
  final ProjectUnitSettings units;

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
                      '${level.name} (${units.formatLength(level.elevationMeters)})',
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
    final wallParameters = WallElementParameters.fromObject(wall);
    final baseLevelId = wallParameters.baseLevelId ?? wall.levelId;
    final topLevelId = wallParameters.topLevelId;
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
    required this.units,
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.wallArcStart,
    required this.wallArcEnd,
    required this.wallArcControl,
    required this.draftSurfaceStart,
    required this.draftSurfaceEnd,
    required this.draftSurfacePointCount,
    required this.draftSurfaceWallCount,
    required this.draftSurfaceThicknessMeters,
    required this.draftSurfaceHeightMeters,
    required this.draftStairWidthMeters,
    required this.draftStairLandingDepthMeters,
    required this.stairLayoutKind,
    required this.stairRailingEnabled,
    required this.stairLevels,
    required this.stairBaseLevelId,
    required this.stairTopLevelId,
    required this.draftFloorTopElevationMeters,
    required this.surfaceDrawMode,
    required this.surfaceControlsEnabled,
    required this.canSurfaceUndo,
    required this.canCloseSurfaceBoundary,
    required this.surfaceBoundaryClosed,
    required this.wallDrawMode,
    required this.wallTypes,
    required this.wallTypeId,
    required this.floorTypes,
    required this.floorAssemblyId,
    required this.roofTypes,
    required this.roofAssemblyId,
    required this.roofType,
    required this.roofSlopeDegrees,
    required this.roofOverhangMeters,
    required this.draftHostWall,
    required this.openingKind,
    required this.openingWidthMeters,
    required this.openingHeightMeters,
    required this.openingSillHeightMeters,
    required this.trimFirstWall,
    required this.trimSecondWall,
    required this.trimPreview,
    required this.canConfirm,
    required this.onOpeningPresetChanged,
    required this.onSurfaceThicknessChanged,
    required this.onSurfaceHeightChanged,
    required this.onFloorTopElevationChanged,
    required this.onSurfaceDrawModeChanged,
    required this.onSurfaceUndo,
    required this.onSurfaceToggleBoundaryClosed,
    required this.onSurfaceRepairJoins,
    required this.onSurfaceTrimExtend,
    required this.onWallDrawModeChanged,
    required this.onWallTypeChanged,
    required this.onFloorAssemblyChanged,
    required this.onRoofAssemblyChanged,
    required this.onRoofTypeChanged,
    required this.onRoofSlopeChanged,
    required this.onRoofOverhangChanged,
    required this.onStairWidthChanged,
    required this.onStairLandingDepthChanged,
    required this.onStairLayoutChanged,
    required this.onStairRailingChanged,
    required this.onStairBaseLevelChanged,
    required this.onStairTopLevelChanged,
    required this.onConfirm,
    required this.onCancel,
    required this.onResetMode,
  });

  final RenderSceneInteractionMode interactionMode;
  final ProjectUnitSettings units;
  final RenderScenePoint? draftWallStart;
  final RenderScenePoint? draftWallEnd;
  final RenderScenePoint? wallArcStart;
  final RenderScenePoint? wallArcEnd;
  final RenderScenePoint? wallArcControl;
  final RenderScenePoint? draftSurfaceStart;
  final RenderScenePoint? draftSurfaceEnd;
  final int draftSurfacePointCount;
  final int draftSurfaceWallCount;
  final double draftSurfaceThicknessMeters;
  final double draftSurfaceHeightMeters;
  final double draftStairWidthMeters;
  final double draftStairLandingDepthMeters;
  final int stairLayoutKind;
  final bool stairRailingEnabled;
  final List<RenderSceneLevel> stairLevels;
  final int? stairBaseLevelId;
  final int? stairTopLevelId;
  final double draftFloorTopElevationMeters;
  final RenderSceneSurfaceDrawMode surfaceDrawMode;
  final bool surfaceControlsEnabled;
  final bool canSurfaceUndo;
  final bool canCloseSurfaceBoundary;
  final bool surfaceBoundaryClosed;
  final WallDrawMode wallDrawMode;
  final List<WallTypeDefinition> wallTypes;
  final int wallTypeId;
  final List<FloorTypeDefinition> floorTypes;
  final int floorAssemblyId;
  final List<FloorTypeDefinition> roofTypes;
  final int roofAssemblyId;
  final int roofType;
  final double roofSlopeDegrees;
  final double roofOverhangMeters;
  final RenderSceneObject? draftHostWall;
  final String openingKind;
  final double openingWidthMeters;
  final double openingHeightMeters;
  final double openingSillHeightMeters;
  final TrimExtendWallSelection? trimFirstWall;
  final TrimExtendWallSelection? trimSecondWall;
  final PlanSketchTrimResult? trimPreview;
  final bool canConfirm;
  final ValueChanged<OpeningPreset> onOpeningPresetChanged;
  final ValueChanged<double> onSurfaceThicknessChanged;
  final ValueChanged<double> onSurfaceHeightChanged;
  final ValueChanged<double> onFloorTopElevationChanged;
  final ValueChanged<RenderSceneSurfaceDrawMode> onSurfaceDrawModeChanged;
  final VoidCallback onSurfaceUndo;
  final VoidCallback onSurfaceToggleBoundaryClosed;
  final VoidCallback onSurfaceRepairJoins;
  final VoidCallback onSurfaceTrimExtend;
  final ValueChanged<WallDrawMode> onWallDrawModeChanged;
  final ValueChanged<int> onWallTypeChanged;
  final ValueChanged<int> onFloorAssemblyChanged;
  final ValueChanged<int> onRoofAssemblyChanged;
  final ValueChanged<int> onRoofTypeChanged;
  final ValueChanged<double> onRoofSlopeChanged;
  final ValueChanged<double> onRoofOverhangChanged;
  final ValueChanged<double> onStairWidthChanged;
  final ValueChanged<double> onStairLandingDepthChanged;
  final ValueChanged<int> onStairLayoutChanged;
  final ValueChanged<bool> onStairRailingChanged;
  final ValueChanged<int?> onStairBaseLevelChanged;
  final ValueChanged<int?> onStairTopLevelChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onResetMode;

  @override
  State<_DraftEditorCard> createState() => _DraftEditorCardState();
}

class _DraftEditorCardState extends State<_DraftEditorCard> {
  TextEditingController? _surfaceThicknessController;
  TextEditingController? _surfaceHeightController;
  TextEditingController? _floorTopController;
  TextEditingController? _stairWidthController;
  TextEditingController? _stairLandingController;
  TextEditingController? _roofSlopeController;
  TextEditingController? _roofOverhangController;

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void didUpdateWidget(covariant _DraftEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.units != widget.units) {
      _surfaceThicknessController?.text =
          _format(widget.draftSurfaceThicknessMeters);
      _surfaceHeightController?.text = _format(widget.draftSurfaceHeightMeters);
      _floorTopController?.text = _format(widget.draftFloorTopElevationMeters);
      _stairWidthController?.text = _format(widget.draftStairWidthMeters);
      _stairLandingController?.text =
          _format(widget.draftStairLandingDepthMeters);
      _roofSlopeController?.text = _angleFormat(widget.roofSlopeDegrees);
      _roofOverhangController?.text = _format(widget.roofOverhangMeters);
      return;
    }
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
    _syncController(
      _stairLandingController,
      widget.draftStairLandingDepthMeters,
      oldWidget.draftStairLandingDepthMeters,
    );
    _syncController(
      _roofSlopeController,
      widget.roofSlopeDegrees,
      oldWidget.roofSlopeDegrees,
      unitAware: false,
    );
    _syncController(
      _roofOverhangController,
      widget.roofOverhangMeters,
      oldWidget.roofOverhangMeters,
    );
  }

  @override
  void dispose() {
    _surfaceThicknessController?.dispose();
    _surfaceHeightController?.dispose();
    _floorTopController?.dispose();
    _stairWidthController?.dispose();
    _stairLandingController?.dispose();
    _roofSlopeController?.dispose();
    _roofOverhangController?.dispose();
    super.dispose();
  }

  void _syncController(
    TextEditingController? controller,
    double next,
    double previous, {
    bool unitAware = true,
  }) {
    if (controller == null) {
      return;
    }
    if ((next - previous).abs() < 1e-9) {
      return;
    }
    controller.text = unitAware ? _format(next) : _angleFormat(next);
  }

  void _ensureControllers() {
    _surfaceThicknessController ??= TextEditingController(
      text: _format(widget.draftSurfaceThicknessMeters),
    );
    _surfaceHeightController ??=
        TextEditingController(text: _format(widget.draftSurfaceHeightMeters));
    _floorTopController ??= TextEditingController(
        text: _format(widget.draftFloorTopElevationMeters));
    _stairWidthController ??=
        TextEditingController(text: _format(widget.draftStairWidthMeters));
    _stairLandingController ??= TextEditingController(
      text: _format(widget.draftStairLandingDepthMeters),
    );
    _roofSlopeController ??=
        TextEditingController(text: _angleFormat(widget.roofSlopeDegrees));
    _roofOverhangController ??= TextEditingController(
      text: _format(widget.roofOverhangMeters),
    );
  }

  String _format(double value) {
    return widget.units.formatLength(value, withUnit: false);
  }

  double? _parse(String text) {
    final displayValue = double.tryParse(text.trim());
    return displayValue == null ? null : widget.units.toMeters(displayValue);
  }

  String _angleFormat(double value) => value.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    _ensureControllers();
    final mode = widget.interactionMode;
    final wall = widget.draftHostWall;

    return _InfoCard(
      title: mode.authoringLabel,
      icon: _toolIcon(mode),
      children: <Widget>[
        if (mode == RenderSceneInteractionMode.select)
          const Text('Select mode: tap objects to inspect them.')
        else if (mode == RenderSceneInteractionMode.addLevel)
          _LevelDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
            units: widget.units,
          )
        else if (mode == RenderSceneInteractionMode.moveLevel)
          _LevelDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
            units: widget.units,
          )
        else if (mode == RenderSceneInteractionMode.addWall)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _wallDrawModeButtons(),
              _wallTypeDrop(),
              _WallDraftSummary(
                start: widget.draftWallStart,
                end: widget.draftWallEnd,
                units: widget.units,
                drawMode: widget.wallDrawMode,
                arcStart: widget.wallArcStart,
                arcEnd: widget.wallArcEnd,
                arcControl: widget.wallArcControl,
              ),
            ],
          )
        else if (mode == RenderSceneInteractionMode.addStair)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                  'Choose a layout, then tap each flight turn. Rise comes from Base/Top Level.'),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const <ButtonSegment<int>>[
                  ButtonSegment<int>(value: 0, label: Text('Straight')),
                  ButtonSegment<int>(value: 1, label: Text('L')),
                  ButtonSegment<int>(value: 2, label: Text('U')),
                ],
                selected: <int>{widget.stairLayoutKind},
                onSelectionChanged: (values) {
                  if (values.isNotEmpty) {
                    widget.onStairLayoutChanged(values.first);
                  }
                },
              ),
              const SizedBox(height: 8),
              _stairLevelDrop(
                label: 'Base level',
                value: widget.stairBaseLevelId,
                onChanged: widget.onStairBaseLevelChanged,
              ),
              _stairLevelDrop(
                label: 'Top level',
                value: widget.stairTopLevelId,
                onChanged: widget.onStairTopLevelChanged,
              ),
              _WallDraftSummary(
                start: widget.draftWallStart,
                end: widget.draftWallEnd,
                units: widget.units,
              ),
              const SizedBox(height: 8),
              _NumericField(
                label: 'Width (${widget.units.lengthSymbol})',
                controller: _stairWidthController!,
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) widget.onStairWidthChanged(parsed);
                },
              ),
              if (widget.stairLayoutKind != 0) ...<Widget>[
                const SizedBox(height: 6),
                _NumericField(
                  label: 'Landing (${widget.units.lengthSymbol})',
                  controller: _stairLandingController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) {
                      widget.onStairLandingDepthChanged(parsed);
                    }
                  },
                ),
                SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Railing'),
                  value: widget.stairRailingEnabled,
                  onChanged: widget.onStairRailingChanged,
                ),
              ],
            ],
          )
        else if (mode == RenderSceneInteractionMode.moveWall)
          _WallDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
            units: widget.units,
          )
        else if (mode == RenderSceneInteractionMode.trimExtend)
          _TrimExtendDraftSummary(
            first: widget.trimFirstWall,
            second: widget.trimSecondWall,
            preview: widget.trimPreview,
            units: widget.units,
          )
        else if (mode == RenderSceneInteractionMode.addFloor ||
            mode == RenderSceneInteractionMode.addCeiling ||
            mode == RenderSceneInteractionMode.addRoof)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SurfaceDraftSummary(
                mode: mode,
                units: widget.units,
                start: widget.draftSurfaceStart,
                end: widget.draftSurfaceEnd,
                pointCount: widget.draftSurfacePointCount,
                wallCount: widget.draftSurfaceWallCount,
                drawMode: widget.surfaceDrawMode,
              ),
              const SizedBox(height: 8),
              _SurfaceDrawingInspectorControls(
                mode: mode,
                drawMode: widget.surfaceDrawMode,
                enabled: widget.surfaceControlsEnabled,
                canUndo: widget.canSurfaceUndo,
                canCloseBoundary: widget.canCloseSurfaceBoundary,
                boundaryClosed: widget.surfaceBoundaryClosed,
                onDrawModeChanged: widget.onSurfaceDrawModeChanged,
                onUndo: widget.onSurfaceUndo,
                onToggleBoundaryClosed: widget.onSurfaceToggleBoundaryClosed,
                onRepairJoins: widget.onSurfaceRepairJoins,
                onTrimExtend: widget.onSurfaceTrimExtend,
              ),
              const SizedBox(height: 8),
              _NumericField(
                label: 'Thickness (${widget.units.lengthSymbol})',
                controller: _surfaceThicknessController!,
                onChanged: (value) {
                  final parsed = _parse(value);
                  if (parsed != null) {
                    widget.onSurfaceThicknessChanged(parsed);
                  }
                },
              ),
              if (mode == RenderSceneInteractionMode.addFloor)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _floorTypeDrop(),
                    _NumericField(
                      label: 'Top elevation (${widget.units.lengthSymbol})',
                      controller: _floorTopController!,
                      onChanged: (value) {
                        final parsed = _parse(value);
                        if (parsed != null) {
                          widget.onFloorTopElevationChanged(parsed);
                        }
                      },
                    ),
                  ],
                )
              else if (mode == RenderSceneInteractionMode.addCeiling)
                _NumericField(
                  label: 'Height offset (${widget.units.lengthSymbol})',
                  controller: _surfaceHeightController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) {
                      widget.onSurfaceHeightChanged(parsed);
                    }
                  },
                )
              else ...<Widget>[
                _roofAssemblyDrop(),
                _roofTypeDrop(),
                if (widget.roofType != 0)
                  _NumericField(
                    label: 'Slope (degrees)',
                    controller: _roofSlopeController!,
                    onChanged: (value) {
                      final parsed = double.tryParse(value.trim());
                      if (parsed != null) widget.onRoofSlopeChanged(parsed);
                    },
                  ),
                _NumericField(
                  label: 'Overhang (${widget.units.lengthSymbol})',
                  controller: _roofOverhangController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) widget.onRoofOverhangChanged(parsed);
                  },
                ),
              ],
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
              _OpeningPresetField(
                kind: widget.openingKind,
                units: widget.units,
                widthMeters: widget.openingWidthMeters,
                heightMeters: widget.openingHeightMeters,
                sillHeightMeters: widget.openingSillHeightMeters,
                onChanged: widget.onOpeningPresetChanged,
              ),
              const SizedBox(height: 6),
              const _InfoRow(
                label: 'Placement',
                value: 'Tap or drag on the host wall',
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
                      : mode == RenderSceneInteractionMode.addFloor ||
                              mode == RenderSceneInteractionMode.addCeiling ||
                              mode == RenderSceneInteractionMode.addRoof
                          ? 'Finish'
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
          child: const Text('Exit tool'),
        ),
      ],
    );
  }

  IconData _toolIcon(RenderSceneInteractionMode mode) => switch (mode) {
        RenderSceneInteractionMode.addWall ||
        RenderSceneInteractionMode.moveWall ||
        RenderSceneInteractionMode.trimExtend =>
          Icons.view_week_outlined,
        RenderSceneInteractionMode.addFloor => Icons.layers_outlined,
        RenderSceneInteractionMode.addCeiling => Icons.layers_clear_outlined,
        RenderSceneInteractionMode.addRoof => Icons.roofing_outlined,
        RenderSceneInteractionMode.addDoor ||
        RenderSceneInteractionMode.addWindow ||
        RenderSceneInteractionMode.moveOpening =>
          Icons.open_in_new_outlined,
        RenderSceneInteractionMode.addStair => Icons.stairs_outlined,
        RenderSceneInteractionMode.addLevel ||
        RenderSceneInteractionMode.moveLevel =>
          Icons.straighten_outlined,
        RenderSceneInteractionMode.select => Icons.ads_click_outlined,
      };

  Widget _roofAssemblyDrop() {
    if (widget.roofTypes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: _InfoRow(label: 'Roof material', value: 'Default roof'),
      );
    }
    final hasCurrent = widget.roofTypes.any(
      (roofType) => roofType.id == widget.roofAssemblyId,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: hasCurrent ? widget.roofAssemblyId : null,
        decoration: _toolDropdownDecoration('Roof material'),
        hint: const Text('Select roof material'),
        items: <DropdownMenuItem<int>>[
          for (final roofType in widget.roofTypes)
            DropdownMenuItem<int>(
              value: roofType.id,
              child: Text(
                '${roofType.name} · ${widget.units.formatLength(roofType.totalThicknessMeters)}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) widget.onRoofAssemblyChanged(value);
        },
      ),
    );
  }

  Widget _roofTypeDrop() => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: DropdownButtonFormField<int>(
          isExpanded: true,
          initialValue: widget.roofType,
          decoration: _toolDropdownDecoration('Roof type'),
          items: const <DropdownMenuItem<int>>[
            DropdownMenuItem(value: 0, child: Text('Flat')),
            DropdownMenuItem(value: 1, child: Text('Simple gable')),
            DropdownMenuItem(value: 2, child: Text('Auto footprint (L/U)')),
          ],
          onChanged: (value) {
            if (value != null) widget.onRoofTypeChanged(value);
          },
        ),
      );

  InputDecoration _toolDropdownDecoration(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );

  Widget _wallTypeDrop() {
    if (widget.wallTypes.isEmpty) return const SizedBox.shrink();
    final hasCurrent = widget.wallTypes.any(
      (wallType) => wallType.id == widget.wallTypeId,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: hasCurrent ? widget.wallTypeId : null,
        decoration: _toolDropdownDecoration('Wall type'),
        hint: const Text('Select wall type'),
        items: <DropdownMenuItem<int>>[
          for (final wallType in widget.wallTypes)
            DropdownMenuItem<int>(
              value: wallType.id,
              child: Text(
                '${wallType.name} · ${wallType.categoryLabel}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) widget.onWallTypeChanged(value);
        },
      ),
    );
  }

  IconData _wallDrawModeIcon(WallDrawMode mode) => switch (mode) {
        WallDrawMode.straight => Icons.straighten,
        WallDrawMode.rectangle => Icons.crop_square,
        WallDrawMode.arc => Icons.rounded_corner,
      };

  Widget _wallDrawModeButtons() {
    final theme = Theme.of(context);
    const modes = WallDrawMode.values;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Wall draw mode', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              for (var index = 0; index < modes.length; index++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: index == modes.length - 1 ? 0 : 6,
                    ),
                    child: Tooltip(
                      message: modes[index].label,
                      child: Semantics(
                        container: true,
                        button: true,
                        selected: widget.wallDrawMode == modes[index],
                        label: 'Wall draw mode ${modes[index].label}',
                        child: InkWell(
                          onTap: () =>
                              widget.onWallDrawModeChanged(modes[index]),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              color: widget.wallDrawMode == modes[index]
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surface,
                              border: Border.all(
                                color: widget.wallDrawMode == modes[index]
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _wallDrawModeIcon(modes[index]),
                              color: widget.wallDrawMode == modes[index]
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _floorTypeDrop() {
    if (widget.floorTypes.isEmpty) return const SizedBox.shrink();
    final hasCurrent = widget.floorTypes.any(
      (floorType) => floorType.id == widget.floorAssemblyId,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: hasCurrent ? widget.floorAssemblyId : null,
        decoration: _toolDropdownDecoration('Floor type'),
        hint: const Text('Select floor type'),
        items: <DropdownMenuItem<int>>[
          for (final floorType in widget.floorTypes)
            DropdownMenuItem<int>(
              value: floorType.id,
              child: Text(
                '${floorType.name} · ${floorType.surfaceLabel}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) widget.onFloorAssemblyChanged(value);
        },
      ),
    );
  }

  Widget _stairLevelDrop({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) {
    final hasCurrent = value != null &&
        widget.stairLevels.any((level) => level.levelId == value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: hasCurrent ? value : null,
        decoration: _toolDropdownDecoration(label),
        hint: Text('Select $label'),
        items: <DropdownMenuItem<int>>[
          for (final level in widget.stairLevels)
            DropdownMenuItem<int>(
              value: level.levelId,
              child: Text(
                '${level.name} (${widget.units.formatLength(level.elevationMeters)})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: widget.stairLevels.isEmpty ? null : onChanged,
      ),
    );
  }
}

class _SurfaceDrawingInspectorControls extends StatelessWidget {
  const _SurfaceDrawingInspectorControls({
    required this.mode,
    required this.drawMode,
    required this.enabled,
    required this.canUndo,
    required this.canCloseBoundary,
    required this.boundaryClosed,
    required this.onDrawModeChanged,
    required this.onUndo,
    required this.onToggleBoundaryClosed,
    required this.onRepairJoins,
    required this.onTrimExtend,
  });

  final RenderSceneInteractionMode mode;
  final RenderSceneSurfaceDrawMode drawMode;
  final bool enabled;
  final bool canUndo;
  final bool canCloseBoundary;
  final bool boundaryClosed;
  final ValueChanged<RenderSceneSurfaceDrawMode> onDrawModeChanged;
  final VoidCallback onUndo;
  final VoidCallback onToggleBoundaryClosed;
  final VoidCallback onRepairJoins;
  final VoidCallback onTrimExtend;

  bool get _supportsAutoRoom =>
      mode == RenderSceneInteractionMode.addFloor ||
      mode == RenderSceneInteractionMode.addCeiling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final modes = <RenderSceneSurfaceDrawMode>[
      RenderSceneSurfaceDrawMode.pickWalls,
      RenderSceneSurfaceDrawMode.polyline,
      RenderSceneSurfaceDrawMode.rectangle,
      if (_supportsAutoRoom) RenderSceneSurfaceDrawMode.autoRoom,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Boundary method', style: theme.textTheme.labelMedium),
        const SizedBox(height: 5),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final option in modes)
              Tooltip(
                message: _surfaceDrawModeHint(option),
                child: ChoiceChip(
                  avatar: Icon(_surfaceDrawModeIcon(option), size: 16),
                  label: Text(_surfaceDrawModeLabel(option)),
                  selected: drawMode == option,
                  onSelected: enabled ? (_) => onDrawModeChanged(option) : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            Tooltip(
              message: drawMode == RenderSceneSurfaceDrawMode.polyline &&
                      boundaryClosed
                  ? 'Reopen the boundary before removing a point'
                  : 'Remove the last point or picked wall',
              child: IconButton.filledTonal(
                onPressed: enabled && canUndo ? onUndo : null,
                icon: const Icon(Icons.undo, size: 19),
              ),
            ),
            if (drawMode == RenderSceneSurfaceDrawMode.polyline)
              OutlinedButton.icon(
                onPressed: enabled && (boundaryClosed || canCloseBoundary)
                    ? onToggleBoundaryClosed
                    : null,
                icon: Icon(
                  boundaryClosed
                      ? Icons.lock_open_outlined
                      : Icons.link_outlined,
                  size: 18,
                ),
                label: Text(boundaryClosed ? 'Reopen' : 'Close contour'),
              ),
            PopupMenuButton<_SurfaceDrawingMoreAction>(
              tooltip: 'More surface actions',
              enabled: enabled,
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) {
                switch (action) {
                  case _SurfaceDrawingMoreAction.repairJoins:
                    onRepairJoins();
                  case _SurfaceDrawingMoreAction.trimExtend:
                    onTrimExtend();
                }
              },
              itemBuilder: (context) =>
                  const <PopupMenuEntry<_SurfaceDrawingMoreAction>>[
                PopupMenuItem<_SurfaceDrawingMoreAction>(
                  value: _SurfaceDrawingMoreAction.repairJoins,
                  child: Text('Repair joins'),
                ),
                PopupMenuItem<_SurfaceDrawingMoreAction>(
                  value: _SurfaceDrawingMoreAction.trimExtend,
                  child: Text('Trim / Extend'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

enum _SurfaceDrawingMoreAction { repairJoins, trimExtend }

IconData _surfaceDrawModeIcon(RenderSceneSurfaceDrawMode mode) =>
    switch (mode) {
      RenderSceneSurfaceDrawMode.polyline => Icons.polyline_outlined,
      RenderSceneSurfaceDrawMode.rectangle => Icons.crop_square,
      RenderSceneSurfaceDrawMode.pickWalls => Icons.ads_click_outlined,
      RenderSceneSurfaceDrawMode.autoRoom => Icons.meeting_room_outlined,
    };

String _surfaceDrawModeLabel(RenderSceneSurfaceDrawMode mode) => switch (mode) {
      RenderSceneSurfaceDrawMode.polyline => 'Boundary',
      RenderSceneSurfaceDrawMode.rectangle => 'Rectangle',
      RenderSceneSurfaceDrawMode.pickWalls => 'Pick Walls',
      RenderSceneSurfaceDrawMode.autoRoom => 'Auto Room',
    };

String _surfaceDrawModeHint(RenderSceneSurfaceDrawMode mode) => switch (mode) {
      RenderSceneSurfaceDrawMode.polyline =>
        'Draw straight boundary segments, then close the loop',
      RenderSceneSurfaceDrawMode.rectangle => 'Set two opposite corners',
      RenderSceneSurfaceDrawMode.pickWalls =>
        'Select enclosing walls to derive the footprint',
      RenderSceneSurfaceDrawMode.autoRoom =>
        'Select a room to create the system from its boundary',
    };

class _OpeningPresetField extends StatelessWidget {
  const _OpeningPresetField({
    required this.kind,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
    required this.onChanged,
    required this.units,
  });

  final String kind;
  final double widthMeters;
  final double heightMeters;
  final double sillHeightMeters;
  final ValueChanged<OpeningPreset> onChanged;
  final ProjectUnitSettings units;

  @override
  Widget build(BuildContext context) {
    final presets = openingPresetsForKind(kind);
    final selected = openingPresetForValues(
      kind: kind,
      widthMeters: widthMeters,
      heightMeters: heightMeters,
      sillHeightMeters: sillHeightMeters,
    );
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: selected.id,
      decoration: InputDecoration(
        labelText: '${kind == 'window' ? 'Window' : 'Door'} type',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: <DropdownMenuItem<String>>[
        for (final preset in presets)
          DropdownMenuItem<String>(
            value: preset.id,
            child: Text(
              preset.labelFor(units),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (id) {
        if (id == null) return;
        onChanged(presets.firstWhere((preset) => preset.id == id));
      },
    );
  }
}

class _WallDraftSummary extends StatelessWidget {
  const _WallDraftSummary({
    required this.start,
    required this.end,
    required this.units,
    this.drawMode = WallDrawMode.straight,
    this.arcStart,
    this.arcEnd,
    this.arcControl,
  });

  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final ProjectUnitSettings units;
  final WallDrawMode drawMode;
  final RenderScenePoint? arcStart;
  final RenderScenePoint? arcEnd;
  final RenderScenePoint? arcControl;

  @override
  Widget build(BuildContext context) {
    if (drawMode == WallDrawMode.arc) {
      return _buildArcSummary();
    }
    if (start == null || end == null) {
      return Text(
        drawMode == WallDrawMode.rectangle
            ? 'Tap once to set the first rectangle corner.'
            : 'Tap once to set the wall start point.',
      );
    }

    final width = (end!.x - start!.x).abs();
    final depth = (end!.y - start!.y).abs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InfoRow(
          label: 'Start',
          value: '(${units.formatLength(start!.x, withUnit: false)}, '
              '${units.formatLength(start!.y, withUnit: false)})',
        ),
        _InfoRow(
          label: 'End',
          value: '(${units.formatLength(end!.x, withUnit: false)}, '
              '${units.formatLength(end!.y, withUnit: false)})',
        ),
        if (drawMode == WallDrawMode.rectangle) ...<Widget>[
          _InfoRow(label: 'Width', value: units.formatLength(width)),
          _InfoRow(label: 'Depth', value: units.formatLength(depth)),
        ] else
          _InfoRow(
            label: 'Length',
            value: units.formatLength(start!.distanceTo(end!)),
          ),
      ],
    );
  }

  Widget _buildArcSummary() {
    final firstPoint = arcStart;
    final secondPoint = arcEnd;
    final bendPoint = arcControl;
    if (firstPoint == null) {
      return const Text('Tap the first point of the curved wall.');
    }
    if (secondPoint == null) {
      return _InfoRow(
        label: 'First point',
        value: '(${units.formatLength(firstPoint.x, withUnit: false)}, '
            '${units.formatLength(firstPoint.y, withUnit: false)}) · '
            'tap second point',
      );
    }
    if (bendPoint == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _InfoRow(
            label: 'Chord',
            value: units.formatLength(firstPoint.distanceTo(secondPoint)),
          ),
          const Text('Tap/drag the radius or bend point.'),
        ],
      );
    }
    final geometry = WallAuthoringGeometry.arcFromThreePoints(
      first: firstPoint,
      second: secondPoint,
      bend: bendPoint,
    );
    if (geometry == null) {
      return const Text('Arc needs a larger radius and a visible bend.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InfoRow(
          label: 'Radius',
          value: units.formatLength(geometry.radiusMeters),
        ),
        _InfoRow(
          label: 'Angle',
          value: '${geometry.sweepDegrees.abs().toStringAsFixed(1)}°',
        ),
        const _InfoRow(
          label: 'Model',
          value: '1 curved wall',
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
    required this.units,
  });

  final TrimExtendWallSelection? first;
  final TrimExtendWallSelection? second;
  final PlanSketchTrimResult? preview;
  final ProjectUnitSettings units;

  String _endpointLabel(PlanSketchEndpoint endpoint) =>
      endpoint == PlanSketchEndpoint.start ? 'Start' : 'End';

  @override
  Widget build(BuildContext context) {
    if (first == null) {
      return const Text(
        'Tap the first wall near the endpoint you want to edit.',
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
              'Now tap the second wall near the endpoint to trim or extend.',
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
                  '(${units.formatLength(preview!.intersection.x, withUnit: false)}, '
                  '${units.formatLength(preview!.intersection.y, withUnit: false)})',
            )
          else
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'These endpoints would create a parallel or very short result. Choose another endpoint.',
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
    required this.units,
  });

  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final ProjectUnitSettings units;

  @override
  Widget build(BuildContext context) {
    if (start == null || end == null) {
      return const Text(
        'In elevation view, tap twice: the first tap sets height and the second sets the level line length.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _InfoRow(
          label: 'Elevation',
          value: units.formatLength(end!.z),
        ),
        _InfoRow(
          label: 'Line',
          value: '(${units.formatLength(start!.x, withUnit: false)}, '
              '${units.formatLength(start!.z, withUnit: false)}) → '
              '(${units.formatLength(end!.x, withUnit: false)}, '
              '${units.formatLength(end!.z, withUnit: false)})',
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
    required this.units,
  });

  final RenderSceneInteractionMode mode;
  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final int pointCount;
  final int wallCount;
  final RenderSceneSurfaceDrawMode drawMode;
  final ProjectUnitSettings units;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = switch (drawMode) {
      RenderSceneSurfaceDrawMode.pickWalls => wallCount == 0
          ? 'No boundary walls selected'
          : wallCount == 1
              ? '1 boundary wall selected'
              : '$wallCount boundary walls selected',
      RenderSceneSurfaceDrawMode.polyline => '$pointCount boundary points',
      RenderSceneSurfaceDrawMode.autoRoom =>
        mode == RenderSceneInteractionMode.addRoof
            ? 'Auto Room unavailable for roofs'
            : 'Room boundary detection',
      RenderSceneSurfaceDrawMode.rectangle => start == null || end == null
          ? 'Rectangle not started'
          : 'Rectangle ready',
    };
    final hasBounds = start != null && end != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          status,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (hasBounds) ...<Widget>[
          const SizedBox(height: 4),
          _InfoRow(
            label: 'Bounds',
            value:
                '${units.formatLength((end!.x - start!.x).abs(), withUnit: false)} × '
                '${units.formatLength((end!.y - start!.y).abs())}',
          ),
        ],
      ],
    );
  }
}
