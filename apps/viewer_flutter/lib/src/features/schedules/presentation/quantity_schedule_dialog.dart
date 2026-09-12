import 'package:flutter/material.dart';

import '../../elements/application/parameters/room_element_parameters.dart';
import '../../authoring/application/scene/render_scene_editor.dart';
import '../application/render_scene_estimator.dart';
import '../application/schedule_csv_export_service.dart';
import '../../../core/application/render_scene/render_scene_models.dart';
import '../application/quantity_schedule_service.dart';
import '../domain/project_schedule_kind.dart';

export '../domain/project_schedule_kind.dart';

class QuantityScheduleWorkspace extends StatelessWidget {
  const QuantityScheduleWorkspace({
    super.key,
    required this.scene,
    required this.kind,
    required this.csvExportService,
  });

  final RenderScene scene;
  final ProjectScheduleKind kind;
  final ScheduleCsvExportService csvExportService;

  @override
  Widget build(BuildContext context) {
    final title = kind == ProjectScheduleKind.rooms
        ? 'Room schedule'
        : 'Quantity takeoff';
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(kind == ProjectScheduleKind.rooms
                    ? Icons.meeting_room_outlined
                    : Icons.table_chart_outlined),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        'Calculated on demand in the background · cached until the model changes',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => exportProjectScheduleCsv(
                    context,
                    scene: scene,
                    kind: kind,
                    service: csvExportService,
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Export CSV'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ScheduleFutureBody(scene: scene, kind: kind),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleFutureBody extends StatelessWidget {
  const _ScheduleFutureBody({required this.scene, required this.kind});

  final RenderScene scene;
  final ProjectScheduleKind kind;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuantityScheduleResult>(
      future: QuantityScheduleService.forScene(scene),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: SelectableText(
                'Schedule calculation failed: ${snapshot.error}'),
          );
        }
        final result = snapshot.data;
        if (result == null) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(),
                SizedBox(height: 12),
                Text('Calculating BIM schedule in background…'),
              ],
            ),
          );
        }
        return kind == ProjectScheduleKind.rooms
            ? _RoomScheduleTable(scene: result.detectedScene)
            : _QuantityScheduleTable(summary: result.summary);
      },
    );
  }
}

Future<void> exportProjectScheduleCsv(
  BuildContext context, {
  required RenderScene scene,
  required ProjectScheduleKind kind,
  required ScheduleCsvExportService service,
}) async {
  try {
    final location = await service.export(scene: scene, kind: kind);
    if (location == null) return;
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV exported: $location')),
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV export failed: $error')),
      );
    }
  }
}

class QuantityScheduleDialog extends StatelessWidget {
  const QuantityScheduleDialog({
    super.key,
    required this.scene,
    required this.kind,
  });

  final RenderScene scene;
  final ProjectScheduleKind kind;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: <Widget>[
          Icon(kind == ProjectScheduleKind.rooms
              ? Icons.meeting_room_outlined
              : Icons.table_chart_outlined),
          const SizedBox(width: 10),
          Text(kind == ProjectScheduleKind.rooms
              ? 'Room schedule'
              : 'Quantity takeoff'),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 520,
        child: _ScheduleFutureBody(scene: scene, kind: kind),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _RoomScheduleTable extends StatefulWidget {
  const _RoomScheduleTable({required this.scene});

  final RenderScene scene;

  @override
  State<_RoomScheduleTable> createState() => _RoomScheduleTableState();
}

class _RoomScheduleTableState extends State<_RoomScheduleTable> {
  late List<RenderSceneObject> _rooms;
  late _RoomScheduleDataSource _source;

  @override
  void initState() {
    super.initState();
    _rebuildSource();
  }

  @override
  void didUpdateWidget(covariant _RoomScheduleTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.scene, widget.scene)) {
      _source.dispose();
      _rebuildSource();
    }
  }

