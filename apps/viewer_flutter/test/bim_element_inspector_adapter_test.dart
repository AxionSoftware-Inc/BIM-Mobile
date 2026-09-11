import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/elements/presentation/bim_element_inspector_adapter.dart';

void main() {
  test('Inspector adapter registry resolves unique keys', () {
    const wall = _FakeInspectorAdapter('wall');
    const generic = _FakeInspectorAdapter('generic');
    final registry = BimElementInspectorAdapterRegistry(<BimElementInspectorAdapter>[
      wall,
      generic,
    ]);

    expect(registry.forKey('wall'), same(wall));
    expect(registry.forKey(' generic '), same(generic));
    expect(registry.forKey('missing'), isNull);
  });

  test('Inspector adapter registry rejects duplicate keys', () {
    expect(
      () => BimElementInspectorAdapterRegistry(<BimElementInspectorAdapter>[
        const _FakeInspectorAdapter('wall'),
        const _FakeInspectorAdapter('wall'),
      ]),
      throwsA(isA<StateError>()),
    );
  });

  test('Inspector adapter registry rejects an empty key', () {
    expect(
      () => BimElementInspectorAdapterRegistry(<BimElementInspectorAdapter>[
        const _FakeInspectorAdapter('   '),
      ]),
      throwsA(isA<StateError>()),
    );
  });
}

final class _FakeInspectorAdapter implements BimElementInspectorAdapter {
  const _FakeInspectorAdapter(this.key);

  @override
  final String key;

  @override
  Widget build(BuildContext context, BimInspectorContext inspector) =>
      const SizedBox.shrink();
}
