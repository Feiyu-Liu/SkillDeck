import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';

enum AppDiagnosticLevel { info, warning, error }

final class AppDiagnosticEvent {
  AppDiagnosticEvent({
    required this.level,
    required this.event,
    this.operationKey,
    this.operationId,
    this.codeKey,
    this.duration,
    this.context = const {},
    this.diagnostic,
    this.errorType,
    this.stack = const [],
  });

  final AppDiagnosticLevel level;
  final String event;
  final String? operationKey;
  final String? operationId;
  final String? codeKey;
  final Duration? duration;
  final Map<String, Object?> context;
  final String? diagnostic;
  final String? errorType;
  final List<String> stack;

  Map<String, Object?> toJson() => {
    'level': level.name,
    'event': event,
    if (operationKey != null) 'operation': operationKey,
    if (operationId != null) 'operationId': operationId,
    if (codeKey != null) 'code': codeKey,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (context.isNotEmpty) 'context': context,
    if (diagnostic != null && diagnostic!.isNotEmpty) 'diagnostic': diagnostic,
    if (errorType != null) 'errorType': errorType,
    if (stack.isNotEmpty) 'stack': stack,
  };
}

abstract interface class AppDiagnosticSink {
  void write(AppDiagnosticEvent event);
}

final class NoopAppDiagnosticSink implements AppDiagnosticSink {
  const NoopAppDiagnosticSink();

  @override
  void write(AppDiagnosticEvent event) {}
}

final class DebugPrintAppDiagnosticSink implements AppDiagnosticSink {
  const DebugPrintAppDiagnosticSink({required void Function(String) writer})
    : _writer = writer;

  final void Function(String) _writer;

  @override
  void write(AppDiagnosticEvent event) {
    _writer('[SkillsManager] ${jsonEncode(event.toJson())}');
  }
}

final appDiagnosticsProvider = Provider<AppDiagnostics>(
  (ref) => AppDiagnostics.disabled(),
);

final class AppDiagnostics {
  AppDiagnostics({
    required AppDiagnosticSink sink,
    AppDiagnosticSanitizer sanitizer = const AppDiagnosticSanitizer(),
  }) : _sink = sink,
       _sanitizer = sanitizer;

  factory AppDiagnostics.disabled() =>
      AppDiagnostics(sink: const NoopAppDiagnosticSink());

  factory AppDiagnostics.debug({required void Function(String) writer}) =>
      AppDiagnostics(sink: DebugPrintAppDiagnosticSink(writer: writer));

  static const _reportedErrorLimit = 128;
  static final _omitDetailsKey = Object();

  /// Keeps event metadata while omitting request-sensitive details throughout
  /// an asynchronous call chain. Unrelated GUI operations retain their details.
  static T withoutDetails<T>(T Function() action) =>
      runZoned(action, zoneValues: {_omitDetailsKey: true});

  final AppDiagnosticSink _sink;
  final AppDiagnosticSanitizer _sanitizer;
  final Queue<Object> _reportedErrors = Queue<Object>();

  void info(String event, {Map<String, Object?> context = const {}}) {
    _write(
      AppDiagnosticEvent(
        level: AppDiagnosticLevel.info,
        event: event,
        context: context,
      ),
    );
  }

  void operationStarted({
    required String operationKey,
    String? operationId,
    Map<String, Object?> context = const {},
  }) {
    _write(
      AppDiagnosticEvent(
        level: AppDiagnosticLevel.info,
        event: 'operation.started',
        operationKey: operationKey,
        operationId: operationId,
        context: context,
      ),
    );
  }

  void operationSucceeded({
    required String operationKey,
    String? operationId,
    required Duration duration,
    Map<String, Object?> context = const {},
  }) {
    _write(
      AppDiagnosticEvent(
        level: AppDiagnosticLevel.info,
        event: 'operation.succeeded',
        operationKey: operationKey,
        operationId: operationId,
        duration: duration,
        context: context,
      ),
    );
  }

  void cancellationRequested({
    required String operationKey,
    String? operationId,
  }) {
    _write(
      AppDiagnosticEvent(
        level: AppDiagnosticLevel.info,
        event: 'operation.cancel_requested',
        operationKey: operationKey,
        operationId: operationId,
      ),
    );
  }

  void failure({
    required Object error,
    required AppFailure failure,
    StackTrace? stackTrace,
    String? operationKey,
    String? operationId,
    Duration? duration,
  }) {
    if (!_remember(error)) return;
    final cancelled = failure.message == AppFailureMessage.operationCancelled;
    _write(
      AppDiagnosticEvent(
        level: cancelled ? AppDiagnosticLevel.info : AppDiagnosticLevel.error,
        event: cancelled ? 'operation.cancelled' : 'operation.failed',
        operationKey: operationKey ?? failure.operationKey,
        operationId: operationId ?? _operationIdOf(failure),
        codeKey: failure.codeKey,
        duration: duration,
        context: failure.context,
        diagnostic: failure.diagnostic,
        errorType: error.runtimeType.toString(),
        stack: _stackLines(stackTrace),
      ),
    );
  }

  void unhandled({
    required Object error,
    required String operationKey,
    StackTrace? stackTrace,
  }) {
    if (!_remember(error)) return;
    final failure = error is AppFailure ? error : null;
    _write(
      AppDiagnosticEvent(
        level: AppDiagnosticLevel.error,
        event: 'error.unhandled',
        operationKey: operationKey,
        codeKey: failure?.codeKey ?? 'unexpected',
        context: failure?.context ?? const {},
        diagnostic: failure?.diagnostic ?? _flutterDiagnostic(error),
        errorType: error.runtimeType.toString(),
        stack: _stackLines(stackTrace),
      ),
    );
  }

