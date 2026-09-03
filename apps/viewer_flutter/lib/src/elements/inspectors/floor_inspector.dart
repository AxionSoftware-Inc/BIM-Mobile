part of '../../property_editor.dart';

class _FloorPropertiesSection extends StatefulWidget {
  const _FloorPropertiesSection({
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
  State<_FloorPropertiesSection> createState() =>
      _FloorPropertiesSectionState();
}

class _FloorPropertiesSectionState extends State<_FloorPropertiesSection> {
  late int _assemblyId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _assemblyId = SurfaceElementParameters.fromObject(widget.object).assemblyId;
  }

  @override
  void didUpdateWidget(covariant _FloorPropertiesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object.elementId != widget.object.elementId ||
        oldWidget.object.revision != widget.object.revision) {
      _assemblyId =
          SurfaceElementParameters.fromObject(widget.object).assemblyId;
    }
  }

  Future<void> _save(int previousAssemblyId) async {
    final elementId = widget.object.elementId;
    if (elementId == null || _assemblyId == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final selected = widget.scene.floorTypes
          .where((floorType) => floorType.id == _assemblyId)
          .firstOrNull;
      final result = await widget.commands.setElementAssembly(
        elementId: elementId,
        assemblyId: _assemblyId,
      );
      if (result.scene == null) {
        if (mounted) setState(() => _assemblyId = previousAssemblyId);
        return;
      }
      await widget.onApplied(
        result,
        selected == null ? 'Floor type applied.' : '${selected.name} applied.',
      );
    } catch (_) {
      if (mounted) setState(() => _assemblyId = previousAssemblyId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parameters = SurfaceElementParameters.fromObject(widget.object);
    final current = widget.scene.floorTypes
        .where((floorType) => floorType.id == _assemblyId)
        .firstOrNull;
    return _InspectorCard(
      title: '${_label(widget.object)} properties',
      icon: Icons.layers_outlined,
      children: <Widget>[
        if (widget.scene.floorTypes.isNotEmpty) ...<Widget>[
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: widget.scene.floorTypes.any(
              (floorType) => floorType.id == _assemblyId,
            )
                ? _assemblyId
                : null,
            decoration: _dropdownDecoration('Floor type'),
            hint: const Text('Select floor type'),
            items: [
              for (final floorType in widget.scene.floorTypes)
                DropdownMenuItem<int>(
                  value: floorType.id,
                  child: Text(
                    '${floorType.name} · ${floorType.surfaceLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (next) {
              if (next != null && !_busy) {
                final previous = _assemblyId;
                setState(() => _assemblyId = next);
                unawaited(_save(previous));
              }
            },
          ),
          if (current != null)
            _row(
              'Assembly',
              '${current.surfaceLabel} · '
                  '${_number(current.totalThicknessMeters, units: widget.units)} · '
                  '${current.layers.length} layers',
            ),
        ] else
          _row('Floor type', parameters.typeName ?? '-'),
        _row('Level', parameters.levelId?.toString() ?? '-'),
        _row(
            'Area (${widget.units.areaSymbol})',
            parameters.areaSquareMeters == null
                ? '-'
                : widget.units.formatArea(parameters.areaSquareMeters!)),
        _row(
            'Vertical offset (${widget.units.lengthSymbol})',
            parameters.verticalOffsetMeters == null
                ? '-'
                : widget.units.formatLength(parameters.verticalOffsetMeters!)),
      ],
    );
  }
}
