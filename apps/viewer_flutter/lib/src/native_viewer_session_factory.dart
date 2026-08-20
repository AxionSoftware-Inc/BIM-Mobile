import 'tbe_ffi.dart';
import 'viewer_project_session.dart';

/// FFI composition adapter. It is the only Flutter-side factory that knows
/// how to prepare and bind the packaged native BIM library.
class NativeViewerSessionFactory
    implements ViewerSessionFactory<ViewerEngineSession> {
  @override
  Future<ViewerEngineSession> create() async {
    await TbeViewerApi.prepareForCurrentPlatform();
    return ViewerRepository(TbeViewerApi.load());
  }
}
