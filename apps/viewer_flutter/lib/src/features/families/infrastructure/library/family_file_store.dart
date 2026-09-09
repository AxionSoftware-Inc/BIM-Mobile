import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../../../../core/infrastructure/io/atomic_file_writer.dart';
import '../../../../core/infrastructure/storage/app_project_storage.dart';
import '../../application/library/family_asset_file.dart';
import '../../application/library/family_library_preferences.dart';
import '../../domain/document/family_document.dart';
import '../../domain/validation/family_validation.dart';
import '../catalog/built_in_family_catalog.dart';
import '../catalog/family_bundled_catalog.dart';

/// Local-file implementation of the reusable Family Library boundary.
///
/// Family semantic models and library preferences live outside this file;
/// this class owns only app storage, file pickers, seeding and validated IO.
abstract final class FamilyFileStore {
  static const String _preferencesFileName = '.family_library_state.json';
  static final SerializedFileWriter _preferencesWriter = SerializedFileWriter();

  static Future<void> ensureBuiltInFamilies() async {
    final directory = await _libraryDirectory();
    final existingIds = <String>{};
    await for (final entity in directory.list()) {
      if (entity is! File || !_isFamilyFile(entity)) continue;
      final document = await _readDocument(entity);
      if (document != null) existingIds.add(document.id);
    }

    final seeds = composeSeedCatalog(
      legacy: BuiltInFamilyCatalog.families,
      bundled: await FamilyBundledCatalog.load(),
    );
    for (final family in seeds) {
      if (existingIds.contains(family.id)) continue;
      await _saveToLibrary(family);
      existingIds.add(family.id);
    }
  }

  /// Bundled assets are authoritative for a stable Family id during the
  /// transition from Dart-defined seeds to code-free `.bimfamily` assets.
  static List<FamilyDocument> composeSeedCatalog({
    required Iterable<FamilyDocument> legacy,
    required Iterable<FamilyDocument> bundled,
  }) {
    final merged = <String, FamilyDocument>{};
    for (final family in legacy) {
      _validateOrThrow(family);
      merged[family.id] = family;
    }

    final bundledById = <String, FamilyDocument>{};
    for (final family in bundled) {
      _validateOrThrow(family);
      final existing = bundledById[family.id];
      if (existing != null && existing.toJsonText() != family.toJsonText()) {
        throw FormatException(
          'Bundled Family id "${family.id}" has conflicting definitions.',
        );
      }
      bundledById[family.id] = family;
    }
    for (final entry in bundledById.entries) {
      merged[entry.key] = entry.value;
    }

    final result = merged.values.toList(growable: false)
      ..sort(
        (left, right) =>
            left.name.toLowerCase().compareTo(right.name.toLowerCase()),
      );
    return List<FamilyDocument>.unmodifiable(result);
  }

