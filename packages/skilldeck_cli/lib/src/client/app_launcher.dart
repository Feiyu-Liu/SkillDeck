import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../skilldeck_protocol.dart';
import 'command_host_client.dart';

typedef HostConnector = Future<CommandHostConnection> Function({
  Duration? timeout,
});
typedef AppProcessStarter = Future<int> Function(
  String executable,
  List<String> arguments, {
  required ProcessStartMode mode,
  required Duration timeout,
});
typedef LaunchLock = Future<CommandHostConnection> Function(
  Future<CommandHostConnection> Function() action,
);

/// Launches only the App; never opens or owns a Workspace.
final class AppLauncher {
  AppLauncher({
    required this.runDirectory,
    String? operatingSystem,
    HostConnector? connect,
    AppProcessStarter? startProcess,
    Duration Function()? clock,
    Future<void> Function(Duration)? delay,
    Future<AppLocation> Function()? readLocation,
    Future<bool> Function(String)? executableExists,
    this.withLock,
    this.launchTimeout = const Duration(seconds: 30),
  }) : operatingSystem = operatingSystem ?? Platform.operatingSystem,
       _connect =
           connect ?? CommandHostClient(runDirectory: runDirectory).connect,
       _startProcess = startProcess ?? _start,
       _clock = clock ?? (Stopwatch()..start()).elapsedDuration,
       _delay = delay ?? Future<void>.delayed,
       _readLocation = readLocation ?? (() => readAppLocation(runDirectory)),
       _executableExists = executableExists ?? ((path) => File(path).exists());

  final String runDirectory;
  final String operatingSystem;
  final Duration launchTimeout;
  final HostConnector _connect;
  final AppProcessStarter _startProcess;
  final Duration Function() _clock;
  final Future<void> Function(Duration) _delay;
  final Future<AppLocation> Function() _readLocation;
  final Future<bool> Function(String) _executableExists;
  final LaunchLock? withLock;

  Future<CommandResult> execute(
    CommandRequest request, {
    bool noLaunch = false,
    void Function()? onStarting,
    Future<void>? cancelled,
  }) async {
    CommandHostConnection? active;
    var interrupted = false;
    unawaited(
      cancelled?.then((_) async {
        interrupted = true;
        try {
          await active?.close();
        } on Object {
          // Cancellation must not create an unhandled transport error.
        }
      }),
    );
    CommandHostConnection connection;
    try {
      connection = await _connect();
    } on ClientFailure catch (failure) {
      if (interrupted ||
          failure.code != ClientFailureCode.appUnavailable ||
          noLaunch ||
          (operatingSystem != 'macos' && operatingSystem != 'windows')) {
        rethrow;
      }
      try {
        connection = await (withLock ?? _locked)(() => _launch(onStarting));
      } on IOException {
        throw const ClientFailure(ClientFailureCode.appUnavailable);
      }
    }
    active = connection;
    if (interrupted) {
      await connection.close();
      return CommandResult.failure(
        request.command,
        'operationCancelled',
        'The command was cancelled.',
      );
    }
    // Never retry a command that may already have executed in the App.
    try {
      return await connection.execute(request);
    } finally {
      await connection.close();
    }
  }

