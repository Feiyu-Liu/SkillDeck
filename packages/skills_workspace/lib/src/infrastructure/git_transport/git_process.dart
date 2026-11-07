import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'git_commands.dart';
import 'git_source_transport.dart';

enum GitProcessTermination { exited, cancelled, timedOut, startFailed }

final class GitProcessOutcome {
  const GitProcessOutcome._({
    required this.termination,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.stdoutBytes = const <int>[],
    this.stderrBytes = const <int>[],
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
  });

  const GitProcessOutcome.exited({
    required int exitCode,
    String stdout = '',
    String stderr = '',
    List<int> stdoutBytes = const <int>[],
    List<int> stderrBytes = const <int>[],
    bool stdoutTruncated = false,
    bool stderrTruncated = false,
  }) : this._(
         termination: GitProcessTermination.exited,
         exitCode: exitCode,
         stdout: stdout,
         stderr: stderr,
         stdoutBytes: stdoutBytes,
         stderrBytes: stderrBytes,
         stdoutTruncated: stdoutTruncated,
         stderrTruncated: stderrTruncated,
       );

  const GitProcessOutcome.cancelled()
    : this._(termination: GitProcessTermination.cancelled);

  const GitProcessOutcome.timedOut()
    : this._(termination: GitProcessTermination.timedOut);

  const GitProcessOutcome.startFailed()
    : this._(termination: GitProcessTermination.startFailed);

  final GitProcessTermination termination;
  final int? exitCode;
  final String stdout;
  final String stderr;
  final List<int> stdoutBytes;
  final List<int> stderrBytes;
  final bool stdoutTruncated;
  final bool stderrTruncated;

  bool get succeeded =>
      termination == GitProcessTermination.exited && exitCode == 0;
}

abstract interface class GitProcessRunner {
  Future<GitProcessOutcome> run(
    GitCommand command, {
    required Duration timeout,
    required GitCancellationSignal cancellation,
  });
}

/// Runs bounded Git control commands without a shell.
///
/// Blob content from `cat-file --batch` is intentionally handled by the
/// streaming transport port rather than this bounded diagnostic runner.
final class DirectGitProcessRunner implements GitProcessRunner {
  DirectGitProcessRunner({
    GitProcessTreeTerminator? processTreeTerminator,
    this.maximumOutputBytes = 64 * 1024,
  }) : _processTreeTerminator =
           processTreeTerminator ?? PlatformGitProcessTreeTerminator.current() {
    if (maximumOutputBytes <= 0) {
      throw ArgumentError.value(
        maximumOutputBytes,
        'maximumOutputBytes',
        'must be positive',
      );
    }
  }

  final GitProcessTreeTerminator _processTreeTerminator;
  final int maximumOutputBytes;

  @override
  Future<GitProcessOutcome> run(
    GitCommand command, {
    required Duration timeout,
    required GitCancellationSignal cancellation,
  }) async {
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (cancellation.isCancelled) {
      return const GitProcessOutcome.cancelled();
    }

    Process process;
    try {
      process = await Process.start(
        command.executable,
        command.arguments,
        workingDirectory: command.workingDirectory,
        environment: command.environment,
        includeParentEnvironment: false,
        runInShell: false,
      );
    } on ProcessException {
      return const GitProcessOutcome.startFailed();
    } on ArgumentError {
      return const GitProcessOutcome.startFailed();
    }

    final stdoutCollector = _BoundedOutputCollector(
      process.stdout,
      maximumBytes: maximumOutputBytes,
    );
    final stderrCollector = _BoundedOutputCollector(
      process.stderr,
      maximumBytes: maximumOutputBytes,
    );
    try {
      if (command.stdinBytes.isNotEmpty) {
        process.stdin.add(command.stdinBytes);
      }
      await process.stdin.close();
    } on Object {
      // Process exit remains authoritative; a closed stdin is expected when
      // startup fails after the process object has been created.
    }

    final exit = process.exitCode.then<_ProcessCompletion>(
      _ProcessCompletion.exited,
    );
    final cancelled = cancellation.whenCancelled.then<_ProcessCompletion>(
      (_) => const _ProcessCompletion.cancelled(),
    );
    final timeoutCompletion = Completer<_ProcessCompletion>();
    final timeoutTimer = Timer(
      timeout,
      () => timeoutCompletion.complete(const _ProcessCompletion.timedOut()),
    );

    final completion = await Future.any([
      exit,
      cancelled,
      timeoutCompletion.future,
    ]);
    timeoutTimer.cancel();
    if (completion.kind != _ProcessCompletionKind.exited) {
      await _processTreeTerminator.terminate(process.pid);
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    }

    await stdoutCollector.close();
    await stderrCollector.close();
    return switch (completion.kind) {
      _ProcessCompletionKind.cancelled => const GitProcessOutcome.cancelled(),
      _ProcessCompletionKind.timedOut => const GitProcessOutcome.timedOut(),
      _ProcessCompletionKind.exited => GitProcessOutcome.exited(
        exitCode: completion.exitCode!,
        stdout: stdoutCollector.value,
        stderr: stderrCollector.value,
        stdoutBytes: stdoutCollector.bytes,
        stderrBytes: stderrCollector.bytes,
        stdoutTruncated: stdoutCollector.truncated,
        stderrTruncated: stderrCollector.truncated,
      ),
    };
  }
}

