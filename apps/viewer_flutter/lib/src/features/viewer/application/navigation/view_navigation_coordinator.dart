/// Serializes view changes so a slower engine response cannot overwrite a
/// newer elevation, section, plan, or 3D navigation request.
///
/// User-driven view navigation is replaceable: when several requests arrive
/// while a native/engine operation is busy, only the newest queued request is
/// still relevant. [run] therefore has latest-request-wins semantics. Strict
/// non-replaceable work can opt into [runStrict].
final class ViewNavigationCoordinator {
  Future<void> _tail = Future<void>.value();
  int _latestGeneration = 0;

  /// Enqueues replaceable navigation and drops stale requests that have not
  /// started yet.
  ///
  /// An FFI call already in flight cannot be cancelled, so that operation is
  /// allowed to finish. The newest request then runs immediately after it and
  /// converges the renderer to the final requested view. Rapid 2D/3D tapping
  /// therefore costs at most the in-flight transition plus the final target,
  /// rather than replaying every intermediate tap.
  Future<void> run(Future<void> Function() operation) {
    final generation = ++_latestGeneration;
    return _enqueue(() async {
      if (generation != _latestGeneration) return;
      await operation();
    });
  }

  /// Same coalescing lane as [run], but exposes a current-generation probe to
  /// callers that can stop between expensive asynchronous stages.
  Future<void> runLatest(
    Future<void> Function(bool Function() isCurrent) operation,
  ) {
    final generation = ++_latestGeneration;
    bool isCurrent() => generation == _latestGeneration;
    return _enqueue(() async {
      if (!isCurrent()) return;
      await operation(isCurrent);
    });
  }

  /// Serializes an operation without making it replaceable.
  Future<void> runStrict(Future<void> Function() operation) =>
      _enqueue(operation);

  Future<void> _enqueue(Future<void> Function() operation) {
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

  /// Invalidates replaceable queued navigation without affecting strict work.
  void invalidateLatest() {
    _latestGeneration += 1;
  }
}
