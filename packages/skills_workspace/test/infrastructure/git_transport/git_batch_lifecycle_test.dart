import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_source_transport.dart';
import 'package:test/test.dart';

const _oid = '0123456789012345678901234567890123456789';
final _source = GitBareSource(
  repositoryPath: 'unused.git',
  resolvedRevision: _oid,
  disabledHooksPath: 'unused-hooks',
);
final _request = GitBlobRequest(objectId: _oid, relativePath: 'SKILL.md');

void main() {
  test(
    'consumes output while stdin close is blocked by backpressure',
    () async {
      final process = _BatchProcess();
      final terminator = _Terminator(process);
      final chunks = <int>[];
      final transport = SystemGitSourceTransport(
        batchProcessStarter: (_) async => process,
        processTreeTerminator: terminator,
        commandTimeout: const Duration(milliseconds: 100),
      );
      final result = await transport.streamBlobs(
        _source,
        requests: [_request],
        onChunk: (chunk) async => chunks.addAll(chunk.bytes),
        cancellation: _Cancellation(),
      );
      expect(result, isA<GitTransportSuccess<void>>());
      expect(chunks, [97, 98, 99]);
      expect(terminator.calls, 0);
      expect(process.input.bytes, utf8.encode('$_oid\n'));
    },
  );
  for (final (label, response, reason) in [
    ('header', 'not a blob\n', 'invalidBlobHeader'),
    ('identity', '${'a' * 40} blob 0\n\n', 'invalidBlobHeader'),
    ('EOF', '$_oid blob 4\nabc', 'truncatedBlobOutput'),
    ('terminator', '$_oid blob 3\nabc!', 'missingBlobTerminator'),
    ('limit', '$_oid blob 99\n', 'blobBytesExceededLimit'),
  ]) {
    test('rejects invalid $label and terminates child', () async {
      final process = _BatchProcess(response: response, exitOnRead: false);
      final terminator = _Terminator(process);
      final result = await _run(process, terminator: terminator);
      expect(result.failureOrNull?.code, GitTransportFailureCode.invalidOutput);
      expect(result.failureOrNull?.context['reason'], reason);
      expect(terminator.calls, 1);
      expect(process.exited.isCompleted, isTrue);
      expect(process.output.hasListener, isFalse);
      expect(process.errors.hasListener, isFalse);
    });
  }

  test('streams fragmented and empty blobs in order', () async {
    final process = _BatchProcess(
      response: '$_oid blob 0\n\n$_oid blob 3\nabc\n',
      fragment: true,
    );
    final chunks = <GitBlobChunk>[];
    final result = await _run(
      process,
      requests: [_request, _request],
      onChunk: (chunk) async => chunks.add(chunk),
    );
    expect(result, isA<GitTransportSuccess<void>>());
    expect(chunks.first.bytes, isEmpty);
    expect(chunks.first.isLast, isTrue);
    expect(chunks.skip(1).expand((chunk) => chunk.bytes), [97, 98, 99]);
    expect(chunks.where((chunk) => chunk.isLast).length, 2);
  });

  test('checks cumulative bytes, accepting the exact boundary', () async {
    final accepted = await _run(
      _BatchProcess(response: '$_oid blob 5\n12345\n$_oid blob 5\n67890\n'),
      requests: [_request, _request],
    );
    expect(accepted, isA<GitTransportSuccess<void>>());
    final rejected = await _run(
      _BatchProcess(response: '$_oid blob 5\n12345\n$_oid blob 6\n678901\n'),
      requests: [_request, _request],
    );
    expect(rejected.failureOrNull?.context['reason'], 'blobBytesExceededLimit');
  });

  test('bounds an unterminated header', () async {
    final result = await _run(
      _BatchProcess(response: 'a' * 1025, exitOnRead: false),
    );
    expect(result.failureOrNull?.code, GitTransportFailureCode.invalidOutput);
  });

  test('timeout can interrupt a never-finishing consumer', () async {
    final process = _BatchProcess(exitOnRead: false);
    final result = await _run(
      process,
      onChunk: (_) => Completer<void>().future,
    );
    expect(result.failureOrNull?.code, GitTransportFailureCode.timedOut);
    expect(process.exited.isCompleted, isTrue);
  });

  test('cancellation during process startup delivers no chunks', () async {
    final cancellation = _Cancellation();
    final process = _BatchProcess(exitOnRead: false);
    var calls = 0;
    final transport = SystemGitSourceTransport(
      batchProcessStarter: (_) async {
        cancellation.signal.complete();
        return process;
      },
      processTreeTerminator: _Terminator(process),
    );
    final result = await transport.streamBlobs(
      _source,
      requests: [_request],
      cancellation: cancellation,
      onChunk: (_) async {
        calls++;
      },
    );
    expect(result.failureOrNull?.code, GitTransportFailureCode.cancelled);
    expect(calls, 0);
  });

  test('late cancellation cannot terminate a completed process', () async {
    final cancellation = _Cancellation();
    final process = _BatchProcess();
    final terminator = _Terminator(process);
    final result = await _run(
      process,
      cancellation: cancellation,
      terminator: terminator,
    );
    expect(result, isA<GitTransportSuccess<void>>());
    cancellation.signal.complete();
    await Future<void>.delayed(Duration.zero);
    expect(terminator.calls, 0);
  });

  for (final failAdd in [true, false]) {
    test('handles stdin ${failAdd ? 'add' : 'close'} failure', () async {
      final process = _BatchProcess(
        failInput: true,
        failAdd: failAdd,
        exitOnRead: false,
      );
      final terminator = _Terminator(process);
      final result = await _run(process, terminator: terminator);
      expect(result.failureOrNull?.code, GitTransportFailureCode.ioFailure);
      expect(result.failureOrNull?.context['reason'], 'batchInputWriteFailed');
      expect(terminator.calls, 1);
    });
  }

  test('handles stdout I/O failure', () async {
    final result = await _run(
      _BatchProcess(readError: true, exitOnRead: false),
    );
    expect(result.failureOrNull?.code, GitTransportFailureCode.ioFailure);
    expect(result.failureOrNull?.context['reason'], 'batchOutputReadFailed');
  });

  test(
    'classifies consumer failure separately from malformed output',
    () async {
      final result = await _run(
        _BatchProcess(exitOnRead: false),
        onChunk: (_) async => throw StateError('consumer failed'),
      );
      expect(result.failureOrNull?.code, GitTransportFailureCode.ioFailure);
      expect(result.failureOrNull?.context['reason'], 'blobConsumerFailed');
    },
  );

  for (final stall in [false, true]) {
    test(
      'timeout covers ${stall ? 'blocked I/O' : 'waiting for exit'}',
      () async {
        final process = _BatchProcess(exitOnRead: false, stall: stall);
        final result = await _run(process);
        expect(result.failureOrNull?.code, GitTransportFailureCode.timedOut);
        expect(process.exited.isCompleted, isTrue);
      },
    );
  }

  test(
    'cancellation stops callbacks and absorbs late consumer failure',
    () async {
      final process = _BatchProcess(
        response: '$_oid blob 3\nabc\n$_oid blob 3\nabc\n',
        exitOnRead: false,
      );
      final cancellation = _Cancellation();
      final consumer = Completer<void>();
      var calls = 0;
      final result = await _run(
        process,
        cancellation: cancellation,
        requests: [_request, _request],
        onChunk: (_) {
          calls++;
          cancellation.signal.complete();
          return consumer.future;
        },
      );
      expect(result.failureOrNull?.code, GitTransportFailureCode.cancelled);
      expect(calls, 1);
      expect(process.exited.isCompleted, isTrue);
      consumer.completeError(StateError('late consumer failure'));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
    },
  );

  test('nonzero exit remains a command failure', () async {
    final result = await _run(_BatchProcess(exitStatus: 1));
    expect(result.failureOrNull?.code, GitTransportFailureCode.commandFailed);
  });

  test('failed termination falls back to kill and preserves timeout', () async {
    final process = _BatchProcess(stall: true);
    final result = await _run(
      process,
      terminator: _Terminator(process, fail: true),
    );
    expect(result.failureOrNull?.code, GitTransportFailureCode.timedOut);
    expect(process.exited.isCompleted, isTrue);
  });

  test(
    'pre-cancelled, empty and over-limit requests do not start Git',
    () async {
      var starts = 0;
      final transport = SystemGitSourceTransport(
        maximumFileCount: 1,
        batchProcessStarter: (_) async {
          starts++;
          throw StateError('unexpected start');
        },
      );
      final cancelled = await transport.streamBlobs(
        _source,
        requests: [_request],
        onChunk: (_) async {},
        cancellation: _Cancellation()..signal.complete(),
      );
      expect(cancelled.failureOrNull?.code, GitTransportFailureCode.cancelled);
      final overLimit = await transport.streamBlobs(
        _source,
        requests: [_request, _request],
        onChunk: (_) async {},
        cancellation: _Cancellation(),
      );
      expect(overLimit.failureOrNull?.context['reason'], 'fileCountExceeded');
      final empty = await transport.streamBlobs(
        _source,
        requests: [],
        onChunk: (_) async {},
        cancellation: _Cancellation(),
      );
      expect(empty, isA<GitTransportSuccess<void>>());
      expect(starts, 0);
    },
  );
}

