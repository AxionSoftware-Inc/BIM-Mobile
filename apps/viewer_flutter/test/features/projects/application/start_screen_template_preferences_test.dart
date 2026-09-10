import 'package:flutter_test/flutter_test.dart';
import 'package:viewer_flutter/src/features/projects/application/templates/start_screen_template_preferences.dart';

void main() {
  test('rename and hidden state remain immutable presentation preferences', () {
    const base = StartScreenTemplatePreferences();
    final renamed = base.rename('architectural', 'Residential');
    final hidden = renamed.setHidden('structural', true);

    expect(base.names, isEmpty);
    expect(renamed.names['architectural'], 'Residential');
    expect(renamed.hidden, isEmpty);
    expect(hidden.hidden, contains('structural'));
    expect(hidden.names['architectural'], 'Residential');
  });

  test('JSON parser ignores empty keys/titles and deduplicates hidden ids', () {
    final parsed = StartScreenTemplatePreferences.fromJson(<String, Object?>{
      'names': <String, Object?>{
        'architectural': '  Architecture  ',
        '': 'Ignored',
        'structural': '   ',
      },
      'hidden': <Object?>['architectural', 'architectural', '', null],
    });

    expect(parsed.names, <String, String>{'architectural': 'Architecture'});
    expect(parsed.hidden, <String>{'architectural'});
  });
}
