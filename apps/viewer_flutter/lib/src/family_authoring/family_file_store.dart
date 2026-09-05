import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../app_project_storage.dart';
import 'built_in_family_catalog.dart';
import 'family_document.dart';

final class FamilyAssetFile {
  const FamilyAssetFile({required this.document, required this.path});

  final FamilyDocument document;
  final String path;
}

/// File boundary owned by the family module.
///
/// No project repository or scene serializer is imported here. A family can
/// therefore be saved and later removed from a project without changing the
/// project persistence contract.
abstract final class FamilyFileStore {
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
        (left, right) => left.document.name.compareTo(right.document.name));
    return List<FamilyAssetFile>.unmodifiable(assets);
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
    return FamilyAssetFile(document: document, path: location.path);
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
