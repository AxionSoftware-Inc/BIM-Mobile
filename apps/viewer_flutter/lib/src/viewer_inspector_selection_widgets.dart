// ignore_for_file: unused_element, unused_element_parameter

part of 'viewer_app.dart';

class _NumericField extends StatelessWidget {
  const _NumericField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        maxLines: 1,
        textInputAction: TextInputAction.done,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 13),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _SelectedObjectCard extends StatelessWidget {
  const _SelectedObjectCard({
    required this.object,
    required this.sceneLevels,
    required this.onLevelLockChanged,
    this.onEditWallLevels,
    this.onMoveOpeningLevel,
    this.onAssignLevel,
    this.onAttachWallToActiveLevel,
    this.onAttachWallTopToNextLevel,
    this.onMoveOpeningToActiveLevel,
    this.onApplyWallLevels,
    this.onEditOpeningPlacement,
    this.onDelete,
  });

  final RenderSceneObject object;
  final List<RenderSceneLevel> sceneLevels;
  final ValueChanged<bool> onLevelLockChanged;
  final VoidCallback? onEditWallLevels;
  final VoidCallback? onMoveOpeningLevel;
  final VoidCallback? onAssignLevel;
  final VoidCallback? onAttachWallToActiveLevel;
  final VoidCallback? onAttachWallTopToNextLevel;
  final VoidCallback? onMoveOpeningToActiveLevel;
  final Future<void> Function({
    required int baseLevelId,
    required int topLevelId,
    required int heightMode,
  })? onApplyWallLevels;
  final Future<void> Function()? onEditOpeningPlacement;
  final Future<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = prettySceneKind(object.kind);
    final area = _objectMetadataDouble(object, 'area_m2');
    final perimeter = _objectMetadataDouble(object, 'perimeter_m');
    final wallThickness = _objectMetadataDouble(object, 'thickness_meters');
    final wallHeight = _objectMetadataDouble(object, 'height_meters');
    final wallStart = _wallPointSummary(
      object,
      xKey: 'start_x',
      yKey: 'start_y',
      legacyKey: 'axis_start',
    );
    final wallEnd = _wallPointSummary(
      object,
      xKey: 'end_x',
      yKey: 'end_y',
      legacyKey: 'axis_end',
    );
    final baseLevelId = object.metadata['base_level_id'];
    final topLevelId = object.metadata['top_level_id'];
    final heightMode = object.metadata['height_mode']?.toString();
    final levelLocked = RenderSceneEditor.isElementLevelLocked(object);
    final canToggleLevelLock =
        object.kindKey == 'door' || object.kindKey == 'window';

    return _InfoCard(
      title: 'Selected object',
      icon: _kindIcon(object.kindKey),
      children: <Widget>[
        _InfoRow(label: 'Kind', value: kind),
        _InfoRow(
            label: 'Element ID', value: object.elementId?.toString() ?? '-'),
        _InfoRow(label: 'Level ID', value: object.levelId?.toString() ?? '-'),
        if (canToggleLevelLock)
          _InfoRow(
            label: 'Level lock',
            value: levelLocked ? 'On' : 'Off',
            trailing: Switch.adaptive(
              value: levelLocked,
              onChanged: onLevelLockChanged,
            ),
          ),
        if (wallThickness != null)
          _InfoRow(
            label: 'Thickness',
            value: '${wallThickness.toStringAsFixed(2)} m',
          ),
        if (wallHeight != null)
          _InfoRow(
            label: 'Height',
            value: '${wallHeight.toStringAsFixed(2)} m',
          ),
        if (object.kindKey == 'wall')
          _InfoRow(label: 'Base level', value: '${baseLevelId ?? '-'}'),
        if (object.kindKey == 'wall')
          _InfoRow(
            label: 'Top constraint',
            value: '${topLevelId ?? '-'} (${heightMode ?? 'Unconnected'})',
          ),
        if (object.kindKey == 'stair') ...<Widget>[
          _InfoRow(label: 'Base level', value: '${baseLevelId ?? '-'}'),
          _InfoRow(label: 'Top level', value: '${topLevelId ?? '-'}'),
          _InfoRow(
            label: 'Run / rise',
            value:
                '${object.metadata['total_run_meters'] ?? '-'} m / ${object.metadata['total_rise_meters'] ?? '-'} m',
          ),
          _InfoRow(
            label: 'Treads / risers',
            value:
                '${object.metadata['tread_count'] ?? '-'} / ${object.metadata['riser_count'] ?? '-'}',
          ),
        ],
        if (object.kindKey == 'wall' &&
            sceneLevels.isNotEmpty &&
            onApplyWallLevels != null)
          _WallLevelInlineEditor(
            object: object,
            levels: sceneLevels,
            onApply: onApplyWallLevels!,
          ),
        if (object.kindKey == 'wall' && onEditWallLevels != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onAttachWallToActiveLevel,
                  icon: const Icon(Icons.vertical_align_bottom),
                  label: const Text('Base -> active'),
                ),
                OutlinedButton.icon(
                  onPressed: onAttachWallTopToNextLevel,
                  icon: const Icon(Icons.unfold_more),
                  label: const Text('Top -> next'),
                ),
                OutlinedButton.icon(
                  onPressed: onEditWallLevels,
                  icon: const Icon(Icons.tune),
                  label: const Text('Advanced'),
                ),
              ],
            ),
          ),
        if ((object.kindKey == 'door' || object.kindKey == 'window') &&
            onMoveOpeningLevel != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: onMoveOpeningToActiveLevel,
                  icon: const Icon(Icons.layers_outlined),
                  label: const Text('Move -> active'),
                ),
                OutlinedButton.icon(
                  onPressed: onMoveOpeningLevel,
                  icon: const Icon(Icons.vertical_align_center),
                  label: const Text('Choose level'),
                ),
              ],
            ),
          ),
        if (onAssignLevel != null &&
            object.kindKey != 'wall' &&
            object.kindKey != 'door' &&
            object.kindKey != 'window')
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onAssignLevel,
              icon: const Icon(Icons.layers),
              label: const Text('Assign level'),
            ),
          ),
        if (onEditOpeningPlacement != null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onEditOpeningPlacement,
              icon: const Icon(Icons.open_with),
              label: const Text('Edit placement and size'),
            ),
          ),
        if (wallStart != null && wallEnd != null) ...<Widget>[
          _InfoRow(label: 'Axis start', value: wallStart),
          _InfoRow(label: 'Axis end', value: wallEnd),
        ],
        if (area != null)
          _InfoRow(
            label: 'Area',
            value: '${area.toStringAsFixed(2)} m²',
          ),
        if (perimeter != null)
          _InfoRow(
            label: 'Perimeter',
            value: '${perimeter.toStringAsFixed(2)} m',
          ),
        _InfoRow(label: 'Material', value: object.materialCategory),
        if (onDelete != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete element'),
            ),
          ),
      ],
    );
  }
}

