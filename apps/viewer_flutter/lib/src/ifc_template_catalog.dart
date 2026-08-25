import 'dart:io';

import 'app_project_storage.dart';

/// A small, publicly hosted IFC starter project.
///
/// The source file is deliberately downloaded on demand instead of being
/// bundled into the APK. This keeps the launch screen light and lets the
/// downloaded model be reused offline from the app cache afterwards.
class IfcTemplate {
  const IfcTemplate({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.fileName,
    required this.downloadUrl,
    required this.sourceUrl,
    required this.kind,
    required this.sizeLabel,
  });

  final String id;
  final String title;
  final String subtitle;
  final String meta;
  final String fileName;
  final String downloadUrl;
  final String sourceUrl;
  final IfcTemplateKind kind;
  final String sizeLabel;
}

enum IfcTemplateKind { building, structure, infrastructure }

const List<IfcTemplate> onlineIfcTemplates = <IfcTemplate>[
  IfcTemplate(
    id: 'kit-office-building',
    title: 'KIT office building',
    subtitle: 'Large multi-storey office model from ArchiCAD',
    meta: 'IFC 4 · 10.9 MB · large building',
    fileName: 'kit-office-building.ifc',
    downloadUrl: 'https://www.ifcwiki.org/images/9/98/AC20-Institute-Var-2.ifc',
    sourceUrl: 'https://www.ifcwiki.org/index.php?title=KIT_IFC_Examples',
    kind: IfcTemplateKind.building,
    sizeLabel: '10.9 MB',
  ),
];

class IfcTemplateDownloader {
  IfcTemplateDownloader({HttpClient? client})
      : _client = client ?? HttpClient();

  static const int _maxDownloadBytes = 32 * 1024 * 1024;

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

        final request = await _client.getUrl(Uri.parse(template.downloadUrl));
        request.headers.set('user-agent', 'Tablet-BIM/${template.id}');
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'IFC download returned HTTP ${response.statusCode}',
            uri: Uri.parse(template.downloadUrl),
          );
        }
        final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
          if (buffer.length + chunk.length > _maxDownloadBytes) {
            throw StateError('IFC sample is larger than 32 MB.');
          }
          buffer.addAll(chunk);
          return buffer;
        });
        if (bytes.isEmpty) {
          throw StateError('IFC sample download was empty.');
        }

        final partial = File('${cached.path}.download');
        await partial.writeAsBytes(bytes, flush: true);
        if (await cached.exists()) {
          await cached.delete();
        }
        await partial.rename(cached.path);
        return cached.path;
      } finally {
        _activeDownloads.remove(template.id);
      }
    });
  }

  void close() => _client.close(force: true);
}
