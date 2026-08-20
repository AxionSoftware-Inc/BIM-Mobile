import 'viewer_project_session.dart';

/// Owns the currently active native project session for the application shell.
///
/// Lifecycle services create sessions; this controller makes replacement and
/// disposal deterministic so feature widgets never own native handles.
class ProjectSessionController<T extends ViewerProjectSession> {
  T? _session;
  bool _engineBacked = false;

  T? get session => _session;
  bool get isEngineBacked => _engineBacked;

  void activate(T session) {
    if (!identical(_session, session)) {
      _session?.dispose();
      _session = session;
    }
    _engineBacked = true;
  }

  void markUnavailable() => _engineBacked = false;

  void dispose() {
    _session?.dispose();
    _session = null;
    _engineBacked = false;
  }
}
