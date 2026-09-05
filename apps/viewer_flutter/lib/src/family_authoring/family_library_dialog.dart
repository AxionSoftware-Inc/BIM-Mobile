import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';

/// Result returned by the in-project family library.
///
/// The library owns browsing and filtering. The project owns placement, so a
/// selected asset crosses the boundary only after the user presses Place.
final class FamilyLibraryResult {
  const FamilyLibraryResult._({this.asset, this.browseFile = false});

  const FamilyLibraryResult.asset(FamilyAssetFile value) : this._(asset: value);

  const FamilyLibraryResult.browseFile() : this._(browseFile: true);

  final FamilyAssetFile? asset;
  final bool browseFile;
}

/// Compact family browser used from inside an open BIM project.
///
/// This widget intentionally does not know about the viewport or the native
/// engine. It is a library surface only; the caller decides how to place the
/// selected asset and whether a host wall is required.
class FamilyLibraryDialog extends StatefulWidget {
  const FamilyLibraryDialog({
    super.key,
    required this.assets,
  });

  final List<FamilyAssetFile> assets;

  static Future<FamilyLibraryResult?> show(
    BuildContext context, {
    required List<FamilyAssetFile> assets,
  }) {
    return showDialog<FamilyLibraryResult>(
      context: context,
      builder: (_) => FamilyLibraryDialog(assets: assets),
    );
  }

  @override
  State<FamilyLibraryDialog> createState() => _FamilyLibraryDialogState();
}

