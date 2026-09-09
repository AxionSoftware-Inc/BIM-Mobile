import 'viewer_scene_gateway.dart';

/// Resolves the currently active scene-query capability for application code.
///
/// Session ownership and engine availability belong to composition/session
/// infrastructure. Scene use-cases consume this narrow resolver instead of
/// coordinating nullable repositories and availability flags themselves.
abstract interface class ViewerSceneGatewayResolver {
  ViewerSceneGateway requireSceneGateway();
}
