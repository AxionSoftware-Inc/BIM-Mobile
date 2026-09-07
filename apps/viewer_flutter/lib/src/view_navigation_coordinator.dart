/// Serializes view changes so a slower engine response cannot overwrite a
/// newer elevation, section, plan, or 3D navigation request.
///
/// Strict operations use [run]. User-driven navigation that is replaceable
/// (for example repeated 2D/3D taps) uses [runLatest]. Only the newest queued
/// request is allowed to start, while an operation that is already in flight
/// receives an [isCurrent] probe so it can stop between asynchronous stages.
/// This keeps expensive native projection/scope reloads from piling up behind
/// rapid taps and gives the last requested view deterministic ownership.
final class ViewNavigationCoordinator {
  Future<void> _tail = Future<void>.value();
  int _latestGeneration = 0;

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

  /// Runs a replaceable navigation operation.
  ///
  /// Requests waiting in the queue are discarded when a newer request arrives.
  /// An already-running operation cannot cancel a native/FFI call that is in
  /// progress, so callers should inspect [isCurrent] after every expensive
  /// await and return as soon as it becomes false. The newest queued operation
  /// then converges the renderer to the final requested state.
  Future<void> runLatest(
    Future<void> Function(bool Function() isCurrent) operation,
  ) {
    final generation = ++_latestGeneration;
    bool isCurrent() => generation == _latestGeneration;

    return run(() async {
      if (!isCurrent()) return;
      await operation(isCurrent);
    });
  }

  /// Invalidates replaceable queued navigation without affecting strict work.
  /// Useful when a project/session teardown makes the pending target obsolete.
  void invalidateLatest() {
    _latestGeneration += 1;
  }
}
