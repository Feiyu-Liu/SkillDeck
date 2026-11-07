import 'dart:convert';

import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';

import 'command_host_dispatcher.dart';
import 'skill_json.dart';
import 'skill_selector_resolver.dart';

const maximumCommandDocumentBytes = 512 * 1024;

/// Reads provider-owned state at dispatch time; never owns a Workspace facade.
Map<String, CommandHostHandler> readCommandHandlers({
  required SkillsWorkspaceSnapshot? Function() snapshot,
  required SkillsWorkspaceRepository Function() repository,
  required SkillUpdateStatus Function() updates,
  required Future<List<WorkspaceAgentInfo>> Function() agents,
  required Future<Set<String>> Function() members,
  required Future<List<WorkspaceActivationTarget>> Function() globalTargets,
}) => {
  'agents': (request) async {
    if (request.arguments.isNotEmpty) {
      throw const SkillSelectionFailure('usage');
    }
    final catalog = await agents();
    final enabled = await members();
    final targets = await globalTargets();
    return CommandResult(
      ok: true,
      command: request.command,
      data: {
        'agents': [
          for (final agent in catalog)
            agentJson(agent, memberIds: enabled, globalTargets: targets),
        ],
      },
    );
  },
  for (final command in ['list', 'show'])
    command: (request) async {
      if (request.arguments.keys.any(
        (key) =>
            key != 'selection' && !(command == 'show' && key == 'document'),
      )) {
        throw const SkillSelectionFailure('usage');
      }
      final SkillSelection selection;
      final String? documentPath;
      try {
        selection = SkillSelection.fromJson(
          request.arguments['selection'] as Map<String, Object?>,
        );
        documentPath = request.arguments['document'] as String?;
      } on Object {
        throw const SkillSelectionFailure('usage');
      }
      final current = snapshot();
      if (current == null ||
          current.integrity == WorkspaceIntegrityStatus.corrupt) {
        throw const SkillSelectionFailure('workspaceUnavailable');
      }
      final update = updates();
      final selected = resolveSkillSelection(
        current,
        selection,
        availableUpdateIds: update.availableSkillIds,
      );
      if (command == 'list') {
        return CommandResult(
          ok: true,
          command: command,
          results: [
            for (final skill in selected)
              {
                'id': skill.id.value,
                'slotKey': skill.slotKey,
                'outcome': 'listed',
              },
          ],
          data: {
            'skills': [
              for (final skill in selected)
                skillJson(skill, current, update: update.stateOf(skill.id)),
            ],
          },
        );
      }
      if (selected.isEmpty) throw const SkillSelectionFailure('skillNotFound');
      if (selected.length != 1) {
        throw const SkillSelectionFailure('ambiguousSelection');
      }
      final skill = selected.single;
      final repo = repository();
      final documents = readCommandValue(
        await repo.listSkillDocuments(skill.id),
      );
      final data = <String, Object?>{
        'skill': skillJson(skill, current, update: update.stateOf(skill.id)),
        'documents': [for (final doc in documents) doc.relativePath],
      };
      if (documentPath != null) {
        final entry = documents
            .where((doc) => doc.relativePath == documentPath)
            .firstOrNull;
        if (entry == null) {
          throw const SkillSelectionFailure('documentNotFound');
        }
        final text = readCommandValue(
          await repo.readSkillDocument(
            skill.id,
            entry.relativePath,
            expectedContentHash: entry.contentHash,
          ),
        );
        if (utf8.encode(text).length > maximumCommandDocumentBytes) {
          throw const SkillSelectionFailure('documentTooLarge');
        }
        data['document'] = {'path': entry.relativePath, 'text': text};
      }
      final result = CommandResult(ok: true, command: command, data: data);
      // JSON escaping can expand a <=512 KiB document beyond the wire limit.
      if (documentPath != null &&
          utf8.encode(jsonEncode(result.toJson())).length >
              maximumCommandHostLineBytes) {
        throw const SkillSelectionFailure('documentTooLarge');
      }
      return result;
    },
};

T readCommandValue<T>(WorkspaceCompletion<T> completion) =>
    switch (completion) {
      WorkspaceCompleted(:final value) => value,
      WorkspaceFailed(:final failure) => throw SkillSelectionFailure(
        switch (failure.code) {
          WorkspaceErrorCode.documentUnavailable ||
          WorkspaceErrorCode.effectiveFileNotFound => 'documentNotFound',
          _ => failure.code.name,
        },
      ),
      _ => throw const SkillSelectionFailure('internalError'),
    };