  Future<CommandHostConnection> _launch(void Function()? onStarting) async {
    // A concurrent CLI can have finished launching while we waited for the lock.
    try {
      return await _connect();
    } on ClientFailure catch (failure) {
      if (failure.code != ClientFailureCode.appUnavailable) rethrow;
    }
    final location = await _readLocation();
    if (!await _executableExists(location.executablePath)) {
      throw const ClientFailure(ClientFailureCode.appNotInstalled);
    }
    final deadline = _clock() + launchTimeout;
    Duration remaining() {
      final value = deadline - _clock();
      if (value <= Duration.zero) {
        throw const ClientFailure(ClientFailureCode.appLaunchTimeout);
      }
      return value;
    }

    onStarting?.call();
    try {
      if (operatingSystem == 'windows') {
        final status = await _startProcess(
          location.executablePath,
          ['--skilldeck-background'],
          mode: ProcessStartMode.detached,
          timeout: remaining(),
        );
        if (status != 0) {
          throw const ClientFailure(ClientFailureCode.appUnavailable);
        }
      } else {
        // Open the exact copy that last ran. Several bundles can share one
        // identifier (an installed release beside a development build), and
        // LaunchServices may pick an older one that has no Command Host.
        final paths = p.Context(style: p.Style.posix);
        final executable = location.executablePath;
        final bundle = paths.dirname(paths.dirname(paths.dirname(executable)));
        final validBundle =
            bundle.endsWith('.app') &&
            paths.basename(paths.dirname(executable)) == 'MacOS' &&
            paths.basename(paths.dirname(paths.dirname(executable))) ==
                'Contents';
        var status = -1;
        if (validBundle) status = await _open('-a', bundle, remaining());
        if (status != 0 && location.bundleIdentifier != null) {
          status = await _open('-b', location.bundleIdentifier!, remaining());
        }
        if (status != 0) {
          throw ClientFailure(
            validBundle || location.bundleIdentifier != null
                ? ClientFailureCode.appUnavailable
                : ClientFailureCode.appNotInstalled,
          );
        }
      }
    } on TimeoutException {
      throw const ClientFailure(ClientFailureCode.appLaunchTimeout);
    } on ProcessException {
      throw const ClientFailure(ClientFailureCode.appUnavailable);
    }

    var backoff = const Duration(milliseconds: 100);
    while (true) {
      final budget = remaining();
      try {
        return await _connect(timeout: budget);
      } on ClientFailure catch (failure) {
        if (failure.code != ClientFailureCode.appUnavailable &&
            failure.code != ClientFailureCode.timeout) {
          rethrow;
        }
      }
      final left = remaining();
      await _delay(backoff < left ? backoff : left);
      backoff = Duration(
        milliseconds: (backoff.inMilliseconds * 2).clamp(100, 500),
      );
    }
  }

  Future<int> _open(String option, String target, Duration timeout) =>
      _startProcess(
        '/usr/bin/open',
        ['-g', '-j', option, target, '--args', '--skilldeck-background'],
        mode: ProcessStartMode.normal,
        timeout: timeout,
      );

  // POSIX record locks are per-process. Serialize local callers too, so tests
  // and embedded clients obey the same exclusion as independent CLI processes.
  static final _localLocks = <String, Future<void>>{};
  Future<CommandHostConnection> _locked(
    Future<CommandHostConnection> Function() action,
  ) async {
    final key = p.normalize(p.absolute(runDirectory));
    final previous = _localLocks[key];
    final released = Completer<void>();
    _localLocks[key] = released.future;
    RandomAccessFile? file;
    var locked = false;
    try {
      await previous;
      await ensurePrivateDirectory(runDirectory);
      file = await File(p.join(runDirectory, 'launch.lock'))
          .open(mode: FileMode.append);
      await file.lock(FileLock.blockingExclusive);
      locked = true;
      return await action();
    } finally {
      try {
        if (locked) await file!.unlock();
      } finally {
        try {
          await file?.close();
        } finally {
          released.complete();
          if (identical(_localLocks[key], released.future)) {
            _localLocks.remove(key);
          }
        }
      }
    }
  }

  static Future<int> _start(
    String executable,
    List<String> arguments, {
    required ProcessStartMode mode,
    required Duration timeout,
  }) async {
    final process = await Process.start(executable, arguments, mode: mode);
    if (mode == ProcessStartMode.detached) return 0;
    // Discard output without decoding or retaining it, including failure output.
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    return process.exitCode.timeout(
      timeout,
      onTimeout: () {
        process.kill();
        throw TimeoutException('');
      },
    );
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}
