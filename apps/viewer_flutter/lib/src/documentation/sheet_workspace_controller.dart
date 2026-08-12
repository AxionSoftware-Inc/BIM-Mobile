import 'package:flutter/foundation.dart';

import 'document_models.dart';

/// Owns sheet composition state independently from the model viewport.
///
/// The controller intentionally stores view references and normalized paper
/// rectangles only. Authoritative geometry stays in RenderScene and is
/// resolved by the application service when a viewport is painted.
class SheetWorkspaceController extends ChangeNotifier {
  final List<ProjectSheet> _sheets = <ProjectSheet>[];
  String? _activeSheetId;
  int _nextSheetNumber = 101;
  int _nextPlacementId = 1;

  List<ProjectSheet> get sheets => List<ProjectSheet>.unmodifiable(_sheets);
  String? get activeSheetId => _activeSheetId;

  ProjectSheet? get activeSheet {
    final id = _activeSheetId;
    if (id == null) return null;
    for (final sheet in _sheets) {
      if (sheet.id == id) return sheet;
    }
    return null;
  }

  ProjectSheet createSheet({String title = 'Unnamed Sheet'}) {
    final number = 'A${_nextSheetNumber.toString().padLeft(3, '0')}';
    _nextSheetNumber += 1;
    final sheet = ProjectSheet(
      id: 'sheet-$number',
      number: number,
      title: title,
    );
    _sheets.add(sheet);
    _activeSheetId = sheet.id;
    notifyListeners();
    return sheet;
  }

  void openSheet(String sheetId) {
    if (_activeSheetId == sheetId ||
        !_sheets.any((sheet) => sheet.id == sheetId)) {
      return;
    }
    _activeSheetId = sheetId;
    notifyListeners();
  }

  void closeSheet() {
    if (_activeSheetId == null) return;
    _activeSheetId = null;
    notifyListeners();
  }

  bool placeView({
    required SheetViewReference view,
    required double centerX,
    required double centerY,
  }) {
    final sheet = activeSheet;
    if (sheet == null) return false;
    if (sheet.placements.any((placement) => placement.view.id == view.id)) {
      return false;
    }

    final (defaultWidth, defaultHeight) = switch (view.kind) {
      SheetViewKind.floorPlan => (0.52, 0.60),
      SheetViewKind.threeD => (0.42, 0.42),
      SheetViewKind.elevation || SheetViewKind.section => (0.43, 0.30),
    };
    final placement = SheetViewportPlacement(
      id: 'viewport-${_nextPlacementId++}',
      view: view,
      left: (centerX - defaultWidth * 0.5).clamp(0.015, 0.985 - defaultWidth),
      top: (centerY - defaultHeight * 0.5).clamp(0.015, 0.88 - defaultHeight),
      width: defaultWidth,
      height: defaultHeight,
    );
    _replaceSheet(
      sheet.copyWith(
        placements: <SheetViewportPlacement>[
          ...sheet.placements,
          placement,
        ],
      ),
    );
    return true;
  }

  void movePlacement(String placementId, double deltaX, double deltaY) {
    final sheet = activeSheet;
    if (sheet == null) return;
    final next = <SheetViewportPlacement>[
      for (final placement in sheet.placements)
        if (placement.id == placementId)
          placement.copyWith(
            left:
                (placement.left + deltaX).clamp(0.005, 0.995 - placement.width),
            top:
                (placement.top + deltaY).clamp(0.005, 0.895 - placement.height),
          )
        else
          placement,
    ];
    _replaceSheet(sheet.copyWith(placements: next));
  }

  void resizePlacement(
      String placementId, double deltaWidth, double deltaHeight) {
    final sheet = activeSheet;
    if (sheet == null) return;
    final next = <SheetViewportPlacement>[
      for (final placement in sheet.placements)
        if (placement.id == placementId)
          placement.copyWith(
            width: (placement.width + deltaWidth)
                .clamp(0.22, 0.99 - placement.left),
            height: (placement.height + deltaHeight)
                .clamp(0.16, 0.89 - placement.top),
          )
        else
          placement,
    ];
    _replaceSheet(sheet.copyWith(placements: next));
  }

  void removePlacement(String placementId) {
    final sheet = activeSheet;
    if (sheet == null) return;
    _replaceSheet(
      sheet.copyWith(
        placements: sheet.placements
            .where((placement) => placement.id != placementId)
            .toList(growable: false),
      ),
    );
  }

  void _replaceSheet(ProjectSheet replacement) {
    final index = _sheets.indexWhere((sheet) => sheet.id == replacement.id);
    if (index < 0) return;
    _sheets[index] = replacement;
    notifyListeners();
  }
}
