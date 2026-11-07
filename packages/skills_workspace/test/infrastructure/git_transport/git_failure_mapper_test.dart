import 'package:skills_workspace/src/infrastructure/git_transport/git_failure_mapper.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:test/test.dart';

void main() {
  test('maps process terminal states to stable internal failures', () {
    expect(
      mapGitProcessFailure<void>(
        const GitProcessOutcome.startFailed(),
        operation: 'fetch',
      ).code,
      GitTransportFailureCode.unavailable,
    );
    expect(
      mapGitProcessFailure<void>(
        const GitProcessOutcome.timedOut(),
        operation: 'fetch',
      ).code,
      GitTransportFailureCode.timedOut,
    );
    expect(
      mapGitProcessFailure<void>(
        const GitProcessOutcome.cancelled(),
        operation: 'fetch',
      ).code,
      GitTransportFailureCode.cancelled,
    );
  });

  test('classifies authentication and redacts diagnostic and context', () {
    final failure = mapGitProcessFailure<void>(
      const GitProcessOutcome.exited(
        exitCode: 128,
        stderr:
            'fatal: Authentication failed for '
            'https://user:secret@example.com/repo.git?token=private',
      ),
      operation: 'fetch',
      locator: 'https://example.com/repo.git',
    );

    expect(failure.code, GitTransportFailureCode.authenticationRequired);
    expect(failure.diagnostic, isNot(contains('user:secret')));
    expect(failure.diagnostic, isNot(contains('token=private')));
    expect(failure.context.toString(), isNot(contains('secret')));
  });

  test('maps an ordinary exit and retains only bounded metadata', () {
    final failure = mapGitProcessFailure<void>(
      const GitProcessOutcome.exited(
        exitCode: 2,
        stderr: 'bad revision',
        stderrTruncated: true,
      ),
      operation: 'lsTree',
    );

    expect(failure.code, GitTransportFailureCode.commandFailed);
    expect(failure.context, {'operation': 'lsTree', 'exitCode': 2});
    expect(failure.diagnostic, 'bad revision\n[truncated]');
  });

  test('separates a missing host toolchain from a bad source address', () {
    final failure = mapGitProcessFailure<void>(
      const GitProcessOutcome.exited(
        exitCode: 1,
        stderr:
            'xcode-select: note: No developer tools were found, requesting '
            'install. Choose an option in the dialog to download the command '
            'line developer tools.',
      ),
      operation: 'initialize',
      locator: 'https://example.com/repo.git',
    );

    expect(failure.code, GitTransportFailureCode.developerToolsRequired);
    expect(failure.context['developerTools'], 'required');
    expect(failure.context['operation'], 'initialize');
  });

  test('marks an install already under way so retrying is not advised', () {
    final failure = mapGitProcessFailure<void>(
      const GitProcessOutcome.exited(
        exitCode: 1,
        stderr:
            'xcode-select: note: install requested for command line developer '
            'tools',
      ),
      operation: 'fetch',
    );

    expect(failure.code, GitTransportFailureCode.developerToolsRequired);
    expect(failure.context['developerTools'], 'installing');
  });

  test('keeps developer-tools classification clear of source credentials', () {
    final failure = mapGitProcessFailure<void>(
      const GitProcessOutcome.exited(
        exitCode: 1,
        stderr:
            'xcode-select: note: No developer tools were found while fetching '
            'https://user:secret@example.com/repo.git?token=private',
      ),
      operation: 'fetch',
      locator: 'https://user:secret@example.com/repo.git',
    );

    expect(failure.code, GitTransportFailureCode.developerToolsRequired);
    expect(failure.diagnostic, isNot(contains('user:secret')));
    expect(failure.diagnostic, isNot(contains('token=private')));
    expect(failure.context.toString(), isNot(contains('secret')));
  });
}
