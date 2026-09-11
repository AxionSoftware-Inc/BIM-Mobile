import '../bim_element_module.dart';

final class RoomElementModule extends BimElementModule {
  const RoomElementModule()
      : super.withIdentity(
          identity: BimElementKindCatalog.room,
          typeFamily: BimElementTypeFamily.none,
          isPlanCore: true,
        );
}
