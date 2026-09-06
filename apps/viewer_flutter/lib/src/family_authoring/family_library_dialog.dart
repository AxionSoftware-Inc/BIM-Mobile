import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'family_document.dart';
import 'family_editor_v2_page.dart';
import 'family_file_store.dart';
import 'family_geometry.dart';
import 'family_parameter_resolver.dart';

/// Result returned to the project placement flow.
///
/// Library browsing/editing remains inside this dialog; project mutation only
/// starts after the user explicitly chooses a family type and presses Place.
final class FamilyLibraryResult {
  const FamilyLibraryResult._({this.asset, this.browseFile = false});

  const FamilyLibraryResult.asset(FamilyAssetFile value)
      : this._(asset: value);

  const FamilyLibraryResult.browseFile() : this._(browseFile: true);

  final FamilyAssetFile? asset;
  final bool browseFile;
}

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

  late List<FamilyAssetFile> _assets;
  FamilyCategory? _category;
  FamilyAssetFile? _selected;
  String? _selectedTypeId;
  _LibraryScope _scope = _LibraryScope.all;
  FamilyLibraryPreferences _preferences = const FamilyLibraryPreferences();
  bool _preferencesLoaded = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _assets = List<FamilyAssetFile>.of(widget.assets);
    if (_assets.isNotEmpty) _selectAsset(_assets.first, rebuild: false);
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
    final result = _assets.where((asset) {
      final document = asset.document;
      if (_category != null && document.category != _category) return false;
      switch (_scope) {
        case _LibraryScope.all:
          break;
        case _LibraryScope.favorites:
          if (!_preferences.isFavorite(document.id)) return false;
        case _LibraryScope.recent:
          if (!recentRank.containsKey(document.id)) return false;
      }
      if (query.isEmpty) return true;
      final haystack = <String>[
        document.name,
        document.description,
        document.category.name,
        _categoryLabel(document.category),
        for (final type in document.types) type.name,
        for (final parameter in document.parameters) parameter.label,
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
      final preferred = asset.preferredTypeId;
      _selectedTypeId = asset.document.types.any((type) => type.id == preferred)
          ? preferred
          : asset.document.types.first.id;
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
    if (mounted) setState(() => _preferences = next);
    await FamilyFileStore.saveLibraryPreferences(next);
  }

  Future<void> _placeSelected() async {
    final asset = _selected;
    final type = _selectedType;
    if (asset == null || type == null) return;

    final next = _preferences.recordRecent(asset.document.id);
    if (mounted) setState(() => _preferences = next);
    await FamilyFileStore.saveLibraryPreferences(next);
    if (!mounted) return;

    // Preserve stable ids and source file order. The preferred type is an
    // in-memory placement hint only; .bimfamily is not rewritten for browsing.
    Navigator.of(context).pop(
      FamilyLibraryResult.asset(asset.withPreferredType(type)),
    );
  }

  Future<void> _editSelected() async {
    final asset = _selected;
    if (asset == null || _refreshing) return;
    final familyId = asset.document.id;
    final typeId = _selectedTypeId;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FamilyEditorV2Page(
          initialAsset: asset.withPreferredType(_selectedType ?? asset.preferredType),
        ),
      ),
    );
    if (!mounted) return;
    await _reloadAssets(preferredFamilyId: familyId, preferredTypeId: typeId);
  }

  Future<void> _reloadAssets({
    String? preferredFamilyId,
    String? preferredTypeId,
  }) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      final assets = await FamilyFileStore.listStored();
      if (!mounted) return;
      _previewCache.clear();
      FamilyAssetFile? selected;
      if (preferredFamilyId != null) {
        for (final asset in assets) {
          if (asset.document.id == preferredFamilyId) {
            selected = asset;
            break;
          }
        }
      }
      selected ??= assets.isEmpty ? null : assets.first;
      setState(() {
        _assets = List<FamilyAssetFile>.of(assets);
        _selected = selected;
        if (selected == null) {
          _selectedTypeId = null;
        } else if (selected.document.types
            .any((type) => type.id == preferredTypeId)) {
          _selectedTypeId = preferredTypeId;
        } else {
          _selectedTypeId = selected.document.types.first.id;
        }
      });
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  FamilyEvaluatedMesh _meshFor(
    FamilyDocument document,
    FamilyTypeDefinition type,
  ) {
    final key = '${document.id}\u001f${type.id}\u001f${document.schemaVersion}';
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
        constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 780),
        child: Column(
          children: <Widget>[
            _buildHeader(context),
            Divider(height: 1, color: colors.outlineVariant),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 840;
                  if (compact) {
                    return Column(
                      children: <Widget>[
                        Expanded(child: _buildLibraryPane(context, assets)),
                        if (_selected != null)
                          SizedBox(height: 300, child: _buildDetails(context)),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SizedBox(
                        width: 470,
                        child: _buildLibraryPane(context, assets),
                      ),
                      VerticalDivider(width: 1, color: colors.outlineVariant),
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
                  '${_assets.length} reusable families · choose a family and type',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (_refreshing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _refreshing
                ? null
                : () => Navigator.of(context).pop(
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
              hintText: 'Search families, types or parameters',
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
              _scopeChip(_LibraryScope.all, 'All', Icons.apps_outlined),
              const SizedBox(width: 6),
              _scopeChip(_LibraryScope.favorites, 'Favorites', Icons.star_outline),
              const SizedBox(width: 6),
              _scopeChip(_LibraryScope.recent, 'Recent', Icons.history),
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
                    mainAxisExtent: 195,
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

  Widget _scopeChip(_LibraryScope scope, String label, IconData icon) {
    return ChoiceChip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      selected: _scope == scope,
      onSelected: (_) => setState(() => _scope = scope),
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
                    Text(
                      _categoryLabel(document.category),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit family',
                onPressed: _refreshing ? null : _editSelected,
                icon: const Icon(Icons.edit_outlined),
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
              constraints: const BoxConstraints(minHeight: 110),
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
              if (document.parameters.any((parameter) => parameter.hasFormula))
                const _InfoChip(icon: Icons.functions, label: 'Parametric'),
              if (hosted)
                const _InfoChip(icon: Icons.link_outlined, label: 'Hosted'),
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
                      ? 'Select the required host wall before placement.'
                      : 'The next step chooses level and position.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _refreshing ? null : _placeSelected,
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
                    top: 2,
                    right: 2,
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
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_categoryLabel(document.category)} · ${document.types.length} type${document.types.length == 1 ? '' : 's'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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
              size: 42,
            ),
            const SizedBox(height: 10),
            Text(
              preferencesLoaded ? 'No matching families' : 'Loading library...',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (preferencesLoaded) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onClear,
                child: const Text('Clear filters'),
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
      child: Text('Choose a family to inspect and place.'),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}

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
    if (mesh.vertices.isEmpty || mesh.faces.isEmpty ||
        size.width <= 2 || size.height <= 2) {
      return;
    }
    final projected = <Offset>[
      for (final vertex in mesh.vertices)
        Offset(
          vertex.x - vertex.z * 0.48,
          -vertex.y + (vertex.x + vertex.z) * 0.24,
        ),
    ];
    final minX = projected.map((point) => point.dx).reduce(math.min);
    final maxX = projected.map((point) => point.dx).reduce(math.max);
    final minY = projected.map((point) => point.dy).reduce(math.min);
    final maxY = projected.map((point) => point.dy).reduce(math.max);
    final width = math.max(maxX - minX, 0.1);
    final height = math.max(maxY - minY, 0.1);
    final scale = math.max(
      0.01,
      math.min((size.width - 22) / width, (size.height - 22) / height) * 0.78,
    );
    final center = Offset(size.width * 0.5, size.height * 0.55);
    final modelCenter = Offset((minX + maxX) * 0.5, (minY + maxY) * 0.5);
    Offset screen(int index) {
      final point = projected[index];
      return Offset(
        center.dx + (point.dx - modelCenter.dx) * scale,
        center.dy + (point.dy - modelCenter.dy) * scale,
      );
    }

    final outline = Paint()
      ..color = lineColor.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final orderedFaces = <int>[
      for (var index = 0; index < mesh.faces.length; index++) index,
    ];
    // Stable ordering prevents preview faces from visually reordering between
    // rebuilds while filters/search update the grid.
    orderedFaces.sort((a, b) => a.compareTo(b));
    for (final faceIndex in orderedFaces) {
      final face = mesh.faces[faceIndex];
      if (face.indices.length < 3 ||
          !face.indices.every((index) => index >= 0 && index < projected.length)) {
        continue;
      }
      final path = Path();
      final first = screen(face.indices.first);
      path.moveTo(first.dx, first.dy);
      for (final index in face.indices.skip(1)) {
        final point = screen(index);
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = fillColor);
      canvas.drawPath(path, outline);
    }

    final ground = Paint()
      ..color = axisColor.withValues(alpha: 0.45)
      ..strokeWidth = 0.7;
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.86),
      Offset(size.width * 0.82, size.height * 0.86),
      ground,
    );
  }

  @override
  bool shouldRepaint(covariant _FamilyLibraryPreviewPainter oldDelegate) =>
      oldDelegate.mesh != mesh ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.fillColor != fillColor ||
      oldDelegate.axisColor != axisColor;
}

({double width, double depth, double height}) _dimensions(
  FamilyDocument document,
  FamilyTypeDefinition type,
) {
  final resolver = FamilyParameterResolver(document, type);
  double read(String id) {
    try {
      final value = resolver.resolveNumber(id);
      return value.isFinite && value > 0.0 ? value : 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  return (
    width: read('width'),
    depth: read('depth'),
    height: read('height'),
  );
}

String _formatDimension(double value) =>
    value <= 0.0 ? '—' : value.toStringAsFixed(value >= 10 ? 1 : 2);

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
      FamilyCategory.genericModel => Icons.category_outlined,
      FamilyCategory.column => Icons.view_column_outlined,
      FamilyCategory.door => Icons.door_front_door_outlined,
      FamilyCategory.window => Icons.window_outlined,
      FamilyCategory.wallSweep => Icons.linear_scale_outlined,
      FamilyCategory.furniture => Icons.chair_outlined,
      FamilyCategory.casework => Icons.kitchen_outlined,
      FamilyCategory.stair => Icons.stairs_outlined,
      FamilyCategory.structural => Icons.foundation_outlined,
    };