final class _BoundedOutputCollector {
  _BoundedOutputCollector(Stream<List<int>> stream, {required int maximumBytes})
    : _remaining = maximumBytes {
    _subscription = stream.listen(
      _add,
      onDone: _complete,
      onError: (_, _) => _complete(),
      cancelOnError: true,
    );
  }

  final BytesBuilder _bytes = BytesBuilder(copy: false);
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<List<int>> _subscription;
  int _remaining;
  bool truncated = false;
  List<int>? _cachedBytes;

  List<int> get bytes =>
      _cachedBytes ??= List<int>.unmodifiable(_bytes.takeBytes());

  String get value => utf8.decode(bytes, allowMalformed: true);

  void _add(List<int> bytes) {
    if (_remaining == 0) {
      truncated = true;
      return;
    }
    final accepted = bytes.length <= _remaining
        ? bytes
        : bytes.sublist(0, _remaining);
    _bytes.add(accepted);
    _remaining -= accepted.length;
    if (accepted.length != bytes.length) {
      truncated = true;
    }
  }

  void _complete() {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  Future<void> close() async {
    try {
      await _done.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      await _subscription.cancel();
    }
  }
}

enum _ProcessCompletionKind { exited, cancelled, timedOut }

final class _ProcessCompletion {
  const _ProcessCompletion._(this.kind, this.exitCode);

  const _ProcessCompletion.exited(int code)
    : this._(_ProcessCompletionKind.exited, code);

  const _ProcessCompletion.cancelled()
    : this._(_ProcessCompletionKind.cancelled, null);

  const _ProcessCompletion.timedOut()
    : this._(_ProcessCompletionKind.timedOut, null);

  final _ProcessCompletionKind kind;
  final int? exitCode;
}

abstract interface class GitProcessTreeTerminator {
  Future<void> terminate(int rootProcessId);
}

enum GitHostPlatform { macos, windows, linux }

final class PlatformGitProcessTreeTerminator
    implements GitProcessTreeTerminator {
  const PlatformGitProcessTreeTerminator(this.platform);

  factory PlatformGitProcessTreeTerminator.current() {
    if (Platform.isMacOS) {
      return const PlatformGitProcessTreeTerminator(GitHostPlatform.macos);
    }
    if (Platform.isWindows) {
      return const PlatformGitProcessTreeTerminator(GitHostPlatform.windows);
    }
    if (Platform.isLinux) {
      return const PlatformGitProcessTreeTerminator(GitHostPlatform.linux);
    }
    throw UnsupportedError('Git transport supports desktop platforms only.');
  }

  final GitHostPlatform platform;

  @override
  Future<void> terminate(int rootProcessId) async {
    if (platform == GitHostPlatform.windows) {
      final descendants = _windowsDescendants(rootProcessId);
      final command = GitProcessTreeCommands.windowsTaskkill(rootProcessId);
      try {
        await Process.run(
          command.executable,
          command.arguments,
          runInShell: false,
        ).timeout(const Duration(seconds: 2));
      } on Object {
        // Native PID termination below remains as a fallback.
      }
      Process.killPid(rootProcessId, ProcessSignal.sigkill);
      for (final childProcessId in descendants.reversed) {
        Process.killPid(childProcessId, ProcessSignal.sigkill);
      }
      return;
    }

    if (!Process.killPid(rootProcessId, ProcessSignal.sigstop)) {
      return;
    }
    final descendants = <int>[];
    final stopped = <int>{};
    for (var pass = 0; pass < 8; pass += 1) {
      var foundNewProcess = false;
      for (final childProcessId in await _posixDescendants(
        rootProcessId,
        platform,
      )) {
        if (stopped.add(childProcessId) &&
            Process.killPid(childProcessId, ProcessSignal.sigstop)) {
          descendants.add(childProcessId);
          foundNewProcess = true;
        }
      }
      if (!foundNewProcess) {
        break;
      }
    }

    for (final childProcessId in descendants.reversed) {
      Process.killPid(childProcessId, ProcessSignal.sigkill);
    }
    Process.killPid(rootProcessId, ProcessSignal.sigkill);
  }
}

Future<List<int>> _posixDescendants(
  int rootProcessId,
  GitHostPlatform platform,
) async {
  if (platform == GitHostPlatform.linux) {
    final processTable = await _linuxProcessTable();
    if (processTable != null) {
      return _collectDescendants(rootProcessId, processTable);
    }
  }

  final command = GitProcessTreeCommands.posixProcessTable();
  try {
    final result = await Process.run(
      command.executable,
      command.arguments,
      runInShell: false,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    ).timeout(const Duration(seconds: 2));
    if (result.exitCode != 0) {
      return const [];
    }
    final childrenByParent = <int, List<int>>{};
    for (final line in (result.stdout as String).split('\n')) {
      final columns = line.trim().split(RegExp(r'\s+'));
      if (columns.length != 2) {
        continue;
      }
      final child = int.tryParse(columns[0]);
      final parent = int.tryParse(columns[1]);
      if (child != null && parent != null) {
        childrenByParent.putIfAbsent(parent, () => <int>[]).add(child);
      }
    }
    return _collectDescendants(rootProcessId, childrenByParent);
  } on Object {
    return const [];
  }
}

Future<Map<int, List<int>>?> _linuxProcessTable() async {
  final childrenByParent = <int, List<int>>{};
  try {
    await for (final entity in Directory('/proc').list(followLinks: false)) {
      final separator = entity.path.lastIndexOf(Platform.pathSeparator);
      final name = entity.path.substring(separator + 1);
      final processId = int.tryParse(name);
      if (processId == null) {
        continue;
      }
      try {
        final stat = await File('/proc/$processId/stat').readAsString();
        final commandEnd = stat.lastIndexOf(')');
        if (commandEnd < 0 || commandEnd + 2 >= stat.length) {
          continue;
        }
        final fields = stat.substring(commandEnd + 2).split(' ');
        if (fields.length < 2) {
          continue;
        }
        final parentId = int.tryParse(fields[1]);
        if (parentId != null) {
          childrenByParent.putIfAbsent(parentId, () => <int>[]).add(processId);
        }
      } on FileSystemException {
        // Processes may exit while /proc is enumerated.
      }
    }
    return childrenByParent;
  } on FileSystemException {
    return null;
  }
}

List<int> _collectDescendants(
  int rootProcessId,
  Map<int, List<int>> childrenByParent,
) {
  final descendants = <int>[];
  final seen = <int>{};

  void collect(int parent) {
    for (final child in childrenByParent[parent] ?? const <int>[]) {
      if (seen.add(child)) {
        descendants.add(child);
        collect(child);
      }
    }
  }

  collect(rootProcessId);
  return descendants;
}

List<int> _windowsDescendants(int rootProcessId) {
  final snapshot = _createToolhelp32Snapshot(_th32csSnapProcess, 0);
  if (snapshot == Pointer<Void>.fromAddress(-1)) {
    return const [];
  }
  final entry = calloc<_ProcessEntry32W>();
  try {
    entry.ref.dwSize = sizeOf<_ProcessEntry32W>();
    if (_process32FirstW(snapshot, entry) == 0) {
      return const [];
    }
    final childrenByParent = <int, List<int>>{};
    do {
      childrenByParent
          .putIfAbsent(entry.ref.th32ParentProcessID, () => <int>[])
          .add(entry.ref.th32ProcessID);
    } while (_process32NextW(snapshot, entry) != 0);
    return _collectDescendants(rootProcessId, childrenByParent);
  } finally {
    calloc.free(entry);
    _closeHandle(snapshot);
  }
}

const int _th32csSnapProcess = 0x00000002;

final class _ProcessEntry32W extends Struct {
  @Uint32()
  external int dwSize;

