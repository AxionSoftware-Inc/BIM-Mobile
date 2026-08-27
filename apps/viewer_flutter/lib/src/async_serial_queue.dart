/// A small FIFO lane for asynchronous operations that share mutable state.
///
/// The same primitive is used at the native authoring boundary and at the
/// viewport presentation boundary. Keeping those lanes explicit prevents
/// callers from depending on timing for correctness.
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
