import 'dart:typed_data';

import 'elements/element_parameter_values.dart';
import 'elements/opening_parameters.dart';
import 'elements/room_parameters.dart';
import 'elements/surface_parameters.dart';
import 'elements/wall_parameters.dart';
import 'render_scene_models.dart';

/// Compact, data-oriented semantic storage for large BIM scenes.
///
/// RenderSceneObject remains an authoring/compatibility facade during the
/// migration, but runtime analytics and spatial indexing can operate on these
/// structure-of-arrays tables instead of retaining one heavyweight object
/// graph per BIM element.
final class BimCompactInstanceStore {
  BimCompactInstanceStore._({
    required this.prototypes,
    required this.instances,
    required this.walls,
    required this.openings,
    required this.surfaces,
    required this.rooms,
  });

  static const int missingId = -1;

  final List<BimPrototype> prototypes;
  final BimSpatialInstanceTable instances;
  final BimWallParameterTable walls;
  final BimOpeningParameterTable openings;
  final BimSurfaceParameterTable surfaces;
  final BimRoomParameterTable rooms;

  int get instanceCount => instances.length;

  /// Single-pass migration boundary from the legacy object scene to compact
  /// typed arrays. Downstream code no longer needs per-instance metadata maps.
  factory BimCompactInstanceStore.fromScene(RenderScene scene) {
    final prototypeRegistry = _PrototypeRegistry();

    final elementIds = <int>[];
    final prototypeIds = <int>[];
    final kindCodes = <int>[];
    final levelIds = <int>[];
    final revisions = <int>[];
    final bounds = <double>[];

    final wallInstanceIndices = <int>[];
    final wallLengths = <double>[];
    final wallThicknesses = <double>[];
    final wallHeights = <double>[];
    final wallBaseOffsets = <double>[];
    final wallTopOffsets = <double>[];

    final openingInstanceIndices = <int>[];
    final openingHostWallIds = <int>[];
    final openingWidths = <double>[];
    final openingHeights = <double>[];
    final openingSills = <double>[];
    final openingOffsets = <double>[];

    final surfaceInstanceIndices = <int>[];
    final surfaceAreas = <double>[];
    final surfaceThicknesses = <double>[];
    final surfaceOffsets = <double>[];

    final roomInstanceIndices = <int>[];
    final roomAreas = <double>[];
    final roomPerimeters = <double>[];

    for (final object in scene.objects) {
      final kind = BimCompactKind.fromSceneKind(object.kindKey);
      final typeKey = _prototypeTypeKey(object, kind);
      final prototypeId = prototypeRegistry.idFor(
        kind: kind,
        typeKey: typeKey,
        materialCategory: object.materialCategory,
      );
      final instanceIndex = elementIds.length;

      elementIds.add(object.elementId ?? missingId);
      prototypeIds.add(prototypeId);
      kindCodes.add(kind.index);
      levelIds.add(object.levelId ?? missingId);
      revisions.add(object.revision);
      bounds.addAll(<double>[
        object.bounds.min.x,
        object.bounds.min.y,
        object.bounds.min.z,
        object.bounds.max.x,
        object.bounds.max.y,
        object.bounds.max.z,
      ]);

      switch (kind) {
        case BimCompactKind.wall:
          final parameters = WallElementParameters.fromObject(object);
          wallInstanceIndices.add(instanceIndex);
          wallLengths.add(_positiveOr(
            parameters.lengthMeters,
            _max2(object.bounds.width, object.bounds.depth),
          ));
          wallThicknesses.add(_positiveOr(
            parameters.thicknessMeters,
            _minPositive(object.bounds.width, object.bounds.depth),
          ));
          wallHeights.add(_positiveOr(
            parameters.heightMeters,
            object.bounds.height,
          ));
          wallBaseOffsets.add(parameters.baseOffsetMeters);
          wallTopOffsets.add(parameters.topOffsetMeters);
          break;
        case BimCompactKind.door:
        case BimCompactKind.window:
          final parameters = OpeningElementParameters.fromObject(object);
          openingInstanceIndices.add(instanceIndex);
          openingHostWallIds.add(parameters.hostWallId ?? missingId);
          openingWidths.add(_positiveOr(
            parameters.widthMeters,
            object.bounds.width,
          ));
          openingHeights.add(_positiveOr(
            parameters.heightMeters,
            object.bounds.height,
          ));
          openingSills.add(parameters.sillHeightMeters ?? 0.0);
          openingOffsets.add(parameters.offsetMeters ?? 0.0);
          break;
        case BimCompactKind.floor:
        case BimCompactKind.slab:
        case BimCompactKind.ceiling:
        case BimCompactKind.roof:
          final parameters = SurfaceElementParameters.fromObject(object);
          surfaceInstanceIndices.add(instanceIndex);
          surfaceAreas.add(_positiveOr(
            parameters.areaSquareMeters,
            object.bounds.width * object.bounds.depth,
          ));
          surfaceThicknesses.add(_positiveOr(
            parameters.thicknessMeters,
            object.bounds.height,
          ));
          surfaceOffsets.add(parameters.verticalOffsetMeters ?? 0.0);
          break;
        case BimCompactKind.room:
          final parameters = RoomElementParameters.fromObject(object);
          roomInstanceIndices.add(instanceIndex);
          roomAreas.add(_positiveOr(
            parameters.areaSquareMeters,
            object.bounds.width * object.bounds.depth,
          ));
          roomPerimeters.add(_positiveOr(
            parameters.perimeterMeters,
            (object.bounds.width + object.bounds.depth) * 2.0,
          ));
          break;
        case BimCompactKind.column:
        case BimCompactKind.beam:
        case BimCompactKind.stair:
        case BimCompactKind.proxy:
        case BimCompactKind.unknown:
          break;
      }
    }

    return BimCompactInstanceStore._(
      prototypes: List<BimPrototype>.unmodifiable(prototypeRegistry.values),
      instances: BimSpatialInstanceTable._(
        elementIds: Int64List.fromList(elementIds),
        prototypeIds: Uint32List.fromList(prototypeIds),
        kindCodes: Uint8List.fromList(kindCodes),
        levelIds: Int32List.fromList(levelIds),
        revisions: Uint32List.fromList(revisions),
        bounds: Float64List.fromList(bounds),
      ),
      walls: BimWallParameterTable._(
        instanceIndices: Uint32List.fromList(wallInstanceIndices),
        lengths: Float64List.fromList(wallLengths),
        thicknesses: Float64List.fromList(wallThicknesses),
        heights: Float64List.fromList(wallHeights),
        baseOffsets: Float64List.fromList(wallBaseOffsets),
        topOffsets: Float64List.fromList(wallTopOffsets),
      ),
      openings: BimOpeningParameterTable._(
        instanceIndices: Uint32List.fromList(openingInstanceIndices),
        hostWallIds: Int64List.fromList(openingHostWallIds),
        widths: Float64List.fromList(openingWidths),
        heights: Float64List.fromList(openingHeights),
        sillHeights: Float64List.fromList(openingSills),
        offsets: Float64List.fromList(openingOffsets),
      ),
      surfaces: BimSurfaceParameterTable._(
        instanceIndices: Uint32List.fromList(surfaceInstanceIndices),
        areas: Float64List.fromList(surfaceAreas),
        thicknesses: Float64List.fromList(surfaceThicknesses),
        verticalOffsets: Float64List.fromList(surfaceOffsets),
      ),
      rooms: BimRoomParameterTable._(
        instanceIndices: Uint32List.fromList(roomInstanceIndices),
        areas: Float64List.fromList(roomAreas),
        perimeters: Float64List.fromList(roomPerimeters),
      ),
    );
  }
}