  @Uint32()
  external int cntUsage;

  @Uint32()
  external int th32ProcessID;

  @IntPtr()
  external int th32DefaultHeapID;

  @Uint32()
  external int th32ModuleID;

  @Uint32()
  external int cntThreads;

  @Uint32()
  external int th32ParentProcessID;

  @Int32()
  external int pcPriClassBase;

  @Uint32()
  external int dwFlags;

  @Array(260)
  external Array<Uint16> szExeFile;
}

typedef _CreateToolhelp32SnapshotNative =
    Pointer<Void> Function(Uint32 flags, Uint32 processId);
typedef _CreateToolhelp32SnapshotDart =
    Pointer<Void> Function(int flags, int processId);
typedef _Process32FirstWNative =
    Int32 Function(Pointer<Void> snapshot, Pointer<_ProcessEntry32W> entry);
typedef _Process32FirstWDart =
    int Function(Pointer<Void> snapshot, Pointer<_ProcessEntry32W> entry);
typedef _Process32NextWNative =
    Int32 Function(Pointer<Void> snapshot, Pointer<_ProcessEntry32W> entry);
typedef _Process32NextWDart =
    int Function(Pointer<Void> snapshot, Pointer<_ProcessEntry32W> entry);
typedef _CloseHandleNative = Int32 Function(Pointer<Void> handle);
typedef _CloseHandleDart = int Function(Pointer<Void> handle);

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final _CreateToolhelp32SnapshotDart _createToolhelp32Snapshot = _kernel32
    .lookupFunction<
      _CreateToolhelp32SnapshotNative,
      _CreateToolhelp32SnapshotDart
    >('CreateToolhelp32Snapshot');
final _Process32FirstWDart _process32FirstW = _kernel32
    .lookupFunction<_Process32FirstWNative, _Process32FirstWDart>(
      'Process32FirstW',
    );
final _Process32NextWDart _process32NextW = _kernel32
    .lookupFunction<_Process32NextWNative, _Process32NextWDart>(
      'Process32NextW',
    );
final _CloseHandleDart _closeHandle = _kernel32
    .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
