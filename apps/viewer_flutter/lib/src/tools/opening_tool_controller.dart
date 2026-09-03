import 'package:flutter/foundation.dart';

import '../render_scene_models.dart';

/// A supported hosted-opening type. Dimensions are deliberately catalogued
/// instead of exposed as free-form fields in the Inspector.
@immutable
class OpeningPreset {
  const OpeningPreset({
    required this.id,
    required this.label,
    required this.widthMeters,
    required this.heightMeters,
    required this.sillHeightMeters,
  });

  final String id;
  final String label;
  final double widthMeters;
  final double heightMeters;
  final double sillHeightMeters;

  String get dimensionsLabel {
    final sill = sillHeightMeters > 0
        ? ' · sill ${sillHeightMeters.toStringAsFixed(2)} m'
        : '';
    return '${widthMeters.toStringAsFixed(2)} × '
        '${heightMeters.toStringAsFixed(2)} m$sill';
  }
}

const List<OpeningPreset> kDoorOpeningPresets = <OpeningPreset>[
  OpeningPreset(
    id: 'door-single',
    label: 'Single door · 0.90 × 2.10 m',
    widthMeters: 0.90,
    heightMeters: 2.10,
    sillHeightMeters: 0.0,
  ),
  OpeningPreset(
    id: 'door-wide',
    label: 'Wide door · 1.20 × 2.10 m',
    widthMeters: 1.20,
    heightMeters: 2.10,
    sillHeightMeters: 0.0,
  ),
  OpeningPreset(
    id: 'door-double',
    label: 'Double door · 1.80 × 2.10 m',
    widthMeters: 1.80,
    heightMeters: 2.10,
    sillHeightMeters: 0.0,
  ),
];

const List<OpeningPreset> kWindowOpeningPresets = <OpeningPreset>[
  OpeningPreset(
    id: 'window-standard',
    label: 'Standard window · 0.90 × 1.20 m',
    widthMeters: 0.90,
    heightMeters: 1.20,
    sillHeightMeters: 0.90,
  ),
  OpeningPreset(
    id: 'window-wide',
    label: 'Wide window · 1.20 × 1.20 m',
    widthMeters: 1.20,
    heightMeters: 1.20,
    sillHeightMeters: 0.90,
  ),
  OpeningPreset(
    id: 'window-tall',
    label: 'Tall window · 1.20 × 1.50 m',
    widthMeters: 1.20,
    heightMeters: 1.50,
    sillHeightMeters: 0.60,
  ),
  OpeningPreset(
    id: 'window-panoramic',
    label: 'Panoramic window · 1.80 × 1.50 m',
    widthMeters: 1.80,
    heightMeters: 1.50,
    sillHeightMeters: 0.60,
  ),
];

List<OpeningPreset> openingPresetsForKind(String kind) =>
    kind.toLowerCase() == 'window'
        ? kWindowOpeningPresets
        : kDoorOpeningPresets;

/// Returns the closest catalog type for an existing opening. Legacy projects
/// may contain hand-entered dimensions, so they are represented by the
/// nearest supported type until the user explicitly chooses another one.
OpeningPreset openingPresetForValues({
  required String kind,
  required double widthMeters,
  required double heightMeters,
  required double sillHeightMeters,
}) {
  final presets = openingPresetsForKind(kind);
  return presets.reduce((best, candidate) {
    final bestDistance = _openingPresetDistance(
      best,
      widthMeters,
      heightMeters,
      sillHeightMeters,
    );
    final candidateDistance = _openingPresetDistance(
      candidate,
      widthMeters,
      heightMeters,
      sillHeightMeters,
    );
    return candidateDistance < bestDistance ? candidate : best;
  });
}

double _openingPresetDistance(
  OpeningPreset preset,
  double widthMeters,
  double heightMeters,
  double sillHeightMeters,
) {
  final sillWeight = preset.sillHeightMeters == 0 && sillHeightMeters == 0
      ? 0.0
      : (preset.sillHeightMeters - sillHeightMeters).abs();
  return (preset.widthMeters - widthMeters).abs() +
      (preset.heightMeters - heightMeters).abs() +
      sillWeight;
}

/// Draft state shared by door, window and hosted-opening move tools.
class OpeningToolController extends ChangeNotifier {
  RenderSceneObject? _hostWall;
  double _offsetMeters = 1.0;
  double _widthMeters = 0.9;
  double _heightMeters = 2.1;
  double _sillHeightMeters = 0.9;

  RenderSceneObject? get hostWall => _hostWall;
  double get offsetMeters => _offsetMeters;
  double get widthMeters => _widthMeters;
  double get heightMeters => _heightMeters;
  double get sillHeightMeters => _sillHeightMeters;

  void setHostWall(RenderSceneObject? wall) {
    if (identical(_hostWall, wall)) return;
    _hostWall = wall;
    notifyListeners();
  }

  void setOffset(double value) =>
      _set(value, _offsetMeters, (next) => _offsetMeters = next);
  void setWidth(double value) =>
      _set(value, _widthMeters, (next) => _widthMeters = next);
  void setHeight(double value) =>
      _set(value, _heightMeters, (next) => _heightMeters = next);
  void setSillHeight(double value) =>
      _set(value, _sillHeightMeters, (next) => _sillHeightMeters = next);

  /// Restores creation defaults for the selected opening family. Doors and
  /// windows share the same placement controller, but a window should start
  /// as a normal sill window rather than inheriting a full door-height panel.
  void prepareForCreation({required bool window}) {
    _hostWall = null;
    _offsetMeters = 1.0;
    _widthMeters = 0.9;
    _heightMeters = window ? 1.2 : 2.1;
    _sillHeightMeters = window ? 0.9 : 0.0;
    notifyListeners();
  }

  void loadFromMetadata(Map<String, Object?> metadata) {
    _offsetMeters = _number(metadata['offset_meters']) ?? _offsetMeters;
    _widthMeters = _number(metadata['width_meters']) ?? _widthMeters;
    _heightMeters = _number(metadata['height_meters']) ?? _heightMeters;
    _sillHeightMeters =
        _number(metadata['sill_height_meters']) ?? _sillHeightMeters;
    notifyListeners();
  }

  void reset() {
    _hostWall = null;
    _offsetMeters = 1.0;
    _widthMeters = 0.9;
    _heightMeters = 2.1;
    _sillHeightMeters = 0.9;
    notifyListeners();
  }

  void _set(double value, double current, void Function(double) assign) {
    if (!value.isFinite || (value - current).abs() < 1e-9) return;
    assign(value);
    notifyListeners();
  }

  static double? _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
}
