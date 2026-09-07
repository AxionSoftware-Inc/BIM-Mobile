import 'dart:io';

import 'package:flutter/services.dart';

import 'app_project_storage.dart';
import 'atomic_file_writer.dart';

/// A bundled IFC sample that can be opened from the start screen without a
/// network connection. The source IFC is copied to the project cache before
/// the normal import pipeline opens it, so the viewer keeps one local source
/// of truth for both bundled and user-selected IFC files.
class IfcTemplate {
  const IfcTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.fileName,
    required this.sourceUrl,
    required this.kind,
    required this.sizeLabel,
    this.assetPath,
    this.downloadUrl,
  }) : assert(assetPath != null || downloadUrl != null);

  final String id;
  final String title;
  final String subtitle;
  final String meta;
  final String fileName;
  final String sourceUrl;
  final IfcTemplateKind kind;
  final String sizeLabel;
  final String? assetPath;
  final String? downloadUrl;
}

enum IfcTemplateKind { building, structure, infrastructure }

const String _bundledSource = 'bundled: IfcSampleFiles-main';

const List<IfcTemplate> defaultIfcTemplates = <IfcTemplate>[
  IfcTemplate(
    id: 'ifc2s3-duplex-electrical',
    title: 'Duplex Electrical',
    subtitle: 'IFC2x3 duplex electrical systems sample',
    meta: 'IFC 2x3 · 1.6 MB · bundled',
    fileName: 'Ifc2s3_Duplex_Electrical.ifc',
    assetPath: 'assets/ifc_samples/Ifc2s3_Duplex_Electrical.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '1.6 MB',
  ),
  IfcTemplate(
    id: 'ifc2x3-duplex-architecture',
    title: 'Duplex Architecture',
    subtitle: 'IFC2x3 duplex architectural model',
    meta: 'IFC 2x3 · 2.4 MB · bundled',
    fileName: 'Ifc2x3_Duplex_Architecture.ifc',
    assetPath: 'assets/ifc_samples/Ifc2x3_Duplex_Architecture.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '2.4 MB',
  ),
  IfcTemplate(
    id: 'ifc2x3-duplex-mep',
    title: 'Duplex MEP',
    subtitle: 'IFC2x3 duplex mechanical, electrical and plumbing model',
    meta: 'IFC 2x3 · 17.9 MB · bundled',
    fileName: 'Ifc2x3_Duplex_MEP.ifc',
    assetPath: 'assets/ifc_samples/Ifc2x3_Duplex_MEP.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '17.9 MB',
  ),
  IfcTemplate(
    id: 'ifc2x3-duplex-mechanical',
    title: 'Duplex Mechanical',
    subtitle: 'IFC2x3 duplex mechanical systems sample',
    meta: 'IFC 2x3 · 8.4 MB · bundled',
    fileName: 'Ifc2x3_Duplex_Mechanical.ifc',
    assetPath: 'assets/ifc_samples/Ifc2x3_Duplex_Mechanical.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '8.4 MB',
  ),
  IfcTemplate(
    id: 'ifc2x3-duplex-plumbing',
    title: 'Duplex Plumbing',
    subtitle: 'IFC2x3 duplex plumbing systems sample',
    meta: 'IFC 2x3 · 30.1 MB · bundled',
    fileName: 'Ifc2x3_Duplex_Plumbing.ifc',
    assetPath: 'assets/ifc_samples/Ifc2x3_Duplex_Plumbing.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '30.1 MB',
  ),
  IfcTemplate(
    id: 'ifc2x3-sample-castle',
    title: 'Sample Castle',
    subtitle: 'Large IFC2x3 architectural castle model',
    meta: 'IFC 2x3 · 47.0 MB · bundled',
    fileName: 'Ifc2x3_SampleCastle.ifc',
    assetPath: 'assets/ifc_samples/Ifc2x3_SampleCastle.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '47.0 MB',
  ),
  IfcTemplate(
    id: 'ifc4-basin-faceted-brep',
    title: 'Basin Faceted BRep',
    subtitle: 'IFC4 faceted BRep geometry sample',
    meta: 'IFC 4 · 0.03 MB · bundled',
    fileName: 'Ifc4_BasinFacetedBrep.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_BasinFacetedBrep.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.structure,
    sizeLabel: '0.03 MB',
  ),
  IfcTemplate(
    id: 'ifc4-cube-advanced-brep',
    title: 'Cube Advanced BRep',
    subtitle: 'IFC4 advanced BRep geometry sample',
    meta: 'IFC 4 · 0.01 MB · bundled',
    fileName: 'Ifc4_CubeAdvancedBrep.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_CubeAdvancedBrep.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.structure,
    sizeLabel: '0.01 MB',
  ),
  IfcTemplate(
    id: 'ifc4-revit-arc',
    title: 'Revit ARC',
    subtitle: 'IFC4 Revit architectural export',
    meta: 'IFC 4 · 13.0 MB · bundled',
    fileName: 'Ifc4_Revit_ARC.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_Revit_ARC.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '13.0 MB',
  ),
  IfcTemplate(
    id: 'ifc4-revit-arc-fire-rating',
    title: 'Revit ARC · Fire Rating',
    subtitle: 'IFC4 Revit architecture model with fire ratings',
    meta: 'IFC 4 · 13.0 MB · bundled',
    fileName: 'Ifc4_Revit_ARC_FireRatingAdded.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_Revit_ARC_FireRatingAdded.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '13.0 MB',
  ),
  IfcTemplate(
    id: 'ifc4-revit-mep',
    title: 'Revit MEP',
    subtitle: 'IFC4 Revit mechanical, electrical and plumbing model',
    meta: 'IFC 4 · 27.8 MB · bundled',
    fileName: 'Ifc4_Revit_MEP.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_Revit_MEP.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '27.8 MB',
  ),
  IfcTemplate(
    id: 'ifc4-revit-str',
    title: 'Revit Structure',
    subtitle: 'IFC4 Revit structural export',
    meta: 'IFC 4 · 10.8 MB · bundled',
    fileName: 'Ifc4_Revit_STR.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_Revit_STR.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.structure,
    sizeLabel: '10.8 MB',
  ),
  IfcTemplate(
    id: 'ifc4-sample-house',
    title: 'Sample House',
    subtitle: 'Complete IFC4 sample house model',
    meta: 'IFC 4 · 2.2 MB · bundled',
    fileName: 'Ifc4_SampleHouse.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_SampleHouse.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '2.2 MB',
  ),
  IfcTemplate(
    id: 'ifc4-sample-house-ground-floor',
    title: 'Sample House · Ground Floor',
    subtitle: 'IFC4 sample house ground-floor extract',
    meta: 'IFC 4 · 2.1 MB · bundled',
    fileName: 'Ifc4_SampleHouse_0_GroundFloor.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_SampleHouse_0_GroundFloor.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '2.1 MB',
  ),
  IfcTemplate(
    id: 'ifc4-sample-house-roof',
    title: 'Sample House · Roof',
    subtitle: 'IFC4 sample house roof extract',
    meta: 'IFC 4 · 0.06 MB · bundled',
    fileName: 'Ifc4_SampleHouse_1_Roof.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_SampleHouse_1_Roof.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.building,
    sizeLabel: '0.06 MB',
  ),
  IfcTemplate(
    id: 'ifc4-sample-house-wall-standard-case',
    title: 'Sample House · Standard Wall',
    subtitle: 'IFC4 standard wall representation extract',
    meta: 'IFC 4 · 0.02 MB · bundled',
    fileName: 'Ifc4_SampleHouse_IfcWallStandardCase.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_SampleHouse_IfcWallStandardCase.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.structure,
    sizeLabel: '0.02 MB',
  ),
  IfcTemplate(
    id: 'ifc4-sample-house-window',
    title: 'Sample House · Window',
    subtitle: 'IFC4 window representation extract',
    meta: 'IFC 4 · 0.02 MB · bundled',
    fileName: 'Ifc4_SampleHouse_IfcWindow.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_SampleHouse_IfcWindow.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.structure,
    sizeLabel: '0.02 MB',
  ),
  IfcTemplate(
    id: 'ifc4-wall-elemented-case',
    title: 'Wall Elemented Case',
    subtitle: 'IFC4 elemented wall geometry sample',
    meta: 'IFC 4 · 0.03 MB · bundled',
    fileName: 'Ifc4_WallElementedCase.ifc',
    assetPath: 'assets/ifc_samples/Ifc4_WallElementedCase.ifc',
    sourceUrl: _bundledSource,
    kind: IfcTemplateKind.structure,
    sizeLabel: '0.03 MB',
  ),
];

