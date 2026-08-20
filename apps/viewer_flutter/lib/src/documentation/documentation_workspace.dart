import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../render_scene_models.dart';
import 'document_models.dart';
import 'document_pdf_service.dart';

class DocumentationWorkspacePage extends StatefulWidget {
  const DocumentationWorkspacePage({
    super.key,
    required this.scene,
    required this.activeLevelId,
    this.initialProjectName = 'Tablet BIM Project',
    this.composedSheet,
    this.composedScenes = const <String, RenderScene>{},
  });

  final RenderScene scene;
  final int? activeLevelId;
  final String initialProjectName;
  final ProjectSheet? composedSheet;
  final Map<String, RenderScene> composedScenes;

  @override
  State<DocumentationWorkspacePage> createState() =>
      _DocumentationWorkspacePageState();
}

class _DocumentationWorkspacePageState
    extends State<DocumentationWorkspacePage> {
  final DocumentPdfService _service = const DocumentPdfService();
  late final TextEditingController _projectController;
  late final TextEditingController _authorController;
  late final TextEditingController _prefixController;
  DocumentationScope _scope = DocumentationScope.currentFloorPlan;
  int _scale = 50;
  late SheetDocumentSettings _settings;
  late Future<Uint8List> _pdf;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectController = TextEditingController(text: widget.initialProjectName);
    _authorController = TextEditingController(text: 'Project Team');
    _prefixController = TextEditingController(text: 'A');
    _settings = _readSettings();
    _pdf = _buildPdf();
  }

  @override
  void dispose() {
    _projectController.dispose();
    _authorController.dispose();
    _prefixController.dispose();
    super.dispose();
  }

  SheetDocumentSettings _readSettings() {
    return SheetDocumentSettings(
      projectName: _projectController.text.trim(),
      author: _authorController.text.trim(),
      sheetPrefix: _prefixController.text.trim(),
      scaleDenominator: _scale,
      scope: _scope,
      generatedAt: DateTime.now(),
    );
  }

  Future<Uint8List> _buildPdf() {
    final composedSheet = widget.composedSheet;
    if (composedSheet != null) {
      return _service.buildComposedSheetPdf(
        scene: widget.scene,
        sheet: composedSheet,
        resolvedScenes: widget.composedScenes,
        settings: _settings,
      );
    }
    return _service.buildPdf(
      scene: widget.scene,
      settings: _settings,
      activeLevelId: widget.activeLevelId,
    );
  }

  void _regenerate() {
    FocusScope.of(context).unfocus();
    setState(() {
      _settings = _readSettings();
      _pdf = _buildPdf();
    });
  }

  Future<void> _savePdf() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await _pdf;
      final file = await _service.saveToProjectDocuments(
        bytes: bytes,
        settings: _settings,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: ${file.path}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF export failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Documentation'),
            Text(
              'Sheet setup, preview, print and PDF issue',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: <Widget>[
          FilledButton.tonalIcon(
            onPressed: _regenerate,
            icon: const Icon(Icons.refresh),
            label: const Text('Update sheets'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _savePdf,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Save PDF'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: <Widget>[
          SizedBox(
            width: 330,
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  Text('Sheet set',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _projectController,
                    decoration: const InputDecoration(
                      labelText: 'Project name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _authorController,
                    decoration: const InputDecoration(
                      labelText: 'Drawn by',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _prefixController,
                          maxLength: 3,
                          decoration: const InputDecoration(
                            labelText: 'Sheet prefix',
                            counterText: '',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _scale,
                          decoration: const InputDecoration(
                            labelText: 'Scale',
                            border: OutlineInputBorder(),
                          ),
                          items: const <DropdownMenuItem<int>>[
                            DropdownMenuItem(value: 50, child: Text('1:50')),
                            DropdownMenuItem(value: 100, child: Text('1:100')),
                            DropdownMenuItem(value: 200, child: Text('1:200')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _scale = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.composedSheet == null ? 'Views' : 'Composed sheet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  if (widget.composedSheet == null)
                    SegmentedButton<DocumentationScope>(
                      segments: const <ButtonSegment<DocumentationScope>>[
                        ButtonSegment<DocumentationScope>(
                          value: DocumentationScope.currentFloorPlan,
                          icon: Icon(Icons.layers_outlined),
                          label: Text('Current'),
                        ),
                        ButtonSegment<DocumentationScope>(
                          value: DocumentationScope.allFloorPlans,
                          icon: Icon(Icons.library_books_outlined),
                          label: Text('All levels'),
                        ),
                      ],
                      selected: <DocumentationScope>{_scope},
                      onSelectionChanged: (value) {
                        setState(() => _scope = value.first);
                      },
                    ),
                  const SizedBox(height: 8),
                  Text(
                    widget.composedSheet != null
                        ? '${widget.composedSheet!.number} · ${widget.composedSheet!.placements.length} placed views'
                        : _scope == DocumentationScope.currentFloorPlan
                            ? (widget.scene
                                    .levelById(widget.activeLevelId)
                                    ?.name ??
                                'Active level')
                            : '${widget.scene.levels.length} sheets',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 28),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.description_outlined),
                    title: Text('A3 landscape'),
                    subtitle: Text('Professional title block and view data'),
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.print_outlined),
                    title: Text('Print or share'),
                    subtitle: Text('Use the actions above the PDF preview'),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: PdfPreview(
              key: ValueKey<Future<Uint8List>>(_pdf),
              build: (_) => _pdf,
              pdfFileName: _settings.safeFileName,
              allowPrinting: true,
              allowSharing: true,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              initialPageFormat: PdfPageFormat.a3.landscape,
              loadingWidget: const Center(child: CircularProgressIndicator()),
            ),
          ),
        ],
      ),
    );
  }
}
