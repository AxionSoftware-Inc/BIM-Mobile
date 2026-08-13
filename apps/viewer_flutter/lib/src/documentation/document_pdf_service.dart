import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_project_storage.dart';
import '../render_scene_models.dart';
import '../render_scene_viewport_painter.dart';
import '../render_scene_viewport_planar.dart';
import '../render_scene_viewport_types.dart';
import 'document_models.dart';

/// Converts authoritative RenderScene views into a printable A3 sheet set.
///
/// The viewport remains interactive-only. Export paints a fresh, high
/// resolution plan from semantic scene data and places it in a stable title
/// block, so selection, zoom and transient authoring overlays cannot leak into
/// issued documents.
class DocumentPdfService {
  const DocumentPdfService();

  static const double _modelPaddingMeters = 1.0;
  static const double _maxRasterWidth = 3200;
  static const double _maxRasterHeight = 2200;

  Future<Uint8List> buildPdf({
    required RenderScene scene,
    required SheetDocumentSettings settings,
    required int? activeLevelId,
  }) async {
    final sheets = resolveDocumentationSheets(
      scene: scene,
      settings: settings,
      activeLevelId: activeLevelId,
    );
    if (sheets.isEmpty) {
      throw StateError('The model has no levels to document.');
    }

    final document = pw.Document(
      title: _pdfSafe(settings.projectName),
      author: _pdfSafe(settings.author),
      creator: 'Tablet BIM Documentation',
      subject: 'Architectural floor plan sheet set',
    );
    for (final sheet in sheets) {
      final viewScene = scene.filteredByLevel(sheet.level.levelId);
      final renderedPlan = await _renderPlanPng(
        scene: viewScene,
        levelId: sheet.level.levelId,
      );
      final planImage = pw.MemoryImage(renderedPlan.bytes);
      final effectiveScale = _effectiveScale(
        scene: viewScene,
        requestedScale: settings.scaleDenominator,
      );
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a3.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => _buildSheet(
            scene: viewScene,
            sheet: sheet,
            settings: settings,
            planImage: planImage,
            planWidthPoints: renderedPlan.widthMeters *
                1000 /
                effectiveScale *
                PdfPageFormat.mm,
            planHeightPoints: renderedPlan.heightMeters *
                1000 /
                effectiveScale *
                PdfPageFormat.mm,
            effectiveScale: effectiveScale,
            pageNumber: context.pageNumber,
            pageCount: sheets.length,
          ),
        ),
      );
    }
    return document.save();
  }

  Future<Uint8List> buildComposedSheetPdf({
    required RenderScene scene,
    required ProjectSheet sheet,
    required Map<String, RenderScene> resolvedScenes,
    required SheetDocumentSettings settings,
  }) async {
    final renderedViews = <String, Uint8List>{};
    for (final placement in sheet.placements) {
      final viewScene = resolvedScenes[placement.view.id] ??
          (placement.view.kind == SheetViewKind.floorPlan
              ? scene.filteredByLevel(placement.view.levelId)
              : scene);
      renderedViews[placement.id] = await _renderSheetViewPng(
        scene: viewScene,
        reference: placement.view,
        aspectRatio: placement.width / placement.height,
      );
    }

    final document = pw.Document(
      title: _pdfSafe('${settings.projectName} ${sheet.number}'),
      author: _pdfSafe(settings.author),
      creator: 'Tablet BIM Documentation',
      subject: 'Composed architectural sheet',
    );
    const pageMargin = 20.0;
    final pageFormat = PdfPageFormat.a3.landscape;
    final paperWidth = pageFormat.width - pageMargin * 2;
    final paperHeight = pageFormat.height - pageMargin * 2;
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(pageMargin),
        build: (context) => _buildComposedSheet(
          sheet: sheet,
          settings: settings,
          renderedViews: renderedViews,
          paperWidth: paperWidth,
          paperHeight: paperHeight,
        ),
      ),
    );
    return document.save();
  }

  Future<File> saveToProjectDocuments({
    required Uint8List bytes,
    required SheetDocumentSettings settings,
  }) async {
    final projectDirectory = await AppProjectStorage.projectDirectory();
    final documentDirectory = Directory(
      '${projectDirectory.path}${Platform.pathSeparator}documents',
    );
    if (!await documentDirectory.exists()) {
      await documentDirectory.create(recursive: true);
    }
    final file = File(
      '${documentDirectory.path}${Platform.pathSeparator}${settings.safeFileName}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<_RenderedPlan> _renderPlanPng({
    required RenderScene scene,
    required int levelId,
  }) async {
    final modelWidth = math.max(scene.bounds.width, 1.0);
    final modelHeight = math.max(scene.bounds.depth, 1.0);
    final paddedWidth = modelWidth + _modelPaddingMeters * 2;
    final paddedHeight = modelHeight + _modelPaddingMeters * 2;
    final pixelsPerMeter = math
        .min(
          200.0,
          math.min(
            _maxRasterWidth / paddedWidth,
            _maxRasterHeight / paddedHeight,
          ),
        )
        .clamp(30.0, 200.0);
    final rasterSize = Size(
      paddedWidth * pixelsPerMeter,
      paddedHeight * pixelsPerMeter,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = FallbackRenderScenePainter(
      scene: scene,
      visibleKinds: const <String>{},
      selectedElementIds: const <String>{},
      activeElementId: null,
      selectedLevelId: levelId,
      highlightedElementId: null,
      projectionMode: RenderSceneProjectionMode.topDown,
      orbitProjectionStyle: RenderSceneOrbitProjectionStyle.orthographic,
      displayStyle: RenderSceneDisplayStyle.solid,
      camera: const RenderSceneCameraState(
        center: RenderScenePoint(x: 0, y: 0, z: 0),
        distance: 24,
        yawRadians: 0.7853981633974483,
        pitchRadians: 0.6283185307179586,
        zoomScale: 1,
      ),
      planCamera: RenderScenePlanCameraState(
        center: RenderScenePoint(
          x: (scene.bounds.min.x + scene.bounds.max.x) * 0.5,
          y: (scene.bounds.min.y + scene.bounds.max.y) * 0.5,
          z: 0,
        ),
        zoom: pixelsPerMeter,
      ),
      draftWallStart: null,
      draftWallEnd: null,
      draftOpening: null,
      draftSurface: null,
      draftWallThicknessMeters: 0.2,
      draftWallHeightMeters: 3,
      showObjectLabels: false,
      showReferenceGrid: false,
    );
    painter.paint(canvas, rasterSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      rasterSize.width.round(),
      rasterSize.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('Failed to rasterize floor plan.');
    return _RenderedPlan(
      bytes: data.buffer.asUint8List(),
      widthMeters: paddedWidth,
      heightMeters: paddedHeight,
    );
  }

  Future<Uint8List> _renderSheetViewPng({
    required RenderScene scene,
    required SheetViewReference reference,
    required double aspectRatio,
  }) async {
    final safeAspect = aspectRatio.clamp(0.5, 2.5);
    const longSide = 1800.0;
    final rasterSize = safeAspect >= 1
        ? Size(longSide, longSide / safeAspect)
        : Size(longSide * safeAspect, longSide);
    final descriptor = reference.projectionMode.planarDescriptor;
    final planCamera = descriptor == null
        ? RenderScenePlanCameraState(center: scene.bounds.center, zoom: 1)
        : RenderScenePlanCameraState(
            center: scene.bounds.center,
            zoom: math.min(
              math.max(rasterSize.width - 80, 1) /
                  math.max(descriptor.boundsWidth(scene.bounds), 0.25),
              math.max(rasterSize.height - 80, 1) /
                  math.max(descriptor.boundsHeight(scene.bounds), 0.25),
            ),
          );
    final maxExtent = math.max(
      math.max(scene.bounds.width, scene.bounds.depth),
      scene.bounds.height,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    FallbackRenderScenePainter(
      scene: scene,
      visibleKinds: const <String>{},
      selectedElementIds: const <String>{},
      activeElementId: null,
      selectedLevelId: reference.levelId,
      highlightedElementId: null,
      projectionMode: reference.projectionMode,
      orbitProjectionStyle: reference.orbitProjectionStyle,
      displayStyle: reference.displayStyle,
      camera: RenderSceneCameraState(
        center: scene.bounds.center,
        distance: math.max(maxExtent * 2.6, 10),
        yawRadians: math.pi / 4,
        pitchRadians: math.pi / 5.2,
        zoomScale: 4.2,
      ),
      planCamera: planCamera,
      draftWallStart: null,
      draftWallEnd: null,
      draftOpening: null,
      draftSurface: null,
      draftWallThicknessMeters: 0.2,
      draftWallHeightMeters: 3,
      showObjectLabels: false,
      showReferenceGrid: false,
    ).paint(canvas, rasterSize);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      rasterSize.width.round(),
      rasterSize.height.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (data == null) throw StateError('Failed to rasterize sheet view.');
    return data.buffer.asUint8List();
  }

  pw.Widget _buildComposedSheet({
    required ProjectSheet sheet,
    required SheetDocumentSettings settings,
    required Map<String, Uint8List> renderedViews,
    required double paperWidth,
    required double paperHeight,
  }) {
    const ink = PdfColor.fromInt(0xFF1F2937);
    const accent = PdfColor.fromInt(0xFF0F766E);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ink, width: 1.2),
      ),
      child: pw.Stack(
        children: <pw.Widget>[
          for (final placement in sheet.placements)
            pw.Positioned(
              left: placement.left * paperWidth,
              top: placement.top * paperHeight,
              child: pw.SizedBox(
                width: placement.width * paperWidth,
                height: placement.height * paperHeight,
                child: pw.Column(
                  children: <pw.Widget>[
                    pw.Expanded(
                      child: pw.Image(
                        pw.MemoryImage(renderedViews[placement.id]!),
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                    pw.Container(
                      height: 16,
                      alignment: pw.Alignment.center,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          top: pw.BorderSide(color: ink, width: 0.7),
                        ),
                      ),
                      child: pw.Text(
                        _pdfSafe(placement.view.label),
                        style: const pw.TextStyle(fontSize: 7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          pw.Positioned(
            left: 0,
            bottom: 0,
            child: pw.SizedBox(
              width: paperWidth,
              height: 68,
              child: pw.Container(
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: ink, width: 1.2),
                  ),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: <pw.Widget>[
                    pw.Expanded(
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(9),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: <pw.Widget>[
                            pw.Text(
                              _pdfSafe(settings.projectName).toUpperCase(),
                              style: const pw.TextStyle(
                                fontSize: 14,
                                fontWeight: pw.FontWeight.bold,
                                color: ink,
                              ),
                            ),
                            pw.SizedBox(height: 3),
                            pw.Text(
                              _pdfSafe(sheet.title),
                              style: const pw.TextStyle(
                                fontSize: 9,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _titleCell('DRAWN BY', _pdfSafe(settings.author),
                        width: 92),
                    _titleCell(
                      'DATE',
                      settings.generatedAt.toIso8601String().split('T').first,
                      width: 72,
                    ),
                    pw.Container(
                      width: 90,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          left: pw.BorderSide(color: ink, width: 0.8),
                        ),
                      ),
                      alignment: pw.Alignment.center,
                      child: pw.Text(
                        sheet.number,
                        style: const pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _effectiveScale({
    required RenderScene scene,
    required int requestedScale,
  }) {
    // A3 landscape drawing frame after the view-data rail and title block.
    const availableWidthMillimeters = 330.0;
    const availableHeightMillimeters = 230.0;
    final required = math.max(
      (scene.bounds.width + _modelPaddingMeters * 2) *
          1000 /
          availableWidthMillimeters,
      (scene.bounds.depth + _modelPaddingMeters * 2) *
          1000 /
          availableHeightMillimeters,
    );
    final minimum = math.max(requestedScale.toDouble(), required);
    for (final standard in const <int>[50, 100, 200, 500, 1000, 2000]) {
      if (standard >= minimum) return standard;
    }
    return (minimum / 1000).ceil() * 1000;
  }

  pw.Widget _buildSheet({
    required RenderScene scene,
    required DocumentationSheet sheet,
    required SheetDocumentSettings settings,
    required pw.MemoryImage planImage,
    required double planWidthPoints,
    required double planHeightPoints,
    required int effectiveScale,
    required int pageNumber,
    required int pageCount,
  }) {
    const ink = PdfColor.fromInt(0xFF1F2937);
    const accent = PdfColor.fromInt(0xFF0F766E);
    const pale = PdfColor.fromInt(0xFFF1F5F4);
    final counts = scene.kindCounts;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: ink, width: 1.2),
      ),
      child: pw.Column(
        children: <pw.Widget>[
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Image(
                      planImage,
                      width: planWidthPoints,
                      height: planHeightPoints,
                      fit: pw.BoxFit.fill,
                    ),
                  ),
                ),
                pw.Container(
                  width: 126,
                  color: pale,
                  padding: const pw.EdgeInsets.all(10),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Text(
                        'VIEW DATA',
                        style: const pw.TextStyle(
                          color: accent,
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 9),
                      _dataRow('Level', _pdfSafe(sheet.level.name)),
                      _dataRow('Elevation',
                          '${sheet.level.elevationMeters.toStringAsFixed(2)} m'),
                      _dataRow('Scale', '1:$effectiveScale'),
                      pw.Divider(color: ink, thickness: 0.5),
                      _dataRow('Walls', '${counts['wall'] ?? 0}'),
                      _dataRow('Doors', '${counts['door'] ?? 0}'),
                      _dataRow('Windows', '${counts['window'] ?? 0}'),
                      _dataRow('Rooms', '${counts['room'] ?? 0}'),
                      pw.Spacer(),
                      pw.Text(
                        'ISSUE STATUS',
                        style: const pw.TextStyle(
                          color: accent,
                          fontSize: 7,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text('Documentation',
                          style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _titleBlock(
            sheet: sheet,
            settings: settings,
            effectiveScale: effectiveScale,
            pageNumber: pageNumber,
            pageCount: pageCount,
          ),
        ],
      ),
    );
  }

  pw.Widget _titleBlock({
    required DocumentationSheet sheet,
    required SheetDocumentSettings settings,
    required int effectiveScale,
    required int pageNumber,
    required int pageCount,
  }) {
    const ink = PdfColor.fromInt(0xFF1F2937);
    const accent = PdfColor.fromInt(0xFF0F766E);
    final date = settings.generatedAt.toIso8601String().split('T').first;
    return pw.Container(
      height: 68,
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: ink, width: 1.2)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Expanded(
            flex: 5,
            child: pw.Padding(
              padding: const pw.EdgeInsets.all(9),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: <pw.Widget>[
                  pw.Text(
                    _pdfSafe(settings.projectName).toUpperCase(),
                    style: const pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    _pdfSafe(sheet.title),
                    style: const pw.TextStyle(fontSize: 10, color: accent),
                  ),
                ],
              ),
            ),
          ),
          _titleCell('DRAWN BY', _pdfSafe(settings.author), width: 82),
          _titleCell('DATE', date, width: 68),
          _titleCell('SCALE', '1:$effectiveScale', width: 58),
          _titleCell('PAGE', '$pageNumber / $pageCount', width: 52),
          pw.Container(
            width: 82,
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: ink, width: 0.8)),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              sheet.number,
              style: const pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _titleCell(String label, String value, {required double width}) {
    const ink = PdfColor.fromInt(0xFF1F2937);
    return pw.Container(
      width: width,
      padding: const pw.EdgeInsets.all(6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(left: pw.BorderSide(color: ink, width: 0.8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: <pw.Widget>[
          pw.Text(label,
              style: const pw.TextStyle(
                fontSize: 6,
                fontWeight: pw.FontWeight.bold,
                color: ink,
              )),
          pw.SizedBox(height: 4),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  pw.Widget _dataRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(label.toUpperCase(),
              style: const pw.TextStyle(
                fontSize: 6,
                color: PdfColors.grey700,
                fontWeight: pw.FontWeight.bold,
              )),
          pw.SizedBox(height: 1),
          pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
  }

  String _pdfSafe(String value) {
    return value
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('×', 'x')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '?');
  }
}

class _RenderedPlan {
  const _RenderedPlan({
    required this.bytes,
    required this.widthMeters,
    required this.heightMeters,
  });

  final Uint8List bytes;
  final double widthMeters;
  final double heightMeters;
}
