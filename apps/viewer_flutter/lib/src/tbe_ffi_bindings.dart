part of 'tbe_ffi.dart';

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

final class TbeRect2 extends ffi.Struct {
  @ffi.Double()
  external double minX;
  @ffi.Double()
  external double minY;
  @ffi.Double()
  external double maxX;
  @ffi.Double()
  external double maxY;
}

final class TbeElementIdListResult extends ffi.Struct {
  @ffi.Uint64()
  external int count;
  external ffi.Pointer<ffi.Uint64> elementIds;
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
typedef _NearbyRenderSceneNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Int32,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _NearbyRenderSceneDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _SectionRenderSceneNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  TbeVec2,
  TbeVec2,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _SectionRenderSceneDart = int Function(
  ffi.Pointer<ffi.Void>,
  TbeVec2,
  TbeVec2,
  ffi.Pointer<ffi.Pointer<Utf8>>,
);
typedef _SetIntOptionNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Int32,
);
typedef _SetIntOptionDart = int Function(ffi.Pointer<ffi.Void>, int);
typedef _CreateResidentialTemplateNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Int32,
  ffi.Int32,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateResidentialTemplateDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  ffi.Pointer<ffi.Uint64>,
);
typedef _ProjectLoadJsonNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef _ProjectLoadJsonDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef _ProjectNewNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
);
typedef _ProjectNewDart = int Function(
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
typedef _AutoJoinWallsNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _AutoJoinWallsDart = int Function(ffi.Pointer<ffi.Void>);
typedef _TrimExtendWallsNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Int32,
  ffi.Uint64,
  ffi.Int32,
);
typedef _TrimExtendWallsDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
  int,
);
typedef _SetElementAssemblyNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
);
typedef _SetElementAssemblyDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
);
typedef _UpdateRoofPropertiesNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Int32,
  ffi.Int32,
  ffi.Double,
  ffi.Int32,
  ffi.Double,
);
typedef _UpdateRoofPropertiesDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
  double,
  int,
  double,
);
typedef _SetStructuralWallCutNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Int32,
  ffi.Double,
);
typedef _SetStructuralWallCutDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
  double,
);
typedef _SetBeamColumnJoinNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Int32,
);
typedef _SetBeamColumnJoinDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  int,
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
typedef _CreateStairNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
  TbeVec2,
  TbeVec2,
  ffi.Double,
  ffi.Double,
  ffi.Double,
  ffi.Int32,
  ffi.Int32,
  ffi.Pointer<ffi.Uint64>,
);
typedef _CreateStairDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  TbeVec2,
  TbeVec2,
  double,
  double,
  double,
  int,
  int,
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
typedef _SetOpeningLevelConstraintNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  ffi.Uint64,
  ffi.Double,
);
typedef _SetOpeningLevelConstraintDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  int,
  double,
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
typedef _ResizeDoorNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Double, ffi.Double);
typedef _ResizeDoorDart = int Function(
    ffi.Pointer<ffi.Void>, int, double, double);
typedef _ResizeWindowNative = ffi.Int32 Function(
    ffi.Pointer<ffi.Void>, ffi.Uint64, ffi.Double, ffi.Double, ffi.Double);
typedef _ResizeWindowDart = int Function(
    ffi.Pointer<ffi.Void>, int, double, double, double);
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
typedef _DetectRoomsNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _DetectRoomsDart = int Function(
  ffi.Pointer<ffi.Void>,
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
typedef _VoidMutationNative = ffi.Int32 Function(ffi.Pointer<ffi.Void>);
typedef _VoidMutationDart = int Function(ffi.Pointer<ffi.Void>);
typedef _HistoryCountsNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
);
typedef _HistoryCountsDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Uint64>,
  ffi.Pointer<ffi.Uint64>,
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
typedef _ProjectUnitSettingsSetterNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
);
typedef _ProjectUnitSettingsSetterDart = int Function(
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
  ffi.Pointer<Utf8>,
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
typedef _QueryRectNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void>,
  ffi.Uint64,
  TbeRect2,
  ffi.Pointer<TbeElementIdListResult>,
);
typedef _QueryRectDart = int Function(
  ffi.Pointer<ffi.Void>,
  int,
  TbeRect2,
  ffi.Pointer<TbeElementIdListResult>,
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
