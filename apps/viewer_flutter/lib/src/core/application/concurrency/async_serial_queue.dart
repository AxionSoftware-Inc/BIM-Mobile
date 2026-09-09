/// A FIFO lane for asynchronous operations that share mutable state.
///
/// This primitive belongs to the application layer: it coordinates ordering
/// but owns no domain data and has no Flutter/native dependency. Named lanes
/// such as authoring commits and viewport presentation may each own an
/// instance; they must not depend on event-loop timing for correctness.
final class AsyncSerialQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final next = _tail.then<T>((_) => operation());
    // Keep the lane usable after a failed operation. The operation itself
    // still reports its original error to its caller.
    _tail = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return next;
  }
}
