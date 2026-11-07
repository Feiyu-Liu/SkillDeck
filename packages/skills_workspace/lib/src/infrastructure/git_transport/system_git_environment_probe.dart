import 'dart:async';
import 'dart:io';

import '../../application/ports/git_environment_ports.dart';
import '../../domain/git_environment.dart';
import 'git_commands.dart';
import 'git_developer_tools_signature.dart';
import 'git_process.dart';
import 'git_redaction.dart';
import 'git_source_transport.dart';

/// Probes the host by running `git --version` through the same command builder
/// the source transport uses.
///
/// Sharing [GitBareCommandBuilder] is deliberate: it owns the executable name,
/// so probing through anything else could report a usable Git while every
/// acquisition kept failing on a different binary.
final class SystemGitEnvironmentProbe implements GitEnvironmentProbe {
  const SystemGitEnvironmentProbe({
    GitProcessRunner? processRunner,
    GitBareCommandBuilder commandBuilder = const GitBareCommandBuilder(),
    GitEnvironmentPolicy environmentPolicy = const GitEnvironmentPolicy(),
    this.timeout = const Duration(seconds: 15),
  }) : _processRunner = processRunner,
       _commandBuilder = commandBuilder,
       _environmentPolicy = environmentPolicy;

  final GitProcessRunner? _processRunner;
  final GitBareCommandBuilder _commandBuilder;
  final GitEnvironmentPolicy _environmentPolicy;

  /// Short by design: a healthy Git answers immediately, and a host that has
  /// not answered in this long is not going to become usable by waiting.
  final Duration timeout;

  @override
  Future<GitEnvironmentReport> probe() async {
    // Constructed here rather than in the constructor so that merely wiring the
    // repository never prepares, let alone runs, a child process.
    final runner = _processRunner ?? DirectGitProcessRunner();
    final outcome = await runner.run(
      _commandBuilder.version(
        environment: _environmentPolicy.apply(Platform.environment),
      ),
      timeout: timeout,
      cancellation: const _NeverCancelled(),
    );
    return GitEnvironmentReport(status: _status(outcome));
  }

  GitEnvironmentStatus _status(GitProcessOutcome outcome) {
    switch (outcome.termination) {
      case GitProcessTermination.startFailed:
        return GitEnvironmentStatus.notInstalled;
      case GitProcessTermination.timedOut:
      case GitProcessTermination.cancelled:
        return GitEnvironmentStatus.probeFailed;
      case GitProcessTermination.exited:
        if (outcome.succeeded) {
          return outcome.stdout.trimLeft().toLowerCase().startsWith(
                'git version',
              )
              ? GitEnvironmentStatus.available
              : GitEnvironmentStatus.probeFailed;
        }
        // Redact before classifying so both this and the failure mapper judge
        // the same shape of input, even though a version probe carries no
        // locator of its own.
        return switch (classifyGitDeveloperToolsSignal(
          redactGitDiagnostic(outcome.stderr),
        )) {
          GitDeveloperToolsSignal.installRequired =>
            GitEnvironmentStatus.developerToolsRequired,
          GitDeveloperToolsSignal.installInProgress =>
            GitEnvironmentStatus.developerToolsInstalling,
          GitDeveloperToolsSignal.absent => GitEnvironmentStatus.probeFailed,
        };
    }
  }
}

/// The probe is a single short command with its own timeout, so it exposes no
/// cancellation of its own.
final class _NeverCancelled implements GitCancellationSignal {
  const _NeverCancelled();

  @override
  bool get isCancelled => false;

  @override
  Future<void> get whenCancelled => Completer<void>().future;
}
