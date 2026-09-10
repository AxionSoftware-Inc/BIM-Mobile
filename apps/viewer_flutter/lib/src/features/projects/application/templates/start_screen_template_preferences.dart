/// App-owned preferences for project-template cards shown on the start screen.
///
/// Template identity remains engine-owned. These values affect presentation
/// only, so rename/hide operations never mutate an existing BIM project.
final class StartScreenTemplatePreferences {
  const StartScreenTemplatePreferences({
    this.names = const <String, String>{},
    this.hidden = const <String>{},
  });

  final Map<String, String> names;
  final Set<String> hidden;

  factory StartScreenTemplatePreferences.fromJson(Object? value) {
    if (value is! Map) return const StartScreenTemplatePreferences();
    final names = <String, String>{};
    final rawNames = value['names'];
    if (rawNames is Map) {
      for (final entry in rawNames.entries) {
        final key = entry.key?.toString().trim() ?? '';
        final title = entry.value?.toString().trim() ?? '';
        if (key.isNotEmpty && title.isNotEmpty) names[key] = title;
      }
    }
    final hidden = <String>{
      if (value['hidden'] is List)
        ...(value['hidden'] as List)
            .map((entry) => entry?.toString().trim() ?? '')
            .where((entry) => entry.isNotEmpty),
    };
    return StartScreenTemplatePreferences(
      names: Map<String, String>.unmodifiable(names),
      hidden: Set<String>.unmodifiable(hidden),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'names': names,
        'hidden': hidden.toList()..sort(),
      };

  StartScreenTemplatePreferences rename(String templateId, String title) {
    final id = templateId.trim();
    final value = title.trim();
    if (id.isEmpty || value.isEmpty) return this;
    return StartScreenTemplatePreferences(
      names: Map<String, String>.unmodifiable(<String, String>{
        ...names,
        id: value,
      }),
      hidden: hidden,
    );
  }

  StartScreenTemplatePreferences setHidden(String templateId, bool value) {
    final id = templateId.trim();
    if (id.isEmpty) return this;
    final next = <String>{...hidden};
    if (value) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return StartScreenTemplatePreferences(
      names: names,
      hidden: Set<String>.unmodifiable(next),
    );
  }
}