enum BimCompactKind {
  unknown,
  wall,
  door,
  window,
  room,
  slab,
  floor,
  ceiling,
  roof,
  column,
  beam,
  stair,
  proxy;

  static BimCompactKind fromSceneKind(String value) {
    return switch (value) {
      'wall' => BimCompactKind.wall,
      'door' => BimCompactKind.door,
      'window' => BimCompactKind.window,
      'room' => BimCompactKind.room,
      'slab' => BimCompactKind.slab,
      'floor' => BimCompactKind.floor,
      'ceiling' => BimCompactKind.ceiling,
      'roof' => BimCompactKind.roof,
      'column' => BimCompactKind.column,
      'beam' => BimCompactKind.beam,
      'stair' => BimCompactKind.stair,
      'proxy' => BimCompactKind.proxy,
      _ => BimCompactKind.unknown,
    };
  }
}

/// One shared definition per repeated wall type, door/window family, surface
/// assembly, stair family, etc. Instance-specific values live in packed
/// parameter tables rather than being duplicated in each object.
final class BimPrototype {
  const BimPrototype({
    required this.id,
    required this.kind,
    required this.typeKey,
    required this.materialCategory,
  });

  final int id;
  final BimCompactKind kind;
  final int typeKey;
  final String materialCategory;
}