  static Future<List<FamilyAssetFile>> listStored() async {
    final directory = await _libraryDirectory();
    final assets = <FamilyAssetFile>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !_isFamilyFile(entity)) continue;
      final document = await _readDocument(entity);
      if (document != null) {
        assets.add(FamilyAssetFile(document: document, path: entity.path));
      }
    }
    assets.sort(
      (left, right) => left.document.name
          .toLowerCase()
          .compareTo(right.document.name.toLowerCase()),
    );
    return List<FamilyAssetFile>.unmodifiable(assets);
  }

  static Future<FamilyLibraryPreferences> loadLibraryPreferences() async {
    final directory = await _libraryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}$_preferencesFileName',
    );
    try {
      if (!await file.exists()) return const FamilyLibraryPreferences();
      return FamilyLibraryPreferences.fromJson(
        jsonDecode(await file.readAsString()),
      );
    } catch (_) {
      return const FamilyLibraryPreferences();
    }
  }

  static Future<void> saveLibraryPreferences(
    FamilyLibraryPreferences preferences,
  ) async {
    final directory = await _libraryDirectory();
    final target = File(
      '${directory.path}${Platform.pathSeparator}$_preferencesFileName',
    );
    await _preferencesWriter.write(
      target,
      const JsonEncoder.withIndent('  ').convert(preferences.toJson()),
    );
  }

  /// Imports one validated external family into app-owned library storage.
  static Future<FamilyAssetFile?> open() async {
    const typeGroup = XTypeGroup(
      label: 'BIM family',
      extensions: <String>[FamilyDocument.fileExtension, 'json'],
    );
    final location =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (location == null) return null;
    final source = File(location.path);
    final document = await _readDocument(source, throwOnInvalid: true);
    if (document == null) {
      throw const FormatException('Selected file is not a valid BIM family.');
    }

    final storedPath = await _saveToLibrary(document);
    return FamilyAssetFile(document: document, path: storedPath);
  }

  /// Loads an instance-referenced family without opening a file picker.
  static Future<FamilyAssetFile?> loadPath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    final file = File(normalized);
    try {
      if (!await file.exists()) return null;
      final document = await _readDocument(file);
      return document == null
          ? null
          : FamilyAssetFile(document: document, path: file.path);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> save(FamilyDocument document) async {
    _validateOrThrow(document);
    return _saveToLibrary(document);
  }

  static Future<String?> exportFile(FamilyDocument document) async {
    _validateOrThrow(document);
    const typeGroup = XTypeGroup(
      label: 'BIM family',
      extensions: <String>[FamilyDocument.fileExtension, 'json'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
      suggestedName:
          '${_safeFileStem(document.name)}.${FamilyDocument.fileExtension}',
    );
    if (location == null) return null;
    final target = File(location.path);
    await _writeDocument(target, document);
    return target.path;
  }

  static Future<String> saveAsset(
    FamilyDocument document, {
    required String existingPath,
  }) async {
    _validateOrThrow(document);
    final normalized = existingPath.trim();
    if (normalized.isEmpty) return _saveToLibrary(document);
    final target = File(normalized);
    final existing = await _readDocument(target);
    if (existing != null && existing.id != document.id) {
      throw const FormatException(
        'Refusing to overwrite a different family asset.',
      );
    }
    await _writeDocument(target, document);
    return target.path;
  }

  static Future<String> _saveToLibrary(FamilyDocument document) async {
    _validateOrThrow(document);
    final directory = await _libraryDirectory();

    final existing = await _findFileByFamilyId(directory, document.id);
    if (existing != null) {
      await _writeDocument(existing, document);
      return existing.path;
    }

    final fileName = _safeFileStem(document.name);
    var target = File(
      '${directory.path}${Platform.pathSeparator}$fileName.${FamilyDocument.fileExtension}',
    );
    var suffix = 2;
    while (await target.exists()) {
      target = File(
        '${directory.path}${Platform.pathSeparator}${fileName}_$suffix.${FamilyDocument.fileExtension}',
      );
      suffix += 1;
    }
    await _writeDocument(target, document);
    return target.path;
  }

  static Future<File?> _findFileByFamilyId(
    Directory directory,
    String familyId,
  ) async {
    await for (final entity in directory.list()) {
      if (entity is! File || !_isFamilyFile(entity)) continue;
      final document = await _readDocument(entity);
      if (document?.id == familyId) return entity;
    }
    return null;
  }

  static Future<void> _writeDocument(
    File target,
    FamilyDocument document,
  ) async {
    _validateOrThrow(document);
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }
    await atomicWriteString(target, document.toJsonText());
  }

  static Future<Directory> _libraryDirectory() async {
    final root = await AppProjectStorage.projectDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}families',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static bool _isFamilyFile(File file) =>
      file.path.endsWith('.${FamilyDocument.fileExtension}');

  static String _safeFileStem(String name) {
    final safe = name
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return safe.isEmpty ? 'New_Family' : safe;
  }

  static Future<FamilyDocument?> _readDocument(
    File file, {
    bool throwOnInvalid = false,
  }) async {
    try {
      final document = FamilyDocument.fromJson(
        jsonDecode(await file.readAsString()),
      );
      if (document == null) {
        if (throwOnInvalid) {
          throw const FormatException('File is not a supported BIM family.');
        }
        return null;
      }
      final validation = FamilyDocumentValidator.validate(document);
      if (!validation.isValid) {
        if (throwOnInvalid) {
          throw FormatException(validation.errors.join('; '));
        }
        return null;
      }
      return document;
    } catch (_) {
      if (throwOnInvalid) rethrow;
      return null;
    }
  }

  static void _validateOrThrow(FamilyDocument document) {
    final validation = FamilyDocumentValidator.validate(document);
    if (!validation.isValid) {
      throw FormatException(validation.errors.join('; '));
    }
  }
}
