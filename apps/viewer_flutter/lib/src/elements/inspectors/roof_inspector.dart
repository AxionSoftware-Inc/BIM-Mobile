part of '../../property_editor.dart';

class _RoofPropertiesSection extends StatefulWidget {
  const _RoofPropertiesSection({
    required this.object,
    required this.scene,
    required this.units,
    required this.commands,
    required this.onApplied,
  });
  final RenderSceneObject object;
  final RenderScene scene;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  @override
  State<_RoofPropertiesSection> createState() => _RoofPropertiesSectionState();
}

class _RoofPropertiesSectionState extends State<_RoofPropertiesSection> {
  late int _assemblyId;
  late int _roofType;
  late final TextEditingController _slope;
  late final TextEditingController _overhang;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _setInitialValues(widget.object, widget.units);
  }

  @override
  void didUpdateWidget(covariant _RoofPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId != widget.object.elementId ||
        oldWidget.object.revision != widget.object.revision ||
        oldWidget.units != widget.units) {
      _restoreFromObject();
    }
  }

  void _setInitialValues(
    RenderSceneObject object,
    ProjectUnitSettings units,
  ) {
    final parameters = RoofElementParameters.fromObject(object);
    _assemblyId = parameters.assemblyId;
    _roofType = parameters.roofType;
    _slope = TextEditingController(
        text: (parameters.slopeDegrees ?? 25).toStringAsFixed(1));
    final overhang = parameters.overhangMeters ?? 0.0;
    _overhang = TextEditingController(
      text: units.formatLength(overhang, withUnit: false),
    );
  }

  void _restoreFromObject() {
    final parameters = RoofElementParameters.fromObject(widget.object);
    _assemblyId = parameters.assemblyId;
    _roofType = parameters.roofType;
    _slope.text = (parameters.slopeDegrees ?? 25).toStringAsFixed(1);
    _overhang.text = widget.units.formatLength(
      parameters.overhangMeters ?? 0.0,
      withUnit: false,
    );
  }

  @override
  void dispose() {
    _slope.dispose();
    _overhang.dispose();
    super.dispose();
  }

  Future<void> _saveAssembly(int previousAssemblyId) async {
    final id = widget.object.elementId;
    if (id == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.commands.setElementAssembly(
        elementId: id,
        assemblyId: _assemblyId,
      );
      if (result.scene == null) {
        if (mounted) setState(() => _assemblyId = previousAssemblyId);
        return;
      }
      await widget.onApplied(result, 'Roof properties updated.');
    } catch (_) {
      if (mounted) setState(() => _assemblyId = previousAssemblyId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveGeometry() async {
    final id = widget.object.elementId;
    final slope = double.tryParse(_slope.text.trim());
    final displayOverhang = double.tryParse(_overhang.text.trim());
    final overhang =
        displayOverhang == null ? null : widget.units.toMeters(displayOverhang);
    if (id == null ||
        overhang == null ||
        !overhang.isFinite ||
        overhang < 0 ||
        (_roofType != 0 &&
            (slope == null || !slope.isFinite || slope <= 0 || slope >= 75))) {
      if (mounted) _restoreFromObject();
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.commands.updateRoofProperties(
        roofId: id,
        roofType: _roofType,
        slopeDegrees: _roofType == 0 ? null : slope,
        overhangMeters: overhang,
      );
      if (result.scene == null) {
        if (mounted) _restoreFromObject();
        return;
      }
      await widget.onApplied(result, 'Roof properties updated.');
    } catch (_) {
      if (mounted) _restoreFromObject();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _InspectorCard(
        title: 'Roof properties',
        icon: _icon(widget.object.kindKey),
        children: <Widget>[
          if (widget.scene.roofTypes.isNotEmpty)
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: widget.scene.roofTypes.any(
                (roofType) => roofType.id == _assemblyId,
              )
                  ? _assemblyId
                  : null,
              decoration: _dropdownDecoration('Material / roof system'),
              hint: const Text('Select roof material'),
              items: <DropdownMenuItem<int>>[
                for (final roofType in widget.scene.roofTypes)
                  DropdownMenuItem<int>(
                    value: roofType.id,
                    child: Text(
                      '${roofType.name} · ${widget.units.formatLength(roofType.totalThicknessMeters)}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null && !_busy) {
                  final previous = _assemblyId;
                  setState(() => _assemblyId = value);
                  unawaited(_saveAssembly(previous));
                }
              },
            ),
          DropdownButtonFormField<int>(
            initialValue: _roofType,
            decoration: _dropdownDecoration('Roof shape'),
            items: const <DropdownMenuItem<int>>[
              DropdownMenuItem(value: 0, child: Text('Flat')),
              DropdownMenuItem(value: 1, child: Text('Simple gable')),
              DropdownMenuItem(value: 2, child: Text('Auto footprint (L/U)')),
            ],
            onChanged: (value) {
              if (value != null && !_busy) {
                setState(() => _roofType = value);
                unawaited(_saveGeometry());
              }
            },
          ),
          if (_roofType != 0)
            _fieldPair(
              'Slope (degrees)',
              _slope,
              'Overhang (${widget.units.lengthSymbol})',
              _overhang,
              numeric: true,
              onEditingComplete: _saveGeometry,
            )
          else
            _field('Overhang (${widget.units.lengthSymbol})', _overhang,
                numeric: true, onEditingComplete: _saveGeometry),
        ],
      );
}
