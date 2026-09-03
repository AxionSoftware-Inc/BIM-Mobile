// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

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
    final baseLevelId =
        _objectMetadataInt(wall, 'base_level_id') ?? wall.levelId;
    final topLevelId = _objectMetadataInt(wall, 'top_level_id');
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
    required this.draftWallStart,
    required this.draftWallEnd,
    required this.draftSurfaceStart,
    required this.draftSurfaceEnd,
    required this.draftSurfacePointCount,
    required this.draftSurfaceWallCount,
    required this.draftSurfaceThicknessMeters,
    required this.draftSurfaceHeightMeters,
    required this.draftStairWidthMeters,
    required this.draftFloorTopElevationMeters,
    required this.surfaceDrawMode,
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
    required this.onStairWidthChanged,
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
  final int draftSurfacePointCount;
  final int draftSurfaceWallCount;
  final double draftSurfaceThicknessMeters;
  final double draftSurfaceHeightMeters;
  final double draftStairWidthMeters;
  final double draftFloorTopElevationMeters;
  final RenderSceneSurfaceDrawMode surfaceDrawMode;
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
  final ValueChanged<double> onStairWidthChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onClearSelection;
  final VoidCallback onResetMode;

  @override
  State<_DraftEditorCard> createState() => _DraftEditorCardState();
}

class _DraftEditorCardState extends State<_DraftEditorCard> {
  TextEditingController? _surfaceThicknessController;
  TextEditingController? _surfaceHeightController;
  TextEditingController? _floorTopController;
  TextEditingController? _stairWidthController;

  @override
  void initState() {
    super.initState();
    _ensureControllers();
  }

  @override
  void didUpdateWidget(covariant _DraftEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
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
  }

  @override
  void dispose() {
    _surfaceThicknessController?.dispose();
    _surfaceHeightController?.dispose();
    _floorTopController?.dispose();
    _stairWidthController?.dispose();
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
    _surfaceThicknessController ??= TextEditingController(
      text: _format(widget.draftSurfaceThicknessMeters),
    );
    _surfaceHeightController ??=
        TextEditingController(text: _format(widget.draftSurfaceHeightMeters));
    _floorTopController ??= TextEditingController(
        text: _format(widget.draftFloorTopElevationMeters));
    _stairWidthController ??=
        TextEditingController(text: _format(widget.draftStairWidthMeters));
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
        _InfoRow(label: 'Mode', value: mode.authoringLabel),
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
          )
        else if (mode == RenderSceneInteractionMode.moveLevel)
          _LevelDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.addWall)
          _WallDraftSummary(
            start: widget.draftWallStart,
            end: widget.draftWallEnd,
          )
        else if (mode == RenderSceneInteractionMode.addStair)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                  'Draw a straight stair run with two points. Rise comes from Base/Top Level.'),
              const SizedBox(height: 8),
              _WallDraftSummary(
                start: widget.draftWallStart,
                end: widget.draftWallEnd,
              ),
              const SizedBox(height: 8),
              _NumericField(
                label: 'Width (m)',
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
          )
        else if (mode == RenderSceneInteractionMode.trimExtend)
          _TrimExtendDraftSummary(
            first: widget.trimFirstWall,
            second: widget.trimSecondWall,
            preview: widget.trimPreview,
          )
        else if (mode == RenderSceneInteractionMode.addFloor ||
            mode == RenderSceneInteractionMode.addCeiling ||
            mode == RenderSceneInteractionMode.addRoof)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _SurfaceDraftSummary(
                mode: mode,
                start: widget.draftSurfaceStart,
                end: widget.draftSurfaceEnd,
                pointCount: widget.draftSurfacePointCount,
                wallCount: widget.draftSurfaceWallCount,
                drawMode: widget.surfaceDrawMode,
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
              else if (mode == RenderSceneInteractionMode.addCeiling)
                _NumericField(
                  label: 'Height offset (m)',
                  controller: _surfaceHeightController!,
                  onChanged: (value) {
                    final parsed = _parse(value);
                    if (parsed != null) {
                      widget.onSurfaceHeightChanged(parsed);
                    }
                  },
                )
              else
                const Text(
                  'Roof uses the same boundary sketch. Shape, slope and overhang stay editable in Properties.',
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
              _OpeningPresetField(
                kind: widget.openingKind,
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

class _OpeningPresetField extends StatelessWidget {
  const _OpeningPresetField({
    required this.kind,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
    required this.onChanged,
  });

  final String kind;
  final double widthMeters;
  final double heightMeters;
  final double sillHeightMeters;
  final ValueChanged<OpeningPreset> onChanged;

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
            child: Text(preset.label, overflow: TextOverflow.ellipsis),
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

class _TrimExtendDraftSummary extends StatelessWidget {
  const _TrimExtendDraftSummary({
    required this.first,
    required this.second,
    required this.preview,
  });

  final TrimExtendWallSelection? first;
  final TrimExtendWallSelection? second;
  final PlanSketchTrimResult? preview;

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
                  '(${preview!.intersection.x.toStringAsFixed(2)}, ${preview!.intersection.y.toStringAsFixed(2)})',
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
  });

  final RenderScenePoint? start;
  final RenderScenePoint? end;

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
          value: '${end!.z.toStringAsFixed(2)} m',
        ),
        _InfoRow(
          label: 'Line',
          value:
              '(${start!.x.toStringAsFixed(2)}, ${start!.z.toStringAsFixed(2)}) → (${end!.x.toStringAsFixed(2)}, ${end!.z.toStringAsFixed(2)})',
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
  });

  final RenderSceneInteractionMode mode;
  final RenderScenePoint? start;
  final RenderScenePoint? end;
  final int pointCount;
  final int wallCount;
  final RenderSceneSurfaceDrawMode drawMode;

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
                  '${(end!.x - start!.x).abs().toStringAsFixed(2)} × ${(end!.y - start!.y).abs().toStringAsFixed(2)} m',
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
