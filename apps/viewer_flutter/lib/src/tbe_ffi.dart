import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'render_scene_models.dart';

final class TbeScheduleSummary extends ffi.Struct {
  @ffi.Size()
  external int wallRows;
  @ffi.Size()
  external int openingRows;
  @ffi.Size()
  external int roomRows;
  @ffi.Size()
  external int slabRows;
  @ffi.Size()
  external int roofRows;
  @ffi.Size()
  external int columnRows;
  @ffi.Size()
  external int beamRows;
  @ffi.Size()
  external int stairRows;
  @ffi.Size()
  external int floorRows;
  @ffi.Size()
  external int ceilingRows;
  @ffi.Size()
  external int materialTakeoffRows;
}

final class TbeValidationSummary extends ffi.Struct {
  @ffi.Int32()
  external int issueCount;
  @ffi.Int32()
  external int warningCount;
  @ffi.Int32()
  external int errorCount;
}

final class TbeVec2 extends ffi.Struct {
  @ffi.Double()
  external double x;
  @ffi.Double()
  external double y;
}

final class TbeHitTestCandidate extends ffi.Struct {
  @ffi.Uint64()
  external int elementId;
  @ffi.Int32()
  external int elementKind;
  @ffi.Int32()
  external int hitKind;
  @ffi.Double()
  external double distanceMeters;
  @ffi.Int32()
  external int priority;
}

final class TbeHitTestCandidatesResult extends ffi.Struct {
  @ffi.Uint64()
  external int candidateCount;
  external ffi.Pointer<TbeHitTestCandidate> candidates;
}

final class TbeApiException implements Exception {
  TbeApiException(this.message);
  final String message;

  @override
  String toString() => 'TbeApiException: $message';
}

final class ViewerSnapshot {
  ViewerSnapshot({
    required this.projectName,
    required this.engineVersion,
    required this.apiVersion,
    required this.schemaVersion,
    required this.levelId,
    required this.validation,
    required this.schedule,
    required this.svgPath,
    required this.packagePath,
    required this.validationMessages,
  });

  final String projectName;
  final String engineVersion;
  final String apiVersion;
  final int schemaVersion;
  final int levelId;
  final ValidationSummary validation;
  final ScheduleSummary schedule;
  final String svgPath;
  final String packagePath;
  final List<String> validationMessages;
}

final class ScheduleSummary {
  ScheduleSummary({
    required this.wallRows,
    required this.openingRows,
    required this.roomRows,
    required this.slabRows,
    required this.roofRows,
    required this.columnRows,
    required this.beamRows,
    required this.stairRows,
    required this.floorRows,
    required this.ceilingRows,
    required this.materialTakeoffRows,
  });

  final int wallRows;
  final int openingRows;
  final int roomRows;
  final int slabRows;
  final int roofRows;
  final int columnRows;
  final int beamRows;
  final int stairRows;
  final int floorRows;
  final int ceilingRows;
  final int materialTakeoffRows;
}

final class ValidationSummary {
  ValidationSummary({
    required this.issueCount,
    required this.warningCount,
    required this.errorCount,
  });

  final int issueCount;
  final int warningCount;
  final int errorCount;
}

final class HitCandidateView {
  HitCandidateView({
    required this.elementId,
    required this.elementKind,
    required this.hitKind,
    required this.distanceMeters,
    required this.priority,
  });

  final int elementId;
  final int elementKind;
  final int hitKind;
  final double distanceMeters;
  final int priority;
}

final class ViewerLoadResult {
  ViewerLoadResult({
    required this.snapshot,
    required this.hitCandidates,
  });

  final ViewerSnapshot snapshot;
  final List<HitCandidateView> hitCandidates;
}

