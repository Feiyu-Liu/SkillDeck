import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/source_descriptor.dart';
import 'git_commands.dart';
import 'git_failure_mapper.dart';
import 'git_process.dart';
import 'git_source_transport.dart';
import 'git_transport_result.dart';
import 'git_tree_listing.dart';

/// Source transport backed by the user's system Git executable.
///
/// It creates no working tree. Source bytes leave Git only through `ls-tree`
/// and one bounded `cat-file --batch` process.
final class SystemGitSourceTransport implements GitSourceTransport {
  SystemGitSourceTransport({
    GitProcessRunner? processRunner,
    GitProcessTreeTerminator? processTreeTerminator,
    Future<Process> Function(GitCommand)? batchProcessStarter,
    GitBareCommandBuilder commandBuilder = const GitBareCommandBuilder(),
    GitEnvironmentPolicy environmentPolicy = const GitEnvironmentPolicy(),
    this.commandTimeout = const Duration(minutes: 2),
    this.maximumFileCount = 1000,
    this.maximumRepositoryEntryCount = maximumGitRepositoryEntryCount,
    this.maximumByteSize = 50 * 1024 * 1024,
  }) : _processRunner =
           processRunner ??
           DirectGitProcessRunner(
             maximumOutputBytes: (maximumRepositoryEntryCount + 1) * 4600,
           ),
       _processTreeTerminator =
           processTreeTerminator ?? PlatformGitProcessTreeTerminator.current(),
       _batchProcessStarter = batchProcessStarter ?? _startBatchProcess,
       _commandBuilder = commandBuilder,
       _environmentPolicy = environmentPolicy {
    if (commandTimeout <= Duration.zero) {
      throw ArgumentError.value(commandTimeout, 'commandTimeout');
    }
    if (maximumRepositoryEntryCount <= 0 ||
        maximumFileCount <= 0 ||
        maximumByteSize <= 0) {
      throw ArgumentError('Git source limits must be positive.');
    }
  }

  final GitProcessRunner _processRunner;
  final GitProcessTreeTerminator _processTreeTerminator;
  final Future<Process> Function(GitCommand) _batchProcessStarter;
  final GitBareCommandBuilder _commandBuilder;
  final GitEnvironmentPolicy _environmentPolicy;
  final Duration commandTimeout;
  final int maximumFileCount;
  final int maximumRepositoryEntryCount;
  final int maximumByteSize;

