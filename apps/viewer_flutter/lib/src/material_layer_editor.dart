import 'package:flutter/material.dart';

class MaterialLayerEditor extends StatefulWidget {
  const MaterialLayerEditor({
    required this.projectJson,
    required this.onApply,
    super.key,
  });

  final Map<String, dynamic> projectJson;
  final Future<void> Function(Map<String, dynamic> projectJson) onApply;

  @override
  State<MaterialLayerEditor> createState() => _MaterialLayerEditorState();
}

class _MaterialLayerEditorState extends State<MaterialLayerEditor> {
  late Map<String, dynamic> _project;
  bool _busy = false;

  List<dynamic> get _materials =>
      ((_project['document'] as Map?)?['materials'] as List?) ?? <dynamic>[];

  List<dynamic> get _assemblies =>
      ((_project['document'] as Map?)?['assemblies'] as List?) ?? <dynamic>[];

  @override
  void initState() {
    super.initState();
    _project = _copyMap(widget.projectJson);
  }

  Map<String, dynamic> _copyMap(Map<String, dynamic> value) {
    return value.map((key, value) {
      if (value is Map) {
        return MapEntry(key, _copyMap(value.cast<String, dynamic>()));
      }
      if (value is List) {
        return MapEntry(
          key,
          value
              .map((entry) => entry is Map
                  ? _copyMap(entry.cast<String, dynamic>())
                  : entry)
              .toList(),
        );
      }
      return MapEntry(key, value);
    });
  }

  String _materialName(Object? id) {
    for (final material in _materials) {
      if (material is Map && _asInt(material['material_id']) == _asInt(id)) {
        return material['name']?.toString() ?? 'Material';
      }
    }
    return 'Missing material';
  }

  int? _asInt(Object? value) => value is num ? value.toInt() : int.tryParse('$value');

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      await widget.onApply(_project);
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _moveLayer(Map<String, dynamic> assembly, int index, int delta) {
    final layers = (assembly['layers'] as List?) ?? <dynamic>[];
    final next = index + delta;
    if (next < 0 || next >= layers.length) return;
    final value = layers.removeAt(index);
    layers.insert(next, value);
    setState(() {});
  }

  void _removeLayer(Map<String, dynamic> assembly, int index) {
    final layers = (assembly['layers'] as List?) ?? <dynamic>[];
    if (layers.length <= 1) return;
    layers.removeAt(index);
    setState(() {});
  }

  void _addLayer(Map<String, dynamic> assembly) {
    final material = _materials.isEmpty ? null : _materials.first;
    if (material is! Map) return;
    final layers = (assembly['layers'] as List?) ?? <dynamic>[];
    layers.add(<String, dynamic>{
      'material_id': material['material_id'],
      'thickness': 0.01,
      'function': 'Generic',
      'priority': 0,
      'structural': false,
    });
    assembly['layers'] = layers;
    setState(() {});
  }

  void _addMaterial() {
    final document = (_project['document'] as Map?)?.cast<String, dynamic>();
    if (document == null) return;
    final nextId = _asInt(document['next_id']) ?? 1;
    document['next_id'] = nextId + 1;
    final materials = (document['materials'] as List?) ?? <dynamic>[];
    materials.add(<String, dynamic>{
      'material_id': nextId,
      'name': 'New Material',
      'category': 'Finish',
      'display_color': '#B0B7C3',
      'metadata': <String, dynamic>{},
    });
    document['materials'] = materials;
    setState(() {});
  }

  Widget _colorEditor(Map<String, dynamic> material) {
    final controller = TextEditingController(
      text: material['display_color']?.toString() ?? '#B0B7C3',
    );
    return Row(
      children: <Widget>[
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: _parseColor(controller.text),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.black26),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 104,
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Color',
              isDense: true,
            ),
            onChanged: (value) => material['display_color'] = value,
          ),
        ),
      ],
    );
  }

  Color _parseColor(String value) {
    final normalized = value.trim().replaceFirst('#', '');
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) return const Color(0xFFB0B7C3);
    return normalized.length == 8 ? Color(parsed) : Color(0xFF000000 | parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Materials and layers'),
      content: SizedBox(
        width: 620,
        height: 560,
        child: ListView(
          children: <Widget>[
            const Text('Material catalog', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._materials.whereType<Map>().map((material) {
              return ListTile(
                dense: true,
                title: Text(material['name']?.toString() ?? 'Material'),
                subtitle: Text(material['category']?.toString() ?? 'Generic'),
                trailing: _colorEditor(material.cast<String, dynamic>()),
              );
            }),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addMaterial,
                icon: const Icon(Icons.add),
                label: const Text('Add material'),
              ),
            ),
            const Divider(height: 24),
            const Text('Layered assemblies', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ..._assemblies.whereType<Map>().map((rawAssembly) {
              final assembly = rawAssembly.cast<String, dynamic>();
              final layers = (assembly['layers'] as List?) ?? <dynamic>[];
              return Card(
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(assembly['name']?.toString() ?? 'Assembly'),
                  subtitle: Text(assembly['kind']?.toString() ?? 'Floor'),
                  children: <Widget>[
                    for (var index = 0; index < layers.length; index += 1)
                      if (layers[index] is Map)
                        ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 13,
                            child: Text('${index + 1}'),
                          ),
                          title: Row(
                            children: <Widget>[
                              Expanded(child: Text(_materialName(layers[index]['material_id']))),
                              DropdownButton<int>(
                                value: _materials
                                        .map((material) => material is Map ? _asInt(material['material_id']) : null)
                                        .whereType<int>()
                                        .contains(_asInt(layers[index]['material_id']))
                                    ? _asInt(layers[index]['material_id'])
                                    : null,
                                items: _materials.whereType<Map>().map((material) {
                                  final id = _asInt(material['material_id']);
                                  return DropdownMenuItem<int>(
                                    value: id,
                                    child: Text(material['name']?.toString() ?? 'Material'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value != null) layers[index]['material_id'] = value;
                                  setState(() {});
                                },
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '${layers[index]['thickness'] ?? 0} m · ${layers[index]['function'] ?? 'Generic'}',
                          ),
                          trailing: Wrap(
                            children: <Widget>[
                              SizedBox(
                                width: 76,
                                child: TextFormField(
                                  initialValue: layers[index]['thickness']?.toString() ?? '0.01',
                                  decoration: const InputDecoration(
                                    labelText: 'm',
                                    isDense: true,
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (value) {
                                    layers[index]['thickness'] = double.tryParse(value) ?? layers[index]['thickness'];
                                  },
                                ),
                              ),
                              IconButton(
                                tooltip: 'Move layer up',
                                onPressed: index == 0 ? null : () => _moveLayer(assembly, index, -1),
                                icon: const Icon(Icons.arrow_upward, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Move layer down',
                                onPressed: index == layers.length - 1 ? null : () => _moveLayer(assembly, index, 1),
                                icon: const Icon(Icons.arrow_downward, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Remove layer',
                                onPressed: layers.length <= 1 ? null : () => _removeLayer(assembly, index),
                                icon: const Icon(Icons.delete_outline, size: 18),
                              ),
                            ],
                          ),
                        ),
                    TextButton.icon(
                      onPressed: () => _addLayer(assembly),
                      icon: const Icon(Icons.add),
                      label: const Text('Add layer'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _apply,
          icon: _busy
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check),
          label: const Text('Apply'),
        ),
      ],
    );
  }
}
