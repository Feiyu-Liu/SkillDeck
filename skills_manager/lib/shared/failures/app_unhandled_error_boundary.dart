import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

typedef UnhandledAppFailureReporter = void Function(AppFailure failure);

final class AppUnhandledErrorBoundary {
  AppUnhandledErrorBoundary({
    required UnhandledAppFailureReporter onFailure,
    required AppDiagnostics diagnostics,
  }) : _onFailure = onFailure,
       _diagnostics = diagnostics;

  static const flutterOperationKey = 'unhandledFlutterError';
  static const platformOperationKey = 'unhandledPlatformError';

  final UnhandledAppFailureReporter _onFailure;
  final AppDiagnostics _diagnostics;

  FlutterExceptionHandler? _previousFlutterHandler;
  ErrorCallback? _previousPlatformHandler;
  FlutterExceptionHandler? _installedFlutterHandler;
  ErrorCallback? _installedPlatformHandler;
  var _installed = false;
  var _reporting = false;

  void install() {
    if (_installed) return;
    _installed = true;
    _previousFlutterHandler = FlutterError.onError;
    _previousPlatformHandler = PlatformDispatcher.instance.onError;

    _installedFlutterHandler = (details) => report(
      error: details.exception,
      stackTrace: details.stack,
      operationKey: flutterOperationKey,
      notifyUser: false,
    );
    _installedPlatformHandler = (error, stackTrace) {
      report(
        error: error,
        stackTrace: stackTrace,
        operationKey: platformOperationKey,
      );
      return true;
    };

    FlutterError.onError = _installedFlutterHandler;
    PlatformDispatcher.instance.onError = _installedPlatformHandler;
  }

  void report({
    required Object error,
    required String operationKey,
    StackTrace? stackTrace,
    bool notifyUser = true,
  }) {
    if (_reporting) return;
    _reporting = true;
    try {
      _diagnostics.unhandled(
        error: error,
        operationKey: operationKey,
        stackTrace: stackTrace,
      );
      if (notifyUser) {
        _onFailure(UnexpectedAppFailure(operationKey: operationKey));
      }
    } finally {
      _reporting = false;
    }
  }

  void dispose() {
    if (!_installed) return;
    if (identical(FlutterError.onError, _installedFlutterHandler)) {
      FlutterError.onError = _previousFlutterHandler;
    }
    if (identical(
      PlatformDispatcher.instance.onError,
      _installedPlatformHandler,
    )) {
      PlatformDispatcher.instance.onError = _previousPlatformHandler;
    }
    _installed = false;
    _previousFlutterHandler = null;
    _previousPlatformHandler = null;
    _installedFlutterHandler = null;
    _installedPlatformHandler = null;
  }
}
