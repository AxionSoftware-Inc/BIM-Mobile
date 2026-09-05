part of '../../property_editor.dart';

class _OpeningPropertiesSection extends StatefulWidget {
  const _OpeningPropertiesSection(
      {required this.object,
      required this.scene,
      required this.levels,
      required this.units,
      required this.commands,
      required this.onApplied});
  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;
  @override
  State<_OpeningPropertiesSection> createState() =>
      _OpeningPropertiesSectionState();
}

class _OpeningPropertiesSectionState extends State<_OpeningPropertiesSection> {
  late OpeningPreset _preset;
  late int _levelId;
  bool _locked = true;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _loadFromObject(widget.object);
  }

  @override
  void didUpdateWidget(covariant _OpeningPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId != widget.object.elementId ||
        oldWidget.object.revision != widget.object.revision) {
      _loadFromObject(widget.object);
    }
  }

  void _loadFromObject(RenderSceneObject object) {
    final parameters = OpeningElementParameters.fromObject(object);
    _preset = openingPresetForValues(
      kind: object.kindKey,
      widthMeters: parameters.widthMeters ?? 0.9,
      heightMeters:
          parameters.heightMeters ?? (object.kindKey == 'window' ? 1.2 : 2.1),
      sillHeightMeters: parameters.sillHeightMeters ??
          (object.kindKey == 'window' ? 0.9 : 0.0),
    );
    _levelId = parameters.levelId ??
        (widget.levels.isNotEmpty ? widget.levels.first.levelId : 0);
    _locked = parameters.levelLocked;
  }

  Future<bool> _runSave({
    required Future<RenderSceneLoadResult> Function() operation,
    required VoidCallback restore,
  }) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final result = await operation();
      if (result.scene == null) {
        if (mounted) restore();
        return false;
      }
      await widget.onApplied(result, '${_label(widget.object)} updated.');
      return true;
    } catch (_) {
      if (mounted) restore();
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePreset(
    OpeningPreset previous,
    OpeningPreset next,
  ) async {
    final parameters = OpeningElementParameters.fromObject(widget.object);
    final offset = parameters.offsetMeters;
    final id = widget.object.elementId;
    if (offset == null ||
        !offset.isFinite ||
        next.widthMeters <= 0 ||
        next.heightMeters <= 0 ||
        id == null) {
      if (mounted) setState(() => _preset = previous);
      return;
    }
    await _runSave(
      operation: () => widget.commands.updateOpening(
          object: widget.object,
          offsetMeters: offset,
          widthMeters: next.widthMeters,
          heightMeters: next.heightMeters,
          sillHeightMeters: next.sillHeightMeters),
      restore: () {
        setState(() => _preset = previous);
      },
    );
  }

  Future<void> _saveLevel(int previousLevelId, int nextLevelId) async {
    final parameters = OpeningElementParameters.fromObject(widget.object);
    final id = widget.object.elementId;
    if (id == null) return;
    await _runSave(
      operation: () => widget.commands.setOpeningLevelConstraint(
        openingId: id,
        levelId: nextLevelId,
        levelOffsetMeters: parameters.levelOffsetMeters,
      ),
      restore: () {
        setState(() => _levelId = previousLevelId);
      },
    );
  }

  Future<void> _saveLock(bool previousLocked, bool nextLocked) async {
    final id = widget.object.elementId;
    if (id == null) return;
    await _runSave(
      operation: () => widget.commands.setOpeningLevelLock(
        openingId: id,
        locked: nextLocked,
      ),
      restore: () {
        setState(() => _locked = previousLocked);
      },
    );
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
          title: _label(widget.object),
          icon: _icon(widget.object.kindKey),
          children: <Widget>[
            if (_FamilyInstanceStateData.fromObject(widget.object) != null)
              _FamilyPropertiesSection(
                object: widget.object,
                scene: widget.scene,
                levels: widget.levels,
                units: widget.units,
                commands: widget.commands,
                onApplied: widget.onApplied,
              ),
            _row(
              'Host wall',
              OpeningElementParameters.fromObject(widget.object)
                      .hostWallId
                      ?.toString() ??
                  '-',
            ),
            _openingPresetDrop(),
            _row('Dimensions', _preset.dimensionsLabelFor(widget.units)),
            _openingLevelDrop(),
            _compactSwitch(
              label: 'Lock to level',
              value: _locked,
              onChanged: (value) {
                if (_busy) return;
                final previous = _locked;
                setState(() => _locked = value);
                unawaited(_saveLock(previous, value));
              },
            ),
          ]);

  Widget _openingPresetDrop() {
    final presets = openingPresetsForKind(widget.object.kindKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _preset.id,
        decoration: _dropdownDecoration('Type'),
        items: <DropdownMenuItem<String>>[
          for (final preset in presets)
            DropdownMenuItem<String>(
              value: preset.id,
              child: Text(
                preset.labelFor(widget.units),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (id) {
          if (id == null || _busy) return;
          final previous = _preset;
          final next = presets.firstWhere((preset) => preset.id == id);
          setState(() {
            _preset = next;
          });
          unawaited(_savePreset(previous, next));
        },
      ),
    );
  }

  Widget _openingLevelDrop() => DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: widget.levels.any((level) => level.levelId == _levelId)
            ? _levelId
            : (widget.levels.isNotEmpty ? widget.levels.first.levelId : null),
        decoration: _dropdownDecoration('Base level'),
        items: <DropdownMenuItem<int>>[
          for (final level in widget.levels)
            DropdownMenuItem<int>(
              value: level.levelId,
              child: Text(
                '${level.name} (${_number(level.elevationMeters, units: widget.units)})',
              ),
            ),
        ],
        onChanged: widget.levels.isEmpty
            ? null
            : (value) {
                if (value != null && !_busy) {
                  final previous = _levelId;
                  setState(() => _levelId = value);
                  unawaited(_saveLevel(previous, value));
                }
              },
      );
}