typedef _EngineCreateNative = ffi.Pointer<ffi.Void> Function();
typedef _EngineCreateDart = ffi.Pointer<ffi.Void> Function();
typedef _EngineDestroyNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _EngineDestroyDart = void Function(ffi.Pointer<ffi.Void>);
typedef _StringGetterNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _StringGetterDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _ProjectLoadJsonNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef _ProjectLoadJsonDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef _CreateLevelNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Double,
  ffi.Double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateLevelDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  double,
  double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _UpdateLevelNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Pointer<Utf8>,
  ffi.Double,
  ffi.Double,
  ffi.Int32,
  ffi.Int32,
);
typedef _UpdateLevelDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  ffi.Pointer<Utf8>,
  double,
  double,
  int,
  int,
);
typedef _MoveLevelElevationNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Double,
);
typedef _MoveLevelElevationDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  double,
);
typedef _SetWallLevelConstraintsNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Double,
  ffi.Double,
  ffi.Int32,
);
typedef _SetWallLevelConstraintsDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
  double,
  double,
  int,
);
typedef _SetWallAxisNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  TbeVec2,
  TbeVec2,
);
typedef _SetWallAxisDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  TbeVec2,
  TbeVec2,
);
typedef _CreateWallNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Uint64,
  TbeVec2,
  TbeVec2,
  ffi.Double,
  ffi.Double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateWallDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  int,
  TbeVec2,
  TbeVec2,
  double,
  double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateDoorNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Uint64,
  ffi.Double,
  ffi.Double,
  ffi.Double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateDoorDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  int,
  double,
  double,
  double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateWindowNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Uint64,
  ffi.Double,
  ffi.Double,
  ffi.Double,
  ffi.Double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateWindowDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  int,
  double,
  double,
  double,
  double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _SetOpeningLevelLockNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Int32,
);
typedef _SetOpeningLevelLockDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
);
typedef _SetOpeningLevelNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
);
typedef _SetOpeningLevelDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
);
typedef _MoveHostedOpeningNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Double,
);
typedef _MoveHostedOpeningDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  double,
);
typedef _CreateProfileNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Int32,
  ffi.Int32,
  ffi.Uint64,
  ffi.Pointer<TbeVec2>,
  ffi.Size,
  ffi.Pointer<ffi.Uint64>,
  ffi.Size,
  ffi.Int32,
  ffi.Double,
  ffi.Double,
  ffi.Double,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Int32,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateFloorSystemForRoomNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateFloorSystemForRoomDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateCeilingSystemForRoomNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateCeilingSystemForRoomDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  double,
  ffi.Pointer<ffi.Uint64>,
);
typedef _DeleteElementNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
);
typedef _DeleteElementDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
);
typedef _CreateProfileDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
  ffi.Pointer<TbeVec2>,
  int,
  ffi.Pointer<ffi.Uint64>,
  int,
  int,
  double,
  double,
  double,
  int,
  int,
  int,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _ProjectExportPathNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef _ProjectExportPathDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef _ProjectImportPackageNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Int32,
);
typedef _ProjectImportPackageDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  int,
);
typedef _ValidateNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<TbeValidationSummary>,
);
typedef _ValidateDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<TbeValidationSummary>,
);
typedef _ScheduleNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<TbeScheduleSummary>,
);
typedef _ScheduleDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<TbeScheduleSummary>,
);
typedef _HitTestCandidatesNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  TbeVec2,
  ffi.Double,
  ffi.Pointer<TbeHitTestCandidatesResult>,
);
typedef _HitTestCandidatesDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  TbeVec2,
  double,
  ffi.Pointer<TbeHitTestCandidatesResult>,
);
typedef _SchemaVersionNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Int32>,
);
typedef _SchemaVersionDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Int32>,
);
typedef _LastErrorNative = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>);
typedef _LastErrorDart = ffi.Pointer<Utf8> Function(ffi.Pointer<ffi.Void>);
typedef _FreeStringNative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef _FreeStringDart = void Function(ffi.Pointer<Utf8>);
typedef _FreeMemoryNative = ffi.Void Function(ffi.Pointer<ffi.Void>);
typedef _FreeMemoryDart = void Function(ffi.Pointer<ffi.Void>);

