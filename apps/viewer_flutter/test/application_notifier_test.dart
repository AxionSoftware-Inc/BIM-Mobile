import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/core/application/signals/application_notifier.dart';

void main() {
  test('application value notifier publishes only semantic changes', () {
    final value = ApplicationValueNotifier<int>(1);
    var notifications = 0;
    void listener() => notifications++;

    value.addListener(listener);
    value.value = 1;
    expect(notifications, 0);

    value.value = 2;
    expect(value.value, 2);
    expect(notifications, 1);

    value.removeListener(listener);
    value.value = 3;
    expect(notifications, 1);
  });

  test('application notifier tolerates listener removal during dispatch', () {
    final notifier = ApplicationChangeNotifier();
    var firstCalls = 0;
    var secondCalls = 0;

    late void Function() second;
    void first() {
      firstCalls++;
      notifier.removeListener(second);
    }

    second = () => secondCalls++;
    notifier
      ..addListener(first)
      ..addListener(second)
      ..notifyListeners();

    expect(firstCalls, 1);
    expect(secondCalls, 0);
  });
}
