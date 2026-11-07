import 'git_developer_tools_signature.dart';
import 'git_process.dart';
import 'git_redaction.dart';
import 'git_transport_result.dart';

GitTransportFailure<T> mapGitProcessFailure<T>(
  GitProcessOutcome outcome, {
  required String operation,
  String? locator,
}) {
  switch (outcome.termination) {
    case GitProcessTermination.cancelled:
      return GitTransportFailure<T>(
        code: GitTransportFailureCode.cancelled,
        context: {'operation': operation},
      );
    case GitProcessTermination.timedOut:
      return GitTransportFailure<T>(
        code: GitTransportFailureCode.timedOut,
        context: {'operation': operation, 'timedOut': true},
        diagnostic: 'The Git command timed out.',
      );
    case GitProcessTermination.startFailed:
      return GitTransportFailure<T>(
        code: GitTransportFailureCode.unavailable,
        context: {'operation': operation},
        diagnostic: 'The system Git executable is unavailable.',
      );
    case GitProcessTermination.exited:
      final rawDiagnostic = outcome.stderrTruncated
          ? '${outcome.stderr}\n[truncated]'
          : outcome.stderr;
      final diagnostic = redactGitDiagnostic(rawDiagnostic, locator: locator);
      // The macOS developer-tools shim exits normally, so this signature is the
      // only thing separating "the host has no usable Git yet" from "your
      // source address is wrong". Check it before authentication: it is the
      // more specific signature, and retrying is never the remedy.
      final developerTools = classifyGitDeveloperToolsSignal(diagnostic);
      return GitTransportFailure<T>(
        code: developerTools != GitDeveloperToolsSignal.absent
            ? GitTransportFailureCode.developerToolsRequired
            : _isAuthenticationFailure(diagnostic)
            ? GitTransportFailureCode.authenticationRequired
            : GitTransportFailureCode.commandFailed,
        context: {
          'operation': operation,
          if (outcome.exitCode != null) 'exitCode': outcome.exitCode!,
          if (locator != null) 'locator': redactGitLocator(locator),
          if (developerTools != GitDeveloperToolsSignal.absent)
            'developerTools':
                developerTools == GitDeveloperToolsSignal.installInProgress
                ? 'installing'
                : 'required',
        },
        diagnostic: diagnostic.isEmpty ? 'The Git command failed.' : diagnostic,
      );
  }
}

bool _isAuthenticationFailure(String diagnostic) {
  final lower = diagnostic.toLowerCase();
  return lower.contains('authentication failed') ||
      lower.contains('could not read username') ||
      lower.contains('terminal prompts disabled') ||
      lower.contains('permission denied (publickey)') ||
      lower.contains('repository not found') ||
      lower.contains('requested url returned error: 401') ||
      lower.contains('requested url returned error: 403') ||
      lower.contains('saml sso') ||
      lower.contains('invalid username or password');
}
