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
  static const _layerFunctions = <String>[
    'Core',
    'InteriorFinish',
    'ExteriorFinish',
    'Insulation',
    'AirGap',
    'Generic',
  ];
  static const _layerSides = <String>['Unspecified', 'Exterior', 'Interior'];

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

  bool _asBool(Object? value, {bool fallback = false}) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  void _normalizeAssemblyCoreRange(Map<String, dynamic> assembly) {
    final layers = (assembly['layers'] as List?) ?? <dynamic>[];
    var first = -1;
    var last = -1;
    for (var index = 0; index < layers.length; index += 1) {
      final layer = layers[index];
      if (layer is Map && layer['function']?.toString() == 'Core') {
        first = first < 0 ? index : first;
        last = index;
      }
    }
    assembly['core_start_layer'] = first;
    assembly['core_end_layer'] = last;
  }

  int _coreStart(Map<String, dynamic> assembly, List<dynamic> layers) {
    final explicit = _asInt(assembly['core_start_layer']);
    if (explicit != null && explicit >= 0 && explicit < layers.length) return explicit;
    for (var index = 0; index < layers.length; index += 1) {
      if (layers[index] is Map && layers[index]['function']?.toString() == 'Core') return index;
    }
    return -1;
  }

  int _coreEnd(Map<String, dynamic> assembly, List<dynamic> layers) {
    final explicit = _asInt(assembly['core_end_layer']);
    if (explicit != null && explicit >= 0 && explicit < layers.length) return explicit;
    for (var index = layers.length - 1; index >= 0; index -= 1) {
      if (layers[index] is Map && layers[index]['function']?.toString() == 'Core') return index;
    }
    return -1;
  }

  void _setCoreRange(Map<String, dynamic> assembly, List<dynamic> layers, int start, int end) {
    if (start < 0 || end < 0) {
      for (final rawLayer in layers) {
        if (rawLayer is Map && rawLayer['function']?.toString() == 'Core') {
          rawLayer['function'] = 'Generic';
        }
      }
      assembly['core_start_layer'] = -1;
      assembly['core_end_layer'] = -1;
      setState(() {});
      return;
    }
    final first = start <= end ? start : end;
    final last = start <= end ? end : start;
    for (var index = 0; index < layers.length; index += 1) {
      final rawLayer = layers[index];
      if (rawLayer is! Map) continue;
      if (index >= first && index <= last) {
        rawLayer['function'] = 'Core';
      } else if (rawLayer['function']?.toString() == 'Core') {
        rawLayer['function'] = 'Generic';
      }
    }
    assembly['core_start_layer'] = first;
    assembly['core_end_layer'] = last;
    setState(() {});
  }

  void _setLayerFunction(Map<String, dynamic> assembly, List<dynamic> layers, int index, String value) {
    final layer = layers[index];
    if (layer is! Map) return;
    layer['function'] = value;
    _normalizeAssemblyCoreRange(assembly);
    setState(() {});
  }

  void _setLayerValue(Map<String, dynamic> layer, String key, Object value) {
    layer[key] = value;
    setState(() {});
  }

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
    _normalizeAssemblyCoreRange(assembly);
    setState(() {});
  }

  void _removeLayer(Map<String, dynamic> assembly, int index) {
    final layers = (assembly['layers'] as List?) ?? <dynamic>[];
    if (layers.length <= 1) return;
    layers.removeAt(index);
    _normalizeAssemblyCoreRange(assembly);
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
      'side': 'Unspecified',
      'wraps_openings': true,
      'wraps_ends': true,
    });
    assembly['layers'] = layers;
    _normalizeAssemblyCoreRange(assembly);
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

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Checkbox(value: value, onChanged: (next) => onChanged(next ?? false)),
        Text(label),
      ],
    );
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              'Core range',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DropdownButton<int>(
                            value: _coreStart(assembly, layers),
                            items: <int>[
                              -1,
                              ...List<int>.generate(layers.length, (index) => index),
                            ].map((value) {
                              return DropdownMenuItem<int>(
                                value: value,
                                child: Text(value < 0 ? 'None' : '${value + 1}'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              final end = _coreEnd(assembly, layers);
                              _setCoreRange(assembly, layers, value, value < 0 ? -1 : (end < 0 ? value : end));
                            },
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('to'),
                          ),
                          DropdownButton<int>(
                            value: _coreEnd(assembly, layers),
                            items: <int>[
                              -1,
                              ...List<int>.generate(layers.length, (index) => index),
                            ].map((value) {
                              return DropdownMenuItem<int>(
                                value: value,
                                child: Text(value < 0 ? 'None' : '${value + 1}'),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              final start = _coreStart(assembly, layers);
                              _setCoreRange(assembly, layers, value < 0 ? -1 : (start < 0 ? value : start), value);
                            },
                          ),
                        ],
                      ),
                    ),
                    for (var index = 0; index < layers.length; index += 1)
                      if (layers[index] is Map)
                        Builder(
                          builder: (context) {
                            final layer = layers[index].cast<String, dynamic>();
                            final function = _layerFunctions.contains(layer['function']?.toString())
                                ? layer['function'].toString()
                                : 'Generic';
                            final side = _layerSides.contains(layer['side']?.toString())
                                ? layer['side'].toString()
                                : 'Unspecified';
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 13,
                                child: Text('${index + 1}'),
                              ),
                              title: Row(
                                children: <Widget>[
                                  Expanded(child: Text(_materialName(layer['material_id']))),
                                  DropdownButton<int>(
                                    value: _materials
                                            .map((material) => material is Map ? _asInt(material['material_id']) : null)
                                            .whereType<int>()
                                            .contains(_asInt(layer['material_id']))
                                        ? _asInt(layer['material_id'])
                                        : null,
                                    items: _materials.whereType<Map>().map((material) {
                                      final id = _asInt(material['material_id']);
                                      return DropdownMenuItem<int>(
                                        value: id,
                                        child: Text(material['name']?.toString() ?? 'Material'),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) _setLayerValue(layer, 'material_id', value);
                                    },
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 6,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: <Widget>[
                                      SizedBox(
                                        width: 88,
                                        child: TextFormField(
                                          initialValue: layer['thickness']?.toString() ?? '0.01',
                                          decoration: const InputDecoration(
                                            labelText: 'Thickness (m)',
                                            isDense: true,
                                          ),
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          onChanged: (value) {
                                            layer['thickness'] = double.tryParse(value) ?? layer['thickness'];
                                          },
                                        ),
                                      ),
                                      DropdownButton<String>(
                                        value: function,
                                        items: _layerFunctions.map((value) {
                                          return DropdownMenuItem<String>(value: value, child: Text(value));
                                        }).toList(),
                                        onChanged: (value) {
                                          if (value != null) _setLayerFunction(assembly, layers, index, value);
                                        },
                                      ),
                                      DropdownButton<String>(
                                        value: side,
                                        items: _layerSides.map((value) {
                                          return DropdownMenuItem<String>(value: value, child: Text(value));
                                        }).toList(),
                                        onChanged: (value) {
                                          if (value != null) _setLayerValue(layer, 'side', value);
                                        },
                                      ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 0,
                                    children: <Widget>[
                                      _toggle(
                                        'Structural',
                                        _asBool(layer['structural']),
                                        (value) => _setLayerValue(layer, 'structural', value),
                                      ),
                                      _toggle(
                                        'Wrap openings',
                                        _asBool(layer['wraps_openings'], fallback: true),
                                        (value) => _setLayerValue(layer, 'wraps_openings', value),
                                      ),
                                      _toggle(
                                        'Wrap ends',
                                        _asBool(layer['wraps_ends'], fallback: true),
                                        (value) => _setLayerValue(layer, 'wraps_ends', value),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              trailing: Wrap(
                                children: <Widget>[
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
                            );
                          },
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
