import 'package:flutter/material.dart';

import 'workspace_chrome.dart';

/// Revit-style launch page shown before a project is opened.
class StartScreen extends StatelessWidget {
  const StartScreen({
    super.key,
    required this.onOpen,
    required this.onCreate,
    required this.onSelectTemplate,
    this.busy = false,
    this.errorMessage,
  });

  final VoidCallback onOpen;
  final VoidCallback onCreate;
  final ValueChanged<WorkspaceTemplate> onSelectTemplate;
  final bool busy;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1080),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Start a project',
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF173D35),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Open an existing BIM project or start with a template.',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: busy ? null : onOpen,
                            icon: const Icon(Icons.folder_open_outlined),
                            label: const Text('Open project'),
                          ),
                          OutlinedButton.icon(
                            onPressed: busy ? null : onCreate,
                            icon: const Icon(Icons.add_box_outlined),
                            label: const Text('Create new'),
                          ),
                        ],
                      ),
                      if (errorMessage != null) ...<Widget>[
                        const SizedBox(height: 20),
                        _StartError(message: errorMessage!),
                      ],
                      const SizedBox(height: 42),
                      Text(
                        'Templates',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: <Widget>[
                          for (final card in <Widget>[
                            _TemplateCard(
                              icon: Icons.apartment_outlined,
                              title: 'Default building',
                              subtitle: '3-storey simple starter project',
                              onPressed: busy
                                  ? null
                                  : () => onSelectTemplate(
                                        WorkspaceTemplate.default3,
                                      ),
                            ),
                            _TemplateCard(
                              icon: Icons.location_city_outlined,
                              title: 'Residential tower',
                              subtitle:
                                  '9-storey single-building starter project',
                              onPressed: busy
                                  ? null
                                  : () => onSelectTemplate(
                                        WorkspaceTemplate.tower9,
                                      ),
                            ),
                            _TemplateCard(
                              icon: Icons.grid_view_rounded,
                              title: 'Residential campus',
                              subtitle: '6 buildings, 9 storeys each',
                              onPressed: busy
                                  ? null
                                  : () => onSelectTemplate(
                                        WorkspaceTemplate.campus6x9,
                                      ),
                            ),
                          ])
                            SizedBox(
                              width: constraints.maxWidth >= 760
                                  ? (constraints.maxWidth - 16) / 2
                                  : constraints.maxWidth,
                              height: 148,
                              child: card,
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Choose a template to open a ready-to-edit model in the BIM workspace.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 30, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 5),
                    Text(subtitle),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartError extends StatelessWidget {
  const _StartError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: colors.onErrorContainer),
      ),
    );
  }
}
