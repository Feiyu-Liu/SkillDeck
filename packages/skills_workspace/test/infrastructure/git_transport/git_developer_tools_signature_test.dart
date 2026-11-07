import 'package:skills_workspace/src/infrastructure/git_transport/git_developer_tools_signature.dart';
import 'package:test/test.dart';

void main() {
  test('recognizes the macOS shim asking the host to install the tools', () {
    const diagnostics = <String>[
      'xcode-select: note: No developer tools were found, requesting install. '
          'Choose an option in the dialog to download the command line '
          'developer tools.',
      "xcode-select: note: No developer tools were found at "
          "'/Applications/Xcode.app', requesting install. Choose an option in "
          'the dialog to download the command line developer tools.',
      'xcode-select: error: tool \'git\' requires Xcode, but active developer '
          "directory '/Library/Developer/CommandLineTools' is a command line "
          'tools instance',
      'git: error: unable to find utility "git", not a developer tool or in '
          'PATH',
    ];
    for (final diagnostic in diagnostics) {
      expect(
        classifyGitDeveloperToolsSignal(diagnostic),
        GitDeveloperToolsSignal.installRequired,
        reason: diagnostic,
      );
    }
  });

  test('separates an install already under way from a missing install', () {
    expect(
      classifyGitDeveloperToolsSignal(
        'xcode-select: note: install requested for command line developer '
        'tools',
      ),
      GitDeveloperToolsSignal.installInProgress,
    );
    expect(
      classifyGitDeveloperToolsSignal(
        'The Command Line Developer Tools are being installed.',
      ),
      GitDeveloperToolsSignal.installInProgress,
    );
  });

  test('leaves ordinary Git diagnostics unclassified', () {
    const diagnostics = <String>[
      '',
      'bad revision',
      'fatal: repository not found',
      'fatal: Authentication failed for https://example.com/repo.git',
      'could not read Username for https://example.com',
      'terminal prompts disabled',
      'Permission denied (publickey).',
      'git: command not found',
      'error: RPC failed; curl 56 Recv failure',
    ];
    for (final diagnostic in diagnostics) {
      expect(
        classifyGitDeveloperToolsSignal(diagnostic),
        GitDeveloperToolsSignal.absent,
        reason: diagnostic,
      );
    }
  });

  test('matches regardless of the diagnostic casing', () {
    expect(
      classifyGitDeveloperToolsSignal(
        'XCODE-SELECT: NOTE: NO DEVELOPER TOOLS WERE FOUND, REQUESTING '
        'INSTALL.',
      ),
      GitDeveloperToolsSignal.installRequired,
    );
  });
}
