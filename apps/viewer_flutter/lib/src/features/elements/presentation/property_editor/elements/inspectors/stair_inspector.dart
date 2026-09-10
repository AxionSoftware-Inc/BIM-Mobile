part of '../../property_editor.dart';

Widget _buildStairInspector(_ObjectInspectorContext context) =>
    _StairPropertiesSection(
      object: context.object,
      units: context.units,
      commands: context.commands,
      onApplied: context.onApplied,
    );

class _StairPropertiesSection extends StatefulWidget {
  const _StairPropertiesSection({
    required this.object,
    required this.units,
    required this.commands,
    required this.onApplied,
  });

  final RenderSceneObject object;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  State<_StairPropertiesSection> createState() =>
      _StairPropertiesSectionState();
}

class _StairPropertiesSectionState extends State<_StairPropertiesSection> {
  late TextEditingController _width;
  late TextEditingController _landing;
  late int _layoutKind;
  late bool _railingEnabled;
  late List<RenderScenePoint> _pathPoints;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _readParameters();
  }

  @override
  void didUpdateWidget(covariant _StairPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId != widget.object.elementId ||
        oldWidget.object.revision != widget.object.revision ||
        oldWidget.units != widget.units) {
      _restoreFromObject();
    }
  }

  void _readParameters() {
    final parameters = StairElementParameters.fromObject(widget.object);
    _width = TextEditingController(
      text: widget.units.formatLength(
        parameters.widthMeters ?? 1.2,
        withUnit: false,
      ),
    );
    _landing = TextEditingController(
      text: widget.units.formatLength(
        parameters.landingDepthMeters,
        withUnit: false,
      ),
    );
    _layoutKind = parameters.layoutKind;
    _railingEnabled = parameters.railingEnabled;
    _pathPoints = parameters.pathPoints;
  }

  void _restoreFromObject() {
    final parameters = StairElementParameters.fromObject(widget.object);
    _width.text = widget.units.formatLength(
      parameters.widthMeters ?? 1.2,
      withUnit: false,
    );
    _landing.text = widget.units.formatLength(
      parameters.landingDepthMeters,
      withUnit: false,
    );
    void apply() {
      _layoutKind = parameters.layoutKind;
      _railingEnabled = parameters.railingEnabled;
      _pathPoints = parameters.pathPoints;
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  @override
  void dispose() {
    _width.dispose();
    _landing.dispose();
    super.dispose();
  }

  double? _length(String value) {
    final display = double.tryParse(value.trim());
    if (display == null || !display.isFinite) return null;
    return widget.units.toMeters(display);
  }

  String _layoutLabel(int kind) => switch (kind) {
        1 => 'L-shaped',
        2 => 'U-shaped',
        _ => 'Straight',
      };

  Future<void> _save() async {
    final stairId = widget.object.elementId;
    final width = _length(_width.text);
    final landing = _length(_landing.text);
    final minimumPathPoints = _layoutKind == 0
        ? 0
        : _layoutKind == 1
            ? 3
            : 4;
    if (_busy ||
        stairId == null ||
        width == null ||
        width <= 0.0 ||
        landing == null ||
        landing < 0.0 ||
        (_pathPoints.isNotEmpty && _pathPoints.length < minimumPathPoints) ||
        (_pathPoints.isEmpty && _layoutKind != 0)) {
      _restoreFromObject();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.commands.updateStairLayout(
        stairId: stairId,
        pathPoints: _pathPoints,
        widthMeters: width,
        landingDepthMeters: landing,
        layoutKind: _layoutKind,
        railingEnabled: _railingEnabled,
      );
      if (result.scene == null) {
        _restoreFromObject();
        return;
      }
      await widget.onApplied(result, 'Stair properties updated.');
    } catch (_) {
      _restoreFromObject();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _selectLayout(int? value) {
    if (value == null || _busy) return;
    final requiredPoints = value == 0
        ? 2
        : value == 1
            ? 3
            : 4;
    if (_pathPoints.isNotEmpty && _pathPoints.length < requiredPoints) return;
    if (_pathPoints.isEmpty && value != 0) return;
    setState(() => _layoutKind = value);
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) {
    final parameters = StairElementParameters.fromObject(widget.object);
    final hasEditablePath = _pathPoints.isNotEmpty;
    return _InspectorCard(
      title: 'Stair properties',
      icon: _icon(widget.object.kindKey),
      children: <Widget>[
        _row('Base level', parameters.baseLevelId?.toString() ?? '-'),
        _row('Top level', parameters.topLevelId?.toString() ?? '-'),
        _fieldPair(
          'Width (${widget.units.lengthSymbol})',
          _width,
          'Landing (${widget.units.lengthSymbol})',
          _landing,
          numeric: true,
          onEditingComplete: _save,
        ),
        DropdownButtonFormField<int>(
          initialValue: _layoutKind,
          decoration: _dropdownDecoration('Layout'),
          items: <DropdownMenuItem<int>>[
            const DropdownMenuItem(value: 0, child: Text('Straight')),
            if (!hasEditablePath || _pathPoints.length >= 3)
              const DropdownMenuItem(value: 1, child: Text('L-shaped')),
            if (!hasEditablePath || _pathPoints.length >= 4)
              const DropdownMenuItem(value: 2, child: Text('U-shaped')),
          ],
          onChanged: _selectLayout,
        ),
        _compactSwitch(
          label: 'Railing',
          value: _railingEnabled,
          onChanged: _busy
              ? null
              : (value) {
                  setState(() => _railingEnabled = value);
                  unawaited(_save());
                },
        ),
        _row(
          'Flights / path points',
          '${_pathPoints.isEmpty ? parameters.pathPointCount : _pathPoints.length - 1} / ${_pathPoints.length}',
        ),
        if (!hasEditablePath)
          const Text(
            'Legacy stair path is preserved; edit its layout path in the 2D view.',
            style: TextStyle(fontSize: 11),
          ),
        if (_layoutKind != 0)
          _row('Selected layout', _layoutLabel(_layoutKind)),
      ],
    );
  }
}
