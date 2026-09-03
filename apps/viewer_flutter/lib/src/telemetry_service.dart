import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

/// One small boundary for crash reporting and product events.
///
/// The app contains no user identity or project payload in telemetry. A
/// release build enables the remote Sentry sink only when SENTRY_DSN is passed
/// with --dart-define; local/debug builds stay fully functional without it.
abstract final class AppTelemetry {
  static const String _dsn = String.fromEnvironment('SENTRY_DSN');
  static const String _environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );
  static const String release = String.fromEnvironment(
    'APP_RELEASE',
    defaultValue: 'viewer_flutter@0.2.5+7',
  );

  static Future<void> initialize(
      {required FutureOr<void> Function() appRunner}) {
    // Local/debug builds intentionally do not carry a Sentry DSN. Recent
    // sentry_flutter versions reject a null DSN instead of treating it as a
    // disabled client, so bypass the SDK entirely and still start Flutter.
    if (_dsn.isEmpty) {
      return Future<void>.sync(appRunner);
    }
    return SentryFlutter.init(
      (options) {
        options.dsn = _dsn.isEmpty ? null : _dsn;
        options.environment = _environment;
        options.release = release;
        options.sendDefaultPii = false;
        options.tracesSampleRate = 0.0;
        options.enableAutoSessionTracking = true;
      },
      appRunner: appRunner,
    );
  }

  static void track(
    String event, {
    Map<String, Object?> properties = const <String, Object?>{},
  }) {
    if (!Sentry.isEnabled) return;
    final tags = <String, String>{
      'analytics': 'true',
      for (final entry in properties.entries)
        if (entry.value != null) entry.key: entry.value.toString(),
    };
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'app',
          message: event,
          data: tags,
        ),
      ),
    );
    unawaited(
      Sentry.captureMessage(
        'analytics.$event',
        level: SentryLevel.info,
        withScope: (scope) {
          for (final entry in tags.entries) {
            scope.setTag(entry.key, entry.value);
          }
        },
      ),
    );
  }

  static void captureError(Object error, StackTrace stackTrace) {
    if (!Sentry.isEnabled) return;
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  }
}
