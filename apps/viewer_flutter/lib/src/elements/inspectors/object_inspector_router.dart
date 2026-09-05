part of '../../property_editor.dart';

class _ObjectInspectorContext {
  const _ObjectInspectorContext({
    required this.object,
    required this.scene,
    required this.levels,
    required this.units,
    required this.commands,
    required this.onApplied,
  });
  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
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
    required this.onApplied,
  });

  final RenderSceneObject object;
  final RenderScene scene;
  final List<RenderSceneLevel> levels;
  final ProjectUnitSettings units;
  final AuthoringCommandService commands;
  final ApplyInspectorResult onApplied;

  static final Map<String, _ObjectInspectorBuilder> _adapters =
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
    BimElementInspectorKeys.ceiling: _buildCeilingInspector,
    BimElementInspectorKeys.linear: _buildLinearInspector,
    BimElementInspectorKeys.family: _buildFamilyInspector,
    BimElementInspectorKeys.generic: _buildGenericInspector,
  };

  @override
  Widget build(BuildContext context) {
    final key = BimElementInspectorRegistry.standard.keyForKind(object.kindKey);
    final builder =
        _adapters[key] ?? _adapters[BimElementInspectorKeys.generic]!;
    return builder(
      _ObjectInspectorContext(
        object: object,
        scene: scene,
        levels: levels,
        units: units,
        commands: commands,
        onApplied: onApplied,
      ),
    );
  }
}
