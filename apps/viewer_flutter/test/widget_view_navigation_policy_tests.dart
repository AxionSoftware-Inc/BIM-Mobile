part of 'widget_test.dart';

void registerViewNavigationPolicyTests() {
  test('top-down navigation keeps the nearby-level render scope', () {
    final scope = ViewNavigationPolicy.scopeFor(
      mode: RenderSceneProjectionMode.topDown,
      objectCount: 12,
      generatedSection: false,
    );

    expect(scope.refreshSceneScope, isFalse);
    expect(scope.useFullScene, isFalse);
    expect(scope.sourceLabel, 'Nearby levels');
  });

  test('elevation navigation always loads the building scope', () {
    final scope = ViewNavigationPolicy.scopeFor(
      mode: RenderSceneProjectionMode.northElevation,
      objectCount: 500,
      generatedSection: false,
    );

    expect(scope.refreshSceneScope, isTrue);
    expect(scope.useFullScene, isTrue);
    expect(scope.sourceLabel, 'Full building elevation');
  });

  test('small orbit views use the full scene while large scenes stay streamed',
      () {
    final small = ViewNavigationPolicy.scopeFor(
      mode: RenderSceneProjectionMode.isometric,
      objectCount: 120,
      generatedSection: false,
    );
    final large = ViewNavigationPolicy.scopeFor(
      mode: RenderSceneProjectionMode.isometric,
      objectCount: 121,
      generatedSection: false,
    );

    expect(small.useFullScene, isTrue);
    expect(small.sourceLabel, 'Full tower 3D');
    expect(large.useFullScene, isFalse);
    expect(large.sourceLabel, 'Nearby levels');
  });

  test('generated sections never switch to the full orbit scope', () {
    final scope = ViewNavigationPolicy.scopeFor(
      mode: RenderSceneProjectionMode.isometric,
      objectCount: 12,
      generatedSection: true,
    );

    expect(scope.refreshSceneScope, isTrue);
    expect(scope.useFullScene, isFalse);
    expect(scope.sourceLabel, 'Nearby levels');
  });
}