class TbeViewerApi {
  TbeViewerApi._(ffi.DynamicLibrary library)
      : _engineCreate =
            library.lookupFunction<_EngineCreateNative, _EngineCreateDart>(
                'tbe_engine_create'),
        _engineDestroy =
            library.lookupFunction<_EngineDestroyNative, _EngineDestroyDart>(
                'tbe_engine_destroy'),
        _getEngineVersion =
            library.lookupFunction<_StringGetterNative, _StringGetterDart>(
                'tbe_get_engine_version'),
        _getApiVersion =
            library.lookupFunction<_StringGetterNative, _StringGetterDart>(
                'tbe_get_api_version'),
        _getSchemaVersion =
            library.lookupFunction<_SchemaVersionNative, _SchemaVersionDart>(
                'tbe_get_schema_version'),
        _projectLoadJson = library.lookupFunction<_ProjectLoadJsonNative,
            _ProjectLoadJsonDart>('tbe_project_load_json'),
        _createLevel =
            library.lookupFunction<_CreateLevelNative, _CreateLevelDart>(
                'tbe_create_level'),
        _updateLevel =
            library.lookupFunction<_UpdateLevelNative, _UpdateLevelDart>(
                'tbe_update_level'),
        _moveLevelElevation = library.lookupFunction<
            _MoveLevelElevationNative,
            _MoveLevelElevationDart>('tbe_move_level_elevation'),
        _setWallLevelConstraints = library.lookupFunction<
                _SetWallLevelConstraintsNative,
                _SetWallLevelConstraintsDart>(
            'tbe_set_wall_level_constraints'),
        _setWallAxis =
            library.lookupFunction<_SetWallAxisNative, _SetWallAxisDart>(
                'tbe_set_wall_axis'),
        _createWall =
            library.lookupFunction<_CreateWallNative, _CreateWallDart>(
                'tbe_create_wall'),
        _createDoor =
            library.lookupFunction<_CreateDoorNative, _CreateDoorDart>(
                'tbe_create_door'),
        _createWindow =
            library.lookupFunction<_CreateWindowNative, _CreateWindowDart>(
                'tbe_create_window'),
        _setOpeningLevelLock = library.lookupFunction<
                _SetOpeningLevelLockNative,
                _SetOpeningLevelLockDart>('tbe_set_opening_level_lock'),
        _setOpeningLevel =
            library.lookupFunction<_SetOpeningLevelNative, _SetOpeningLevelDart>(
                'tbe_set_opening_level'),
        _moveHostedOpening = library.lookupFunction<
                _MoveHostedOpeningNative,
                _MoveHostedOpeningDart>('tbe_move_hosted_opening'),
        _createProfile =
            library.lookupFunction<_CreateProfileNative, _CreateProfileDart>(
                'tbe_create_profile'),
        _createFloorSystemForRoom = library.lookupFunction<
                _CreateFloorSystemForRoomNative,
                _CreateFloorSystemForRoomDart>(
            'tbe_create_floor_system_for_room'),
        _createCeilingSystemForRoom = library.lookupFunction<
                _CreateCeilingSystemForRoomNative,
                _CreateCeilingSystemForRoomDart>(
            'tbe_create_ceiling_system_for_room'),
        _deleteElement =
            library.lookupFunction<_DeleteElementNative, _DeleteElementDart>(
                'tbe_delete_element'),
        _importProjectPackage = library.lookupFunction<
            _ProjectImportPackageNative,
            _ProjectImportPackageDart>('tbe_import_project_package'),
        _validate = library
            .lookupFunction<_ValidateNative, _ValidateDart>('tbe_validate'),
        _generateSchedules =
            library.lookupFunction<_ScheduleNative, _ScheduleDart>(
                'tbe_generate_schedules'),
        _exportSvg = library.lookupFunction<_ProjectExportPathNative,
            _ProjectExportPathDart>('tbe_export_svg'),
        _exportPackage = library.lookupFunction<_ProjectExportPathNative,
            _ProjectExportPathDart>('tbe_export_project_package'),
        _hitTestCandidates = library.lookupFunction<_HitTestCandidatesNative,
            _HitTestCandidatesDart>('tbe_hit_test_candidates'),
        _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
            'tbe_get_last_error'),
        _freeString =
            library.lookupFunction<_FreeStringNative, _FreeStringDart>(
                'tbe_free_string'),
        _freeMemory =
            library.lookupFunction<_FreeMemoryNative, _FreeMemoryDart>(
                'tbe_free_memory');

  factory TbeViewerApi.load() {
    return TbeViewerApi._(_openLibrary());
  }

  static ffi.DynamicLibrary _openLibrary() {
    final overridePath = Platform.environment['TBE_CAPI_PATH'];
    final current = Directory.current.absolute;
    final executableDir = File(Platform.resolvedExecutable).parent.absolute;

    Iterable<Directory> climbRoots(Directory start, int depth) sync* {
      var cursor = start;
      for (var index = 0; index < depth; index += 1) {
        yield cursor;
        final parent = cursor.parent;
        if (parent.path == cursor.path) {
          break;
        }
        cursor = parent;
      }
    }

    final repoLikeRoots = <Directory>{
      ...climbRoots(current, 8),
      ...climbRoots(executableDir, 12),
    };
    final candidates = <String>[
      if (overridePath != null && overridePath.isNotEmpty) overridePath,
      if (Platform.isMacOS) ...<String>[
        '${executableDir.path}/../Frameworks/libtbe_capi.dylib',
        '${executableDir.path}/../Resources/libtbe_capi.dylib',
      ],
      for (final root in repoLikeRoots) ...<String>[
        '${root.path}/build/dev/src/api/libtbe_capi.dylib',
        '${root.path}/build/dev/src/api/Debug/libtbe_capi.dylib',
        '${root.path}/build/dev/src/api/Release/libtbe_capi.dylib',
      ],
      'libtbe_capi.dylib',
    ];
    final attempted = <String>[];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (candidate == 'libtbe_capi.dylib' || file.existsSync()) {
        try {
          return ffi.DynamicLibrary.open(candidate);
        } catch (_) {
          attempted.add(candidate);
          continue;
        }
      }
    }
    throw TbeApiException(
      'Unable to locate libtbe_capi.dylib. Build `tbe_capi_shared`, set TBE_CAPI_PATH, '
      'or place the dylib at build/dev/src/api/libtbe_capi.dylib. Attempted: ${attempted.join(', ')}',
    );
  }

  final _EngineCreateDart _engineCreate;
  final _EngineDestroyDart _engineDestroy;
  final _StringGetterDart _getEngineVersion;
  final _StringGetterDart _getApiVersion;
  final _SchemaVersionDart _getSchemaVersion;
  final _ProjectLoadJsonDart _projectLoadJson;
  final _CreateLevelDart _createLevel;
  final _UpdateLevelDart _updateLevel;
  final _MoveLevelElevationDart _moveLevelElevation;
  final _SetWallLevelConstraintsDart _setWallLevelConstraints;
  final _SetWallAxisDart _setWallAxis;
  final _CreateWallDart _createWall;
  final _CreateDoorDart _createDoor;
  final _CreateWindowDart _createWindow;
  final _SetOpeningLevelLockDart _setOpeningLevelLock;
  final _SetOpeningLevelDart _setOpeningLevel;
  final _MoveHostedOpeningDart _moveHostedOpening;
  final _CreateProfileDart _createProfile;
  final _CreateFloorSystemForRoomDart _createFloorSystemForRoom;
  final _CreateCeilingSystemForRoomDart _createCeilingSystemForRoom;
  final _DeleteElementDart _deleteElement;
  final _ProjectImportPackageDart _importProjectPackage;
  final _ValidateDart _validate;
  final _ScheduleDart _generateSchedules;
  final _ProjectExportPathDart _exportSvg;
  final _ProjectExportPathDart _exportPackage;
  final _HitTestCandidatesDart _hitTestCandidates;
  final _LastErrorDart _lastError;
  final _FreeStringDart _freeString;
  final _FreeMemoryDart _freeMemory;

  ffi.Pointer<ffi.Void> createSession() {
    final handle = _engineCreate();
    if (handle == ffi.nullptr) {
      throw TbeApiException('Failed to create engine session');
    }
    return handle;
  }

  void destroySession(ffi.Pointer<ffi.Void> handle) => _engineDestroy(handle);

  String _readOwnedString(
    ffi.Pointer<ffi.Void> handle,
    int Function(ffi.Pointer<ffi.Void>, ffi.Pointer<ffi.Pointer<Utf8>>) fn,
  ) {
    final out = calloc<ffi.Pointer<Utf8>>();
    try {
      _check(handle, fn(handle, out));
      final value = out.value.toDartString();
      _freeString(out.value);
      return value;
    } finally {
      calloc.free(out);
    }
  }

  String getEngineVersion(ffi.Pointer<ffi.Void> handle) =>
      _readOwnedString(handle, _getEngineVersion);
  String getApiVersion(ffi.Pointer<ffi.Void> handle) =>
      _readOwnedString(handle, _getApiVersion);

  int getSchemaVersion(ffi.Pointer<ffi.Void> handle) {
    final out = calloc<ffi.Int32>();
    try {
      _check(handle, _getSchemaVersion(handle, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void loadProjectJson(ffi.Pointer<ffi.Void> handle, String json) {
    final jsonPtr = json.toNativeUtf8();
    try {
      _check(handle, _projectLoadJson(handle, jsonPtr));
    } finally {
      calloc.free(jsonPtr);
    }
  }

  int createLevel(
    ffi.Pointer<ffi.Void> handle,
    String name,
    double elevationMeters,
    double defaultWallHeightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createLevel(
          handle,
          namePtr,
          elevationMeters,
          defaultWallHeightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(out);
    }
  }

  void updateLevel(
    ffi.Pointer<ffi.Void> handle,
    int levelId, {
    String? name,
    double? elevationMeters,
    double? defaultWallHeightMeters,
  }) {
    final namePtr = (name ?? '').toNativeUtf8();
    try {
      _check(
        handle,
        _updateLevel(
          handle,
          levelId,
          namePtr,
          elevationMeters ?? 0.0,
          defaultWallHeightMeters ?? 0.0,
          elevationMeters == null ? 0 : 1,
          defaultWallHeightMeters == null ? 0 : 1,
        ),
      );
    } finally {
      calloc.free(namePtr);
    }
  }

  void moveLevelElevation(
    ffi.Pointer<ffi.Void> handle,
    int levelId,
    double elevationMeters,
  ) {
    _check(handle, _moveLevelElevation(handle, levelId, elevationMeters));
  }

  void setWallLevelConstraints(
    ffi.Pointer<ffi.Void> handle, {
    required int wallId,
    required int baseLevelId,
    required int topLevelId,
    required double baseOffsetMeters,
    required double topOffsetMeters,
    required int heightMode,
  }) {
    _check(
      handle,
      _setWallLevelConstraints(
        handle,
        wallId,
        baseLevelId,
        topLevelId,
        baseOffsetMeters,
        topOffsetMeters,
        heightMode,
      ),
    );
  }

  void setWallAxis(
    ffi.Pointer<ffi.Void> handle, {
    required int wallId,
    required double startX,
    required double startY,
    required double endX,
    required double endY,
  }) {
    final start = calloc<TbeVec2>();
    final end = calloc<TbeVec2>();
    start.ref
      ..x = startX
      ..y = startY;
    end.ref
      ..x = endX
      ..y = endY;
    try {
      _check(handle, _setWallAxis(handle, wallId, start.ref, end.ref));
    } finally {
      calloc.free(start);
      calloc.free(end);
    }
  }

  int createWall(
    ffi.Pointer<ffi.Void> handle,
    String name,
    int levelId,
    double startX,
    double startY,
    double endX,
    double endY,
    double thicknessMeters,
    double heightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    final start = calloc<TbeVec2>();
    final end = calloc<TbeVec2>();
    start.ref
      ..x = startX
      ..y = startY;
    end.ref
      ..x = endX
      ..y = endY;
    try {
      _check(
        handle,
        _createWall(
          handle,
          namePtr,
          levelId,
          start.ref,
          end.ref,
          thicknessMeters,
          heightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(start);
      calloc.free(end);
      calloc.free(out);
    }
  }

  int createDoor(
    ffi.Pointer<ffi.Void> handle,
    String name,
    int hostWallId,
    double offsetMeters,
    double widthMeters,
    double heightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createDoor(
          handle,
          namePtr,
          hostWallId,
          offsetMeters,
          widthMeters,
          heightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(out);
    }
  }

  int createWindow(
    ffi.Pointer<ffi.Void> handle,
    String name,
    int hostWallId,
    double offsetMeters,
    double widthMeters,
    double heightMeters,
    double sillHeightMeters,
  ) {
    final namePtr = name.toNativeUtf8();
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createWindow(
          handle,
          namePtr,
          hostWallId,
          offsetMeters,
          widthMeters,
          heightMeters,
          sillHeightMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(namePtr);
      calloc.free(out);
    }
  }

  void setOpeningLevelLock(
    ffi.Pointer<ffi.Void> handle,
    int openingId,
    bool locked,
  ) {
    _check(handle, _setOpeningLevelLock(handle, openingId, locked ? 1 : 0));
  }

  void setOpeningLevel(
    ffi.Pointer<ffi.Void> handle,
    int openingId,
    int levelId,
  ) {
    _check(handle, _setOpeningLevel(handle, openingId, levelId));
  }

  void moveHostedOpening(
    ffi.Pointer<ffi.Void> handle,
    int openingId,
    double offsetMeters,
  ) {
    _check(handle, _moveHostedOpening(handle, openingId, offsetMeters));
  }

  List<int> createProfile(
    ffi.Pointer<ffi.Void> handle, {
    required int targetKind,
    required int draftMode,
    required int levelId,
    required List<RenderScenePoint> points,
    required List<int> wallIds,
    required bool closed,
    required double thicknessMeters,
    required double heightMeters,
    required double verticalOffsetMeters,
    required int materialId,
    required int assemblyId,
    required int roofType,
  }) {
    final pointBuffer = calloc<TbeVec2>(points.length);
    for (var i = 0; i < points.length; i += 1) {
      pointBuffer[i]
        ..x = points[i].x
        ..y = points[i].y;
    }
    final wallBuffer = calloc<ffi.Uint64>(wallIds.length);
    for (var i = 0; i < wallIds.length; i += 1) {
      wallBuffer[i] = wallIds[i];
    }
    final firstId = calloc<ffi.Uint64>();
    final count = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createProfile(
          handle,
          targetKind,
          draftMode,
          levelId,
          pointBuffer,
          points.length,
          wallBuffer,
          wallIds.length,
          closed ? 1 : 0,
          thicknessMeters,
          heightMeters,
          verticalOffsetMeters,
          materialId,
          assemblyId,
          roofType,
          firstId,
          count,
        ),
      );
      if (count.value == 0) {
        return const <int>[];
      }
      return <int>[firstId.value];
    } finally {
      calloc.free(pointBuffer);
      calloc.free(wallBuffer);
      calloc.free(firstId);
      calloc.free(count);
    }
  }

  int createFloorSystemForRoom(
    ffi.Pointer<ffi.Void> handle,
    int roomId,
    int assemblyId,
  ) {
    final out = calloc<ffi.Uint64>();
    try {
      _check(handle, _createFloorSystemForRoom(handle, roomId, assemblyId, out));
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  int createCeilingSystemForRoom(
    ffi.Pointer<ffi.Void> handle,
    int roomId,
    int assemblyId,
    double heightOffsetMeters,
  ) {
    final out = calloc<ffi.Uint64>();
    try {
      _check(
        handle,
        _createCeilingSystemForRoom(
          handle,
          roomId,
          assemblyId,
          heightOffsetMeters,
          out,
        ),
      );
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  void deleteElement(ffi.Pointer<ffi.Void> handle, int elementId) {
    _check(handle, _deleteElement(handle, elementId));
  }

  void importProjectPackage(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _importProjectPackage(handle, pathPtr, 2));
    } finally {
      calloc.free(pathPtr);
    }
  }

  ValidationSummary validate(ffi.Pointer<ffi.Void> handle) {
    final summary = calloc<TbeValidationSummary>();
    try {
      _check(handle, _validate(handle, summary));
      return ValidationSummary(
        issueCount: summary.ref.issueCount,
        warningCount: summary.ref.warningCount,
        errorCount: summary.ref.errorCount,
      );
    } finally {
      calloc.free(summary);
    }
  }

  ScheduleSummary schedules(ffi.Pointer<ffi.Void> handle) {
    final summary = calloc<TbeScheduleSummary>();
    try {
      _check(handle, _generateSchedules(handle, summary));
      return ScheduleSummary(
        wallRows: summary.ref.wallRows,
        openingRows: summary.ref.openingRows,
        roomRows: summary.ref.roomRows,
        slabRows: summary.ref.slabRows,
        roofRows: summary.ref.roofRows,
        columnRows: summary.ref.columnRows,
        beamRows: summary.ref.beamRows,
        stairRows: summary.ref.stairRows,
        floorRows: summary.ref.floorRows,
        ceilingRows: summary.ref.ceilingRows,
        materialTakeoffRows: summary.ref.materialTakeoffRows,
      );
    } finally {
      calloc.free(summary);
    }
  }

  void exportSvg(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _exportSvg(handle, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  void exportPackage(ffi.Pointer<ffi.Void> handle, String path) {
    final pathPtr = path.toNativeUtf8();
    try {
      _check(handle, _exportPackage(handle, pathPtr));
    } finally {
      calloc.free(pathPtr);
    }
  }

  List<HitCandidateView> hitTestCandidates(
    ffi.Pointer<ffi.Void> handle,
    int levelId,
    double x,
    double y, {
    double toleranceMeters = 0.25,
  }) {
    final result = calloc<TbeHitTestCandidatesResult>();
    final point = calloc<TbeVec2>();
    point.ref
      ..x = x
      ..y = y;
    try {
      _check(
          handle,
          _hitTestCandidates(
              handle, levelId, point.ref, toleranceMeters, result));
      final count = result.ref.candidateCount;
      final views = <HitCandidateView>[];
      for (var index = 0; index < count; index += 1) {
        final candidate = result.ref.candidates[index];
        views.add(
          HitCandidateView(
            elementId: candidate.elementId,
            elementKind: candidate.elementKind,
            hitKind: candidate.hitKind,
            distanceMeters: candidate.distanceMeters,
            priority: candidate.priority,
          ),
        );
      }
      return views;
    } finally {
      if (result.ref.candidates != ffi.nullptr) {
        _freeMemory(result.ref.candidates.cast());
      }
      calloc.free(result);
      calloc.free(point);
    }
  }

  String lastError(ffi.Pointer<ffi.Void> handle) =>
      _lastError(handle).toDartString();

  void _check(ffi.Pointer<ffi.Void> handle, int status) {
    if (status != 0) {
      throw TbeApiException(lastError(handle));
    }
  }
}

class ViewerRepository {
  ViewerRepository(this._api);

  final TbeViewerApi _api;
  ffi.Pointer<ffi.Void>? _handle;
  String? _projectName;
  int _activeLevelId = 0;
  String? _currentJson;
  String? _currentJsonPath;
  String? _currentPackagePath;
  String? _lastExportedPackagePath;

  Future<ViewerLoadResult> loadFromJson({
    required String projectName,
    required String json,
    String? sourcePath,
  }) async {
    _projectName = projectName;
    _currentJson = json;
    _currentJsonPath = sourcePath;
    _currentPackagePath = null;
    _activeLevelId = _extractPrimaryLevelIdFromProjectJson(json);
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.loadProjectJson(handle, json);
    final snapshot = await _buildSnapshot(handle, _projectName ?? projectName);
    return ViewerLoadResult(
      snapshot: snapshot,
      hitCandidates: const <HitCandidateView>[],
    );
  }

  Future<ViewerLoadResult> loadFromPackage({
    required String packagePath,
  }) async {
    _projectName = packagePath.split(Platform.pathSeparator).last;
    _currentJson = null;
    _currentJsonPath = null;
    _currentPackagePath = packagePath;
    _activeLevelId = _extractPrimaryLevelIdFromPackage(packagePath);
    _handle ??= _api.createSession();
    final handle = _handle!;
    _api.importProjectPackage(handle, packagePath);
    final snapshot =
        await _buildSnapshot(handle, _projectName ?? 'Imported Package');
    return ViewerLoadResult(
      snapshot: snapshot,
      hitCandidates: const <HitCandidateView>[],
    );
  }

  Future<ViewerLoadResult> reloadCurrent() async {
    if (_currentJsonPath != null) {
      final json = await File(_currentJsonPath!).readAsString();
      return loadFromJson(
        projectName:
            _projectName ?? File(_currentJsonPath!).uri.pathSegments.last,
        json: json,
        sourcePath: _currentJsonPath,
      );
    }
    if (_currentJson != null) {
      return loadFromJson(
          projectName: _projectName ?? 'Reloaded Project', json: _currentJson!);
    }
    if (_currentPackagePath != null) {
      return loadFromPackage(packagePath: _currentPackagePath!);
    }
    throw TbeApiException('No current project to reload');
  }

  Future<ViewerSnapshot> _buildSnapshot(
    ffi.Pointer<ffi.Void> handle,
    String projectName,
  ) async {
    final validation = _api.validate(handle);
    final schedules = _api.schedules(handle);
    final tempDir =
        await Directory.systemTemp.createTemp('tbe_viewer_flutter_');
    final svgPath = '${tempDir.path}/floorplan.svg';
    final packagePath = '${tempDir.path}/package';
    _api.exportSvg(handle, svgPath);
    _api.exportPackage(handle, packagePath);
    _lastExportedPackagePath = packagePath;
    return ViewerSnapshot(
      projectName: _projectName ?? projectName,
      engineVersion: _api.getEngineVersion(handle),
      apiVersion: _api.getApiVersion(handle),
      schemaVersion: _api.getSchemaVersion(handle),
      levelId: _activeLevelId,
      validation: validation,
      schedule: schedules,
      svgPath: svgPath,
      packagePath: packagePath,
      validationMessages: _extractValidationMessages(packagePath),
    );
  }

  Future<RenderSceneLoadResult> currentRenderScene() async {
    final packagePath = _lastExportedPackagePath;
    if (packagePath == null) {
      return const RenderSceneLoadResult(
        scene: null,
        warnings: <String>[],
        errors: <String>['Engine render scene package has not been exported yet.'],
      );
    }
    final renderScenePath = '$packagePath/exports/render_scene.json';
    final json = await File(renderScenePath).readAsString();
    return parseRenderSceneJson(json, source: renderScenePath);
  }

  Future<RenderSceneLoadResult> createLevel({
    required String name,
    required double elevationMeters,
    required double defaultWallHeightMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.createLevel(handle, name, elevationMeters, defaultWallHeightMeters);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> moveLevelElevation({
    required int levelId,
    required double elevationMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.moveLevelElevation(handle, levelId, elevationMeters);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> updateLevel({
    required int levelId,
    String? name,
    double? elevationMeters,
    double? defaultWallHeightMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.updateLevel(
      handle,
      levelId,
      name: name,
      elevationMeters: elevationMeters,
      defaultWallHeightMeters: defaultWallHeightMeters,
    );
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> createWall({
    required String name,
    required int levelId,
    required RenderScenePoint start,
    required RenderScenePoint end,
    required double thicknessMeters,
    required double heightMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.createWall(
      handle,
      name,
      levelId,
      start.x,
      start.y,
      end.x,
      end.y,
      thicknessMeters,
      heightMeters,
    );
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> setWallLevelConstraints({
    required int wallId,
    required int baseLevelId,
    int topLevelId = 0,
    double baseOffsetMeters = 0.0,
    double topOffsetMeters = 0.0,
    int heightMode = 0,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.setWallLevelConstraints(
      handle,
      wallId: wallId,
      baseLevelId: baseLevelId,
      topLevelId: topLevelId,
      baseOffsetMeters: baseOffsetMeters,
      topOffsetMeters: topOffsetMeters,
      heightMode: heightMode,
    );
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> setWallAxis({
    required int wallId,
    required RenderScenePoint start,
    required RenderScenePoint end,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.setWallAxis(
      handle,
      wallId: wallId,
      startX: start.x,
      startY: start.y,
      endX: end.x,
      endY: end.y,
    );
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> createDoor({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.createDoor(handle, name, hostWallId, offsetMeters, widthMeters, heightMeters);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> createWindow({
    required String name,
    required int hostWallId,
    required double offsetMeters,
    required double widthMeters,
    required double heightMeters,
    required double sillHeightMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.createWindow(handle, name, hostWallId, offsetMeters, widthMeters, heightMeters, sillHeightMeters);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> setOpeningLevelLock({
    required int openingId,
    required bool locked,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.setOpeningLevelLock(handle, openingId, locked);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> setOpeningLevel({
    required int openingId,
    required int levelId,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.setOpeningLevel(handle, openingId, levelId);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> moveHostedOpening({
    required int openingId,
    required double offsetMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.moveHostedOpening(handle, openingId, offsetMeters);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> createProfile({
    required int targetKind,
    required int draftMode,
    required int levelId,
    required List<RenderScenePoint> points,
    List<int> wallIds = const <int>[],
    required bool closed,
    required double thicknessMeters,
    required double heightMeters,
    required double verticalOffsetMeters,
    int materialId = 0,
    int assemblyId = 0,
    int roofType = 0,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.createProfile(
      handle,
      targetKind: targetKind,
      draftMode: draftMode,
      levelId: levelId,
      points: points,
      wallIds: wallIds,
      closed: closed,
      thicknessMeters: thicknessMeters,
      heightMeters: heightMeters,
      verticalOffsetMeters: verticalOffsetMeters,
      materialId: materialId,
      assemblyId: assemblyId,
      roofType: roofType,
    );
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> createFloorSystemForRoom({
    required int roomId,
    required int assemblyId,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.createFloorSystemForRoom(handle, roomId, assemblyId);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> createCeilingSystemForRoom({
    required int roomId,
    required int assemblyId,
    required double heightOffsetMeters,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.createCeilingSystemForRoom(
      handle,
      roomId,
      assemblyId,
      heightOffsetMeters,
    );
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  Future<RenderSceneLoadResult> deleteElement({
    required int elementId,
  }) async {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    _api.deleteElement(handle, elementId);
    await _buildSnapshot(handle, _projectName ?? 'Project');
    return currentRenderScene();
  }

  List<HitCandidateView> hitTest(double modelX, double modelY) {
    final handle = _handle;
    if (handle == null) {
      throw TbeApiException('No loaded project');
    }
    return _api.hitTestCandidates(handle, _activeLevelId, modelX, modelY);
  }

  int _extractPrimaryLevelIdFromPackage(String packagePath) {
    final projectJsonFile = File('$packagePath/project.json');
    if (!projectJsonFile.existsSync()) {
      return 0;
    }
    try {
      return _extractPrimaryLevelIdFromProjectJson(
          projectJsonFile.readAsStringSync());
    } catch (_) {
      return 0;
    }
  }

  int _extractPrimaryLevelIdFromProjectJson(String json) {
    try {
      final decoded = jsonDecode(json);
      final document =
          decoded is Map<String, dynamic> ? decoded['document'] : null;
      final elements =
          document is Map<String, dynamic> ? document['elements'] : null;
      if (elements is List) {
        for (final element in elements) {
          if (element is Map<String, dynamic> &&
              element['kind']?.toString().toLowerCase() == 'level') {
            final idValue = element['id'];
            if (idValue is int) {
              return idValue;
            }
            if (idValue is num) {
              return idValue.toInt();
            }
          }
        }
      }
    } catch (_) {
      return 0;
    }
    return 0;
  }

  List<String> _extractValidationMessages(String packagePath) {
    final debugFile = File('$packagePath/debug/debug_report.json');
    if (!debugFile.existsSync()) {
      return const <String>[
        'Validation message list not available from exported debug report.'
      ];
    }
    try {
      final decoded = jsonDecode(debugFile.readAsStringSync());
      final validation =
          decoded is Map<String, dynamic> ? decoded['validation'] : null;
      final issues =
          validation is Map<String, dynamic> ? validation['issues'] : null;
      if (issues is List) {
        return issues
            .map((issue) => issue is Map<String, dynamic>
                ? (issue['message']?.toString() ?? issue.toString())
                : issue.toString())
            .toList();
      }
    } catch (_) {
      return const <String>['Unable to parse debug validation messages.'];
    }
    return const <String>['No validation issues reported.'];
  }

  int? defaultAssemblyId(String kind) {
    final packagePath = _lastExportedPackagePath ?? _currentPackagePath;
    if (packagePath == null) {
      return null;
    }
    final projectJson = File('$packagePath/project.json');
    if (!projectJson.existsSync()) {
      return null;
    }
    try {
      final decoded = jsonDecode(projectJson.readAsStringSync());
      final document =
          decoded is Map<String, dynamic> ? decoded['document'] : null;
      final assemblies =
          document is Map<String, dynamic> ? document['assemblies'] : null;
      if (assemblies is List) {
        for (final entry in assemblies) {
          if (entry is Map<String, dynamic> &&
              entry['kind']?.toString().toLowerCase() == kind.toLowerCase()) {
            final id = entry['assembly_id'];
            if (id is int) {
              return id;
            }
            if (id is num) {
              return id.toInt();
            }
          }
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void dispose() {
    if (_handle != null) {
      _api.destroySession(_handle!);
      _handle = null;
    }
  }
}
