import 'package:skills_workspace/src/infrastructure/git_transport/git_commands.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';

/// A [GitProcessRunner] that returns scripted outcomes and records what it was
/// asked to run, so transport classification can be tested without a host Git.
final class FakeGitProcessRunner implements GitProcessRunner {
  FakeGitProcessRunner(this.outcome);

  final GitProcessOutcome outcome;
  final List<GitCommand> commands = <GitCommand>[];

  @override
  Future<GitProcessOutcome> run(
    GitCommand command, {
    required Duration timeout,
    required GitCancellationSignal cancellation,
  }) async {
    commands.add(command);
    return outcome;
  }
}
