import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../app_project_storage.dart';
import '../atomic_file_writer.dart';
import 'built_in_family_catalog.dart';
import 'family_bundled_catalog.dart';
import 'family_document.dart';
import 'family_validation.dart';

final class FamilyAssetFile {
  const FamilyAssetFile({
    required this.document,
    required this.path,
    this.preferredTypeId,
  });

  final FamilyDocument document;
  final String path;

  /// Optional UI hint carried from Family Library into the existing placement
  /// flow. Old callers still begin with `document.types.first`, so
  /// [withPreferredType] also moves the selected type to the front of an
  /// in-memory document copy. The file on disk is never reordered or mutated.
  final String? preferredTypeId;

  FamilyTypeDefinition get preferredType {
    final preferred = preferredTypeId;
    if (preferred != null) {
      for (final type in document.types) {
        if (type.id == preferred) return type;
      }
    }
    return document.types.first;
  }

  FamilyAssetFile withPreferredType(FamilyTypeDefinition type) {
    if (!document.types.any((candidate) => candidate.id == type.id)) {
      throw ArgumentError.value(
        type.id,
        'type',
        'Type does not belong to family',
      );
    }
    final ordered = <FamilyTypeDefinition>[
      type,
      for (final candidate in document.types)
        if (candidate.id != type.id) candidate,
    ];
    return FamilyAssetFile(
      document: document.copyWith(types: ordered),
      path: path,
      preferredTypeId: type.id,
    );
  }
}

/// Small app-owned UI state for a potentially large family library.
/// Favorites and recents are user/library preferences, not BIM model data.
final class FamilyLibraryPreferences {
  const FamilyLibraryPreferences({
    this.favoriteFamilyIds = const <String>{},
    this.recentFamilyIds = const <String>[],
  });

  final Set<String> favoriteFamilyIds;
  final List<String> recentFamilyIds;

  bool isFavorite(String familyId) => favoriteFamilyIds.contains(familyId);

  FamilyLibraryPreferences toggleFavorite(String familyId) {
    final next = <String>{...favoriteFamilyIds};
    if (!next.add(familyId)) next.remove(familyId);
    return FamilyLibraryPreferences(
      favoriteFamilyIds: Set<String>.unmodifiable(next),
      recentFamilyIds: recentFamilyIds,
    );
  }

  FamilyLibraryPreferences recordRecent(String familyId) {
    final next = <String>[
      familyId,
      for (final id in recentFamilyIds)
        if (id != familyId) id,
    ];
    if (next.length > 24) next.removeRange(24, next.length);
    return FamilyLibraryPreferences(
      favoriteFamilyIds: favoriteFamilyIds,
      recentFamilyIds: List<String>.unmodifiable(next),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'favorites': favoriteFamilyIds.toList()..sort(),
        'recent': recentFamilyIds,
      };

  static FamilyLibraryPreferences fromJson(Object? raw) {
    if (raw is! Map) return const FamilyLibraryPreferences();
    final favorites = <String>{};
    final recent = <String>[];
    final rawFavorites = raw['favorites'];
    if (rawFavorites is List) {
      for (final item in rawFavorites) {
        final id = item.toString().trim();
        if (id.isNotEmpty) favorites.add(id);
      }
    }
    final rawRecent = raw['recent'];
    if (rawRecent is List) {
      for (final item in rawRecent) {
        final id = item.toString().trim();
        if (id.isNotEmpty && !recent.contains(id)) recent.add(id);
        if (recent.length >= 24) break;
      }
    }
    return FamilyLibraryPreferences(
      favoriteFamilyIds: Set<String>.unmodifiable(favorites),
      recentFamilyIds: List<String>.unmodifiable(recent),
    );
  }
}

/// File boundary owned by the family module.
///
/// Every file is validated before it enters the reusable library or project
/// placement flow. Invalid/corrupt assets are skipped rather than poisoning the
/// whole catalog.
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

    // Keep the original code catalog for backwards compatibility, while new
    // product content can ship as ordinary assets/families/*.bimfamily files.
    // Stable ids are authoritative across both sources.
    final seedById = <String, FamilyDocument>{};
    void registerSeed(FamilyDocument family, String source) {
      _validateOrThrow(family);
      final existing = seedById[family.id];
      if (existing != null && existing.toJsonText() != family.toJsonText()) {
        throw FormatException(
          'Family seed id "${family.id}" is defined differently by $source.',
        );
      }
      seedById[family.id] = family;
    }

    for (final family in BuiltInFamilyCatalog.families) {
      registerSeed(family, 'BuiltInFamilyCatalog');
    }
    for (final family in await FamilyBundledCatalog.load()) {
      registerSeed(family, 'assets/families');
    }

    for (final family in seedById.values) {
      if (existingIds.contains(family.id)) continue;
      await _saveToLibrary(family);
      existingIds.add(family.id);
    }
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
  ///
  /// "Import family" has the same persistence contract on every platform: the
  /// project never depends on the user leaving the picked source file at its
  /// original path. Stable family id deduplicates/replaces the app-owned copy.
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
    if (Platform.isAndroid) return _saveToLibrary(document);

    const typeGroup = XTypeGroup(
      label: 'BIM family',
      extensions: <String>[FamilyDocument.fileExtension, 'json'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
      suggestedName: '${_safeFileStem(document.name)}.${FamilyDocument.fileExtension}',
    );
    if (location == null) return null;
    final target = File(location.path);
    await _writeDocument(target, document);
    return target.path;
  }

  /// Saves an editor-opened asset back to its known path when possible.
  /// This is the update path used by future/edit-existing library UI; it avoids
  /// creating a new file just because the family display name changed.
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

    // Stable family id is authoritative. Search the whole library first so a
    // rename updates the existing asset instead of creating a duplicate under
    // the new filename.
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
    } catch (error) {
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
