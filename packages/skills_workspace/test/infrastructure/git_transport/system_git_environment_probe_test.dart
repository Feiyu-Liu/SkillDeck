import 'package:skills_workspace/src/domain/git_environment.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_commands.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/system_git_environment_probe.dart';
import 'package:test/test.dart';

import '../../support/git_transport/fake_git_process_runner.dart';

Future<GitEnvironmentStatus> _probe(
  GitProcessOutcome outcome, {
  GitBareCommandBuilder commandBuilder = const GitBareCommandBuilder(),
}) async {
  final report = await SystemGitEnvironmentProbe(
    processRunner: FakeGitProcessRunner(outcome),
    commandBuilder: commandBuilder,
  ).probe();
  return report.status;
}

void main() {
  test('reports an available Git from a recognizable version banner', () async {
    expect(
      await _probe(
        const GitProcessOutcome.exited(
          exitCode: 0,
          stdout: 'git version 2.39.5 (Apple Git-154)\n',
        ),
      ),
      GitEnvironmentStatus.available,
    );
  });

  test('reports a missing executable when the process cannot start', () async {
    expect(
      await _probe(const GitProcessOutcome.startFailed()),
      GitEnvironmentStatus.notInstalled,
    );
  });

  test('distinguishes missing developer tools from an install under '
      'way', () async {
    expect(
      await _probe(
        const GitProcessOutcome.exited(
          exitCode: 1,
          stderr:
              'xcode-select: note: No developer tools were found, requesting '
              'install.',
        ),
      ),
      GitEnvironmentStatus.developerToolsRequired,
    );
    expect(
      await _probe(
        const GitProcessOutcome.exited(
          exitCode: 1,
          stderr:
              'xcode-select: note: install requested for command line '
              'developer tools',
        ),
      ),
      GitEnvironmentStatus.developerToolsInstalling,
    );
  });

  test('falls back to a failed probe for unrecognized outcomes', () async {
    expect(
      await _probe(const GitProcessOutcome.exited(exitCode: 1, stderr: 'boom')),
      GitEnvironmentStatus.probeFailed,
    );
    expect(
      await _probe(const GitProcessOutcome.timedOut()),
      GitEnvironmentStatus.probeFailed,
    );
    expect(
      await _probe(const GitProcessOutcome.cancelled()),
      GitEnvironmentStatus.probeFailed,
    );
    expect(
      await _probe(const GitProcessOutcome.exited(exitCode: 0, stdout: '')),
      GitEnvironmentStatus.probeFailed,
    );
  });

  test('probes the same executable the source transport would run', () async {
    final runner = FakeGitProcessRunner(
      const GitProcessOutcome.exited(exitCode: 0, stdout: 'git version 2.39.5'),
    );
    await SystemGitEnvironmentProbe(
      processRunner: runner,
      commandBuilder: const GitBareCommandBuilder(executable: '/opt/bin/git'),
    ).probe();

    expect(runner.commands, hasLength(1));
    expect(runner.commands.single.executable, '/opt/bin/git');
    expect(runner.commands.single.arguments, ['--version']);
    expect(runner.commands.single.workingDirectory, isNull);
  });

  test('applies the transport environment policy to the probe', () async {
    final runner = FakeGitProcessRunner(
      const GitProcessOutcome.exited(exitCode: 0, stdout: 'git version 2.39.5'),
    );
    await SystemGitEnvironmentProbe(processRunner: runner).probe();

    expect(runner.commands.single.environment['GIT_TERMINAL_PROMPT'], '0');
  });
}
