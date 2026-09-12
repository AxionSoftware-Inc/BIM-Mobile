import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/core/application/render_scene/render_scene_models.dart';
import 'package:viewer_flutter/src/features/schedules/application/schedule_csv_export_service.dart';
import 'package:viewer_flutter/src/features/schedules/domain/project_schedule_kind.dart';

void main() {
  test('quantity CSV export delegates a complete document to the port',
      () async {
    final parsed = parseRenderSceneJson(
      File('assets/render_scene.json').readAsStringSync(),
      source: 'assets/render_scene.json',
    );
    final scene = parsed.scene;
    expect(scene, isNotNull, reason: parsed.errors.join('\n'));

    final port = _RecordingScheduleCsvExportPort();
    final service = ScheduleCsvExportService(port);

    final location = await service.export(
      scene: scene!,
      kind: ProjectScheduleKind.quantities,
    );

    expect(location, 'content://test/quantity_takeoff.csv');
    expect(port.suggestedName, 'quantity_takeoff.csv');
    expect(
      port.contents,
      contains('"Category","Quantity","Unit","Unit cost","Total cost"'),
    );
    expect(port.contents, contains('Estimated total'));
  });
}

final class _RecordingScheduleCsvExportPort implements ScheduleCsvExportPort {
  String? suggestedName;
  String? contents;

  @override
  Future<String> saveTextFile({
    required String suggestedName,
    required String contents,
  }) async {
    this.suggestedName = suggestedName;
    this.contents = contents;
    return 'content://test/$suggestedName';
  }
}
