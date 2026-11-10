import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import '../../support/recording_app_diagnostic_sink.dart';

void main() {
  test('writes structured operation lifecycle events', () {
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);

    diagnostics.operationStarted(
      operationKey: 'install',
      operationId: 'operation-1',
      context: const {'sourceKind': 'git'},
    );
    diagnostics.operationSucceeded(
      operationKey: 'install',
      operationId: 'operation-1',
      duration: const Duration(milliseconds: 42),
      context: const {'affectedSlotCount': 2},
    );

    expect(sink.events, hasLength(2));
    expect(sink.events.first.event, 'operation.started');
    expect(sink.events.first.operationKey, 'install');
    expect(sink.events.first.operationId, 'operation-1');
    expect(sink.events.last.event, 'operation.succeeded');
    expect(sink.events.last.duration, const Duration(milliseconds: 42));
    expect(sink.events.last.context['affectedSlotCount'], 2);
  });

  test('redacts credentials, process output, content, and URL secrets', () {
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.gitFailed,
      operation: WorkspaceOperationKind.install,
      context: const {
        'locator': 'https://user:pass@example.com/repo?token=secret',
        'environment': {'API_KEY': 'plain-secret'},
        'stderr': 'fatal: token=secret',
        'skillContent': 'private instructions',
      },
      diagnostic:
          'authorization: Bearer abc https://user:pass@example.com/repo?x=y',
    );

    diagnostics.failure(
      error: failure,
      failure: failure,
      stackTrace: StackTrace.fromString(
        '#0 install (file:///tmp/install.dart:1:1)\n',
      ),
    );

    final json = jsonEncode(sink.events.single.toJson());
    expect(json, contains('example.com/repo'));
    expect(json, isNot(contains('user:pass')));
    expect(json, isNot(contains('plain-secret')));
    expect(json, isNot(contains('private instructions')));
    expect(json, isNot(contains('Bearer abc')));
    expect(json, isNot(contains('token=secret')));
    expect(json, contains(AppDiagnosticSanitizer.redacted));
  });

  test('reports the same error object only once', () {
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.ioFailure,
      operation: WorkspaceOperationKind.refresh,
    );

    diagnostics.failure(error: failure, failure: failure);
    diagnostics.failure(error: failure, failure: failure);

    expect(sink.events, hasLength(1));
  });

  test('uses the caller operation and promotes a failure operation id', () {
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.repositoryNotOpen,
      operation: WorkspaceOperationKind.open,
      context: const {'operationId': 'recovery-1'},
    );

    diagnostics.failure(
      error: failure,
      failure: failure,
      operationKey: WorkspaceOperationKind.discoverExternalSkills.name,
    );

    expect(sink.events.single.operationKey, 'discoverExternalSkills');
    expect(sink.events.single.operationId, 'recovery-1');
  });

  test('bounds diagnostics and stack traces', () {
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.operationFailed,
      operation: WorkspaceOperationKind.install,
      diagnostic: List.filled(5000, 'x').join(),
    );
    final stack = StackTrace.fromString(
      List.generate(
        60,
        (index) => '#$index ${List.filled(500, 'y').join()}',
      ).join('\n'),
    );

    diagnostics.failure(error: failure, failure: failure, stackTrace: stack);

    final event = sink.events.single;
    expect(
      event.diagnostic!.length,
      lessThanOrEqualTo(AppDiagnosticSanitizer.maximumDiagnosticLength + 3),
    );
    expect(
      event.stack.length,
      lessThanOrEqualTo(AppDiagnosticSanitizer.maximumStackFrames),
    );
    expect(
      event.stack.fold<int>(0, (total, line) => total + line.length),
      lessThanOrEqualTo(AppDiagnosticSanitizer.maximumStackLength + 3),
    );
  });

  test('unknown errors expose type and stack without raw error text', () {
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);
    final error = StateError('/private/path?token=secret');

    diagnostics.unhandled(
      error: error,
      operationKey: 'unhandledPlatformError',
      stackTrace: StackTrace.fromString('#0 main (main.dart:1:1)'),
    );

    final event = sink.events.single;
    final json = jsonEncode(event.toJson());
    expect(event.errorType, 'StateError');
    expect(event.diagnostic, isNull);
    expect(event.stack, isNotEmpty);
    expect(json, isNot(contains('/private/path')));
    expect(json, isNot(contains('secret')));
  });

  test('Flutter errors retain a sanitized framework diagnostic', () {
    final sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);

    diagnostics.unhandled(
      error: FlutterError(
        'Layout failed for https://user:pass@example.com/?token=secret',
      ),
      operationKey: 'unhandledFlutterError',
    );

    final diagnostic = sink.events.single.diagnostic!;
    expect(diagnostic, contains('Layout failed'));
    expect(diagnostic, isNot(contains('user:pass')));
    expect(diagnostic, isNot(contains('token=secret')));
  });

  test('debug sink emits one searchable terminal line', () {
    final output = <String>[];
    final diagnostics = AppDiagnostics.debug(writer: output.add);

    diagnostics.info(
      'app.bootstrap.ready',
      context: const {'platform': 'macos'},
    );

    expect(output, hasLength(1));
    expect(output.single, startsWith('[SkillsManager] {'));
    expect(output.single, contains('app.bootstrap.ready'));
    expect(output.single, contains('macos'));
  });
}
