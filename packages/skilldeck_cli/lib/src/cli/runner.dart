import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../skilldeck_protocol.dart';
import '../client/app_launcher.dart';
import 'command_catalog.dart';
import 'command_line.dart';
import 'exit_code.dart';
import 'human_output.dart';
import 'version.dart';

Future<int> runSkilldeck(
  List<String> arguments, {
  required Map<String, String> environment,
  required bool isWindows,
  required StringSink out,
  required StringSink err,
  String? cwd,
  AppLauncher? appLauncher,
  Stream<void>? interrupts,
}) async {
  var json = arguments.contains('--json');
  var command = '';
  var wasInterrupted = false;
  StreamSubscription<void>? signalSubscription;
  Map<String, Object?> requestArguments = const {};
  void emit(CommandResult result, {String? human}) {
    if (json) {
      out.writeln(jsonEncode(result.toOutputJson()));
    } else if (!result.ok) {
      if (result.results.isNotEmpty ||
          result.error?.code == 'ambiguousSource') {
        out.writeln(renderHumanResult(result, arguments: requestArguments));
      }
      err.writeln(result.error!.message);
    } else {
      final text =
          human ?? renderHumanResult(result, arguments: requestArguments);
      if (result.command == 'show' && result.data.containsKey('document')) {
        out.write(text);
      } else {
        out.writeln(text);
      }
    }
  }

  try {
    final parsed = parseSkilldeckCommandLine(
      arguments,
      cwd: cwd ?? Directory.current.path,
      isWindows: isWindows,
    );
    json = parsed.json;
    command = parsed.command;
    if (command == 'help' || command == 'version') {
      emit(
        CommandResult(
          ok: true,
          command: command,
          data: command == 'version'
              ? {'cliVersion': cliVersion}
              : helpCatalog(parsed.helpCommand),
        ),
        human: command == 'version' ? cliVersion : helpText(parsed.helpCommand),
      );
      return CliExitCode.success.value;
    }
    final runDirectory = commandHostRunDirectory(
      environment: environment,
      isWindows: isWindows,
    );
    final interrupted = Completer<void>();
    try {
      signalSubscription = (interrupts ?? ProcessSignal.sigint.watch()).listen((
        _,
      ) {
        wasInterrupted = true;
        if (!interrupted.isCompleted) interrupted.complete();
      });
    } on Object {
      // Best effort on platforms without signal support.
    }
    requestArguments = parsed.requestArguments;
    final executing = (appLauncher ?? AppLauncher(runDirectory: runDirectory))
        .execute(
          CommandRequest(command: command, arguments: parsed.requestArguments),
          noLaunch: parsed.noLaunch,
          cancelled: interrupted.future,
          onStarting: json
              ? null
              : () => err.writeln('Starting SkillDeck in the background…'),
        );
    final result = await Future.any([
      executing,
      interrupted.future.then(
        (_) => CommandResult.failure(
          command,
          'operationCancelled',
          'The command was cancelled.',
        ),
      ),
    ]);
    if (interrupted.isCompleted) {
      emit(
        CommandResult.failure(
          command,
          'operationCancelled',
          'The command was cancelled.',
        ),
      );
      return CliExitCode.cancelled.value;
    }
    emit(result);
    return commandExitCode(result);
  } on FormatException {
    // Never echo parser exception text: it can contain arbitrary arguments.
    if (command.isEmpty) {
      command = arguments.where(commandCatalog.containsKey).firstOrNull ?? '';
    }
    emit(
      CommandResult.failure(
        command,
        'usage',
        'Usage: skilldeck <command> [refs] [options]. Run skilldeck help.',
      ),
    );
    return CliExitCode.usage.value;
  } on ClientFailure catch (failure) {
    if (wasInterrupted) {
      emit(
        CommandResult.failure(
          command,
          'operationCancelled',
          'The command was cancelled.',
        ),
      );
      return CliExitCode.cancelled.value;
    }
    emit(CommandResult.failure(command, failure.code.name, failure.message));
    return switch (failure.code) {
      ClientFailureCode.appUnavailable ||
      ClientFailureCode.appNotInstalled ||
      ClientFailureCode.appLaunchTimeout ||
      ClientFailureCode.protocolMismatch ||
      ClientFailureCode.missingHome => CliExitCode.appUnavailable.value,
      _ => CliExitCode.failed.value,
    };
  } on Object {
    if (wasInterrupted) {
      emit(
        CommandResult.failure(
          command,
          'operationCancelled',
          'The command was cancelled.',
        ),
      );
      return CliExitCode.cancelled.value;
    }
    emit(
      CommandResult.failure(command, 'internalError', 'The command failed.'),
    );
    return CliExitCode.failed.value;
  } finally {
    await signalSubscription?.cancel();
  }
}
