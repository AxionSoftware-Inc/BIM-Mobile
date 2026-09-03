import 'package:flutter/foundation.dart';

import '../project_unit_settings.dart';

/// A supported hosted-opening type. Dimensions are catalogued instead of
/// exposed as free-form Inspector fields.
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

  String dimensionsLabelFor(ProjectUnitSettings units) {
    final sill = sillHeightMeters > 0
        ? ' · sill ${units.formatLength(sillHeightMeters)}'
        : '';
    return '${units.formatLength(widthMeters, withUnit: false)} × '
        '${units.formatLength(heightMeters)}$sill';
  }

  String labelFor(ProjectUnitSettings units) =>
      '${label.split(' · ').first} · ${dimensionsLabelFor(units)}';
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
