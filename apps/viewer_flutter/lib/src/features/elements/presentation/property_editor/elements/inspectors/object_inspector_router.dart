part of '../../property_editor.dart';

class _ObjectInspectorContext {
  const _ObjectInspectorContext({
    required this.object,
    required this.scene,
    required this.levels,
    required this.units,
    required this.commands,
    required this.familyCommands,
    required this.familyAssets,
    required this.onApplied,
  });
  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final FamilyCommandService? familyCommands;
  final FamilyAssetRepository familyAssets;
  final ApplyInspectorResult onApplied;
}

typedef _ObjectInspectorBuilder = Widget Function(_ObjectInspectorContext);

class _ObjectInspectorRouter extends StatelessWidget {
  const _ObjectInspectorRouter({
    required this.object,
    required this.scene,
    required this.levels,
    required this.units,
    required this.commands,
    required this.familyCommands,
    required this.familyAssets,
    required this.onApplied,
  });

  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final FamilyCommandService? familyCommands;
  final FamilyAssetRepository familyAssets;
  final ApplyInspectorResult onApplied;

  static final BimElementInspectorAdapterRegistry _standaloneAdapters =
      BimElementInspectorAdapterRegistry(
    const <BimElementInspectorAdapter>[
      CeilingElementInspectorAdapter(),
      GenericElementInspectorAdapter(),
    ],
  );

  // Temporary bridge for Inspector parts that still depend on private
  // property_editor.dart helpers. Each entry disappears as its standalone
  // BimElementInspectorAdapter lands.
  static final Map<String, _ObjectInspectorBuilder> _legacyAdapters =
      <String, _ObjectInspectorBuilder>{
    BimElementInspectorKeys.wall: (context) => _WallPropertiesSection(
          object: context.object,
          scene: context.scene,
          levels: context.levels,
          units: context.units,
          commands: context.commands,
          onApplied: context.onApplied,
        ),
    BimElementInspectorKeys.opening: (context) => _OpeningPropertiesSection(
          object: context.object,
          scene: context.scene,
          levels: context.levels,
          units: context.units,
          commands: context.commands,
          familyCommands: context.familyCommands,
          familyAssets: context.familyAssets,
          onApplied: context.onApplied,
        ),
    BimElementInspectorKeys.surface: (context) => _FloorPropertiesSection(
          object: context.object,
          scene: context.scene,
          units: context.units,
          commands: context.commands,
          onApplied: context.onApplied,
        ),
    BimElementInspectorKeys.roof: (context) => _RoofPropertiesSection(
          object: context.object,
          scene: context.scene,
          units: context.units,
          commands: context.commands,
          onApplied: context.onApplied,
        ),
    BimElementInspectorKeys.stair: _buildStairInspector,
    BimElementInspectorKeys.linear: _buildLinearInspector,
    BimElementInspectorKeys.family: _buildFamilyInspector,
  };

  @override
  Widget build(BuildContext context) {
    final key = BimElementInspectorRegistry.standard.keyForKind(object.kindKey);
    final standalone = _standaloneAdapters.forKey(key);
    if (standalone != null) {
      return standalone.build(
        context,
        BimInspectorContext(
          object: object,
          scene: scene,
          units: units,
          commands: commands,
          onApplied: onApplied,
        ),
      );
    }

    final legacy = _legacyAdapters[key];
    if (legacy != null) {
      return legacy(
        _ObjectInspectorContext(
          object: object,
          scene: scene,
          levels: levels,
          units: units,
          commands: commands,
          familyCommands: familyCommands,
          familyAssets: familyAssets,
          onApplied: onApplied,
        ),
      );
    }

    // A module can temporarily point at a not-yet-migrated key without making
    // the Inspector blank. Generic is always the final standalone fallback.
    final fallback =
        _standaloneAdapters.forKey(BimElementInspectorKeys.generic)!;
    return fallback.build(
      context,
      BimInspectorContext(
        object: object,
        scene: scene,
        units: units,
        commands: commands,
        onApplied: onApplied,
      ),
    );
  }
}