Future<GitTransportResult<void>> _run(
  _BatchProcess process, {
  _Terminator? terminator,
  _Cancellation? cancellation,
  List<GitBlobRequest>? requests,
  GitBlobChunkConsumer? onChunk,
}) =>
    SystemGitSourceTransport(
      batchProcessStarter: (_) async => process,
      processTreeTerminator: terminator ?? _Terminator(process),
      maximumByteSize: 10,
      commandTimeout: const Duration(milliseconds: 100),
    ).streamBlobs(
      _source,
      requests: requests ?? [_request],
      onChunk: onChunk ?? (_) async {},
      cancellation: cancellation ?? _Cancellation(),
    );

final class _BatchProcess implements Process {
  _BatchProcess({
    String response = '$_oid blob 3\nabc\n',
    bool exitOnRead = true,
    int exitStatus = 0,
    bool fragment = false,
    bool stall = false,
    bool readError = false,
    bool failInput = false,
    bool failAdd = false,
  }) : input = _Input(failInput: failInput, failAdd: failAdd) {
    output = StreamController<List<int>>(
      onListen: () {
        if (output.isClosed || stall) return;
        // The child cannot finish consuming stdin until its output is read.
        if (!input.finished.isCompleted) {
          if (failInput) {
            input.finished.completeError(StateError('input failed'));
          } else {
            input.finished.complete();
          }
        }
        if (readError) {
          output.addError(const FileSystemException('read failed'));
        } else if (fragment) {
          for (final byte in utf8.encode(response)) {
            output.add([byte]);
          }
        } else {
          output.add(utf8.encode(response));
        }
        unawaited(output.close());
        unawaited(errors.close());
        if (exitOnRead && !exited.isCompleted) exited.complete(exitStatus);
      },
    );
  }

