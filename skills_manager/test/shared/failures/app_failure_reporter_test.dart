import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

import '../../support/recording_app_diagnostic_sink.dart';

void main() {
  test(
    'normalizes and reports an unknown error without retaining its text',
    () {
      final sink = RecordingAppDiagnosticSink();
      final reporter = AppFailureReporter(AppDiagnostics(sink: sink));
      final error = StateError('token=secret');

      final failure = reporter.capture(
        error,
        StackTrace.fromString('#0 loadCatalog (catalog.dart:1:1)'),
        operationKey: 'loadCatalog',
        message: AppFailureMessage.repositoryOpen,
      );

      expect(failure, isA<UnexpectedAppFailure>());
      expect(failure.message, AppFailureMessage.repositoryOpen);
      expect(failure.toString(), isNot(contains('secret')));
      expect(sink.events.single.operationKey, 'loadCatalog');
      expect(sink.events.single.errorType, 'StateError');
    },
  );
}
