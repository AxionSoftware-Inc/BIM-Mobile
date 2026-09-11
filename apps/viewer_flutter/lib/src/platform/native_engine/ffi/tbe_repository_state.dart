part of 'tbe_ffi.dart';

/// Mutable state for one native project session.
///
/// Keeping handles, active-view scope and persistence checkpoints together
/// prevents query and authoring services from each inventing their own session
/// state. The state is deliberately not exposed outside the FFI adapter.
final class TbeRepositoryState {
  ffi.Pointer<ffi.Void>? handle;
  String? projectName;
  int activeLevelId = 0;
  bool fullSceneRenderScope = false;
  String? currentJson;
  String? currentJsonPath;
  String? currentPackagePath;
  int? lastCreatedElementId;
}
