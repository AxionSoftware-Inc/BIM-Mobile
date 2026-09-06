import 'dart:convert';

import 'package:flutter/services.dart';

import 'family_document.dart';
import 'family_validation.dart';

/// Loads code-free Family content shipped under `assets/families/`.
///
/// Any valid `.bimfamily` file added to that asset directory becomes part of
/// the application seed catalog without adding Dart source or touching the
/// built-in catalog class. Runtime library storage remains authoritative after
/// first seed so user edits are never overwritten by a later app launch.
abstract final class FamilyBundledCatalog {
  static const String assetPrefix = 'assets/families/';

  static Future<List<FamilyDocument>> load({AssetBundle? bundle}) async {
    final source = bundle ?? rootBundle;
    final manifest = await AssetManifest.loadFromAssetBundle(source);
    final paths = manifest
        .listAssets()
        .where(
          (path) =>
              path.startsWith(assetPrefix) &&
              path.endsWith('.${FamilyDocument.fileExtension}'),
        )
        .toList(growable: false)
      ..sort();

    final documents = <FamilyDocument>[];
    final byId = <String, FamilyDocument>{};
    for (final path in paths) {
      final document = decodeAsset(
        path,
        await source.loadString(path),
      );
      final existing = byId[document.id];
      if (existing != null) {
        if (existing.toJsonText() != document.toJsonText()) {
          throw FormatException(
            'Bundled Family id "${document.id}" is duplicated by $path.',
          );
        }
        continue;
      }
      byId[document.id] = document;
      documents.add(document);
    }

    documents.sort(
      (left, right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
    return List<FamilyDocument>.unmodifiable(documents);
  }

  /// Pure decoder kept public for packaging/unit tests.
  static FamilyDocument decodeAsset(String assetPath, String source) {
    final Object? raw;
    try {
      raw = jsonDecode(source);
    } catch (error) {
      throw FormatException('Bundled Family $assetPath contains invalid JSON.');
    }
    final document = FamilyDocument.fromJson(raw);
    if (document == null) {
      throw FormatException(
        'Bundled Family $assetPath is not a supported .bimfamily document.',
      );
    }
    final validation = FamilyDocumentValidator.validate(document);
    if (!validation.isValid) {
      throw FormatException(
        'Bundled Family $assetPath is invalid: ${validation.errors.join('; ')}',
      );
    }
    return document;
  }
}
