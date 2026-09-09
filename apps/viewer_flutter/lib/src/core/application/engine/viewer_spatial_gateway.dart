import 'viewer_engine_contracts.dart';

/// Read-only spatial query boundary used by plan authoring and selection.
abstract interface class ViewerSpatialGateway {
  List<HitCandidateView> hitTest(
    double modelX,
    double modelY, {
    double toleranceMeters,
  });
}
