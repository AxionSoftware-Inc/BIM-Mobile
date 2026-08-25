// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

class _EstimateSummaryCard extends StatelessWidget {
  const _EstimateSummaryCard({
    required this.summary,
    required this.catalog,
    required this.onCatalogChanged,
  });

  final RenderSceneEstimateSummary summary;
  final RenderSceneEstimateCatalog catalog;
  final ValueChanged<RenderSceneEstimateCatalog> onCatalogChanged;

  String _money(double value) => '\$${value.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Estimate',
      icon: Icons.request_quote_outlined,
      children: <Widget>[
        _InfoRow(label: 'Rooms', value: summary.roomCount.toString()),
        _InfoRow(
          label: 'Room area',
          value: '${summary.totalRoomArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Room perimeter',
          value: '${summary.totalRoomPerimeter.toStringAsFixed(2)} m',
        ),
        _InfoRow(label: 'Walls', value: summary.wallCount.toString()),
        _InfoRow(
          label: 'Wall gross volume',
          value: '${summary.wallGrossVolume.toStringAsFixed(2)} m³',
        ),
        _InfoRow(
          label: 'Wall net volume',
          value: '${summary.wallNetVolume.toStringAsFixed(2)} m³',
        ),
        _InfoRow(
          label: 'Wall net area',
          value: '${summary.wallNetArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Brick count',
          value: summary.brickCount.toString(),
        ),
        _InfoRow(
          label: 'Floors',
          value:
              '${summary.floorCount} · ${summary.floorArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Concrete',
          value: '${summary.floorConcreteVolume.toStringAsFixed(2)} m³',
        ),
        _InfoRow(
          label: 'Floor finish',
          value: '${summary.floorArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Ceilings',
          value:
              '${summary.ceilingCount} · ${summary.ceilingArea.toStringAsFixed(2)} m²',
        ),
        _InfoRow(
          label: 'Doors / Windows',
          value: '${summary.doorCount} / ${summary.windowCount}',
        ),
        _InfoRow(
          label: 'Opening area',
          value: '${summary.openingArea.toStringAsFixed(2)} m²',
        ),
        const SizedBox(height: 10),
        Text(
          'Cost lines',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final item in summary.lineItems)
          _InfoRow(
            label:
                '${item.label} (${item.quantity.toStringAsFixed(item.unit == 'pcs' ? 0 : 2)} ${item.unit})',
            value: '${_money(item.unitCost)} → ${_money(item.totalCost)}',
          ),
        const SizedBox(height: 8),
        _InfoRow(
          label: 'Estimated total',
          value: _money(summary.totalCost),
        ),
        const SizedBox(height: 12),
        _EstimateCatalogEditor(
          catalog: catalog,
          onChanged: onCatalogChanged,
        ),
      ],
    );
  }
}

class _EstimateCatalogEditor extends StatefulWidget {
  const _EstimateCatalogEditor({
    required this.catalog,
    required this.onChanged,
  });

  final RenderSceneEstimateCatalog catalog;
  final ValueChanged<RenderSceneEstimateCatalog> onChanged;

  @override
  State<_EstimateCatalogEditor> createState() => _EstimateCatalogEditorState();
}

class _EstimateCatalogEditorState extends State<_EstimateCatalogEditor> {
  late final TextEditingController _brickDensityController;
  late final TextEditingController _brickUnitCostController;
  late final TextEditingController _concreteController;
  late final TextEditingController _floorFinishController;
  late final TextEditingController _ceilingController;
  late final TextEditingController _doorController;
  late final TextEditingController _windowController;

  @override
  void initState() {
    super.initState();
    _brickDensityController = TextEditingController();
    _brickUnitCostController = TextEditingController();
    _concreteController = TextEditingController();
    _floorFinishController = TextEditingController();
    _ceilingController = TextEditingController();
    _doorController = TextEditingController();
    _windowController = TextEditingController();
    _syncFromCatalog(widget.catalog);
  }

  @override
  void didUpdateWidget(covariant _EstimateCatalogEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      _syncFromCatalog(widget.catalog);
    }
  }

  @override
  void dispose() {
    _brickDensityController.dispose();
    _brickUnitCostController.dispose();
    _concreteController.dispose();
    _floorFinishController.dispose();
    _ceilingController.dispose();
    _doorController.dispose();
    _windowController.dispose();
    super.dispose();
  }

  void _syncFromCatalog(RenderSceneEstimateCatalog catalog) {
    _brickDensityController.text = _format(catalog.bricksPerCubicMeter);
    _brickUnitCostController.text = _format(catalog.brickUnitCost);
    _concreteController.text = _format(catalog.concreteCostPerCubicMeter);
    _floorFinishController.text =
        _format(catalog.floorFinishCostPerSquareMeter);
    _ceilingController.text = _format(catalog.ceilingCostPerSquareMeter);
    _doorController.text = _format(catalog.doorUnitCost);
    _windowController.text = _format(catalog.windowUnitCost);
  }

  String _format(double value) => value.toStringAsFixed(2);

  void _updateCatalog({
    double? bricksPerCubicMeter,
    double? brickUnitCost,
    double? concreteCostPerCubicMeter,
    double? floorFinishCostPerSquareMeter,
    double? ceilingCostPerSquareMeter,
    double? doorUnitCost,
    double? windowUnitCost,
  }) {
    widget.onChanged(
      widget.catalog.copyWith(
        bricksPerCubicMeter: bricksPerCubicMeter,
        brickUnitCost: brickUnitCost,
        concreteCostPerCubicMeter: concreteCostPerCubicMeter,
        floorFinishCostPerSquareMeter: floorFinishCostPerSquareMeter,
        ceilingCostPerSquareMeter: ceilingCostPerSquareMeter,
        doorUnitCost: doorUnitCost,
        windowUnitCost: windowUnitCost,
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required ValueChanged<double> onValue,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = double.tryParse(value.trim());
          if (parsed != null && parsed >= 0) {
            onValue(parsed);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: Text(
        'Unit prices',
        style: Theme.of(context).textTheme.labelLarge,
      ),
      subtitle: const Text('Live estimate updates from these values'),
      children: <Widget>[
        _buildField(
          label: 'Bricks per m³',
          controller: _brickDensityController,
          onValue: (value) => _updateCatalog(bricksPerCubicMeter: value),
        ),
        _buildField(
          label: 'Brick unit cost',
          controller: _brickUnitCostController,
          onValue: (value) => _updateCatalog(brickUnitCost: value),
        ),
        _buildField(
          label: 'Concrete cost per m³',
          controller: _concreteController,
          onValue: (value) => _updateCatalog(concreteCostPerCubicMeter: value),
        ),
        _buildField(
          label: 'Floor finish cost per m²',
          controller: _floorFinishController,
          onValue: (value) =>
              _updateCatalog(floorFinishCostPerSquareMeter: value),
        ),
        _buildField(
          label: 'Ceiling cost per m²',
          controller: _ceilingController,
          onValue: (value) => _updateCatalog(ceilingCostPerSquareMeter: value),
        ),
        _buildField(
          label: 'Door unit cost',
          controller: _doorController,
          onValue: (value) => _updateCatalog(doorUnitCost: value),
        ),
        _buildField(
          label: 'Window unit cost',
          controller: _windowController,
          onValue: (value) => _updateCatalog(windowUnitCost: value),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () {
              const defaults = RenderSceneEstimateCatalog();
              _syncFromCatalog(defaults);
              widget.onChanged(defaults);
            },
            child: const Text('Reset defaults'),
          ),
        ),
      ],
    );
  }
}