class _FamilyLibraryDialogState extends State<FamilyLibraryDialog> {
  FamilyCategory? _category;
  FamilyAssetFile? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.assets.isEmpty ? null : widget.assets.first;
  }

  List<FamilyAssetFile> get _filtered {
    return widget.assets.where((asset) {
      final categoryMatches =
          _category == null || asset.document.category == _category;
      return categoryMatches;
    }).toList(growable: false);
  }

  List<FamilyCategory> get _availableCategories {
    final categories = <FamilyCategory>[];
    for (final category in FamilyCategory.values) {
      if (widget.assets.any((asset) => asset.document.category == category)) {
        categories.add(category);
      }
    }
    return categories;
  }

  void _syncSelectedAsset() {
    final visible = _filtered;
    if (_selected == null ||
        !visible.any((asset) => asset.document.id == _selected!.document.id)) {
      _selected = visible.isEmpty ? null : visible.first;
    }
  }

  void _setCategory(FamilyCategory? value) {
    setState(() {
      _category = value;
      _syncSelectedAsset();
    });
  }

  void _select(FamilyAssetFile asset) {
    setState(() => _selected = asset);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(size.width - 32.0, 1100.0);
    final height = math.min(size.height - 48.0, 760.0);
    final colors = Theme.of(context).colorScheme;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.widgets_outlined, color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Family Library',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        Text(
                          '${widget.assets.length} reusable families · choose a type and place it in this project',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colors.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(
                      const FamilyLibraryResult.browseFile(),
                    ),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Import family'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: _category == null,
                        onSelected: (_) => _setCategory(null),
                      ),
                    ),
                    for (final category in _availableCategories)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(
                            _categoryIcon(category),
                            size: 16,
                          ),
                          label: Text(_categoryLabel(category)),
                          selected: _category == category,
                          onSelected: (selected) =>
                              _setCategory(selected ? category : null),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final browser = _buildBrowser(context, constraints);
                    final details = _buildDetails(context);
                    if (!wide) {
                      return Column(
                        children: <Widget>[
                          Expanded(flex: 5, child: browser),
                          const SizedBox(height: 12),
                          Expanded(flex: 4, child: details),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Expanded(flex: 6, child: browser),
                        const SizedBox(width: 16),
                        SizedBox(width: 310, child: details),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrowser(BuildContext context, BoxConstraints constraints) {
    final assets = _filtered;
    if (assets.isEmpty) {
      return _EmptyLibraryState(onClear: () => _setCategory(null));
    }
    final columns = constraints.maxWidth >= 860 ? 3 : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '${assets.length} result${assets.length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const Spacer(),
            Text(
              'Tap a card to preview',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(right: 2, bottom: 2),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: columns == 3 ? 1.55 : 1.7,
            ),
            itemCount: assets.length,
            itemBuilder: (context, index) => _FamilyLibraryCard(
              asset: assets[index],
              selected: assets[index].document.id == _selected?.document.id,
              onTap: () => _select(assets[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context) {
    final asset = _selected;
    if (asset == null) {
      return const _EmptyLibraryState();
    }
    final document = asset.document;
    final type = document.types.first;
    final hosted = document.category == FamilyCategory.door ||
        document.category == FamilyCategory.window ||
        document.category == FamilyCategory.wallSweep;
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.48),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                height: 150,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: _FamilyLibraryPreviewPainter(
                      mesh:
                          FamilyGeometryEvaluator.evaluateMesh(document, type),
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(_categoryIcon(document.category), color: colors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      document.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${_categoryLabel(document.category)} · ${document.types.length} type${document.types.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              _DetailRow(label: 'Type', value: type.name),
              _DetailRow(
                label: 'Size',
                value: _dimensions(document, type),
              ),
              const SizedBox(height: 10),
              Text(
                document.description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 10),
              if (hosted)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Icon(Icons.info_outline, size: 16, color: colors.primary),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          document.category == FamilyCategory.wallSweep
                              ? 'Wall sweep is hosted on the selected wall and follows its direction.'
                              : 'Doors and windows are hosted openings. Select a solid wall first.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  FamilyLibraryResult.asset(asset),
                ),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Place in project'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FamilyLibraryCard extends StatelessWidget {
  const _FamilyLibraryCard({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final FamilyAssetFile asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final document = asset.document;
    final type = document.types.first;
    return Card(
      margin: EdgeInsets.zero,
      elevation: selected ? 1 : 0,
      color: selected
          ? colors.secondaryContainer
          : colors.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: CustomPaint(
                    painter: _FamilyLibraryPreviewPainter(
                      mesh:
                          FamilyGeometryEvaluator.evaluateMesh(document, type),
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                document.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                type.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({this.onClear});

  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.inventory_2_outlined,
            size: 38,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(height: 10),
          Text(
            'Family library is empty',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (onClear != null) ...<Widget>[
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: const Text('Show all')),
          ],
        ],
      ),
    );
  }
}

class _FamilyLibraryPreviewPainter extends CustomPainter {
  const _FamilyLibraryPreviewPainter({
    required this.mesh,
    required this.color,
  });

  final FamilyEvaluatedMesh mesh;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.vertices.isEmpty || mesh.faces.isEmpty || size.isEmpty) return;

    final projected = <Offset>[
      for (final vertex in mesh.vertices)
        Offset(
          vertex.x - vertex.z * 0.78,
          -vertex.y + (vertex.x + vertex.z) * 0.30,
        ),
    ];
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final point in projected) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    final rangeX = math.max(maxX - minX, 1e-6);
    final rangeY = math.max(maxY - minY, 1e-6);
    final scale = math.min(
      (size.width - 20) / rangeX,
      (size.height - 20) / rangeY,
    );
    final center = Offset(size.width / 2, size.height / 2);
    final projectedCenter = Offset((minX + maxX) / 2, (minY + maxY) / 2);
    final screenPoints = <Offset>[
      for (final point in projected)
        center +
            Offset(
              (point.dx - projectedCenter.dx) * scale,
              (point.dy - projectedCenter.dy) * scale,
            ),
    ];

    final orderedFaces = <int>[
      ...List<int>.generate(mesh.faces.length, (i) => i)
    ];
    orderedFaces.sort((left, right) {
      final leftDepth = _faceDepth(mesh.faces[left]);
      final rightDepth = _faceDepth(mesh.faces[right]);
      return leftDepth.compareTo(rightDepth);
    });
    final edgePaint = Paint()
      ..color = color.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round;
    for (final faceIndex in orderedFaces) {
      final face = mesh.faces[faceIndex];
      if (face.indices.length < 3 ||
          face.indices
              .any((index) => index < 0 || index >= screenPoints.length)) {
        continue;
      }
      final path = Path()
        ..moveTo(screenPoints[face.indices.first].dx,
            screenPoints[face.indices.first].dy);
      for (final index in face.indices.skip(1)) {
        path.lineTo(screenPoints[index].dx, screenPoints[index].dy);
      }
      path.close();
      final fillPaint = Paint()
        ..color = color.withValues(alpha: 0.18 + (faceIndex % 4) * 0.08)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, edgePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _FamilyLibraryPreviewPainter oldDelegate) {
    return oldDelegate.mesh != mesh || oldDelegate.color != color;
  }

  double _faceDepth(FamilyMeshFace face) {
    var depth = 0.0;
    var count = 0;
    for (final index in face.indices) {
      if (index < 0 || index >= mesh.vertices.length) continue;
      final vertex = mesh.vertices[index];
      depth += vertex.x + vertex.z + vertex.y * 0.05;
      count++;
    }
    return count == 0 ? 0.0 : depth / count;
  }
}

double _length(
  FamilyDocument family,
  FamilyTypeDefinition type,
  String parameterId, {
  required double fallback,
}) {
  for (final parameter in family.parameters) {
    if (parameter.id != parameterId) continue;
    final value = type.valueFor(parameter);
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed != null && parsed.isFinite && parsed > 0.0) return parsed;
  }
  return fallback;
}

String _dimensions(FamilyDocument family, FamilyTypeDefinition type) {
  final width = _length(family, type, 'width', fallback: 1.0);
  final depth = _length(family, type, 'depth', fallback: width);
  final height = _length(family, type, 'height', fallback: 1.0);
  return '${_millimetres(width)} × ${_millimetres(depth)} × ${_millimetres(height)} mm';
}

String _millimetres(double value) => (value * 1000).round().toString();

String _categoryLabel(FamilyCategory category) {
  return switch (category) {
    FamilyCategory.genericModel => 'Generic model',
    FamilyCategory.column => 'Column',
    FamilyCategory.door => 'Door',
    FamilyCategory.window => 'Window',
    FamilyCategory.wallSweep => 'Wall sweep',
    FamilyCategory.furniture => 'Furniture',
    FamilyCategory.casework => 'Casework',
    FamilyCategory.stair => 'Stair',
    FamilyCategory.structural => 'Structural',
  };
}

IconData _categoryIcon(FamilyCategory category) {
  return switch (category) {
    FamilyCategory.column ||
    FamilyCategory.structural =>
      Icons.view_column_outlined,
    FamilyCategory.door => Icons.door_front_door_outlined,
    FamilyCategory.window => Icons.window_outlined,
    FamilyCategory.wallSweep => Icons.border_style_outlined,
    FamilyCategory.stair => Icons.stairs_outlined,
    FamilyCategory.casework => Icons.kitchen_outlined,
    FamilyCategory.furniture => Icons.chair_outlined,
    FamilyCategory.genericModel => Icons.view_in_ar_outlined,
  };
}
