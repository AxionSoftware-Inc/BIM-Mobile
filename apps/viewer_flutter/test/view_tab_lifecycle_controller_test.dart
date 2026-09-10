import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/viewer/application/workspace/opened_view_tab.dart';
import 'package:viewer_flutter/src/features/viewer/application/workspace/view_tab_lifecycle_controller.dart';
import 'package:viewer_flutter/src/features/viewer/application/workspace/view_workspace_store.dart';

void main() {
  OpenedViewTab tab(String id) => OpenedViewTab(
        id: id,
        label: id,
        kind: OpenedViewKind.threeD,
      );

  test('open commits a new tab only after activation succeeds', () async {
    final store = ViewWorkspaceStore.standard();
    final controller = ViewTabLifecycleController(store);
    final first = tab('first');
    final second = tab('second');
    store.addTab(first);
    store.setActiveTab(first.id);

    await controller.open(second, activate: (_) async {});

    expect(store.tabById(second.id), isNotNull);
    expect(store.activeTabId, second.id);
  });

  test('failed open removes new tab and restores previous activation', () async {
    final store = ViewWorkspaceStore.standard();
    final controller = ViewTabLifecycleController(store);
    final first = tab('first');
    final second = tab('second');
    final activated = <String>[];
    store.addTab(first);
    store.setActiveTab(first.id);

    await expectLater(
      controller.open(
        second,
        activate: (view) async {
          activated.add(view.id);
          if (view.id == second.id) throw StateError('failed');
        },
      ),
      throwsStateError,
    );

    expect(store.tabById(second.id), isNull);
    expect(store.activeTabId, first.id);
    expect(activated, <String>[second.id, first.id]);
  });

  test('failed select restores the previous active tab', () async {
    final store = ViewWorkspaceStore.standard();
    final controller = ViewTabLifecycleController(store);
    final first = tab('first');
    final second = tab('second');
    store
      ..addTab(first)
      ..addTab(second)
      ..setActiveTab(first.id);

    await expectLater(
      controller.select(
        second.id,
        activate: (view) async {
          if (view.id == second.id) throw StateError('failed');
        },
      ),
      throwsStateError,
    );

    expect(store.activeTabId, first.id);
  });

  test('closing active tab chooses its deterministic neighbour', () async {
    final store = ViewWorkspaceStore.standard();
    final controller = ViewTabLifecycleController(store);
    final first = tab('first');
    final middle = tab('middle');
    final last = tab('last');
    store
      ..addTab(first)
      ..addTab(middle)
      ..addTab(last)
      ..setActiveTab(middle.id);

    final result = await controller.close(middle.id, activate: (_) async {});

    expect(result?.closing?.id, middle.id);
    expect(result?.active?.id, last.id);
    expect(result?.activated, isTrue);
    expect(store.activeTabId, last.id);
    expect(store.tabById(middle.id), isNull);
  });

  test('final tab cannot be closed by application controller', () async {
    final store = ViewWorkspaceStore.standard();
    final controller = ViewTabLifecycleController(store);
    final only = tab('only');
    store
      ..addTab(only)
      ..setActiveTab(only.id);

    final result = await controller.close(only.id, activate: (_) async {});

    expect(result, isNull);
    expect(store.activeTabId, only.id);
    expect(store.tabs, hasLength(1));
  });
}