  @override
  Future<GitTransportResult<GitBareSource>> fetchBare(
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  }) async {
    final environment = _environmentPolicy.apply(Platform.environment);
    final commands = <(String, GitCommand)>[
      (
        'initialize',
        _commandBuilder.initialize(
          repositoryPath: repositoryPath,
          disabledHooksPath: disabledHooksPath,
          environment: environment,
        ),
      ),
      (
        'fetch',
        _commandBuilder.fetch(
          repositoryPath: repositoryPath,
          disabledHooksPath: disabledHooksPath,
          locator: source.locator,
          ref: source.ref,
          environment: environment,
        ),
      ),
      (
        'resolve',
        _commandBuilder.resolveFetchedCommit(
          repositoryPath: repositoryPath,
          disabledHooksPath: disabledHooksPath,
          environment: environment,
        ),
      ),
    ];

    GitProcessOutcome? resolved;
    for (final (operation, command) in commands) {
      final outcome = await _processRunner.run(
        command,
        timeout: commandTimeout,
        cancellation: cancellation,
      );
      if (!outcome.succeeded) {
        await _deleteRepository(repositoryPath);
        return mapGitProcessFailure<GitBareSource>(
          outcome,
          operation: operation,
          locator: source.locator,
        );
      }
      resolved = outcome;
    }

    final objectId = resolved!.stdout.trim();
    if (!isGitObjectId(objectId)) {
      await _deleteRepository(repositoryPath);
      return GitTransportFailure<GitBareSource>(
        code: GitTransportFailureCode.invalidOutput,
        context: const <String, Object?>{'operation': 'resolve'},
      );
    }
    return GitTransportSuccess(
      GitBareSource(
        repositoryPath: repositoryPath,
        resolvedRevision: objectId,
        disabledHooksPath: disabledHooksPath,
      ),
    );
  }

  @override
  Future<GitTransportResult<List<GitTreeEntry>>> listTree(
    GitBareSource source, {
    required String repositorySubpath,
    required GitCancellationSignal cancellation,
  }) async {
    final command = _commandBuilder.listTree(
      repositoryPath: source.repositoryPath,
      disabledHooksPath: source.disabledHooksPath,
      objectId: source.resolvedRevision,
      repositorySubpath: repositorySubpath,
      environment: _environmentPolicy.apply(Platform.environment),
    );
    final outcome = await _processRunner.run(
      command,
      timeout: commandTimeout,
      cancellation: cancellation,
    );
    if (!outcome.succeeded) {
      return mapGitProcessFailure<List<GitTreeEntry>>(
        outcome,
        operation: 'listTree',
      );
    }
    if (outcome.stdoutTruncated) {
      return GitTransportFailure<List<GitTreeEntry>>(
        code: GitTransportFailureCode.invalidOutput,
        context: const <String, Object?>{'reason': 'treeOutputExceededLimit'},
      );
    }
    return parseGitTreeListing(
      outcome.stdoutBytes,
      repositorySubpath: repositorySubpath,
      maximumRepositoryEntryCount: maximumRepositoryEntryCount,
    );
  }

  @override
  Future<GitTransportResult<void>> streamBlobs(
    GitBareSource source, {
    required List<GitBlobRequest> requests,
    required GitBlobChunkConsumer onChunk,
    required GitCancellationSignal cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.cancelled,
        context: const {'operation': 'catFileBatch'},
      );
    }
    if (requests.isEmpty) {
      return const GitTransportSuccess<void>(null);
    }
    if (requests.length > maximumFileCount) {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.invalidOutput,
        context: <String, Object?>{
          'reason': 'fileCountExceeded',
          'maximum': maximumFileCount,
        },
      );
    }
    final command = _commandBuilder.catFileBatch(
      repositoryPath: source.repositoryPath,
      disabledHooksPath: source.disabledHooksPath,
      environment: _environmentPolicy.apply(Platform.environment),
      objectIds: requests.map((request) => request.objectId).toList(),
    );

    Process process;
    try {
      process = await _batchProcessStarter(command);
    } on Object {
      return GitTransportFailure<void>(
        code: GitTransportFailureCode.unavailable,
        context: const <String, Object?>{'operation': 'catFileBatch'},
      );
    }

    final stderr = _BoundedDiagnostic(process.stderr, 64 * 1024);
    final reader = _BatchReader(process.stdout);
    final completion = Completer<GitTransportResult<void>>();
    final stopped = Completer<void>();
    var exited = false;
    final exit = process.exitCode.then((code) {
      exited = true;
      return code;
    });

    void complete(GitTransportResult<void> result) {
      if (completion.isCompleted) return;
      if (result is GitTransportFailure<void>) stopped.complete();
      completion.complete(result);
    }

    Future<void> observe(Future<GitTransportResult<void>> task) async {
      try {
        final result = await task;
        if (result is GitTransportFailure<void>) complete(result);
      } on Object {
        complete(_batchIoFailure('batchIoFailed'));
      }
    }

    // Cancellation may have arrived while Process.start was pending.
    if (cancellation.isCancelled) {
      complete(
        GitTransportFailure<void>(
          code: GitTransportFailureCode.cancelled,
          context: const {'operation': 'catFileBatch'},
        ),
      );
    }

    // Attach handlers before either side can fail. In particular, never await
    // stdin.close before consuming stdout: Git writes while reading requests.
    final sinkDone = observe(
      process.stdin.done.then<GitTransportResult<void>>(
        (_) => const GitTransportSuccess<void>(null),
        onError: (Object _, StackTrace _) =>
            _batchIoFailure('batchInputWriteFailed'),
      ),
    );
    final write = observe(_writeBatch(process.stdin, requests));
    final read = observe(
      _consumeBatch(reader, requests, (chunk) async {
        if (stopped.isCompleted) throw const _BatchStopped();
        try {
          await Future.any<void>([
            Future<void>.sync(() => onChunk(chunk)),
            stopped.future.then((_) => throw const _BatchStopped()),
          ]);
        } on _BatchStopped {
          rethrow;
        } on Object {
          throw const _BatchConsumerFailure();
        }
      }),
    );
    final work = observe(() async {
      await Future.wait([write, read, sinkDone]);
      if (completion.isCompleted) return const GitTransportSuccess<void>(null);
      final exitCode = await exit;
      await stderr.close();
      final result = exitCode == 0
          ? const GitTransportSuccess<void>(null)
          : mapGitProcessFailure<void>(
              GitProcessOutcome.exited(
                exitCode: exitCode,
                stderr: stderr.value,
              ),
              operation: 'catFileBatch',
            );
      complete(result);
      return result;
    }());
    final timer = Timer(
      commandTimeout,
      () => complete(
        GitTransportFailure<void>(
          code: GitTransportFailureCode.timedOut,
          context: const {'operation': 'catFileBatch'},
        ),
      ),
    );
    // A Stream subscription can be cancelled, unlike a callback retained on
    // a long-lived cancellation Future after every successful batch.
    final cancellationSubscription = cancellation.whenCancelled
        .asStream()
        .listen(
          (_) => complete(
            GitTransportFailure<void>(
              code: GitTransportFailureCode.cancelled,
              context: const {'operation': 'catFileBatch'},
            ),
          ),
          onError: (Object _, StackTrace _) =>
              complete(_batchIoFailure('cancellationFailed')),
        );
    try {
      final result = await completion.future;
      if (result is GitTransportFailure<void> && !exited) {
        await _bestEffort(() => _processTreeTerminator.terminate(process.pid));
        if (!exited) {
          await _bestEffort(() async {
            process.kill(ProcessSignal.sigkill);
          });
        }
      }
      await _bestEffort(() async {
        await exit;
      });
      return result;
    } finally {
      timer.cancel();
      if (!stopped.isCompleted) stopped.complete();
      await _bestEffort(cancellationSubscription.cancel);
      await _bestEffort(reader.close);
      await stderr.close();
      // All tasks already have error handlers. Bound the join even if a sink
      // or a consumer supplied by the caller never completes.
      await _bestEffort(() async {
        await work;
      });
    }
  }

  Future<GitTransportResult<void>> _writeBatch(
    IOSink input,
    List<GitBlobRequest> requests,
  ) async {
    try {
      input.add(utf8.encode('${requests.map((e) => e.objectId).join('\n')}\n'));
    } on Object {
      unawaited(
        _bestEffort(() async {
          await input.close();
        }),
      );
      return _batchIoFailure('batchInputWriteFailed');
    }
    try {
      await input.close();
      return const GitTransportSuccess<void>(null);
    } on Object {
      return _batchIoFailure('batchInputWriteFailed');
    }
  }

  Future<GitTransportResult<void>> _consumeBatch(
    _BatchReader reader,
    List<GitBlobRequest> requests,
    GitBlobChunkConsumer onChunk,
  ) async {
    try {
      var totalBytes = 0;
      for (final request in requests) {
        final header = await reader.readLine(maximumBytes: 1024);
        final match = RegExp(
          r'^([0-9a-f]{40}|[0-9a-f]{64}) blob ([0-9]+)$',
        ).firstMatch(header);
        if (match == null || match.group(1) != request.objectId) {
          return _invalidBatch('invalidBlobHeader');
        }
        final size = int.tryParse(match.group(2)!);
        if (size == null || size > maximumByteSize - totalBytes) {
          return _invalidBatch('blobBytesExceededLimit');
        }
        totalBytes += size;
        var remaining = size;
        if (remaining == 0) {
          await onChunk(
            GitBlobChunk(request: request, bytes: Uint8List(0), isLast: true),
          );
        }
        while (remaining > 0) {
          final chunk = await reader.readAtMost(
            remaining < 64 * 1024 ? remaining : 64 * 1024,
          );
          remaining -= chunk.length;
          await onChunk(
            GitBlobChunk(
              request: request,
              bytes: chunk,
              isLast: remaining == 0,
            ),
          );
        }
        if (await reader.readByte() != 0x0a) {
          return _invalidBatch('missingBlobTerminator');
        }
      }
      return const GitTransportSuccess<void>(null);
    } on _BatchStopped {
      return GitTransportFailure<void>(code: GitTransportFailureCode.cancelled);
    } on _BatchConsumerFailure {
      return _batchIoFailure('blobConsumerFailed');
    } on FormatException {
      return _invalidBatch('truncatedBlobOutput');
    } on Object {
      return _batchIoFailure('batchOutputReadFailed');
    }
  }

  @override
  Future<void> dispose(GitBareSource source) =>
      _deleteRepository(source.repositoryPath);

  Future<void> _deleteRepository(String path) async {
    try {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // Temporary source cleanup is best effort. Workspace operations retain
      // their own durable cleanup evidence at the coordinator boundary.
    }
  }

  GitTransportFailure<void> _invalidBatch(String reason) =>
      GitTransportFailure<void>(
        code: GitTransportFailureCode.invalidOutput,
        context: <String, Object?>{'reason': reason},
      );
}

