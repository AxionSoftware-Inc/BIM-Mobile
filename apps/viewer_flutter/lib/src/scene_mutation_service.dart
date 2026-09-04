import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'render_scene_editor.dart';
import 'render_scene_models.dart';
import 'viewer_authoring_gateway.dart';
import 'tools/wall_authoring_geometry.dart';

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

@immutable
class CreateCurvedWallRequest {
  const CreateCurvedWallRequest({
    required this.scene,
    required this.geometry,
    required this.baseLevelId,
    required this.topLevelId,
    required this.heightMeters,
    required this.thicknessMeters,
  });

  final RenderScene scene;
  final WallArcGeometry geometry;
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

  final ViewerAuthoringGateway? engineRepository;

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
      final previousWallIds = request.scene.objects
          .where((object) => object.kindKey == 'wall')
          .map((object) => object.elementId)
          .whereType<int>()
          .toSet();
      final created = scene.objects
          .where((object) =>
              object.kindKey == 'wall' &&
              object.elementId != null &&
              !previousWallIds.contains(object.elementId))
          .map((object) => object.elementId)
          .whereType<int>()
          .cast<int?>()
          .lastOrNull;
      final success = created != null;
      trace.add(
          'fallback snapshot walls=${scene.kindCounts['wall'] ?? 0} id=$created');
      return SceneMutationOutcome(
        scene: scene,
        createdElementId: created,
        success: success,
        trace: trace,
        error: success ? null : 'Fallback wall could not be created.',
      );
    }

    try {
      final nearbyEndpoint = _hasNearbyWallEndpoint(request);
      final created = await engine.createWallTransaction(
        name: 'Wall',
        levelId: request.baseLevelId,
        start: request.start,
        end: request.end,
        thicknessMeters: request.thicknessMeters,
        heightMeters: request.heightMeters,
        topLevelId: request.topLevelId,
        autoJoin: nearbyEndpoint,
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

      if (request.topLevelId != 0) {
        trace.add(
          'engine constraints committed atomically '
          'top=${request.topLevelId}',
        );
      } else {
        trace.add('single-level wall: keeping explicit wall height');
      }
      // IFC and large template imports deliberately disable the engine's
      // automatic join pass while bulk-loading. Re-enable the useful
      // interactive behavior only when this new wall actually lands near an
      // existing endpoint; ordinary isolated walls stay O(1) after creation.
      if (nearbyEndpoint) {
        trace.add(
          'endpoint auto-join committed atomically '
          'walls=${created.scene?.kindCounts['wall']}',
        );
      }
      final finalScene = created.scene;
      if (finalScene == null || finalScene.objectById(wallId) == null) {
        return SceneMutationOutcome(
          scene: finalScene,
          createdElementId: wallId,
          success: false,
          trace: trace,
          error: created.errors.isEmpty
              ? 'Wall is missing from the snapshot.'
              : created.errors.join(' '),
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

  Future<SceneMutationOutcome> createCurvedWall(
    CreateCurvedWallRequest request,
  ) async {
    final trace = <String>[
      'request curved wall base=${request.baseLevelId} top=${request.topLevelId}',
      'start=${_pointLabel(request.geometry.start)} end=${_pointLabel(request.geometry.end)}',
      'radius=${request.geometry.radiusMeters.toStringAsFixed(3)} sweep=${request.geometry.sweepDegrees.toStringAsFixed(1)}',
    ];
    final engine = engineRepository;
    if (engine == null) {
      final scene = RenderSceneEditor.addCurvedWall(
        scene: request.scene,
        start: request.geometry.start,
        end: request.geometry.end,
        center: request.geometry.center,
        radiusMeters: request.geometry.radiusMeters,
        startAngleRadians: math.atan2(
          request.geometry.start.y - request.geometry.center.y,
          request.geometry.start.x - request.geometry.center.x,
        ),
        sweepRadians: request.geometry.sweepRadians,
        heightMeters: request.heightMeters,
        thicknessMeters: request.thicknessMeters,
        levelId: request.baseLevelId,
        topLevelId: request.topLevelId,
      );
      final previousWallIds = request.scene.objects
          .where((object) => object.kindKey == 'wall')
          .map((object) => object.elementId)
          .whereType<int>()
          .toSet();
      final created = scene.objects
          .where((object) =>
              object.kindKey == 'wall' &&
              object.elementId != null &&
              !previousWallIds.contains(object.elementId))
          .map((object) => object.elementId)
          .whereType<int>()
          .cast<int?>()
          .lastOrNull;
      final success = created != null;
      trace.add('fallback curved wall id=$created');
      return SceneMutationOutcome(
        scene: scene,
        createdElementId: created,
        success: success,
        trace: trace,
        error: success ? null : 'Fallback curved wall could not be created.',
      );
    }
    try {
      var result = await engine.createCurvedWall(
        name: 'Curved Wall',
        levelId: request.baseLevelId,
        geometry: request.geometry,
        thicknessMeters: request.thicknessMeters,
        heightMeters: request.heightMeters,
      );
      var scene = result.scene;
      final wallId = engine.lastCreatedElementId;
      trace.add(
        'engine create curved id=$wallId walls=${scene?.kindCounts['wall']} '
        'errors=${result.errors.join('|')}',
      );
      if (scene == null || wallId == null || scene.objectById(wallId) == null) {
        return SceneMutationOutcome(
          scene: scene,
          createdElementId: wallId,
          success: false,
          trace: trace,
          error: result.errors.isEmpty
              ? 'Curved wall ID yoki snapshot tasdiqlanmadi.'
              : result.errors.join(' '),
        );
      }
      if (request.topLevelId != 0) {
        result = await engine.setWallLevelConstraints(
          wallId: wallId,
          baseLevelId: request.baseLevelId,
          topLevelId: request.topLevelId,
          heightMode: 1,
        );
        scene = result.scene;
        trace.add(
            'curved wall level constraint committed top=${request.topLevelId}');
      }
      if (scene == null || scene.objectById(wallId) == null) {
        return SceneMutationOutcome(
          scene: scene,
          createdElementId: wallId,
          success: false,
          trace: trace,
          error: result.errors.isEmpty
              ? 'Curved wall is missing from the final snapshot.'
              : result.errors.join(' '),
        );
      }
      return SceneMutationOutcome(
        scene: scene,
        createdElementId: wallId,
        success: true,
        trace: trace,
      );
    } catch (error) {
      trace.add('engine curved wall exception=$error');
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

  static bool _hasNearbyWallEndpoint(CreateWallRequest request) {
    const endpointJoinToleranceMeters = 0.35;
    for (final object in request.scene.objects) {
      if (object.kindKey != 'wall' || object.levelId != request.baseLevelId) {
        continue;
      }
      final start = RenderSceneEditor.wallStartPoint(object);
      final end = RenderSceneEditor.wallEndPoint(object);
      if ((start != null &&
              (_planDistance(start, request.start) <=
                      endpointJoinToleranceMeters ||
                  _planDistance(start, request.end) <=
                      endpointJoinToleranceMeters)) ||
          (end != null &&
              (_planDistance(end, request.start) <=
                      endpointJoinToleranceMeters ||
                  _planDistance(end, request.end) <=
                      endpointJoinToleranceMeters))) {
        return true;
      }
    }
    return false;
  }

  static double _planDistance(RenderScenePoint first, RenderScenePoint second) {
    final dx = first.x - second.x;
    final dy = first.y - second.y;
    return math.sqrt(dx * dx + dy * dy);
  }
}
