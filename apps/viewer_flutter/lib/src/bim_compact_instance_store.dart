import 'dart:typed_data';

import 'elements/element_parameter_values.dart';
import 'elements/opening_parameters.dart';
import 'elements/room_parameters.dart';
import 'elements/surface_parameters.dart';
import 'elements/wall_parameters.dart';
import 'render_scene_models.dart';

/// Compact, data-oriented semantic storage for large BIM scenes.
///
/// Runtime code should prefer this structure-of-arrays representation over a
/// `RenderSceneObject` graph. The legacy object model remains an authoring /
/// compatibility facade while the migration is in progress, but it must not
/// become the long-lived runtime authority for a campus-scale scene.
///
/// Memory policy:
/// * IDs/revisions keep integer precision.
/// * World-space coordinates keep one Float64 origin per scene.
/// * Per-instance bounds and physical parameters are Float32 *relative* to
///   that origin. BIM dimensions are small enough for Float32, while the
///   Float64 origin prevents georeferenced projects from losing world-space
///   precision.
/// * Arrays are allocated at their final size. We deliberately avoid building
///   temporary `List<double>` / `List<int>` columns because boxed Dart numbers
///   can create a much larger transient heap spike than the final typed data.
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

  /// Two-pass migration boundary from the legacy object scene to compact typed
  /// arrays. Pass one only classifies/counts rows. Pass two writes directly
  /// into final buffers, avoiding a second boxed representation at load time.
  factory BimCompactInstanceStore.fromScene(RenderScene scene) {
    final objectCount = scene.objects.length;
    final kindCodes = Uint8List(objectCount);
    var wallCount = 0;
    var openingCount = 0;
    var surfaceCount = 0;
    var roomCount = 0;

    for (var index = 0; index < objectCount; index += 1) {
      final kind = BimCompactKind.fromSceneKind(scene.objects[index].kindKey);
      kindCodes[index] = kind.index;
      switch (kind) {
        case BimCompactKind.wall:
          wallCount += 1;
          break;
        case BimCompactKind.door:
        case BimCompactKind.window:
          openingCount += 1;
          break;
        case BimCompactKind.floor:
        case BimCompactKind.slab:
        case BimCompactKind.ceiling:
        case BimCompactKind.roof:
          surfaceCount += 1;
          break;
        case BimCompactKind.room:
          roomCount += 1;
          break;
        case BimCompactKind.column:
        case BimCompactKind.beam:
        case BimCompactKind.stair:
        case BimCompactKind.proxy:
        case BimCompactKind.unknown:
          break;
      }
    }

    final originX = _finiteOrZero(
      (scene.bounds.min.x + scene.bounds.max.x) * 0.5,
    );
    final originY = _finiteOrZero(
      (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
    );
    final originZ = _finiteOrZero(
      (scene.bounds.min.z + scene.bounds.max.z) * 0.5,
    );

    final elementIds = Int64List(objectCount);
    final prototypeIds = Uint32List(objectCount);
    final levelIds = Int32List(objectCount);
    final revisions = Uint32List(objectCount);
    final bounds = Float32List(objectCount * 6);

    final wallInstanceIndices = Uint32List(wallCount);
    final wallLengths = Float32List(wallCount);
    final wallThicknesses = Float32List(wallCount);
    final wallHeights = Float32List(wallCount);
    final wallBaseOffsets = Float32List(wallCount);
    final wallTopOffsets = Float32List(wallCount);

    final openingInstanceIndices = Uint32List(openingCount);
    final openingHostWallIds = Int64List(openingCount);
    final openingWidths = Float32List(openingCount);
    final openingHeights = Float32List(openingCount);
    final openingSills = Float32List(openingCount);
    final openingOffsets = Float32List(openingCount);

    final surfaceInstanceIndices = Uint32List(surfaceCount);
    final surfaceAreas = Float32List(surfaceCount);
    final surfaceThicknesses = Float32List(surfaceCount);
    final surfaceOffsets = Float32List(surfaceCount);

    final roomInstanceIndices = Uint32List(roomCount);
    final roomAreas = Float32List(roomCount);
    final roomPerimeters = Float32List(roomCount);

    final prototypeRegistry = _PrototypeRegistry();
    var wallRow = 0;
    var openingRow = 0;
    var surfaceRow = 0;
    var roomRow = 0;

    for (var instanceIndex = 0;
        instanceIndex < objectCount;
        instanceIndex += 1) {
      final object = scene.objects[instanceIndex];
      final kind = BimCompactKind.values[kindCodes[instanceIndex]];
      final prototypeId = prototypeRegistry.idFor(
        kind: kind,
        typeKey: _prototypeTypeKey(object, kind),
        materialCategory: object.materialCategory,
      );

      elementIds[instanceIndex] = object.elementId ?? missingId;
      prototypeIds[instanceIndex] = prototypeId;
      levelIds[instanceIndex] = object.levelId ?? missingId;
      revisions[instanceIndex] = object.revision;
      final boundsOffset = instanceIndex * 6;
      bounds[boundsOffset] = object.bounds.min.x - originX;
      bounds[boundsOffset + 1] = object.bounds.min.y - originY;
      bounds[boundsOffset + 2] = object.bounds.min.z - originZ;
      bounds[boundsOffset + 3] = object.bounds.max.x - originX;
      bounds[boundsOffset + 4] = object.bounds.max.y - originY;
      bounds[boundsOffset + 5] = object.bounds.max.z - originZ;

      switch (kind) {
        case BimCompactKind.wall:
          final parameters = WallElementParameters.fromObject(object);
          wallInstanceIndices[wallRow] = instanceIndex;
          wallLengths[wallRow] = _positiveOr(
            parameters.lengthMeters,
            _max2(object.bounds.width, object.bounds.depth),
          );
          wallThicknesses[wallRow] = _positiveOr(
            parameters.thicknessMeters,
            _minPositive(object.bounds.width, object.bounds.depth),
          );
          wallHeights[wallRow] = _positiveOr(
            parameters.heightMeters,
            object.bounds.height,
          );
          wallBaseOffsets[wallRow] = parameters.baseOffsetMeters;
          wallTopOffsets[wallRow] = parameters.topOffsetMeters;
          wallRow += 1;
          break;
        case BimCompactKind.door:
        case BimCompactKind.window:
          final parameters = OpeningElementParameters.fromObject(object);
          openingInstanceIndices[openingRow] = instanceIndex;
          openingHostWallIds[openingRow] =
              parameters.hostWallId ?? missingId;
          openingWidths[openingRow] = _positiveOr(
            parameters.widthMeters,
            object.bounds.width,
          );
          openingHeights[openingRow] = _positiveOr(
            parameters.heightMeters,
            object.bounds.height,
          );
          openingSills[openingRow] = parameters.sillHeightMeters ?? 0.0;
          openingOffsets[openingRow] = parameters.offsetMeters ?? 0.0;
          openingRow += 1;
          break;
        case BimCompactKind.floor:
        case BimCompactKind.slab:
        case BimCompactKind.ceiling:
        case BimCompactKind.roof:
          final parameters = SurfaceElementParameters.fromObject(object);
          surfaceInstanceIndices[surfaceRow] = instanceIndex;
          surfaceAreas[surfaceRow] = _positiveOr(
            parameters.areaSquareMeters,
            object.bounds.width * object.bounds.depth,
          );
          surfaceThicknesses[surfaceRow] = _positiveOr(
            parameters.thicknessMeters,
            object.bounds.height,
          );
          surfaceOffsets[surfaceRow] = parameters.verticalOffsetMeters ?? 0.0;
          surfaceRow += 1;
          break;
        case BimCompactKind.room:
          final parameters = RoomElementParameters.fromObject(object);
          roomInstanceIndices[roomRow] = instanceIndex;
          roomAreas[roomRow] = _positiveOr(
            parameters.areaSquareMeters,
            object.bounds.width * object.bounds.depth,
          );
          roomPerimeters[roomRow] = _positiveOr(
            parameters.perimeterMeters,
            (object.bounds.width + object.bounds.depth) * 2.0,
          );
          roomRow += 1;
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
        originX: originX,
        originY: originY,
        originZ: originZ,
        elementIds: elementIds,
        prototypeIds: prototypeIds,
        kindCodes: kindCodes,
        levelIds: levelIds,
        revisions: revisions,
        bounds: bounds,
      ),
      walls: BimWallParameterTable._(
        instanceIndices: wallInstanceIndices,
        lengths: wallLengths,
        thicknesses: wallThicknesses,
        heights: wallHeights,
        baseOffsets: wallBaseOffsets,
        topOffsets: wallTopOffsets,
      ),
      openings: BimOpeningParameterTable._(
        instanceIndices: openingInstanceIndices,
        hostWallIds: openingHostWallIds,
        widths: openingWidths,
        heights: openingHeights,
        sillHeights: openingSills,
        offsets: openingOffsets,
      ),
      surfaces: BimSurfaceParameterTable._(
        instanceIndices: surfaceInstanceIndices,
        areas: surfaceAreas,
        thicknesses: surfaceThicknesses,
        verticalOffsets: surfaceOffsets,
      ),
      rooms: BimRoomParameterTable._(
        instanceIndices: roomInstanceIndices,
        areas: roomAreas,
        perimeters: roomPerimeters,
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

/// Common columns shared by all BIM instances.
///
/// `bounds` stores six Float32 values per row in local scene coordinates:
/// minX/minY/minZ/maxX/maxY/maxZ. Public accessors restore the Float64 scene
/// origin. Do not expose or persist the local buffer as world coordinates.
final class BimSpatialInstanceTable {
  const BimSpatialInstanceTable._({
    required this.originX,
    required this.originY,
    required this.originZ,
    required this.elementIds,
    required this.prototypeIds,
    required this.kindCodes,
    required this.levelIds,
    required this.revisions,
    required this.bounds,
  });

  final double originX;
  final double originY;
  final double originZ;
  final Int64List elementIds;
  final Uint32List prototypeIds;
  final Uint8List kindCodes;
  final Int32List levelIds;
  final Uint32List revisions;
  final Float32List bounds;

  int get length => elementIds.length;

  double minX(int index) => originX + bounds[index * 6];
  double minY(int index) => originY + bounds[index * 6 + 1];
  double minZ(int index) => originZ + bounds[index * 6 + 2];
  double maxX(int index) => originX + bounds[index * 6 + 3];
  double maxY(int index) => originY + bounds[index * 6 + 4];
  double maxZ(int index) => originZ + bounds[index * 6 + 5];
}

/// Physical wall dimensions are deliberately Float32. They are local BIM
/// measurements rather than global survey coordinates, so Float64 only doubles
/// memory/bandwidth without improving practical authoring precision.
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
  final Float32List lengths;
  final Float32List thicknesses;
  final Float32List heights;
  final Float32List baseOffsets;
  final Float32List topOffsets;

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
  final Float32List widths;
  final Float32List heights;
  final Float32List sillHeights;
  final Float32List offsets;

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
  final Float32List areas;
  final Float32List thicknesses;
  final Float32List verticalOffsets;

  int get length => instanceIndices.length;
}

final class BimRoomParameterTable {
  const BimRoomParameterTable._({
    required this.instanceIndices,
    required this.areas,
    required this.perimeters,
  });

  final Uint32List instanceIndices;
  final Float32List areas;
  final Float32List perimeters;

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

double _finiteOrZero(double value) => value.isFinite ? value : 0.0;

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