  void _rebuildSource() {
    _rooms = widget.scene.objects
        .where((object) => object.kindKey == 'room')
        .toList()
      ..sort((a, b) => (a.levelId ?? 0).compareTo(b.levelId ?? 0));
    _source = _RoomScheduleDataSource(widget.scene, _rooms);
  }

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rooms.isEmpty) {
      return const Center(
        child: Text(
            'No closed room boundaries found. Use the Room tool after closing the walls.'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          '${_rooms.length} room(s) · rows are built page-by-page',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: PaginatedDataTable(
                showFirstLastButtons: true,
                showEmptyRows: false,
                rowsPerPage: 25,
                columns: const <DataColumn>[
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Level')),
                  DataColumn(label: Text('Area (m²)')),
                  DataColumn(label: Text('Perimeter (m)')),
                  DataColumn(label: Text('Boundary walls')),
                ],
                source: _source,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RoomScheduleDataSource extends DataTableSource {
  _RoomScheduleDataSource(this.scene, this.rooms);

  final RenderScene scene;
  final List<RenderSceneObject> rooms;

  @override
  DataRow? getRow(int index) {
    if (index < 0 || index >= rooms.length) return null;
    final room = rooms[index];
    final parameters = RoomElementParameters.fromObject(room);
    final area =
        parameters.areaSquareMeters ?? room.bounds.width * room.bounds.depth;
    final perimeter = parameters.perimeterMeters ??
        (room.bounds.width + room.bounds.depth) * 2.0;
    final level = scene.levelById(room.levelId)?.name ?? 'Unassigned';
    return DataRow.byIndex(
      index: index,
      cells: <DataCell>[
        DataCell(Text('${index + 1}')),
        DataCell(Text(level)),
        DataCell(Text(area.toStringAsFixed(2))),
        DataCell(Text(perimeter.toStringAsFixed(2))),
        DataCell(Text(
          RenderSceneEditor.roomBoundaryWallIds(room).length.toString(),
        )),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rooms.length;

  @override
  int get selectedRowCount => 0;
}

class _QuantityScheduleTable extends StatelessWidget {
  const _QuantityScheduleTable({required this.summary});

  final RenderSceneEstimateSummary summary;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String quantity, String unit})>[
      (label: 'Rooms', quantity: summary.roomCount.toString(), unit: 'pcs'),
      (
        label: 'Room area',
        quantity: summary.totalRoomArea.toStringAsFixed(2),
        unit: 'm²'
      ),
      (label: 'Walls', quantity: summary.wallCount.toString(), unit: 'pcs'),
      (
        label: 'Net wall volume',
        quantity: summary.wallNetVolume.toStringAsFixed(2),
        unit: 'm³'
      ),
      (
        label: 'Brick masonry',
        quantity: summary.brickCount.toString(),
        unit: 'pcs'
      ),
      (label: 'Floors', quantity: summary.floorCount.toString(), unit: 'pcs'),
      (
        label: 'Floor area',
        quantity: summary.floorArea.toStringAsFixed(2),
        unit: 'm²'
      ),
      (
        label: 'Concrete',
        quantity: summary.floorConcreteVolume.toStringAsFixed(2),
        unit: 'm³'
      ),
      (
        label: 'Ceilings',
        quantity: summary.ceilingCount.toString(),
        unit: 'pcs'
      ),
      (
        label: 'Ceiling area',
        quantity: summary.ceilingArea.toStringAsFixed(2),
        unit: 'm²'
      ),
      (label: 'Doors', quantity: summary.doorCount.toString(), unit: 'pcs'),
      (label: 'Windows', quantity: summary.windowCount.toString(), unit: 'pcs'),
      (
        label: 'Opening area',
        quantity: summary.openingArea.toStringAsFixed(2),
        unit: 'm²'
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('Live quantities from the requested model snapshot',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),
        Expanded(
          child: SingleChildScrollView(
            child: DataTable(
              columns: const <DataColumn>[
                DataColumn(label: Text('Category')),
                DataColumn(label: Text('Quantity')),
                DataColumn(label: Text('Unit')),
              ],
              rows: <DataRow>[
                for (final row in rows)
                  DataRow(cells: <DataCell>[
                    DataCell(Text(row.label)),
                    DataCell(Text(row.quantity)),
                    DataCell(Text(row.unit)),
                  ]),
              ],
            ),
          ),
        ),
        const Divider(),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
              'Estimated total: \$${summary.totalCost.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}