/// Common columns shared by all BIM instances. Bounds use six consecutive
/// doubles per row: minX/minY/minZ/maxX/maxY/maxZ.
final class BimSpatialInstanceTable {
  const BimSpatialInstanceTable._({
    required this.elementIds,
    required this.prototypeIds,
    required this.kindCodes,
    required this.levelIds,
    required this.revisions,
    required this.bounds,
  });

  final Int64List elementIds;
  final Uint32List prototypeIds;
  final Uint8List kindCodes;
  final Int32List levelIds;
  final Uint32List revisions;
  final Float64List bounds;

  int get length => elementIds.length;

  double minX(int index) => bounds[index * 6];
  double minY(int index) => bounds[index * 6 + 1];
  double minZ(int index) => bounds[index * 6 + 2];
  double maxX(int index) => bounds[index * 6 + 3];
  double maxY(int index) => bounds[index * 6 + 4];
  double maxZ(int index) => bounds[index * 6 + 5];
}

final class BimWallParameterTable {
  const BimWallParameterTable._({
    required this.instanceIndices,
    required this.lengths,
    required this.thicknesses,
    required this.heights,
    required this.baseOffsets,
    required this.topOffsets,
  });

  final Uint32List instanceIndices;
  final Float64List lengths;
  final Float64List thicknesses;
  final Float64List heights;
  final Float64List baseOffsets;
  final Float64List topOffsets;

  int get length => instanceIndices.length;
}

final class BimOpeningParameterTable {
  const BimOpeningParameterTable._({
    required this.instanceIndices,
    required this.hostWallIds,
    required this.widths,
    required this.heights,
    required this.sillHeights,
    required this.offsets,
  });

  final Uint32List instanceIndices;
  final Int64List hostWallIds;
  final Float64List widths;
  final Float64List heights;
  final Float64List sillHeights;
  final Float64List offsets;

  int get length => instanceIndices.length;
}

final class BimSurfaceParameterTable {
  const BimSurfaceParameterTable._({
    required this.instanceIndices,
    required this.areas,
    required this.thicknesses,
    required this.verticalOffsets,
  });

  final Uint32List instanceIndices;
  final Float64List areas;
  final Float64List thicknesses;
  final Float64List verticalOffsets;

  int get length => instanceIndices.length;
}

final class BimRoomParameterTable {
  const BimRoomParameterTable._({
    required this.instanceIndices,
    required this.areas,
    required this.perimeters,
  });

  final Uint32List instanceIndices;
  final Float64List areas;
  final Float64List perimeters;

  int get length => instanceIndices.length;
}

final class _PrototypeRegistry {
  final Map<String, int> _ids = <String, int>{};
  final List<BimPrototype> values = <BimPrototype>[];

  int idFor({
    required BimCompactKind kind,
    required int typeKey,
    required String materialCategory,
  }) {
    final key = '${kind.index}:$typeKey:$materialCategory';
    final existing = _ids[key];
    if (existing != null) return existing;
    final id = values.length;
    _ids[key] = id;
    values.add(BimPrototype(
      id: id,
      kind: kind,
      typeKey: typeKey,
      materialCategory: materialCategory,
    ));
    return id;
  }
}

int _prototypeTypeKey(RenderSceneObject object, BimCompactKind kind) {
  switch (kind) {
    case BimCompactKind.wall:
      return WallElementParameters.fromObject(object).wallTypeId;
    case BimCompactKind.floor:
    case BimCompactKind.slab:
    case BimCompactKind.ceiling:
    case BimCompactKind.roof:
      return SurfaceElementParameters.fromObject(object).assemblyId;
    case BimCompactKind.door:
    case BimCompactKind.window:
      return elementParameterInt(object, 'family_type_id') ??
          elementParameterInt(object, 'type_id') ??
          0;
    case BimCompactKind.stair:
      return elementParameterInt(object, 'stair_type_id') ?? 0;
    case BimCompactKind.column:
    case BimCompactKind.beam:
      return elementParameterInt(object, 'family_type_id') ?? 0;
    case BimCompactKind.room:
    case BimCompactKind.proxy:
    case BimCompactKind.unknown:
      return 0;
  }
}

double _positiveOr(double? value, double fallback) {
  if (value != null && value.isFinite && value > 0) return value;
  if (fallback.isFinite && fallback > 0) return fallback;
  return 0.0;
}

double _max2(double first, double second) => first > second ? first : second;

double _minPositive(double first, double second) {
  if (first <= 0) return second > 0 ? second : 0.0;
  if (second <= 0) return first;
  return first < second ? first : second;
}
