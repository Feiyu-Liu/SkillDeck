import 'dart:async';
import 'dart:convert';

import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import 'skill_json.dart';
import 'command_cancellation.dart';
import 'skill_selector_resolver.dart';

typedef CommandHostHandler = FutureOr<CommandResult> Function(CommandRequest);

final class CommandHostDispatcher {
  CommandHostDispatcher(Map<String, CommandHostHandler> handlers)
    : _handlers = Map.unmodifiable(handlers);
  final Map<String, CommandHostHandler> _handlers;

  bool recognizes(String command) => _handlers.containsKey(command);

  Future<CommandResult> dispatch(
    CommandRequest request, {
    CommandCancellation? cancellation,
  }) async {
    final handler = _handlers[request.command];
    if (handler == null) {
      return CommandResult.failure(
        request.command,
        'unknownCommand',
        'The Command Host does not support this command.',
      );
    }
    try {
      final result = await AppDiagnostics.withoutDetails(
        () =>
            (cancellation ?? CommandCancellation()).run(() => handler(request)),
      );
      if (utf8.encode(jsonEncode(result.toJson())).length >
          maximumCommandHostLineBytes) {
        return CommandResult.failure(
          request.command,
          'responseTooLarge',
          'The response is too large. Narrow the selection.',
        );
      }
      return result;
    } on SkillSelectionFailure catch (failure) {
      return CommandResult(
        ok: false,
        command: request.command,
        error: CommandError(
          code: failure.code,
          message: _readFailureMessage(failure.code),
          details: failure.details,
        ),
      );
    } on Object {
      return CommandResult.failure(
        request.command,
        'internalError',
        'The command could not be completed.',
      );
    }
  }
}

CommandHostHandler statusCommandHandler({
  required String appVersion,
  required SkillsWorkspaceSnapshot? Function() snapshot,
}) => (request) {
  final current = snapshot();
  final ready =
      current != null && current.integrity != WorkspaceIntegrityStatus.corrupt;
  return CommandResult(
    ok: true,
    command: request.command,
    data: {
      'appVersion': appVersion,
      'protocolVersion': commandHostProtocolVersion,
      'projectRoots': [
        for (final root in current?.projectRoots ?? <SkillProjectRoot>[])
          projectRootJson(root),
      ],
      'workspace': {
        'state': ready ? 'ready' : 'unavailable',
        'skillCount': current?.skills.length ?? 0,
        'projectRootCount': current?.projectRoots.length ?? 0,
      },
    },
  );
};

String _readFailureMessage(String code) => switch (code) {
  'usage' => 'Provide a Skill ref, filter, or --all.',
  'skillNotFound' => 'No matching Skill was found.',
  'ambiguousSelection' => 'Select exactly one Skill.',
  'documentNotFound' => 'The document was not found.',
  'documentTooLarge' => 'The document is too large for the Command Host.',
  'workspaceUnavailable' => 'The Workspace is unavailable.',
  'ambiguousSource' => 'This Source contains several Skills.',
  'candidateNotFound' => 'No Skill with that name was found in this Source.',
  'replacementCandidateNotFound' =>
    'No replacement candidate matches this Skill.',
  'replacementCandidateAmbiguous' =>
    'Several replacement candidates match this Skill.',
  'lockUnavailable' => 'The skills lock is unavailable or invalid.',
  'lockEntryMissing' => 'No skills lock entry matches this Skill.',
  'lockSourceUnsupported' => 'Only GitHub skills lock entries are supported.',
  'notAdopted' => 'This Skill does not have an Adopted Snapshot Source.',
  'unknownAgent' => 'That Agent is not set up on this device.',
  _ => 'The command could not be completed.',
};
