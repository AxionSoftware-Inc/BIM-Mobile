import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../app_project_storage.dart';
import 'built_in_family_catalog.dart';
import 'family_document.dart';

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
      throw ArgumentError.value(type.id, 'type', 'Type does not belong to family');
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
///
/// This deliberately lives beside family assets rather than in project JSON:
/// favorites and recents are user/library preferences, not BIM model data.
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
/// No project repository or scene serializer is imported here. A family can
/// therefore be saved and later removed from a project without changing the
/// project persistence contract.
abstract final class FamilyFileStore {
  static const String _preferencesFileName = '.family_library_state.json';

  /// Seeds the local library with the curated starter families once. The
  /// files are ordinary family assets after this call and can be edited,
  /// copied or removed independently of project documents.
  static Future<void> ensureBuiltInFamilies() async {
    final directory = await _libraryDirectory();
    final existingIds = <String>{};
    await for (final entity in directory.list()) {
      if (entity is! File ||
          !entity.path.endsWith('.${FamilyDocument.fileExtension}')) {
        continue;
      }
      final document = await _readDocument(entity);
      if (document != null) existingIds.add(document.id);
    }
    for (final family in BuiltInFamilyCatalog.families) {
      if (!existingIds.contains(family.id)) {
        await _saveToLibrary(family);
      }
    }
  }

  static Future<List<FamilyAssetFile>> listStored() async {
    final directory = await _libraryDirectory();
    final assets = <FamilyAssetFile>[];
    await for (final entity in directory.list()) {
      if (entity is! File ||
          !entity.path.endsWith('.${FamilyDocument.fileExtension}')) {
        continue;
      }
      try {
        final document = FamilyDocument.fromJson(
          jsonDecode(await entity.readAsString()),
        );
        if (document != null) {
          assets.add(FamilyAssetFile(document: document, path: entity.path));
        }
      } catch (_) {
        // A partially written family must not prevent the rest of the library
        // from loading.
      }
    }
    assets.sort(
      (left, right) => left.document.name.compareTo(right.document.name),
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
      // Corrupt UI preferences must never make the BIM family library fail.
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
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(
        const JsonEncoder.withIndent('  ').convert(preferences.toJson()),
        flush: true,
      );
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
      }
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<FamilyAssetFile?> open() async {
    const typeGroup = XTypeGroup(
      label: 'BIM family',
      extensions: <String>[FamilyDocument.fileExtension, 'json'],
    );
    final location =
        await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (location == null) return null;
    final text = await File(location.path).readAsString();
    final decoded = jsonDecode(text);
    final document = FamilyDocument.fromJson(decoded);
    if (document == null) {
      throw const FormatException('Selected file is not a valid BIM family.');
    }

    // On Android, "Import family" means add it to the app-owned reusable
    // library, not merely hold a fragile document-provider path for one
    // placement. This makes new content data-driven: adding a .bimfamily does
    // not require changing Dart source or rebuilding the application.
    if (Platform.isAndroid) {
      final storedPath = await _saveToLibrary(document);
      return FamilyAssetFile(document: document, path: storedPath);
    }
    return FamilyAssetFile(document: document, path: location.path);
  }

  /// Loads an instance-referenced family without opening a file picker.
  static Future<FamilyAssetFile?> loadPath(String path) async {
    final normalized = path.trim();
    if (normalized.isEmpty) return null;
    final file = File(normalized);
    try {
      if (!await file.exists()) return null;
      final document = FamilyDocument.fromJson(
        jsonDecode(await file.readAsString()),
      );
      return document == null
          ? null
          : FamilyAssetFile(document: document, path: file.path);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> save(FamilyDocument document) async {
    if (Platform.isAndroid) {
      return _saveToLibrary(document);
    }
    const typeGroup = XTypeGroup(
      label: 'BIM family',
      extensions: <String>[FamilyDocument.fileExtension, 'json'],
    );
    final location = await getSaveLocation(
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
      suggestedName:
          '${document.name.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')}.${FamilyDocument.fileExtension}',
    );
    if (location == null) return null;
    final target = File(location.path);
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(document.toJsonText(), flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
      }
      return target.path;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<String> _saveToLibrary(FamilyDocument document) async {
    final directory = await _libraryDirectory();
    final safeName = document.name
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final fileName = safeName.isEmpty ? 'New_Family' : safeName;
    var target = File(
      '${directory.path}${Platform.pathSeparator}$fileName.${FamilyDocument.fileExtension}',
    );
    var suffix = 2;
    while (await target.exists()) {
      final existing = await _readDocument(target);
      if (existing?.id == document.id) {
        break;
      }
      target = File(
        '${directory.path}${Platform.pathSeparator}${fileName}_$suffix.${FamilyDocument.fileExtension}',
      );
      suffix += 1;
    }
    final temporary = File(
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(document.toJsonText(), flush: true);
      try {
        await temporary.rename(target.path);
      } on FileSystemException {
        if (await target.exists()) await target.delete();
        await temporary.rename(target.path);
      }
      return target.path;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  static Future<Directory> _libraryDirectory() async {
    final root = await AppProjectStorage.projectDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}families',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  static Future<FamilyDocument?> _readDocument(File file) async {
    try {
      return FamilyDocument.fromJson(jsonDecode(await file.readAsString()));
    } catch (_) {
      return null;
    }
  }
}