  bool _remember(Object error) {
    if (_reportedErrors.any((reported) => identical(reported, error))) {
      return false;
    }
    if (_reportedErrors.length == _reportedErrorLimit) {
      _reportedErrors.removeFirst();
    }
    _reportedErrors.addLast(error);
    return true;
  }

  String? _operationIdOf(AppFailure failure) {
    final value = failure.context['operationId'];
    return value is String ? value : null;
  }

  String? _flutterDiagnostic(Object error) =>
      error is FlutterError ? error.toString() : null;

  List<String> _stackLines(StackTrace? stackTrace) {
    if (stackTrace == null) return const [];
    return stackTrace
        .toString()
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .take(AppDiagnosticSanitizer.maximumStackFrames)
        .toList(growable: false);
  }

  void _write(AppDiagnosticEvent event) {
    try {
      if (Zone.current[_omitDetailsKey] == true) {
        event = AppDiagnosticEvent(
          level: event.level,
          event: event.event,
          operationKey: event.operationKey,
          codeKey: event.codeKey,
          duration: event.duration,
          errorType: event.errorType,
        );
      }
      _sink.write(_sanitizer.sanitize(event));
    } on Object {
      // Diagnostics must never become a second application failure.
    }
  }
}

final class AppDiagnosticSanitizer {
  const AppDiagnosticSanitizer();

  static const redacted = '[REDACTED]';
  static const maximumDiagnosticLength = 4 * 1024;
  static const maximumStackLength = 16 * 1024;
  static const maximumStackFrames = 40;
  static const maximumTextLength = 2 * 1024;

  AppDiagnosticEvent sanitize(AppDiagnosticEvent event) => AppDiagnosticEvent(
    level: event.level,
    event: _sanitizeText(event.event, maximumTextLength),
    operationKey: _nullableText(event.operationKey),
    operationId: _nullableText(event.operationId),
    codeKey: _nullableText(event.codeKey),
    duration: event.duration,
    context: _sanitizeMap(event.context),
    diagnostic: event.diagnostic == null
        ? null
        : _sanitizeText(event.diagnostic!, maximumDiagnosticLength),
    errorType: _nullableText(event.errorType),
    stack: _sanitizeStack(event.stack),
  );

  String? _nullableText(String? value) =>
      value == null ? null : _sanitizeText(value, maximumTextLength);

  Map<String, Object?> _sanitizeMap(Map<String, Object?> source) =>
      Map.unmodifiable(
        source.map(
          (key, value) => MapEntry(
            _sanitizeText(key, maximumTextLength),
            _isSensitiveKey(key) ? redacted : _sanitizeValue(value),
          ),
        ),
      );

  Object? _sanitizeValue(Object? value) {
    if (value == null || value is bool || value is num) return value;
    if (value is String) return _sanitizeText(value, maximumTextLength);
    if (value is Map<String, Object?>) return _sanitizeMap(value);
    if (value is Iterable<Object?>) {
      return List<Object?>.unmodifiable(value.map(_sanitizeValue));
    }
    return redacted;
  }

  List<String> _sanitizeStack(List<String> stack) {
    final sanitized = <String>[];
    var remaining = maximumStackLength;
    for (final frame in stack.take(maximumStackFrames)) {
      if (remaining <= 0) break;
      final line = _sanitizeText(frame, remaining);
      sanitized.add(line);
      remaining -= line.length;
    }
    return List.unmodifiable(sanitized);
  }

  String _sanitizeText(String source, int maximumLength) {
    var sanitized = source
        .replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f]'), ' ')
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ');
    sanitized = sanitized.replaceAllMapped(
      RegExp(r'[a-zA-Z][a-zA-Z0-9+.-]*://[^\s\]\[{}<>"\x27]+'),
      (match) => _sanitizeUrl(match.group(0)!),
    );
    sanitized = sanitized
        .replaceAll(
          RegExp(
            r'\b(authorization|proxy-authorization)\s*:\s*[^\s,;]+(?:\s+[^\s,;]+)?',
            caseSensitive: false,
          ),
          r'$1: [REDACTED]',
        )
        .replaceAll(
          RegExp(
            r'''\b(password|passwd|token|secret|api[_-]?key|access[_-]?key|private[_-]?key)\s*[:=]\s*([^\s,;]+|"[^"]*"|'[^']*')''',
            caseSensitive: false,
          ),
          r'$1=[REDACTED]',
        );
    if (sanitized.length > maximumLength) {
      return '${sanitized.substring(0, maximumLength)}...';
    }
    return sanitized;
  }

  String _sanitizeUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return raw;
    return uri
        .replace(
          userInfo: uri.userInfo.isEmpty ? null : 'REDACTED',
          queryParameters: uri.queryParameters.isEmpty
              ? null
              : {for (final key in uri.queryParameters.keys) key: redacted},
        )
        .toString();
  }

  bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'env' ||
        normalized == 'environment' ||
        normalized == 'environmentvariables' ||
        normalized == 'stdout' ||
        normalized == 'stderr' ||
        normalized == 'processoutput' ||
        normalized == 'output' ||
        normalized == 'skillbytes' ||
        normalized == 'skillcontent' ||
        normalized == 'content' ||
        normalized == 'bytes' ||
        normalized.contains('password') ||
        normalized.contains('credential') ||
        normalized.contains('authorization') ||
        normalized.contains('apikey') ||
        normalized.contains('accesstoken') ||
        normalized.contains('refreshtoken') ||
        normalized.contains('privatekey') ||
        normalized == 'token' ||
        normalized == 'secret';
  }
}
