import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';

final class FamilyLibraryResult {
  const FamilyLibraryResult._({this.asset, this.browseFile = false});

  const FamilyLibraryResult.asset(FamilyAssetFile value)
      : this._(asset: value);

  const FamilyLibraryResult.browseFile() : this._(browseFile: true);

  final FamilyAssetFile? asset;
  final bool browseFile;
}

/// Project-side family picker.
///
/// V2 intentionally owns library/navigation UX only. Geometry authoring stays
/// in Family Editor and project mutation stays in FamilyInstanceAdapter.
/// Keeping these boundaries separate lets the catalog grow to hundreds or
/// thousands of assets without coupling search/favorites to the BIM engine.
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

enum _LibraryScope { all, favorites, recent }

class _FamilyLibraryDialogState extends State<FamilyLibraryDialog> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, FamilyEvaluatedMesh> _previewCache =
      <String, FamilyEvaluatedMesh>{};

  FamilyCategory? _category;
  FamilyAssetFile? _selected;
  String? _selectedTypeId;
  _LibraryScope _scope = _LibraryScope.all;
  FamilyLibraryPreferences _preferences = const FamilyLibraryPreferences();
  bool _preferencesLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.assets.isNotEmpty) {
      _selectAsset(widget.assets.first, rebuild: false);
    }
    unawaited(_loadPreferences());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    final preferences = await FamilyFileStore.loadLibraryPreferences();
    if (!mounted) return;
    setState(() {
      _preferences = preferences;
      _preferencesLoaded = true;
    });
  }

  List<FamilyAssetFile> get _visibleAssets {
    final query = _searchController.text.trim().toLowerCase();
    final recentRank = <String, int>{
      for (var index = 0; index < _preferences.recentFamilyIds.length; index++)
        _preferences.recentFamilyIds[index]: index,
    };
    final result = widget.assets.where((asset) {
      final document = asset.document;
      if (_category != null && document.category != _category) return false;
      switch (_scope) {
        case _LibraryScope.all:
          break;
        case _LibraryScope.favorites:
          if (!_preferences.isFavorite(document.id)) return false;
          break;
        case _LibraryScope.recent:
          if (!recentRank.containsKey(document.id)) return false;
          break;
      }
      if (query.isEmpty) return true;
      final haystack = <String>[
        document.name,
        document.description,
        _categoryLabel(document.category),
        document.category.name,
        for (final type in document.types) type.name,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);

    result.sort((left, right) {
      if (_scope == _LibraryScope.recent) {
        final leftRank = recentRank[left.document.id] ?? 1 << 20;
        final rightRank = recentRank[right.document.id] ?? 1 << 20;
        if (leftRank != rightRank) return leftRank.compareTo(rightRank);
      }
      final leftFavorite = _preferences.isFavorite(left.document.id);
      final rightFavorite = _preferences.isFavorite(right.document.id);
      if (leftFavorite != rightFavorite) return leftFavorite ? -1 : 1;
      return left.document.name
          .toLowerCase()
          .compareTo(right.document.name.toLowerCase());
    });
    return result;
  }

  FamilyTypeDefinition? get _selectedType {
    final asset = _selected;
    if (asset == null || asset.document.types.isEmpty) return null;
    final id = _selectedTypeId;
    if (id != null) {
      for (final type in asset.document.types) {
        if (type.id == id) return type;
      }
    }
    return asset.document.types.first;
  }

  void _selectAsset(FamilyAssetFile asset, {bool rebuild = true}) {
    void apply() {
      _selected = asset;
      _selectedTypeId = asset.preferredTypeId ?? asset.document.types.first.id;
    }

    if (rebuild) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _setType(String? typeId) {
    if (typeId == null) return;
    setState(() => _selectedTypeId = typeId);
  }

  Future<void> _toggleFavorite(FamilyAssetFile asset) async {
    final next = _preferences.toggleFavorite(asset.document.id);
    setState(() => _preferences = next);
    await FamilyFileStore.saveLibraryPreferences(next);
  }

  Future<void> _placeSelected() async {
    final asset = _selected;
    final type = _selectedType;
    if (asset == null || type == null) return;

    final next = _preferences.recordRecent(asset.document.id);
    setState(() => _preferences = next);
    await FamilyFileStore.saveLibraryPreferences(next);
    if (!mounted) return;

    // The existing placement dialog historically initializes from
    // document.types.first. Carry the library's explicit type choice forward
    // by returning an in-memory asset whose preferred type is first. The
    // .bimfamily on disk is NOT reordered, and the adapter still persists the
    // stable type id/name on the placed instance.
    Navigator.of(context).pop(
      FamilyLibraryResult.asset(asset.withPreferredType(type)),
    );
  }

  FamilyEvaluatedMesh _meshFor(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    final key = '${document.id}\u001f${type.id}';
    return _previewCache.putIfAbsent(
      key,
      () => FamilyGeometryEvaluator.evaluateMesh(document, type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final assets = _visibleAssets;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120, maxHeight: 760),
        child: Column(
          children: <Widget>[
            _buildHeader(context),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 820;
                  if (compact) {
                    return Column(
                      children: <Widget>[
                        Expanded(child: _buildLibraryPane(context, assets)),
                        if (_selected != null)
                          SizedBox(
                            height: 270,
                            child: _buildDetails(context),
                          ),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 430,
                        child: _buildLibraryPane(context, assets),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: colors.outlineVariant,
                      ),
                      Expanded(child: _buildDetails(context)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.inventory_2_outlined, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Family Library',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  '${widget.assets.length} families · search, choose a type, then place',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(
              const FamilyLibraryResult.browseFile(),
            ),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import family'),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryPane(
    BuildContext context,
    List<FamilyAssetFile> assets,
  ) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Search families or types',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              ChoiceChip(
                label: const Text('All'),
                selected: _scope == _LibraryScope.all,
                onSelected: (_) => setState(() => _scope = _LibraryScope.all),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                avatar: const Icon(Icons.star_outline, size: 17),
                label: const Text('Favorites'),
                selected: _scope == _LibraryScope.favorites,
                onSelected: (_) =>
                    setState(() => _scope = _LibraryScope.favorites),
              ),
              const SizedBox(width: 6),
              ChoiceChip(
                avatar: const Icon(Icons.history, size: 17),
                label: const Text('Recent'),
                selected: _scope == _LibraryScope.recent,
                onSelected: (_) =>
                    setState(() => _scope = _LibraryScope.recent),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              ChoiceChip(
                label: const Text('Any category'),
                selected: _category == null,
                onSelected: (_) => setState(() => _category = null),
              ),
              for (final category in FamilyCategory.values) ...<Widget>[
                const SizedBox(width: 6),
                ChoiceChip(
                  avatar: Icon(_categoryIcon(category), size: 17),
                  label: Text(_categoryLabel(category)),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: assets.isEmpty
              ? _EmptyLibraryState(
                  preferencesLoaded: _preferencesLoaded,
                  onClear: () {
                    _searchController.clear();
                    setState(() {
                      _category = null;
                      _scope = _LibraryScope.all;
                    });
                  },
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 190,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: assets.length,
                  itemBuilder: (context, index) {
                    final asset = assets[index];
                    final type = asset.document.types.first;
                    return _FamilyCard(
                      asset: asset,
                      mesh: _meshFor(asset.document, type),
                      selected: _selected?.document.id == asset.document.id,
                      favorite: _preferences.isFavorite(asset.document.id),
                      onTap: () => _selectAsset(asset),
                      onFavorite: () => unawaited(_toggleFavorite(asset)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildDetails(BuildContext context) {
    final asset = _selected;
    final type = _selectedType;
    if (asset == null || type == null) return const _NoSelectionState();
    final document = asset.document;
    final mesh = _meshFor(document, type);
    final dimensions = _dimensions(document, type);
    final hosted = document.category == FamilyCategory.door ||
        document.category == FamilyCategory.window ||
        document.category == FamilyCategory.wallSweep;
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      document.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _categoryLabel(document.category),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: _preferences.isFavorite(document.id)
                    ? 'Remove favorite'
                    : 'Add favorite',
                onPressed: () => unawaited(_toggleFavorite(asset)),
                icon: Icon(
                  _preferences.isFavorite(document.id)
                      ? Icons.star
                      : Icons.star_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 120),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomPaint(
                painter: _FamilyLibraryPreviewPainter(
                  mesh: mesh,
                  lineColor: colors.primary,
                  fillColor: colors.primary.withValues(alpha: 0.13),
                  axisColor: colors.outlineVariant,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('${document.id}:${type.id}'),
            initialValue: type.id,
            decoration: const InputDecoration(
              labelText: 'Family type',
              prefixIcon: Icon(Icons.tune_outlined),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: document.types
                .map(
                  (candidate) => DropdownMenuItem<String>(
                    value: candidate.id,
                    child: Text(candidate.name),
                  ),
                )
                .toList(growable: false),
            onChanged: _setType,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _InfoChip(
                icon: Icons.straighten,
                label:
                    '${_formatDimension(dimensions.width)} × ${_formatDimension(dimensions.depth)} × ${_formatDimension(dimensions.height)} m',
              ),
              _InfoChip(
                icon: Icons.account_tree_outlined,
                label:
                    '${document.types.length} type${document.types.length == 1 ? '' : 's'}',
              ),
              if (hosted)
                const _InfoChip(
                  icon: Icons.link_outlined,
                  label: 'Hosted',
                ),
              if (mesh.isApproximate)
                const _InfoChip(
                  icon: Icons.warning_amber_outlined,
                  label: 'Approximate preview',
                ),
            ],
          ),
          if (document.description.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              document.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  hosted
                      ? 'Select a host wall before placement.'
                      : 'The next step chooses level and position.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _placeSelected,
                icon: const Icon(Icons.add_location_alt_outlined),
                label: Text('Place ${type.name}'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({
    required this.asset,
    required this.mesh,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
  });

  final FamilyAssetFile asset;
  final FamilyEvaluatedMesh mesh;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final document = asset.document;
    return Card(
      margin: EdgeInsets.zero,
      elevation: selected ? 1 : 0,
      color: selected ? colors.secondaryContainer : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FamilyLibraryPreviewPainter(
                        mesh: mesh,
                        lineColor: colors.primary,
                        fillColor: colors.primary.withValues(alpha: 0.10),
                        axisColor: colors.outlineVariant,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: favorite ? 'Remove favorite' : 'Add favorite',
                      onPressed: onFavorite,
                      icon: Icon(favorite ? Icons.star : Icons.star_outline),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    document.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_categoryLabel(document.category)} · ${document.types.length} type${document.types.length == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _EmptyLibraryState extends StatelessWidget {
  const _EmptyLibraryState({
    required this.preferencesLoaded,
    required this.onClear,
  });

  final bool preferencesLoaded;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              preferencesLoaded ? Icons.search_off : Icons.hourglass_empty,
              size: 36,
            ),
            const SizedBox(height: 10),
            Text(preferencesLoaded
                ? 'No families match these filters.'
                : 'Loading library preferences...'),
            if (preferencesLoaded) ...<Widget>[
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Clear filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoSelectionState extends StatelessWidget {
  const _NoSelectionState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.inventory_2_outlined, size: 42),
          SizedBox(height: 10),
          Text('Choose a family to inspect and place.'),
        ],
      ),
    );
  }
}

/// Cheap cached-mesh preview. The evaluator runs once per family/type in the
/// dialog; scrolling no longer rebuilds the same geometry on every card frame.
class _FamilyLibraryPreviewPainter extends CustomPainter {
  const _FamilyLibraryPreviewPainter({
    required this.mesh,
    required this.lineColor,
    required this.fillColor,
    required this.axisColor,
  });

  final FamilyEvaluatedMesh mesh;
  final Color lineColor;
  final Color fillColor;
  final Color axisColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (mesh.vertices.isEmpty || size.width <= 1 || size.height <= 1) return;

    final projected = <Offset>[
      for (final vertex in mesh.vertices)
        Offset(
          (vertex.x - vertex.z) * 0.82,
          -vertex.y + (vertex.x + vertex.z) * 0.34,
        ),
    ];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final point in projected) {
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
    final width = math.max(maxX - minX, 0.001);
    final height = math.max(maxY - minY, 0.001);
    final scale = math.min(
      (size.width - 24) / width,
      (size.height - 24) / height,
    );
    final modelCenter = Offset((minX + maxX) * 0.5, (minY + maxY) * 0.5);
    final screenCenter = Offset(size.width * 0.5, size.height * 0.52);
    Offset screen(Offset point) =>
        screenCenter + (point - modelCenter) * scale;

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    for (final face in mesh.faces) {
      if (face.indices.length < 3) continue;
      final valid = face.indices
          .where((index) => index >= 0 && index < projected.length)
          .toList(growable: false);
      if (valid.length < 3) continue;
      final path = Path();
      final first = screen(projected[valid.first]);
      path.moveTo(first.dx, first.dy);
      for (final index in valid.skip(1)) {
        final point = screen(projected[index]);
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, fillPaint);
    }

    final edgePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final edges = <String>{};
    for (final face in mesh.faces) {
      if (face.indices.length < 2) continue;
      for (var i = 0; i < face.indices.length; i++) {
        final a = face.indices[i];
        final b = face.indices[(i + 1) % face.indices.length];
        if (a < 0 || b < 0 || a >= projected.length || b >= projected.length) {
          continue;
        }
        final low = math.min(a, b);
        final high = math.max(a, b);
        if (!edges.add('$low:$high')) continue;
        canvas.drawLine(screen(projected[a]), screen(projected[b]), edgePaint);
      }
    }

    final axisPaint = Paint()
      ..color = axisColor.withValues(alpha: 0.65)
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(12, size.height - 12),
      Offset(size.width - 12, size.height - 12),
      axisPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _FamilyLibraryPreviewPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.axisColor != axisColor;
}

({double? width, double? depth, double? height}) _dimensions(
  FamilyDocument document,
  FamilyTypeDefinition type,
) {
  double? value(String id) {
    for (final parameter in document.parameters) {
      if (parameter.id != id) continue;
      final raw = type.valueFor(parameter);
      final parsed = raw is num ? raw.toDouble() : double.tryParse('$raw');
      return parsed != null && parsed.isFinite ? parsed : null;
    }
    return null;
  }

  return (width: value('width'), depth: value('depth'), height: value('height'));
}

String _formatDimension(double? value) =>
    value == null ? '—' : value.toStringAsFixed(value >= 10 ? 1 : 2);

String _categoryLabel(FamilyCategory category) => switch (category) {
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

IconData _categoryIcon(FamilyCategory category) => switch (category) {
      FamilyCategory.genericModel => Icons.widgets_outlined,
      FamilyCategory.column => Icons.view_column_outlined,
      FamilyCategory.door => Icons.door_front_door_outlined,
      FamilyCategory.window => Icons.window_outlined,
      FamilyCategory.wallSweep => Icons.linear_scale_outlined,
      FamilyCategory.furniture => Icons.chair_outlined,
      FamilyCategory.casework => Icons.kitchen_outlined,
      FamilyCategory.stair => Icons.stairs_outlined,
      FamilyCategory.structural => Icons.account_tree_outlined,
    };
