import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/infrastructure/git_transport/git_commands.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:test/test.dart';

import '../../support/process/direct_dart_process.dart';

void main() {
  test(
    'runs direct argv with an explicit environment and bounded output',
    () async {
      final printable = await DirectGitProcessRunner().run(
        GitCommand(
          executable: Platform.resolvedExecutable,
          arguments: directDartScriptArguments(
            'test/support/git_transport/process_fixture.dart',
            const <String>['--print'],
          ),
          environment: {
            ...Platform.environment,
            'GIT_FIXTURE_VALUE': 'direct-argv',
          },
        ),
        timeout: const Duration(seconds: 10),
        cancellation: const _NeverCancellation(),
      );

      expect(printable.succeeded, isTrue);
      expect(printable.stdout, endsWith('direct-argv'));
      expect(printable.stderr, 'diagnostic');

      final bounded = await DirectGitProcessRunner(maximumOutputBytes: 32).run(
        GitCommand(
          executable: Platform.resolvedExecutable,
          arguments: directDartScriptArguments(
            'test/support/git_transport/process_fixture.dart',
            const <String>['--large-output'],
          ),
          environment: Platform.environment,
        ),
        timeout: const Duration(seconds: 10),
        cancellation: const _NeverCancellation(),
      );
      expect(bounded.stdout.length, 32);
      expect(bounded.stderr.length, 32);
      expect(bounded.stdoutTruncated, isTrue);
      expect(bounded.stderrTruncated, isTrue);
    },
  );

  test(
    'cancellation terminates the spawned process tree on macOS',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'skills-workspace-process-tree-',
      );
      addTearDown(() async {
        if (await temporaryDirectory.exists()) {
          await temporaryDirectory.delete(recursive: true);
        }
      });
      final heartbeat = File(path.join(temporaryDirectory.path, 'heartbeat'));
      final pidDirectory = Directory(
        path.join(temporaryDirectory.path, 'pids'),
      );
      await pidDirectory.create();
      final cancellation = _TestCancellation();
      final run = DirectGitProcessRunner().run(
        GitCommand(
          executable: Platform.resolvedExecutable,
          arguments: directDartScriptArguments(
            'test/support/git_transport/hanging_process.dart',
            <String>['--parent', heartbeat.path, pidDirectory.path],
          ),
          environment: Platform.environment,
        ),
        timeout: const Duration(seconds: 20),
        cancellation: cancellation,
      );

      await _waitForFile(heartbeat);
      await _waitForHeartbeatAdvance(heartbeat);
      final processIds = await _readProcessIds(pidDirectory);
      addTearDown(() {
        for (final processId in processIds) {
          Process.killPid(processId, ProcessSignal.sigkill);
        }
      });
      cancellation.cancel();
      final outcome = await run;
      await _waitForProcessesToExit(processIds);
      await _waitForHeartbeatToSettle(heartbeat);
      final afterCancellation = await heartbeat.readAsString();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(outcome.termination, GitProcessTermination.cancelled);
      expect(await heartbeat.readAsString(), afterCancellation);
    },
    skip: !Platform.isMacOS,
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('pre-cancelled and timed-out commands have stable outcomes', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-timeout-',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });
    final cancelled = _TestCancellation()..cancel();
    final runner = DirectGitProcessRunner();
    final command = GitCommand(
      executable: Platform.resolvedExecutable,
      arguments: directDartScriptArguments(
        'test/support/git_transport/hanging_process.dart',
      ),
    );

    final cancelledOutcome = await runner.run(
      command,
      timeout: const Duration(seconds: 1),
      cancellation: cancelled,
    );
    expect(cancelledOutcome.termination, GitProcessTermination.cancelled);

    final timedOutOutcome = await runner.run(
      GitCommand(
        executable: Platform.resolvedExecutable,
        arguments: directDartScriptArguments(
          'test/support/git_transport/hanging_process.dart',
          <String>[
            '--child',
            path.join(temporaryDirectory.path, 'heartbeat'),
            temporaryDirectory.path,
          ],
        ),
        environment: Platform.environment,
      ),
      timeout: const Duration(milliseconds: 100),
      cancellation: const _NeverCancellation(),
    );
    expect(timedOutOutcome.termination, GitProcessTermination.timedOut);
  });
}

final class _TestCancellation implements GitCancellationSignal {
  final Completer<void> _completer = Completer<void>();

  @override
  bool get isCancelled => _completer.isCompleted;

  @override
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) {
      _completer.complete();
    }
  }
}

final class _NeverCancellation implements GitCancellationSignal {
  const _NeverCancellation();

  static final Future<void> _never = Completer<void>().future;

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => _never;
}

Future<void> _waitForHeartbeatToSettle(File heartbeat) async {
  var previous = await heartbeat.readAsString();
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (true) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final current = await heartbeat.readAsString();
    if (current == previous) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('The heartbeat process did not stop.');
    }
    previous = current;
  }
}

Future<void> _waitForFile(File file) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await file.exists()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('The child process did not start.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _waitForHeartbeatAdvance(File heartbeat) async {
  final initial = await heartbeat.readAsString();
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (await heartbeat.readAsString() == initial) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('The heartbeat process did not become active.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<List<int>> _readProcessIds(Directory directory) async {
  final result = <int>[];
  for (final name in const ['parent', 'middle', 'child']) {
    final value = await File(
      path.join(directory.path, '$name.pid'),
    ).readAsString();
    result.add(int.parse(value));
  }
  return result;
}

Future<void> _waitForProcessesToExit(List<int> processIds) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (true) {
    final running = <int>[];
    for (final processId in processIds) {
      if (await _isProcessRunning(processId)) {
        running.add(processId);
      }
    }
    if (running.isEmpty) {
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'Processes still running after cancellation: $running',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<bool> _isProcessRunning(int processId) async {
  final result = await Process.run('ps', [
    '-o',
    'stat=',
    '-p',
    '$processId',
  ], runInShell: false);
  final state = '${result.stdout}'.trim();
  return result.exitCode == 0 && state.isNotEmpty && !state.startsWith('Z');
}
