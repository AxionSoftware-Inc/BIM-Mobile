import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/view_navigation_coordinator.dart';

void main() {
  group('ViewNavigationCoordinator', () {
    test('drops stale queued navigation and keeps the final request', () async {
      final coordinator = ViewNavigationCoordinator();
      final firstGate = Completer<void>();
      final started = <String>[];

      final first = coordinator.run(() async {
        started.add('2D-first');
        await firstGate.future;
      });
      await Future<void>.delayed(Duration.zero);

      final stale3d = coordinator.run(() async {
        started.add('3D-stale');
      });
      final stale2d = coordinator.run(() async {
        started.add('2D-stale');
      });
      final final3d = coordinator.run(() async {
        started.add('3D-final');
      });

      firstGate.complete();
      await Future.wait(<Future<void>>[first, stale3d, stale2d, final3d]);

      expect(started, <String>['2D-first', '3D-final']);
    });

    test('runStrict preserves every serialized operation', () async {
      final coordinator = ViewNavigationCoordinator();
      final order = <int>[];

      await Future.wait(<Future<void>>[
        coordinator.runStrict(() async => order.add(1)),
        coordinator.runStrict(() async => order.add(2)),
        coordinator.runStrict(() async => order.add(3)),
      ]);

      expect(order, <int>[1, 2, 3]);
    });

    test('runLatest lets an in-flight operation detect supersession', () async {
      final coordinator = ViewNavigationCoordinator();
      final gate = Completer<void>();
      var firstStillCurrent = true;
      var finalRan = false;

      final first = coordinator.runLatest((isCurrent) async {
        await gate.future;
        firstStillCurrent = isCurrent();
      });
      await Future<void>.delayed(Duration.zero);
      final last = coordinator.runLatest((isCurrent) async {
        finalRan = isCurrent();
      });

      gate.complete();
      await Future.wait(<Future<void>>[first, last]);

      expect(firstStillCurrent, isFalse);
      expect(finalRan, isTrue);
    });
  });
}
