import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'async_serial_queue.dart';
import 'app_project_storage.dart';
import 'atomic_file_writer.dart';
import 'elements/wall_parameters.dart';
import 'elements/wall_type_catalog.dart';
import 'native_engine_library_loader.dart';
import 'render_scene_models.dart';
import 'tools/wall_authoring_geometry.dart';
import 'viewer_authoring_gateway.dart';
import 'viewer_bim_cache_gateway.dart';
import 'viewer_engine_contracts.dart';
import 'viewer_project_session.dart';
import 'viewer_scene_gateway.dart';

part 'tbe_ffi_bindings.dart';
part 'tbe_ffi_api_methods.dart';
part 'tbe_repository_state.dart';
part 'tbe_project_persistence_repository.dart';
part 'tbe_scene_query_repository.dart';
part 'tbe_authoring_mutation_repository.dart';
part 'tbe_ffi_repository.dart';

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
        _getRenderSceneJson =
            library.lookupFunction<_StringGetterNative, _StringGetterDart>(
                'tbe_get_render_scene_json'),
        _getRenderSceneJsonNearLevel = library.lookupFunction<
            _NearbyRenderSceneNative,
            _NearbyRenderSceneDart>('tbe_get_render_scene_json_near_level'),
        _getRenderSceneJsonPrimary = library.lookupFunction<
            _PrimaryRenderSceneNative,
            _PrimaryRenderSceneDart>('tbe_get_render_scene_json_primary'),
        _getSectionSceneJson = library.lookupFunction<_SectionRenderSceneNative,
            _SectionRenderSceneDart>('tbe_get_section_scene_json'),
        _setPerformanceProfile =
            library.lookupFunction<_SetIntOptionNative, _SetIntOptionDart>(
                'tbe_set_performance_profile'),
        _setComputeMode =
            library.lookupFunction<_SetIntOptionNative, _SetIntOptionDart>(
                'tbe_set_compute_mode'),
        _createResidentialTemplate = library.lookupFunction<
            _CreateResidentialTemplateNative,
            _CreateResidentialTemplateDart>('tbe_create_residential_template'),
        _createShowcaseTemplate = library.lookupFunction<
            _CreateShowcaseTemplateNative,
            _CreateShowcaseTemplateDart>('tbe_create_showcase_template'),
        _getSchemaVersion =
            library.lookupFunction<_SchemaVersionNative, _SchemaVersionDart>(
                'tbe_get_schema_version'),
        _projectLoadJson = library.lookupFunction<_ProjectLoadJsonNative,
            _ProjectLoadJsonDart>('tbe_project_load_json'),
        _projectNew =
            library.lookupFunction<_ProjectNewNative, _ProjectNewDart>(
                'tbe_project_new'),
        _projectSaveJson =
            library.lookupFunction<_StringGetterNative, _StringGetterDart>(
                'tbe_project_save_json'),
        _createLevel =
            library.lookupFunction<_CreateLevelNative, _CreateLevelDart>(
                'tbe_create_level'),
        _updateLevel =
            library.lookupFunction<_UpdateLevelNative, _UpdateLevelDart>(
                'tbe_update_level'),
        _moveLevelElevation = library.lookupFunction<_MoveLevelElevationNative,
            _MoveLevelElevationDart>('tbe_move_level_elevation'),
        _setWallType =
            library.lookupFunction<_SetWallTypeNative, _SetWallTypeDart>(
                'tbe_set_wall_type'),
        _createWallType =
            library.lookupFunction<_CreateWallTypeNative, _CreateWallTypeDart>(
                'tbe_create_wall_type'),
        _upsertWallTypeForWall = library.lookupFunction<
            _UpsertWallTypeForWallNative,
            _UpsertWallTypeForWallDart>('tbe_upsert_wall_type_for_wall'),
        _setWallLevelConstraints = library.lookupFunction<
            _SetWallLevelConstraintsNative,
            _SetWallLevelConstraintsDart>('tbe_set_wall_level_constraints'),
        _setWallAxis =
            library.lookupFunction<_SetWallAxisNative, _SetWallAxisDart>(
                'tbe_set_wall_axis'),
        _autoJoinWalls =
            library.lookupFunction<_AutoJoinWallsNative, _AutoJoinWallsDart>(
                'tbe_auto_join_walls'),
        _trimExtendWalls = library.lookupFunction<_TrimExtendWallsNative,
            _TrimExtendWallsDart>('tbe_trim_extend_walls'),
        _setElementAssembly = library.lookupFunction<_SetElementAssemblyNative,
            _SetElementAssemblyDart>('tbe_set_element_assembly'),
        _updateRoofProperties = library.lookupFunction<
            _UpdateRoofPropertiesNative,
            _UpdateRoofPropertiesDart>('tbe_update_roof_properties'),
        _setStructuralWallCut = library.lookupFunction<
            _SetStructuralWallCutNative,
            _SetStructuralWallCutDart>('tbe_set_structural_wall_cut'),
        _setBeamColumnJoin = library.lookupFunction<_SetBeamColumnJoinNative,
            _SetBeamColumnJoinDart>('tbe_set_beam_column_join'),
        _createWall =
            library.lookupFunction<_CreateWallNative, _CreateWallDart>(
                'tbe_create_wall'),
        _createCurvedWall = library.lookupFunction<
            _CreateCurvedWallNative,
            _CreateCurvedWallDart>('tbe_create_curved_wall'),
        _createStair =
            library.lookupFunction<_CreateStairNative, _CreateStairDart>(
                'tbe_create_stair'),
        _createDoor =
            library.lookupFunction<_CreateDoorNative, _CreateDoorDart>(
                'tbe_create_door'),
        _createWindow =
            library.lookupFunction<_CreateWindowNative, _CreateWindowDart>(
                'tbe_create_window'),
        _setOpeningLevelLock = library.lookupFunction<
            _SetOpeningLevelLockNative,
            _SetOpeningLevelLockDart>('tbe_set_opening_level_lock'),
        _setOpeningLevel = library.lookupFunction<_SetOpeningLevelNative,
            _SetOpeningLevelDart>('tbe_set_opening_level'),
        _setOpeningLevelConstraint = library.lookupFunction<
            _SetOpeningLevelConstraintNative,
            _SetOpeningLevelConstraintDart>('tbe_set_opening_level_constraint'),
        _moveHostedOpening = library.lookupFunction<_MoveHostedOpeningNative,
            _MoveHostedOpeningDart>('tbe_move_hosted_opening'),
        _resizeDoor =
            library.lookupFunction<_ResizeDoorNative, _ResizeDoorDart>(
                'tbe_resize_door'),
        _resizeWindow =
            library.lookupFunction<_ResizeWindowNative, _ResizeWindowDart>(
                'tbe_resize_window'),
        _updateHostedOpening = library.lookupFunction<
            _UpdateHostedOpeningNative,
            _UpdateHostedOpeningDart>('tbe_update_hosted_opening'),
        _createProfile =
            library.lookupFunction<_CreateProfileNative, _CreateProfileDart>(
                'tbe_create_profile'),
        _createFloorSystemForRoom = library.lookupFunction<
            _CreateFloorSystemForRoomNative,
            _CreateFloorSystemForRoomDart>('tbe_create_floor_system_for_room'),
        _createCeilingSystemForRoom = library.lookupFunction<
                _CreateCeilingSystemForRoomNative,
                _CreateCeilingSystemForRoomDart>(
            'tbe_create_ceiling_system_for_room'),
        _detectRooms =
            library.lookupFunction<_DetectRoomsNative, _DetectRoomsDart>(
                'tbe_detect_rooms'),
        _deleteElement =
            library.lookupFunction<_DeleteElementNative, _DeleteElementDart>(
                'tbe_delete_element'),
        _undo = library
            .lookupFunction<_VoidMutationNative, _VoidMutationDart>('tbe_undo'),
        _redo = library
            .lookupFunction<_VoidMutationNative, _VoidMutationDart>('tbe_redo'),
        _getHistoryCounts =
            library.lookupFunction<_HistoryCountsNative, _HistoryCountsDart>(
                'tbe_get_history_counts'),
        _importProjectPackage = library.lookupFunction<
            _ProjectImportPackageNative,
            _ProjectImportPackageDart>('tbe_import_project_package'),
        _exportIfc = library.lookupFunction<_ProjectExportPathNative,
            _ProjectExportPathDart>('tbe_export_ifc'),
        _importIfc = library.lookupFunction<_ProjectImportPackageNative,
            _ProjectImportPackageDart>('tbe_import_ifc'),
        _compileBimCache =
            library.lookupFunction<_BimCacheNative, _BimCacheDart>(
                'tbe_compile_bim_cache'),
        _inspectBimCache =
            library.lookupFunction<_BimCacheNative, _BimCacheDart>(
                'tbe_inspect_bim_cache'),
        _getUnitSettings =
            library.lookupFunction<_StringGetterNative, _StringGetterDart>(
                'tbe_get_unit_settings'),
        _setUnitSettings = library.lookupFunction<
            _ProjectUnitSettingsSetterNative,
            _ProjectUnitSettingsSetterDart>('tbe_set_unit_settings'),
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
        _queryRect = library
            .lookupFunction<_QueryRectNative, _QueryRectDart>('tbe_query_rect'),
        _lastError = library.lookupFunction<_LastErrorNative, _LastErrorDart>(
            'tbe_get_last_error'),
        _freeString =
            library.lookupFunction<_FreeStringNative, _FreeStringDart>(
                'tbe_free_string'),
        _freeMemory =
            library.lookupFunction<_FreeMemoryNative, _FreeMemoryDart>(
                'tbe_free_memory');

  factory TbeViewerApi.load() {
    return TbeViewerApi._(NativeEngineLibraryLoader.open());
  }

  static Future<void> prepareForCurrentPlatform() =>
      NativeEngineLibraryLoader.prepareForCurrentPlatform();

  final _EngineCreateDart _engineCreate;
  final _EngineDestroyDart _engineDestroy;
  final _StringGetterDart _getEngineVersion;
  final _StringGetterDart _getApiVersion;
  final _StringGetterDart _getRenderSceneJson;
  final _NearbyRenderSceneDart _getRenderSceneJsonNearLevel;
  final _PrimaryRenderSceneDart _getRenderSceneJsonPrimary;
  final _SectionRenderSceneDart _getSectionSceneJson;
  final _SetIntOptionDart _setPerformanceProfile;
  final _SetIntOptionDart _setComputeMode;
  final _CreateResidentialTemplateDart _createResidentialTemplate;
  final _CreateShowcaseTemplateDart _createShowcaseTemplate;
  final _SchemaVersionDart _getSchemaVersion;
  final _ProjectLoadJsonDart _projectLoadJson;
  final _ProjectNewDart _projectNew;
  final _StringGetterDart _projectSaveJson;
  final _CreateLevelDart _createLevel;
  final _UpdateLevelDart _updateLevel;
  final _MoveLevelElevationDart _moveLevelElevation;
  final _SetWallTypeDart _setWallType;
  final _CreateWallTypeDart _createWallType;
  final _UpsertWallTypeForWallDart _upsertWallTypeForWall;
  final _SetWallLevelConstraintsDart _setWallLevelConstraints;
  final _SetWallAxisDart _setWallAxis;
  final _AutoJoinWallsDart _autoJoinWalls;
  final _TrimExtendWallsDart _trimExtendWalls;
  final _SetElementAssemblyDart _setElementAssembly;
  final _UpdateRoofPropertiesDart _updateRoofProperties;
  final _SetStructuralWallCutDart _setStructuralWallCut;
  final _SetBeamColumnJoinDart _setBeamColumnJoin;
  final _CreateWallDart _createWall;
  final _CreateCurvedWallDart _createCurvedWall;
  final _CreateStairDart _createStair;
  final _CreateDoorDart _createDoor;
  final _CreateWindowDart _createWindow;
  final _SetOpeningLevelLockDart _setOpeningLevelLock;
  final _SetOpeningLevelDart _setOpeningLevel;
  final _SetOpeningLevelConstraintDart _setOpeningLevelConstraint;
  final _MoveHostedOpeningDart _moveHostedOpening;
  final _ResizeDoorDart _resizeDoor;
  final _ResizeWindowDart _resizeWindow;
  final _UpdateHostedOpeningDart _updateHostedOpening;
  final _CreateProfileDart _createProfile;
  final _CreateFloorSystemForRoomDart _createFloorSystemForRoom;
  final _CreateCeilingSystemForRoomDart _createCeilingSystemForRoom;
  final _DetectRoomsDart _detectRooms;
  final _DeleteElementDart _deleteElement;
  final _VoidMutationDart _undo;
  final _VoidMutationDart _redo;
  final _HistoryCountsDart _getHistoryCounts;
  final _ProjectImportPackageDart _importProjectPackage;
  final _ProjectExportPathDart _exportIfc;
  final _ProjectImportPackageDart _importIfc;
  final _BimCacheDart _compileBimCache;
  final _BimCacheDart _inspectBimCache;
  final _StringGetterDart _getUnitSettings;
  final _ProjectUnitSettingsSetterDart _setUnitSettings;
  final _ValidateDart _validate;
  final _ScheduleDart _generateSchedules;
  final _ProjectExportPathDart _exportSvg;
  final _ProjectExportPathDart _exportPackage;
  final _HitTestCandidatesDart _hitTestCandidates;
  final _QueryRectDart _queryRect;
  final _LastErrorDart _lastError;
  final _FreeStringDart _freeString;
  final _FreeMemoryDart _freeMemory;
}
