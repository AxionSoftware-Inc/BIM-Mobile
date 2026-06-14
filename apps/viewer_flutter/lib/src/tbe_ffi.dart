import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

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
    final repoLikeRoots = <Directory>{
      current,
      current.parent,
      current.parent.parent,
      current.parent.parent.parent,
    };
    final candidates = <String>[
      if (overridePath != null && overridePath.isNotEmpty) overridePath,
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

  void dispose() {
    if (_handle != null) {
      _api.destroySession(_handle!);
      _handle = null;
    }
  }
}