String? _wallPointSummary(
  RenderSceneObject object, {
  required String xKey,
  required String yKey,
  required String legacyKey,
}) {
  final x = _objectMetadataDouble(object, xKey);
  final y = _objectMetadataDouble(object, yKey);
  if (x != null && y != null) {
    return '${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)}';
  }
  final legacy = object.metadata[legacyKey];
  if (legacy is Map && legacy['x'] != null && legacy['y'] != null) {
    return '${legacy['x']}, ${legacy['y']}';
  }
  return null;
}

double? _objectMetadataDouble(RenderSceneObject object, String key) {
  final value = object.metadata[key];
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

int? _objectMetadataInt(RenderSceneObject object, String key) {
  final value = object.metadata[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

// Kept as a diagnostics building block for the optional diagnostics surface.
class _SceneSummaryCard extends StatelessWidget {
  const _SceneSummaryCard({
    required this.scene,
    required this.activeLevel,
  });

  final RenderScene scene;
  final RenderSceneLevel? activeLevel;

  @override
  Widget build(BuildContext context) {
    final bounds = scene.bounds;

    return _InfoCard(
      title: 'Scene summary',
      icon: Icons.analytics_outlined,
      children: <Widget>[
        _InfoRow(label: 'Source', value: scene.source),
        _InfoRow(label: 'Version', value: scene.sceneVersion.toString()),
        _InfoRow(label: 'Units', value: scene.units),
        _InfoRow(label: 'Coordinates', value: scene.coordinateSystem),
        _InfoRow(label: 'Levels', value: scene.levels.length.toString()),
        if (activeLevel != null)
          _InfoRow(
            label: 'Active level',
            value:
                '${activeLevel!.name} @ ${activeLevel!.elevationMeters.toStringAsFixed(2)} m',
          ),
        _InfoRow(label: 'Objects', value: scene.objectCount.toString()),
        _InfoRow(label: 'Vertices', value: scene.vertexCount.toString()),
        _InfoRow(label: 'Indices', value: scene.indexCount.toString()),
        _InfoRow(label: 'Triangles', value: scene.triangleCount.toString()),
        _InfoRow(
          label: 'Bounds',
          value:
              '${bounds.width.toStringAsFixed(2)} × ${bounds.depth.toStringAsFixed(2)} × ${bounds.height.toStringAsFixed(2)} m',
        ),
      ],
    );
  }
}

class _AndroidMutationTrace extends StatelessWidget {
  const _AndroidMutationTrace({required this.entries});

  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Card(
        color: const Color(0xED111827),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.25,
              fontFamily: 'monospace',
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('ANDROID MUTATION TRACE',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                for (final entry in entries) Text(entry, maxLines: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedLevelCard extends StatelessWidget {
  const _SelectedLevelCard({
    required this.level,
    required this.onElevationSubmitted,
    required this.onEdit,
  });

  final RenderSceneLevel level;
  final Future<void> Function(String value) onElevationSubmitted;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Selected level',
      icon: Icons.straighten,
      children: <Widget>[
        _InfoRow(label: 'Name', value: level.name),
        _InfoRow(label: 'Level ID', value: level.levelId.toString()),
        TextFormField(
          initialValue: level.elevationMeters.toStringAsFixed(2),
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Elevation (m)',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onFieldSubmitted: onElevationSubmitted,
        ),
        _InfoRow(
          label: 'Default wall height',
          value: '${level.defaultWallHeightMeters.toStringAsFixed(2)} m',
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit level properties'),
          ),
        ),
      ],
    );
  }
}

class _MultiSelectionInspectorCard extends StatelessWidget {
  const _MultiSelectionInspectorCard({
    required this.count,
    required this.onClear,
  });

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _InfoCard(
      title: 'Multiple selection',
      icon: Icons.select_all,
      children: <Widget>[
        Text('$count object(s) selected.'),
        const SizedBox(height: 6),
        const Text(
          'Batch edit will be added for safe properties shared by all selected objects. Open an individual Inspector to avoid changing an incorrect value.',
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear),
            label: const Text('Clear selection'),
          ),
        ),
      ],
    );
  }
}

class _ActiveLevelCard extends StatelessWidget {
  const _ActiveLevelCard({
    required this.level,
    required this.levels,
    required this.activeLevelId,
    required this.onSelectLevel,
  });

  final RenderSceneLevel? level;
  final List<RenderSceneLevel> levels;
  final int? activeLevelId;
  final Future<void> Function(int? levelId) onSelectLevel;

  @override
  Widget build(BuildContext context) {
    if (level == null) {
      return const _InfoCard(
        title: 'Active level',
        icon: Icons.straighten,
        children: <Widget>[
          Text('No active level selected.'),
        ],
      );
    }

    return _InfoCard(
      title: 'Active level',
      icon: Icons.straighten,
      children: <Widget>[
        _InfoRow(label: 'Name', value: level!.name),
        _InfoRow(label: 'Level ID', value: level!.levelId.toString()),
        _InfoRow(
          label: 'Elevation',
          value: '${level!.elevationMeters.toStringAsFixed(2)} m',
        ),
        _InfoRow(
          label: 'Default wall height',
          value: '${level!.defaultWallHeightMeters.toStringAsFixed(2)} m',
        ),
        if (levels.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          const Text(
            'Levels',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Column(
            children: levels
                .map<Widget>(
                  (entry) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        tileColor: entry.levelId == activeLevelId
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.55)
                            : Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        leading: Icon(
                          entry.levelId == activeLevelId
                              ? Icons.check_circle
                              : Icons.straighten,
                          size: 18,
                        ),
                        title: Text(entry.name),
                        subtitle: Text(
                            '${entry.elevationMeters.toStringAsFixed(2)} m'),
                        onTap: () => onSelectLevel(entry.levelId),
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 4),
          const Text('Tap row: select level.', style: TextStyle(fontSize: 12)),
        ],
      ],
    );
  }
}

class _WallLevelInlineEditor extends StatefulWidget {
  const _WallLevelInlineEditor({
    required this.object,
    required this.levels,
    required this.onApply,
  });

  final RenderSceneObject object;
  final List<RenderSceneLevel> levels;
  final Future<void> Function({
    required int baseLevelId,
    required int topLevelId,
    required int heightMode,
  }) onApply;

  @override
  State<_WallLevelInlineEditor> createState() => _WallLevelInlineEditorState();
}

class _WallLevelInlineEditorState extends State<_WallLevelInlineEditor> {
  late int _baseLevelId;
  late int _topLevelId;
  late int _heightMode;

  @override
  void initState() {
    super.initState();
    _syncFromObject();
  }

  @override
  void didUpdateWidget(covariant _WallLevelInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.object != widget.object ||
        oldWidget.levels != widget.levels) {
      _syncFromObject();
    }
  }

  void _syncFromObject() {
    final firstLevelId =
        widget.levels.isNotEmpty ? widget.levels.first.levelId : 0;
    _baseLevelId = _objectInt(widget.object, 'base_level_id') ??
        widget.object.levelId ??
        firstLevelId;
    _topLevelId = _objectInt(widget.object, 'top_level_id') ?? 0;
    _heightMode =
        (widget.object.metadata['height_mode']?.toString() == 'TopLevel')
            ? 1
            : 0;
    if (_heightMode == 1 && _topLevelId == 0 && widget.levels.length > 1) {
      final sorted = [...widget.levels]
        ..sort((a, b) => a.elevationMeters.compareTo(b.elevationMeters));
      RenderSceneLevel? base;
      for (final level in sorted) {
        if (level.levelId == _baseLevelId) {
          base = level;
          break;
        }
      }
      if (base != null) {
        RenderSceneLevel? next;
        for (final level in sorted) {
          if (level.elevationMeters > base.elevationMeters + 1e-6) {
            next = level;
            break;
          }
        }
        _topLevelId = next?.levelId ?? 0;
      }
    }
  }

  int? _objectInt(RenderSceneObject object, String key) {
    final value = object.metadata[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final levels = widget.levels;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        const Text(
          'Wall levels',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: levels.any((level) => level.levelId == _baseLevelId)
              ? _baseLevelId
              : levels.first.levelId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Base level',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: levels
              .map(
                (level) => DropdownMenuItem<int>(
                  value: level.levelId,
                  child: Text(
                    '${level.name} (${level.elevationMeters.toStringAsFixed(2)}m)',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _baseLevelId = value;
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _heightMode,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Height mode',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const <DropdownMenuItem<int>>[
            DropdownMenuItem<int>(value: 0, child: Text('Unconnected')),
            DropdownMenuItem<int>(value: 1, child: Text('Top level')),
          ],
          onChanged: (value) {
            if (value == null) {
              return;
            }
            setState(() {
              _heightMode = value;
              if (_heightMode == 0) {
                _topLevelId = 0;
              }
            });
          },
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _topLevelId == 0 ? null : _topLevelId,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Top level',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: levels
              .map(
                (level) => DropdownMenuItem<int>(
                  value: level.levelId,
                  child: Text(
                    '${level.name} (${level.elevationMeters.toStringAsFixed(2)}m)',
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: _heightMode == 0
              ? null
              : (value) {
                  setState(() {
                    _topLevelId = value ?? 0;
                  });
                },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: () {
              widget.onApply(
                baseLevelId: _baseLevelId,
                topLevelId: _topLevelId,
                heightMode: _heightMode,
              );
            },
            icon: const Icon(Icons.save_outlined),
            label: const Text('Apply wall levels'),
          ),
        ),
      ],
    );
  }
}
