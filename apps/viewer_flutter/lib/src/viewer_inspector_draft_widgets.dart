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
    required this.draftSurfaceStart,
    required this.draftSurfaceEnd,
    required this.draftSurfacePointCount,
    required this.draftSurfaceWallCount,
    required this.draftSurfaceThicknessMeters,
    required this.draftSurfaceHeightMeters,
    required this.draftStairWidthMeters,
    required this.stairLevels,
    required this.stairBaseLevelId,
    required this.stairTopLevelId,
    required this.draftFloorTopElevationMeters,
    required this.surfaceDrawMode,
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
    required this.editStatusMessage,
    required this.snapEnabled,
    required this.canConfirm,
    required this.onSnapToggled,
    required this.onOpeningPresetChanged,
    required this.onSurfaceThicknessChanged,
    required this.onSurfaceHeightChanged,
    required this.onFloorTopElevationChanged,
    required this.onWallTypeChanged,
    required this.onFloorAssemblyChanged,
    required this.onRoofAssemblyChanged,
    required this.onRoofTypeChanged,
    required this.onRoofSlopeChanged,
    required this.onRoofOverhangChanged,
    required this.onStairWidthChanged,
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
  final RenderScenePoint? draftSurfaceStart;
  final RenderScenePoint? draftSurfaceEnd;
  final int draftSurfacePointCount;
  final int draftSurfaceWallCount;
  final double draftSurfaceThicknessMeters;
  final double draftSurfaceHeightMeters;
  final double draftStairWidthMeters;
  final List<RenderSceneLevel> stairLevels;
  final int? stairBaseLevelId;
  final int? stairTopLevelId;
  final double draftFloorTopElevationMeters;
  final RenderSceneSurfaceDrawMode surfaceDrawMode;
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
  final String? editStatusMessage;
  final bool snapEnabled;
  final bool canConfirm;
  final ValueChanged<bool> onSnapToggled;
  final ValueChanged<OpeningPreset> onOpeningPresetChanged;
  final ValueChanged<double> onSurfaceThicknessChanged;
  final ValueChanged<double> onSurfaceHeightChanged;
  final ValueChanged<double> onFloorTopElevationChanged;
  final ValueChanged<int> onWallTypeChanged;
  final ValueChanged<int> onFloorAssemblyChanged;
  final ValueChanged<int> onRoofAssemblyChanged;
  final ValueChanged<int> onRoofTypeChanged;
  final ValueChanged<double> onRoofSlopeChanged;
  final ValueChanged<double> onRoofOverhangChanged;
  final ValueChanged<double> onStairWidthChanged;
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
    final theme = Theme.of(context);
    final mode = widget.interactionMode;
    final wall = widget.draftHostWall;

    return _InfoCard(
      title: mode.authoringLabel,
      icon: _toolIcon(mode),
      children: <Widget>[
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
              _wallTypeDrop(),
              _WallDraftSummary(
                start: widget.draftWallStart,
                end: widget.draftWallEnd,
                units: widget.units,
              ),
            ],
          )
        else if (mode == RenderSceneInteractionMode.addStair)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                  'Draw a straight stair run with two points. Rise comes from Base/Top Level.'),
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
  });

  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final ProjectUnitSettings units;

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
          value: '(${units.formatLength(start!.x, withUnit: false)}, '
              '${units.formatLength(start!.y, withUnit: false)})',
        ),
        _InfoRow(
          label: 'End',
          value: '(${units.formatLength(end!.x, withUnit: false)}, '
              '${units.formatLength(end!.y, withUnit: false)})',
        ),
        _InfoRow(
          label: 'Length',
          value: units.formatLength(length),
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
            '$wallCount wall(s) selected. Confirm to create $label from the wall boundary.',
          ),
          if (start != null && end != null) ...<Widget>[
            const SizedBox(height: 8),
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

    if (drawMode == RenderSceneSurfaceDrawMode.polyline) {
      return Text(
        pointCount < 3
            ? '$pointCount point(s) added. Add another point.'
            : 'Polyline boundary ready. Confirm to create $label.',
      );
    }

    if (drawMode == RenderSceneSurfaceDrawMode.autoRoom) {
      return Text(
        mode == RenderSceneInteractionMode.addRoof
            ? 'Auto Room is not available for roofs yet. Use Rectangle, Polyline, or Pick Walls.'
            : 'Tap inside a room to create $label.',
      );
    }

    if (start == null || end == null) {
      return Text(
        'Draw in an empty area or select walls. This kernel creates $label.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Rectangle draft ready. Confirm to create $label.'),
        const SizedBox(height: 8),
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
        _InfoRow(
          label: 'Size',
          value:
              '${units.formatLength((end!.x - start!.x).abs(), withUnit: false)} × '
              '${units.formatLength((end!.y - start!.y).abs())}',
        ),
      ],
    );
  }
}
