import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_unhandled_error_boundary.dart';

import '../../support/recording_app_diagnostic_sink.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reports only a generic typed failure', () {
    final failures = <AppFailure>[];
    final sink = RecordingAppDiagnosticSink();
    final boundary = AppUnhandledErrorBoundary(
      onFailure: failures.add,
      diagnostics: AppDiagnostics(sink: sink),
    );

    boundary.report(
      error: StateError('private detail'),
      stackTrace: StackTrace.fromString('#0 build (app.dart:1:1)'),
      operationKey: AppUnhandledErrorBoundary.flutterOperationKey,
    );

    expect(failures, hasLength(1));
    expect(failures.single, isA<UnexpectedAppFailure>());
    expect(
      failures.single.operationKey,
      AppUnhandledErrorBoundary.flutterOperationKey,
    );
    expect(failures.single.context, isEmpty);
    expect(sink.events.single.event, 'error.unhandled');
    expect(sink.events.single.errorType, 'StateError');
    expect(sink.events.single.stack, isNotEmpty);
  });

  test('install is idempotent and dispose restores global handlers', () {
    final previousFlutterHandler = FlutterError.onError;
    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    final boundary = AppUnhandledErrorBoundary(
      onFailure: (_) {},
      diagnostics: AppDiagnostics.disabled(),
    );
    addTearDown(boundary.dispose);

    boundary
      ..install()
      ..install();

    expect(FlutterError.onError, isNot(same(previousFlutterHandler)));
    expect(
      PlatformDispatcher.instance.onError,
      isNot(same(previousPlatformHandler)),
    );

    boundary.dispose();

    expect(FlutterError.onError, same(previousFlutterHandler));
    expect(PlatformDispatcher.instance.onError, same(previousPlatformHandler));
  });

  test(
    'installed handlers retain diagnostics but only notify platform errors',
    () {
      final failures = <AppFailure>[];
      final sink = RecordingAppDiagnosticSink();
      final boundary = AppUnhandledErrorBoundary(
        onFailure: failures.add,
        diagnostics: AppDiagnostics(sink: sink),
      );
      addTearDown(boundary.dispose);
      boundary.install();
      final flutterError = FlutterError('layout failed');
      final platformError = StateError('async failed');

      FlutterError.onError!(
        FlutterErrorDetails(
          exception: flutterError,
          stack: StackTrace.fromString('#0 build (app.dart:1:1)'),
        ),
      );
      final handled = PlatformDispatcher.instance.onError!(
        platformError,
        StackTrace.fromString('#0 callback (app.dart:2:1)'),
      );

      expect(handled, isTrue);
      expect(failures, hasLength(1));
      expect(
        failures.single.operationKey,
        AppUnhandledErrorBoundary.platformOperationKey,
      );
      expect(sink.events, hasLength(2));
      expect(sink.events.first.diagnostic, 'layout failed');
      expect(sink.events.last.errorType, 'StateError');
      expect(sink.events.every((event) => event.stack.isNotEmpty), isTrue);
    },
  );
}
