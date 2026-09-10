import 'package:flutter/foundation.dart';

import '../../../core/application/signals/application_notifier.dart';
import '../application/annotation_workspace_runtime.dart';

/// Flutter-only bridge over framework-neutral annotation application signals.
final class ApplicationListenableAdapter extends ChangeNotifier {
  ApplicationListenableAdapter(ApplicationChangeNotifier source)
      : _source = source {
    _source.addListener(_forwardChange);
  }

  final ApplicationChangeNotifier _source;

  void _forwardChange() => notifyListeners();

  @override
  void dispose() {
    _source.removeListener(_forwardChange);
    super.dispose();
  }
}

/// Presentation-owned observables for annotation widgets.
abstract final class AnnotationPresentationSignals {
  static final ApplicationListenableAdapter document =
      ApplicationListenableAdapter(AnnotationWorkspaceRuntime.document);
  static final ApplicationListenableAdapter draft =
      ApplicationListenableAdapter(AnnotationWorkspaceRuntime.draft);
  static final ApplicationListenableAdapter selection =
      ApplicationListenableAdapter(AnnotationWorkspaceRuntime.selectedAnnotationId);
  static final ApplicationListenableAdapter moveSelected =
      ApplicationListenableAdapter(AnnotationWorkspaceRuntime.moveSelectedArmed);
}
