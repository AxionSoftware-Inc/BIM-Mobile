import '../../../core/application/render_scene/render_scene_models.dart';
import '../../authoring/application/scene/render_scene_editor.dart';
import '../../elements/application/parameters/room_element_parameters.dart';
import 'quantity_schedule_service.dart';
import 'render_scene_estimator.dart';
import '../domain/project_schedule_kind.dart';

/// Platform-neutral boundary for exporting a generated schedule document.
///
/// The schedule feature owns the CSV content and use-case. File pickers,
/// Android document providers and desktop filesystem details stay below this
/// port in infrastructure.
abstract interface class ScheduleCsvExportPort {
  Future<String?> saveTextFile({
    required String suggestedName,
    required String contents,
  });
}

final class ScheduleCsvExportService {
  const ScheduleCsvExportService(this._exportPort);

  final ScheduleCsvExportPort _exportPort;

  Future<String?> export({
    required RenderScene scene,
    required ProjectScheduleKind kind,
  }) async {
    final result = await QuantityScheduleService.forScene(scene);
    final roomSchedule = kind == ProjectScheduleKind.rooms;
    return _exportPort.saveTextFile(
      suggestedName:
          roomSchedule ? 'room_schedule.csv' : 'quantity_takeoff.csv',
      contents: roomSchedule
          ? _roomScheduleCsv(result.detectedScene)
          : _quantityScheduleCsv(result.summary),
    );
  }
}

String _csvCell(Object? value) {
  final text = value?.toString() ?? '';
  return '"${text.replaceAll('"', '""')}"';
}

String _roomScheduleCsv(RenderScene scene) {
  final rooms = scene.objects
      .where((object) => object.kindKey == 'room')
      .toList()
    ..sort((a, b) => (a.levelId ?? 0).compareTo(b.levelId ?? 0));
  final lines = <String>[
    <String>['Room', 'Level', 'Area (m2)', 'Perimeter (m)', 'Boundary walls']
        .map(_csvCell)
        .join(','),
  ];
  for (var index = 0; index < rooms.length; index += 1) {
    final room = rooms[index];
    final parameters = RoomElementParameters.fromObject(room);
    final area =
        parameters.areaSquareMeters ?? room.bounds.width * room.bounds.depth;
    final perimeter = parameters.perimeterMeters ??
        (room.bounds.width + room.bounds.depth) * 2.0;
    lines.add(<Object?>[
      index + 1,
      scene.levelById(room.levelId)?.name ?? 'Unassigned',
      area.toStringAsFixed(2),
      perimeter.toStringAsFixed(2),
      RenderSceneEditor.roomBoundaryWallIds(room).length,
    ].map(_csvCell).join(','));
  }
  return '${lines.join('\r\n')}\r\n';
}

String _quantityScheduleCsv(RenderSceneEstimateSummary summary) {
  final lines = <String>[
    <String>['Category', 'Quantity', 'Unit', 'Unit cost', 'Total cost']
        .map(_csvCell)
        .join(','),
  ];
  for (final item in summary.lineItems) {
    lines.add(<Object?>[
      item.label,
      item.quantity.toStringAsFixed(item.unit == 'pcs' ? 0 : 2),
      item.unit,
      item.unitCost.toStringAsFixed(2),
      item.totalCost.toStringAsFixed(2),
    ].map(_csvCell).join(','));
  }
  lines.add(<Object?>[
    'Estimated total',
    '',
    '',
    '',
    summary.totalCost.toStringAsFixed(2),
  ].map(_csvCell).join(','));
  return '${lines.join('\r\n')}\r\n';
}