  final _Input input;
  late final StreamController<List<int>> output;
  final errors = StreamController<List<int>>();
  final exited = Completer<int>();

  @override
  IOSink get stdin => input;
  @override
  Stream<List<int>> get stdout => output.stream;
  @override
  Stream<List<int>> get stderr => errors.stream;
  @override
  Future<int> get exitCode => exited.future;
  @override
  int get pid => 123;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!input.finished.isCompleted) input.finished.complete();
    if (!exited.isCompleted) exited.complete(-1);
    unawaited(output.close());
    unawaited(errors.close());
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Input implements IOSink {
  _Input({this.failInput = false, this.failAdd = false});
  final bool failInput;
  final bool failAdd;
  final bytes = <int>[];
  final finished = Completer<void>();
  @override
  void add(List<int> data) {
    if (failInput && failAdd) throw StateError('input failed');
    bytes.addAll(data);
  }

  @override
  Future<void> close() => finished.future;
  @override
  Future<void> get done => finished.future;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Terminator implements GitProcessTreeTerminator {
  _Terminator(this.process, {this.fail = false});
  final bool fail;
  final _BatchProcess process;
  int calls = 0;
  @override
  Future<void> terminate(int rootProcessId) async {
    calls++;
    if (fail) throw StateError('termination failed');
    process.kill();
  }
}

final class _Cancellation implements GitCancellationSignal {
  final signal = Completer<void>();
  @override
  bool get isCancelled => signal.isCompleted;
  @override
  Future<void> get whenCancelled => signal.future;
}
