import '../../tbe_ffi.dart';
import '../../viewer_project_session.dart';

/// FFI composition adapter.
///
/// PLATFORM BOUNDARY: this is the only app-composition factory that knows how
/// to prepare and bind the packaged native BIM library. Feature/application
/// code depends on `ViewerSessionFactory`, never on FFI loading details.
final class NativeViewerSessionFactory
    implements ViewerSessionFactory<ViewerEngineSession> {
  @override
  Future<ViewerEngineSession> create() async {
    await TbeViewerApi.prepareForCurrentPlatform();
    return ViewerRepository(TbeViewerApi.load());
  }
}
