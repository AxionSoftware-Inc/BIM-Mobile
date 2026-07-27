import 'package:flutter/foundation.dart';

import 'render_scene_editor.dart';
import 'render_scene_models.dart';
import 'tbe_ffi.dart';

/// A completed model mutation. UI code may render [scene] only after [success]
/// is true; this prevents a draft preview from being mistaken for a committed
/// BIM element.
class SceneMutationOutcome {
  const SceneMutationOutcome({
    required this.scene,
    required this.createdElementId,
    required this.success,
    required this.trace,
    this.error,
  });

  final RenderScene? scene;
  final int? createdElementId;
  final bool success;
  final List<String> trace;
  final String? error;
}

@immutable
class CreateWallRequest {
  const CreateWallRequest({
    required this.scene,
    required this.start,
    required this.end,
    required this.baseLevelId,
    required this.topLevelId,
    required this.heightMeters,
    required this.thicknessMeters,
  });

  final RenderScene scene;
  final RenderScenePoint start;
  final RenderScenePoint end;
  final int baseLevelId;
  final int topLevelId;
  final double heightMeters;
  final double thicknessMeters;
}

/// The only Flutter entry point for authoritative wall creation.
///
/// It makes engine create -> level constraints -> snapshot verification one
/// transaction. The local editor is used solely when no engine was loaded.
class SceneMutationService {
  const SceneMutationService({this.engineRepository});

  final ViewerRepository? engineRepository;

  Future<SceneMutationOutcome> createWall(CreateWallRequest request) async {
    final trace = <String>[
      'request wall base=${request.baseLevelId} top=${request.topLevelId}',
      'start=${_pointLabel(request.start)} end=${_pointLabel(request.end)}',
    ];
    final engine = engineRepository;
    if (engine == null) {
      final scene = RenderSceneEditor.addWall(
        scene: request.scene,
        start: request.start,
        end: request.end,
        heightMeters: request.heightMeters,
        thicknessMeters: request.thicknessMeters,
        levelId: request.baseLevelId,
        topLevelId: request.topLevelId,
      );
      final created = scene.objects.length > request.scene.objects.length
          ? scene.objects.last.elementId
          : null;
      final success = created != null;
      trace.add(
          'fallback snapshot walls=${scene.kindCounts['wall'] ?? 0} id=$created');
      return SceneMutationOutcome(
        scene: scene,
        createdElementId: created,
        success: success,
        trace: trace,
        error: success ? null : 'Fallback wall yaratilmadi.',
      );
    }

    try {
      final created = await engine.createWall(
        name: 'Wall',
        levelId: request.baseLevelId,
        start: request.start,
        end: request.end,
        thicknessMeters: request.thicknessMeters,
        heightMeters: request.heightMeters,
      );
      final wallId = engine.lastCreatedElementId;
      trace.add(
        'engine create id=$wallId walls=${created.scene?.kindCounts['wall']} '
        'errors=${created.errors.join('|')}',
      );
      if (created.scene == null ||
          wallId == null ||
          created.scene!.objectById(wallId) == null) {
        return SceneMutationOutcome(
          scene: created.scene,
          createdElementId: wallId,
          success: false,
          trace: trace,
          error: created.errors.isEmpty
              ? 'Engine wall ID yoki snapshot tasdiqlanmadi.'
              : created.errors.join(' '),
        );
      }

      final constrained = await engine.setWallLevelConstraints(
        wallId: wallId,
        baseLevelId: request.baseLevelId,
        topLevelId: request.topLevelId,
        heightMode: 1,
      );
      final finalScene = constrained.scene;
      trace.add(
        'engine constraints walls=${finalScene?.kindCounts['wall']} '
        'exists=${finalScene?.objectById(wallId) != null} '
        'errors=${constrained.errors.join('|')}',
      );
      if (finalScene == null || finalScene.objectById(wallId) == null) {
        return SceneMutationOutcome(
          scene: finalScene,
          createdElementId: wallId,
          success: false,
          trace: trace,
          error: constrained.errors.isEmpty
              ? 'Constraintdan keyin wall snapshotda yo‘q.'
              : constrained.errors.join(' '),
        );
      }
      return SceneMutationOutcome(
        scene: finalScene,
        createdElementId: wallId,
        success: true,
        trace: trace,
      );
    } catch (error) {
      trace.add('engine exception=$error');
      return SceneMutationOutcome(
        scene: null,
        createdElementId: null,
        success: false,
        trace: trace,
        error: error.toString(),
      );
    }
  }

  static String _pointLabel(RenderScenePoint point) =>
      '${point.x.toStringAsFixed(3)},${point.y.toStringAsFixed(3)},${point.z.toStringAsFixed(3)}';
}
