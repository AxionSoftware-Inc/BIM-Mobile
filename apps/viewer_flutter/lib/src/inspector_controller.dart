import 'package:flutter/foundation.dart';

import 'render_scene_models.dart';
import 'selection_controller.dart';

enum InspectorTargetKind { empty, level, object, multiple }

@immutable
class InspectorTarget {
  const InspectorTarget._({
    required this.kind,
    this.level,
    this.object,
    this.objects = const <RenderSceneObject>[],
  });

  const InspectorTarget.empty() : this._(kind: InspectorTargetKind.empty);
  const InspectorTarget.level(RenderSceneLevel value)
      : this._(kind: InspectorTargetKind.level, level: value);
  const InspectorTarget.object(RenderSceneObject value)
      : this._(kind: InspectorTargetKind.object, object: value);
  const InspectorTarget.multiple(List<RenderSceneObject> values)
      : this._(kind: InspectorTargetKind.multiple, objects: values);

  final InspectorTargetKind kind;
  final RenderSceneLevel? level;
  final RenderSceneObject? object;
  final List<RenderSceneObject> objects;
}

/// Converts central selection state into exactly one Inspector target.
class InspectorController extends ChangeNotifier {
  InspectorController(this.selection) {
    selection.addListener(_onSelectionChanged);
  }

  final SelectionController selection;

  void _onSelectionChanged() => notifyListeners();

  InspectorTarget targetFor(RenderScene? scene) {
    if (scene == null) return const InspectorTarget.empty();
    if (selection.levelId case final id?) {
      final level = scene.levelById(id);
      if (level != null) return InspectorTarget.level(level);
    }
    final objects = selection.selectedObjects(scene);
    if (objects.length > 1) return InspectorTarget.multiple(objects);
    if (objects.length == 1) return InspectorTarget.object(objects.single);
    return const InspectorTarget.empty();
  }

  @override
  void dispose() {
    selection.removeListener(_onSelectionChanged);
    super.dispose();
  }
}
