import 'package:flutter_test/flutter_test.dart';

import 'package:viewer_flutter/src/core/application/render_scene/render_scene_models.dart';
import 'package:viewer_flutter/src/features/annotations/application/annotation_snap_service.dart';

void main() {
  const start = RenderScenePoint(x: 0, y: 0, z: 0);
  const end = RenderScenePoint(x: 10, y: 0, z: 0);

  test('endpoint wins over a nearby segment projection', () {
    final result = AnnotationSnapResolver.resolve(
      pointer: const Offset(0.8, 0.2),
      points: const <AnnotationSnapCandidate>[
        AnnotationSnapCandidate(
          modelPoint: start,
          screenPoint: Offset(0, 0),
          kind: AnnotationSnapKind.endpoint,
        ),
      ],
      segments: const <AnnotationSnapSegment>[
        AnnotationSnapSegment(
          start: start,
          end: end,
          startScreen: Offset(0, 10),
          endScreen: Offset(10, 10),
        ),
      ],
      tolerancePixels: 4,
    );

    expect(result, isNotNull);
    expect(result!.kind, AnnotationSnapKind.endpoint);
    expect(result.modelPoint, start);
  });

  test('segment snap interpolates the model point', () {
    final result = AnnotationSnapResolver.resolve(
      pointer: const Offset(5, 1),
      segments: const <AnnotationSnapSegment>[
        AnnotationSnapSegment(
          start: start,
          end: end,
          startScreen: Offset(0, 0),
          endScreen: Offset(10, 0),
        ),
      ],
      tolerancePixels: 2,
    );

    expect(result, isNotNull);
    expect(result!.kind, AnnotationSnapKind.edge);
    expect(result.modelPoint.x, closeTo(5, 0.0001));
    expect(result.modelPoint.y, closeTo(0, 0.0001));
  });

  test('grid fallback rounds all model axes', () {
    final result = snapAnnotationPointToGrid(
      const RenderScenePoint(x: 1.24, y: -0.26, z: 2.76),
      spacing: 0.5,
    );

    expect(result.x, closeTo(1.0, 0.0001));
    expect(result.y, closeTo(-0.5, 0.0001));
    expect(result.z, closeTo(3.0, 0.0001));
  });
}
