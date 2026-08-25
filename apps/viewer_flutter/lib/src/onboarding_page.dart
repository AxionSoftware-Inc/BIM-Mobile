import 'package:flutter/material.dart';

/// First-run orientation for tablet users. It is deliberately local and
/// lightweight: no images, network requests, or renderer startup are needed.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pages = PageController();
  int _page = 0;

  static const _steps = <({IconData icon, String title, String body})>[
    (
      icon: Icons.architecture_outlined,
      title: 'Work with models on a tablet',
      body:
          'Floor plans, elevations, sections, and 3D views stay in one coordinated project.',
    ),
    (
      icon: Icons.pan_tool_alt_outlined,
      title: 'Natural gestures',
      body:
          'Use one finger to select or draw. Use two fingers to pan and pinch to zoom.',
    ),
    (
      icon: Icons.save_as_outlined,
      title: 'Keep your work safe',
      body:
          'Undo/redo, recovery autosave, and save-on-exit protection are built in.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _steps.length - 1) {
      widget.onComplete();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final step = _steps[_page];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: widget.onComplete,
                      child: const Text('Skip'),
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pages,
                      itemCount: _steps.length,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, index) {
                        final item = _steps[index];
                        return Semantics(
                          container: true,
                          header: true,
                          label: item.title,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: colors.primaryContainer,
                                  shape: BoxShape.circle,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(28),
                                  child: Icon(
                                    item.icon,
                                    size: 76,
                                    color: colors.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 36),
                              Text(
                                item.title,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                item.body,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var index = 0; index < _steps.length; index++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: index == _page ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: index == _page
                                ? colors.primary
                                : colors.outlineVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _next,
                      icon: Icon(
                        _page == _steps.length - 1
                            ? Icons.check
                            : Icons.arrow_forward,
                      ),
                      label: Text(
                        _page == _steps.length - 1 ? 'Get started' : 'Continue',
                      ),
                    ),
                  ),
                  // Keep the current page exposed to TalkBack without making
                  // the decorative indicator focusable.
                  Semantics(
                    liveRegion: true,
                    label: '${step.title}, ${_page + 1}/${_steps.length}',
                    child: const SizedBox(height: 1),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