final class _BatchStopped implements Exception {
  const _BatchStopped();
}

final class _BatchConsumerFailure implements Exception {
  const _BatchConsumerFailure();
}

GitTransportFailure<void> _batchIoFailure(String reason) =>
    GitTransportFailure<void>(
      code: GitTransportFailureCode.ioFailure,
      context: {'operation': 'catFileBatch', 'reason': reason},
    );

Future<void> _bestEffort(Future<void> Function() cleanup) async {
  try {
    await cleanup().timeout(const Duration(seconds: 3));
  } on Object {
    // Cleanup must not replace the original failure or escape asynchronously.
  }
}

Future<Process> _startBatchProcess(GitCommand command) => Process.start(
  command.executable,
  command.arguments,
  environment: command.environment,
  includeParentEnvironment: false,
  runInShell: false,
);

final class _BatchReader {
  _BatchReader(Stream<List<int>> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<List<int>> _iterator;
  Future<void> close() => _iterator.cancel();
  Uint8List _buffer = Uint8List(0);
  var _offset = 0;

  Future<String> readLine({required int maximumBytes}) async {
    final bytes = BytesBuilder(copy: false);
    while (true) {
      if (_offset >= _buffer.length && !await _fill()) {
        throw const FormatException('Unexpected end of batch output.');
      }
      final newline = _buffer.indexOf(0x0a, _offset);
      final end = newline < 0 ? _buffer.length : newline;
      bytes.add(_buffer.sublist(_offset, end));
      if (bytes.length > maximumBytes) {
        throw const FormatException('Batch header exceeded its bound.');
      }
      _offset = end;
      if (newline >= 0) {
        _offset += 1;
        return ascii.decode(bytes.takeBytes());
      }
    }
  }

  Future<Uint8List> readAtMost(int count) async {
    if (_offset >= _buffer.length && !await _fill()) {
      throw const FormatException('Unexpected end of batch output.');
    }
    final available = _buffer.length - _offset;
    final length = count < available ? count : available;
    final result = Uint8List.fromList(
      _buffer.sublist(_offset, _offset + length),
    );
    _offset += length;
    return result;
  }

  Future<int> readByte() async => (await readAtMost(1)).single;

  Future<bool> _fill() async {
    if (!await _iterator.moveNext()) return false;
    _buffer = Uint8List.fromList(_iterator.current);
    _offset = 0;
    return true;
  }
}

final class _BoundedDiagnostic {
  _BoundedDiagnostic(Stream<List<int>> stream, this.maximumBytes) {
    _subscription = stream.listen(
      (chunk) {
        final remaining = maximumBytes - _bytes.length;
        if (remaining > 0) {
          _bytes.add(
            chunk.length <= remaining ? chunk : chunk.sublist(0, remaining),
          );
        }
      },
      onDone: _done.complete,
      onError: (_, _) => _done.complete(),
      cancelOnError: true,
    );
  }

  final int maximumBytes;
  late final StreamSubscription<List<int>> _subscription;
  Future<void>? _closing;
  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  Future<void> get done => _done.future;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    await _bestEffort(() => done);
    await _bestEffort(_subscription.cancel);
  }

  String get value => utf8.decode(_bytes.takeBytes(), allowMalformed: true);
}
