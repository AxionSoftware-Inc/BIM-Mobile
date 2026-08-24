/// Serializes view changes so a slower engine response cannot overwrite a
/// newer elevation, section, plan, or 3D navigation request.
///
/// The coordinator intentionally knows nothing about Flutter or the engine.
/// Callers keep their state transitions in the workspace and enqueue only the
/// complete asynchronous navigation operation.
final class ViewNavigationCoordinator {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() operation) {
    final task = _tail.then<void>(
      (_) => operation(),
      onError: (Object _, StackTrace __) => operation(),
    );
    // Keep the queue alive after a failed operation while preserving the
    // original error on `task` for the caller to handle.
    _tail = task.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return task;
  }
}