class IfcTemplateDownloader {
  IfcTemplateDownloader({HttpClient? client})
      : _client = client ?? HttpClient();

  static const int _maxDownloadBytes = 64 * 1024 * 1024;

  final HttpClient _client;
  final Map<String, Future<String>> _activeDownloads =
      <String, Future<String>>{};

  Future<String> download(IfcTemplate template) {
    return _activeDownloads.putIfAbsent(template.id, () async {
      try {
        final directory = await AppProjectStorage.projectDirectory();
        final cacheDirectory = Directory(
          '${directory.path}${Platform.pathSeparator}templates',
        );
        if (!await cacheDirectory.exists()) {
          await cacheDirectory.create(recursive: true);
        }
        final cached = File(
          '${cacheDirectory.path}${Platform.pathSeparator}${template.fileName}',
        );
        if (await cached.exists() && await cached.length() > 0) {
          return cached.path;
        }

        final assetPath = template.assetPath;
        if (assetPath != null) {
          final data = await rootBundle.load(assetPath);
          final bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          if (bytes.isEmpty) {
            throw StateError('Bundled IFC sample is empty.');
          }
          await atomicWriteBytes(cached, bytes);
          return cached.path;
        }

        final downloadUrl = template.downloadUrl;
        if (downloadUrl == null) {
          throw StateError('IFC sample has no bundled asset or download URL.');
        }
        final request = await _client.getUrl(Uri.parse(downloadUrl));
        request.headers.set('user-agent', 'Tablet-BIM/${template.id}');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'IFC download returned HTTP ${response.statusCode}',
            uri: Uri.parse(downloadUrl),
          );
        }
        final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
          if (buffer.length + chunk.length > _maxDownloadBytes) {
            throw StateError('IFC sample is larger than 64 MB.');
          }
          buffer.addAll(chunk);
          return buffer;
        });
        if (bytes.isEmpty) {
          throw StateError('IFC sample download was empty.');
        }

        await atomicWriteBytes(cached, bytes);
        return cached.path;
      } finally {
        _activeDownloads.remove(template.id);
      }
    });
  }

  void close() => _client.close(force: true);
}
