import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

final appFailureReporterProvider = Provider<AppFailureReporter>(
  (ref) => AppFailureReporter(ref.watch(appDiagnosticsProvider)),
);

final class AppFailureReporter {
  const AppFailureReporter(this._diagnostics);

  final AppDiagnostics _diagnostics;

  AppFailure capture(
    Object error,
    StackTrace stackTrace, {
    required String operationKey,
    AppFailureMessage message = AppFailureMessage.unexpected,
    AppRecoveryPolicy recoveryPolicy = AppRecoveryPolicy.retryExplicitly,
    String? operationId,
    Duration? duration,
  }) {
    final failure = normalizeAppFailure(
      error,
      operationKey: operationKey,
      message: message,
      recoveryPolicy: recoveryPolicy,
    );
    _diagnostics.failure(
      error: error,
      failure: failure,
      stackTrace: stackTrace,
      operationKey: operationKey,
      operationId: operationId,
      duration: duration,
    );
    return failure;
  }
}
