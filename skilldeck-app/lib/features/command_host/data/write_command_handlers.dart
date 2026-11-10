import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_coordinator.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_input_parser.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';

import 'command_cancellation.dart';
import 'command_host_dispatcher.dart';
import 'skill_selector_resolver.dart';
import 'skill_json.dart';
import 'source_command_support.dart';

const writeCommands = [
  'install',
  'update',
  'activate',
  'deactivate',
  'favorite',
  'note',
  'tag add',
  'tag remove',
  'tag rename',
];

typedef WriteActivityItem = ({String id, String slotKey});
typedef _ResultItem = ({String? id, String slotKey});

_ResultItem _resultItem(WorkspaceSkill skill) =>
    (id: skill.id.value, slotKey: skill.slotKey);

/// Lets the App show a running batch while this layer stays UI-agnostic.
abstract interface class WriteActivityReporter {
  WriteActivity begin({
    required String command,
    required bool favorite,
    required List<String> agentIds,
    required List<WriteActivityItem> items,
    required void Function() cancel,
  });
}

/// One reported batch. Outcomes use the wire vocabulary, such as `succeeded`.
abstract interface class WriteActivity {
  void start(String id);
  void finish(String id, String outcome, {String? errorCode});
  void end();
}

Map<String, CommandHostHandler> writeCommandHandlers({
  required SkillsWorkspaceSnapshot? Function() snapshot,
  required SkillsWorkspaceRepository Function() repository,
  required SkillUpdateStatus Function() updates,
  required Future<List<WorkspaceAgentInfo>> Function() agents,
  required Future<Set<String>> Function() members,
  WriteActivityReporter? activity,
  SkillUpdateStatusCoordinator Function()? updateCoordinator,
}) => {
  for (final command in writeCommands)
    command: (request) =>
        AgentRootOwnershipCoordinator.withoutInteractiveRepair(
          () => _execute(
            request,
            snapshot,
            repository,
            updates,
            agents,
            members,
            activity,
            updateCoordinator,
          ),
        ),
};

Future<CommandResult> _execute(
  CommandRequest request,
  SkillsWorkspaceSnapshot? Function() snapshot,
  SkillsWorkspaceRepository Function() repository,
  SkillUpdateStatus Function() updates,
  Future<List<WorkspaceAgentInfo>> Function() agents,
  Future<Set<String>> Function() members,
  WriteActivityReporter? reporter,
  SkillUpdateStatusCoordinator Function()? updateCoordinator,
) async {
  if (request.command == 'install') {
    return _install(request, snapshot, repository, agents, members, reporter);
  }
  final command = request.command;
  final args = request.arguments;
  final activation = command == 'activate' || command == 'deactivate';
  final tagCommand = command == 'tag add' || command == 'tag remove';
  late final bool dryRun;
  late final bool keepGoing;
  late final SkillSelection selection;
  late final List<String> agentIds;
  late final List<String> tagNames;
  late final String? projectPath;
  late final bool favorite;
  String? note;
  String? renameFrom;
  String? renameTo;
  try {
    final allowed = {
      'dryRun',
      'keepGoing',
      'wait',
      if (command != 'tag rename') 'selection',
      if (activation) ...['agents', 'projectPath'],
      if (command == 'update') 'check',
      if (command == 'favorite') 'favorite',
      if (command == 'note') 'note',
      if (tagCommand) 'tags',
      if (command == 'tag rename') 'rename',
    };
    if (args.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException();
    }
    if (command == 'update' &&
        args['check'] != null &&
        args['check'] is! bool) {
      throw const FormatException();
    }
    dryRun = args['dryRun'] as bool? ?? false;
    keepGoing = args['keepGoing'] as bool? ?? false;
    final wait = args['wait'] as int? ?? 30;
    if (wait < 0) throw const FormatException();
    selection = command == 'tag rename'
        ? SkillSelection(all: true)
        : SkillSelection.fromJson(args['selection'] as Map<String, Object?>);
    agentIds = (args['agents'] as List? ?? []).cast<String>();
    tagNames = (args['tags'] as List? ?? []).cast<String>();
    favorite = args['favorite'] as bool? ?? true;
    projectPath = args['projectPath'] as String?;
    if (projectPath != null && !p.isAbsolute(projectPath)) {
      throw const FormatException();
    }
    if (activation && agentIds.isEmpty || tagCommand && tagNames.isEmpty) {
      throw const FormatException();
    }
    if (command == 'note') {
      final value = args['note'] as Map;
      if (value.length != 1) throw const FormatException();
      if (value.containsKey('set')) {
        note = (value['set'] as String).trim();
      } else if (value['clear'] != true) {
        throw const FormatException();
      }
    }
    if (command == 'tag rename') {
      final rename = args['rename'] as Map;
      if (rename.length != 2) throw const FormatException();
      renameFrom = (rename['from'] as String).trim();
      renameTo = (rename['to'] as String).trim();
    }
  } on Object {
    throw const SkillSelectionFailure('usage');
  }
  final current = snapshot();
  if (current == null ||
      current.integrity == WorkspaceIntegrityStatus.corrupt) {
    throw const SkillSelectionFailure('workspaceUnavailable');
  }
  if (activation) {
    final catalog = await agents();
    final enabled = await members();
    for (final id in agentIds) {
      if (!enabled.contains(id) || !catalog.any((a) => a.id == id)) {
        throw SkillSelectionFailure('unknownAgent', details: {'agent': id});
      }
    }
  }
  final batch = _Batch(request.command, dryRun);
  if (command == 'update') {
    batch.data['check'] = args['check'] == true && !dryRun;
  }
  final repo = repository();
  final tags = {for (final t in current.personalTags) t.name.toLowerCase(): t};
  if (command == 'tag rename') {
    final tag = tags[renameFrom!.toLowerCase()];
    await batch.item(null, () async {
      if (tag == null) throw _WriteFailure('tagNotFound');
      _validateTag(renameTo!);
      final conflict = tags[renameTo.toLowerCase()];
      if (conflict != null && conflict.id != tag.id) {
        throw _WriteFailure('tagNameConflict');
      }
      if (tag.name == renameTo) return false;
      if (!dryRun) {
        await batch.perform(
          () => repo.updatePersonalTag(
            tagId: tag.id,
            name: renameTo!,
            color: tag.color,
          ),
        );
      }
      return true;
    });
    return batch.finish();
  }
  // Destination project is deliberately distinct from the selection's project
  // filter: selecting refs to activate at a new root must still resolve them.
  final selected = resolveSkillSelection(
    current,
    selection,
    availableUpdateIds: updates().availableSkillIds,
  );
  if (command == 'note' && selected.length != 1) {
    throw const SkillSelectionFailure('ambiguousSelection');
  }
  SkillProjectRoot? root = projectPath == null
      ? null
      : current.projectRoots
            .where(
              (r) => p.equals(p.normalize(r.path), p.normalize(projectPath!)),
            )
            .firstOrNull;
  var rootRegistered = false;
  final requestedTags = {
    for (final name in tagNames) name.trim().toLowerCase(): name.trim(),
  };
  final createdTags = <String>[];
  var stopped = false;
  // Dry runs change nothing, so the App has nothing to show for them.
  final activity = dryRun || args['check'] == true || selected.isEmpty
      ? null
      : reporter?.begin(
          command: command,
          favorite: favorite,
          agentIds: agentIds,
          items: [
            for (final skill in selected)
              (id: skill.id.value, slotKey: skill.slotKey),
          ],
          cancel: () => unawaited(batch.cancellation.cancel()),
        );
  void report(WorkspaceSkill skill) {
    final last = batch.results.last;
    activity?.finish(
      skill.id.value,
      last['outcome']! as String,
      errorCode: (last['error'] as Map<String, Object?>?)?['code'] as String?,
    );
  }

  try {
    for (final skill in selected) {
      if (batch.cancellation.isCancelled) {
        batch.record(_resultItem(skill), 'cancelled');
        report(skill);
        continue;
      }
      if (stopped) {
        batch.record(_resultItem(skill), 'notAttempted');
        report(skill);
        continue;
      }
      activity?.start(skill.id.value);
      await batch.item(_resultItem(skill), () async {
        switch (command) {
          case 'update':
            final latest = repo.current?.findSkillById(skill.id) ?? skill;
            if (args['check'] == true && !dryRun) {
              final state = await updateCoordinator!().checkSkill(skill.id);
              final code = _checkFailureCode(state);
              if (code != null) {
                batch.firstError ??= CommandError(
                  code: code,
                  message: 'The update check could not be completed.',
                );
              }
              batch.record(
                _resultItem(skill),
                code == null
                    ? (state.updateAvailable ? 'updateAvailable' : 'upToDate')
                    : 'checkFailed',
                error: code == null
                    ? null
                    : CommandError(
                        code: code,
                        message: 'The update check could not be completed.',
                      ),
              );
              return false;
            }
            // Dry runs describe observed availability without starting checks.
            if (dryRun) return updates().stateOf(skill.id).updateAvailable;
            if (latest.draft?.isDirty ?? false) {
              throw _WriteFailure(
                'dirtyDraftResolutionRequired',
                screen: 'skillDetail',
              );
            }
            if (latest.updateCandidate != null ||
                updates().stateOf(skill.id).report?.status ==
                    WorkspaceUpdateStatus.resolutionRequired) {
              throw _WriteFailure(
                'updateCandidateResolutionRequired',
                screen: 'updates',
              );
            }
            if (!updates().stateOf(skill.id).updateAvailable) return false;
            try {
              final receipt = await batch.perform(
                () => repo.update(skillIds: {skill.id}),
              );
              updateCoordinator!().deriveAfterUpdate(skill.id);
              if (receipt.snapshot.findSkillById(skill.id)?.updateCandidate !=
                      null ||
                  updates().stateOf(skill.id).report?.status ==
                      WorkspaceUpdateStatus.resolutionRequired) {
                throw _WriteFailure(
                  'updateCandidateResolutionRequired',
                  screen: 'updates',
                );
              }
            } on _Pending {
              updateCoordinator!().deriveAfterUpdate(skill.id);
              rethrow;
            }
            return true;
          case 'activate':
          case 'deactivate':
            bool matches(SkillActivationLocation a) => projectPath == null
                ? a.scope == WorkspaceScope.global
                : a.scope == WorkspaceScope.project &&
                      root != null &&
                      a.projectRootId == root!.id;
            final locations = skill.activations
                .where((a) => matches(a) && a.agentIds.any(agentIds.contains))
                .toList();
            if (command == 'deactivate') {
              if (locations.isEmpty) return false;
              if (!dryRun) {
                await batch.perform(
                  () => repo.deactivate(
                    skillIds: {skill.id},
                    locations: locations.map((a) => a.location).toSet(),
                  ),
                );
              }
            } else {
              if (agentIds.every(
                (id) => locations.any((a) => a.agentIds.contains(id)),
              )) {
                return false;
              }
              if (projectPath != null && root == null) {
                if (dryRun) {
                  batch.data['wouldRegisterProjectRoot'] = {
                    'path': projectPath,
                  };
                } else {
                  // A previous committed-pending registration may have published
                  // the root without returning a receipt.
                  root = repo.current?.projectRoots
                      .where((r) => p.equals(r.path, projectPath!))
                      .firstOrNull;
                  if (root == null) {
                    final receipt = await batch.perform(
                      () => repo.registerProjectRoot(path: projectPath!),
                    );
                    root = receipt.snapshot.projectRoots
                        .where((r) => p.equals(r.path, projectPath!))
                        .firstOrNull;
                    rootRegistered = true;
                  }
                  if (root == null) throw _WriteFailure('projectRootNotFound');
                  if (rootRegistered) {
                    batch.data['projectRootRegistered'] = {
                      'id': root!.id,
                      'path': root!.path,
                    };
                  }
                }
              }
              if (!dryRun) {
                final attempt = await batch.perform(
                  () => repo.activate(
                    skillIds: {skill.id},
                    scope: projectPath == null
                        ? WorkspaceScope.global
                        : WorkspaceScope.project,
                    agentIds: agentIds.toSet(),
                    projectRootId: root?.id,
                  ),
                  commits: (value) => value is WorkspaceActivationCompleted,
                );
                if (attempt is WorkspaceActivationTakeoverRequired) {
                  throw _WriteFailure(
                    'activationTargetOccupied',
                    screen: 'skillDetail',
                  );
                }
              }
            }
            return true;
          case 'favorite':
            if (skill.isFavorite == favorite) return false;
            if (!dryRun) {
              await batch.perform(
                () => repo.setFavorite(skillId: skill.id, isFavorite: favorite),
              );
            }
            return true;
          case 'note':
            if (note != null && note.isEmpty) {
              throw _WriteFailure('invalidNote');
            }
            if (skill.note == note) return false;
            if (!dryRun) {
              if (note == null) {
                await batch.perform(() => repo.deleteNote(skill.id));
              } else {
                await batch.perform(
                  () => repo.saveNote(skillId: skill.id, note: note!),
                );
              }
            }
            return true;
          default:
            var changed = false;
            for (final entry in requestedTags.entries) {
              _validateTag(entry.value);
              var tag = tags[entry.key];
              if (tag == null && command == 'tag remove') {
                throw _WriteFailure('tagNotFound');
              }
              if (tag == null) {
                changed = true;
                if (dryRun) {
                  if (!createdTags.contains(entry.value)) {
                    createdTags.add(entry.value);
                  }
                } else {
                  tag = repo.current?.personalTags
                      .where((t) => t.name.toLowerCase() == entry.key)
                      .firstOrNull;
                  tag ??= await batch.perform(
                    () => repo.createPersonalTag(name: entry.value),
                  );
                  tags[entry.key] = tag!;
                  if (!createdTags.contains(tag.name)) {
                    createdTags.add(tag.name);
                  }
                }
              }
              final assigned =
                  tag != null && skill.personalTagIds.contains(tag.id);
              if (assigned == (command == 'tag add')) continue;
              changed = true;
              if (!dryRun) {
                if (command == 'tag add') {
                  await batch.perform(
                    () => repo.assignPersonalTag(
                      skillId: skill.id,
                      tagId: tag!.id,
                    ),
                  );
                } else {
                  await batch.perform(
                    () => repo.unassignPersonalTag(
                      skillId: skill.id,
                      tagId: tag!.id,
                    ),
                  );
                }
              }
            }
            return changed;
        }
      });
      report(skill);
      if (batch.lastFailed && !keepGoing) stopped = true;
    }
  } finally {
    activity?.end();
  }
  if (createdTags.isNotEmpty) {
    batch.data[dryRun ? 'wouldCreateTags' : 'tagsCreated'] = createdTags;
  }
  return batch.finish();
}

String? _checkFailureCode(SkillUpdateState state) => switch (state) {
  SkillUpdateCheckFailed(:final failure) =>
    failure.codeKey == 'unexpected' ? 'checkFailed' : failure.codeKey,
  SkillUpdateChecked(:final report) => switch (report.status) {
    WorkspaceUpdateStatus.sourceUnavailable => 'sourceUnavailable',
    WorkspaceUpdateStatus.updateUnsupported => 'updateUnsupported',
    WorkspaceUpdateStatus.resolutionRequired =>
      'updateCandidateResolutionRequired',
    _ => null,
  },
  _ => 'checkFailed',
};

Future<CommandResult> _install(
  CommandRequest request,
  SkillsWorkspaceSnapshot? Function() snapshot,
  SkillsWorkspaceRepository Function() repository,
  Future<List<WorkspaceAgentInfo>> Function() agents,
  Future<Set<String>> Function() members,
  WriteActivityReporter? reporter,
) async {
  final args = request.arguments;
  late final bool dryRun;
  late final bool keepGoing;
  late final bool allSkills;
  late final List<String> names;
  late final List<String> agentIds;
  late final String? projectPath;
  late final ParsedSkillSourceInput parsed;
  late final SkillSourceInput source;
  try {
    if (args.keys.any(
      (key) => !{
        'source',
        'skills',
        'allSkills',
        'agents',
        'projectPath',
        'dryRun',
        'keepGoing',
        'wait',
      }.contains(key),
    )) {
      throw const FormatException();
    }
    dryRun = args['dryRun'] as bool? ?? false;
    keepGoing = args['keepGoing'] as bool? ?? false;
    allSkills = args['allSkills'] as bool? ?? false;
    names = (args['skills'] as List? ?? []).cast<String>();
    agentIds = (args['agents'] as List? ?? []).cast<String>();
    projectPath = args['projectPath'] as String?;
    if ((args['wait'] as int? ?? 30) < 0 ||
        allSkills && names.isNotEmpty ||
        projectPath != null &&
            (agentIds.isEmpty || !p.isAbsolute(projectPath))) {
      throw const FormatException();
    }
    final input = args['source'] as String;
    if (input.trim().isEmpty || names.any((n) => n.trim().isEmpty)) {
      throw const FormatException();
    }
    parsed = SkillSourceInputParser().parse(
      input,
      mode: SkillSourceInputMode.smart,
    );
    source = parseSourceArgument(input).source;
  } on SkillSelectionFailure {
    rethrow;
  } on SkillAcquisitionException {
    throw const SkillSelectionFailure('invalidSource');
  } on Object {
    throw const SkillSelectionFailure('usage');
  }
  final current = snapshot();
  if (current == null ||
      current.integrity == WorkspaceIntegrityStatus.corrupt) {
    throw const SkillSelectionFailure('workspaceUnavailable');
  }
  if (agentIds.isNotEmpty) {
    final catalog = await agents();
    final enabled = await members();
    for (final id in agentIds) {
      if (!enabled.contains(id) || !catalog.any((a) => a.id == id)) {
        throw SkillSelectionFailure('unknownAgent', details: {'agent': id});
      }
    }
  }
  final repo = repository();
  final batch = _Batch('install', dryRun);
  final inspection = await inspectSourceForCommand(
    repo,
    source,
    parsed.detection,
    batch.cancellation,
  );
  final requested = names.isNotEmpty
      ? names.toSet()
      : parsed.requestedSkillNames;
  final selectAll = allSkills || names.isEmpty && requested.contains('*');
  final candidates = inspection.candidates;
  final selected = <WorkspaceSourceCandidate>[];
  if (selectAll) {
    selected.addAll(candidates);
  } else if (requested.isNotEmpty) {
    for (final name in requested) {
      if (!candidates.any(
        (c) =>
            c.declaredName.toLowerCase() == name.toLowerCase() ||
            c.slotKey.toLowerCase() == name.toLowerCase(),
      )) {
        throw const SkillSelectionFailure('candidateNotFound');
      }
    }
    selected.addAll(
      candidates.where(
        (c) => requested.any(
          (name) =>
              c.declaredName.toLowerCase() == name.toLowerCase() ||
              c.slotKey.toLowerCase() == name.toLowerCase(),
        ),
      ),
    );
  } else if (candidates.length > 1) {
    throw SkillSelectionFailure(
      'ambiguousSource',
      details: {
        'candidates': [
          for (final c in candidates.take(200))
            {
              'name': c.declaredName,
              'slotKey': c.slotKey,
              'description': c.description,
            },
        ],
      },
    );
  } else {
    selected.addAll(candidates);
  }
  if (selected.isEmpty) throw const SkillSelectionFailure('candidateNotFound');
  batch.data['source'] = {
    'kind': inspection.source.kind.name,
    'locator': stripLocatorUserinfo(inspection.source.locator),
  };
  SkillProjectRoot? root = projectPath == null
      ? null
      : current.projectRoots
            .where(
              (r) => p.equals(p.normalize(r.path), p.normalize(projectPath!)),
            )
            .firstOrNull;
  final activity = dryRun
      ? null
      : reporter?.begin(
          command: 'install',
          favorite: true,
          agentIds: agentIds,
          items: [
            for (final c in selected) (id: c.slotKey, slotKey: c.slotKey),
          ],
          cancel: () => unawaited(batch.cancellation.cancel()),
        );
  var stopped = false;
  try {
    for (final candidate in selected) {
      final item = (id: null, slotKey: candidate.slotKey);
      if (batch.cancellation.isCancelled) {
        batch.record(item, 'cancelled');
      } else if (stopped) {
        batch.record(item, 'notAttempted');
      } else {
        activity?.start(candidate.slotKey);
        WorkspaceSkillId? installedId;
        await batch.item(item, () async {
          final existing = repo.current?.skills
              .where((s) => s.slotKey == candidate.slotKey)
              .firstOrNull;
          if (existing != null) {
            if (dryRun) {
              batch.record((
                id: existing.id.value,
                slotKey: candidate.slotKey,
              ), 'alreadyInstalled');
              return false;
            }
            throw _WriteFailure('alreadyInstalled');
          }
          if (projectPath != null && root == null) {
            if (dryRun) {
              batch.data['wouldRegisterProjectRoot'] = {'path': projectPath};
            } else {
              root = repo.current?.projectRoots
                  .where((r) => p.equals(r.path, projectPath!))
                  .firstOrNull;
              if (root == null) {
                final receipt = await batch.perform(
                  () => repo.registerProjectRoot(path: projectPath!),
                );
                root = receipt.snapshot.projectRoots
                    .where((r) => p.equals(r.path, projectPath!))
                    .firstOrNull;
                if (root == null) throw _WriteFailure('projectRootNotFound');
                batch.data['projectRootRegistered'] = {
                  'id': root!.id,
                  'path': root!.path,
                };
              }
            }
          }
          if (!dryRun) {
            final attempt = await batch.perform(
              () => repo.install(
                WorkspaceInstallRequest(
                  source: inspection.source,
                  skillNames: {candidate.declaredName},
                  scope: projectPath == null
                      ? WorkspaceScope.global
                      : WorkspaceScope.project,
                  projectRootId: root?.id,
                  agentIds: agentIds.toSet(),
                  storeOnly: agentIds.isEmpty,
                ),
              ),
              commits: (value) => value is WorkspaceInstallCompleted,
            );
            if (attempt is WorkspaceInstallTakeoverRequired) {
              throw _WriteFailure(
                'activationTargetOccupied',
                screen: 'addSkill',
              );
            }
            if (attempt is WorkspaceInstallCompleted) {
              installedId = attempt.receipt.snapshot.skills
                  .where((s) => s.slotKey == candidate.slotKey)
                  .firstOrNull
                  ?.id;
            }
          }
          return true;
        });
        // A committed-pending operation can also have published the Skill.
        installedId ??= repo.current?.skills
            .where((s) => s.slotKey == candidate.slotKey)
            .firstOrNull
            ?.id;
        if (installedId != null) batch.results.last['id'] = installedId!.value;
        if (batch.lastFailed && !keepGoing) stopped = true;
      }
      final last = batch.results.last;
      activity?.finish(
        candidate.slotKey,
        last['outcome']! as String,
        errorCode: (last['error'] as Map<String, Object?>?)?['code'] as String?,
      );
    }
  } finally {
    activity?.end();
  }
  return batch.finish();
}

void _validateTag(String name) {
  if (name.isEmpty || name.contains('\u0000')) {
    throw _WriteFailure('invalidTagName');
  }
}

final class _WriteFailure implements Exception {
  _WriteFailure(this.code, {this.screen});
  final String code;
  final String? screen;
}

final class _Pending implements Exception {}

final class _Batch {
  _Batch(this.command, this.dryRun);
  final String command;
  final bool dryRun;
  final cancellation = CommandCancellation.current ?? CommandCancellation();
  final results = <Map<String, Object?>>[];
  final data = <String, Object?>{};
  CommandError? firstError;
  bool committed = false;
  bool lastFailed = false;
  String? operationId;

  Future<T> perform<T>(
    WorkspaceTask<T> Function() start, {
    bool Function(T)? commits,
  }) async {
    if (cancellation.isCancelled) throw _WriteFailure('operationCancelled');
    final task = start();
    operationId = task.current.operationId;
    final completion = await cancellation.complete(
      task,
      observe: (progress) => operationId = progress.operationId,
    );
    switch (completion) {
      case WorkspaceCompleted(:final value):
        if (commits == null || commits(value)) committed = true;
        return value;
      case WorkspaceCommittedPending(:final operationId):
        committed = true;
        this.operationId = operationId;
        throw _Pending();
      case WorkspaceFailed(:final failure):
        throw _WriteFailure(
          switch (failure.code) {
            WorkspaceErrorCode.duplicateSkillSlot ||
            WorkspaceErrorCode.sourceReplacementRequired
                when command == 'install' =>
              'alreadyInstalled',
            WorkspaceErrorCode.personalTagNotFound => 'tagNotFound',
            WorkspaceErrorCode.duplicatePersonalTag => 'tagNameConflict',
            WorkspaceErrorCode.agentRootOwnership =>
              'agentRootOwnershipRepairRequired',
            _ => failure.code.name,
          },
          screen: switch (failure.code) {
            WorkspaceErrorCode.agentRootOwnership => 'settings',
            WorkspaceErrorCode.dirtyDraftResolutionRequired
                when command == 'update' =>
              'skillDetail',
            WorkspaceErrorCode.externalConflict ||
            WorkspaceErrorCode.updateCandidateResolutionRequired
                when command == 'update' =>
              'updates',
            _ => null,
          },
        );
    }
  }

  void record(_ResultItem? skill, String outcome, {CommandError? error}) {
    results.add({
      if (skill != null) ...{
        if (skill.id != null) 'id': skill.id,
        'slotKey': skill.slotKey,
      },
      'outcome': outcome,
      if (operationId != null) 'operationId': operationId,
      if (error != null) 'error': error.toJson(),
    });
    operationId = null;
  }

  Future<void> item(_ResultItem? skill, Future<bool> Function() action) async {
    lastFailed = false;
    try {
      if (cancellation.isCancelled) throw _WriteFailure('operationCancelled');
      final count = results.length;
      final changed = await action();
      if (results.length != count) return;
      record(
        skill,
        changed ? (dryRun ? 'wouldSucceed' : 'succeeded') : 'unchanged',
      );
    } on _Pending {
      record(skill, 'committedFinalizationPending');
    } on Object catch (error) {
      final failure = error is _WriteFailure
          ? error
          : _WriteFailure('operationFailed');
      final cancelled =
          cancellation.isCancelled || failure.code == 'operationCancelled';
      if (cancelled) await cancellation.cancel();
      final commandError = CommandError(
        code: failure.code,
        message: switch (failure.screen) {
          'settings' =>
            'Open SkillDeck Settings to review Agent Root Ownership Repair.',
          'skillDetail' => 'Open SkillDeck Skill Detail to resolve this item.',
          'updates' => 'Open SkillDeck Updates to resolve this item.',
          'addSkill' =>
            'Open SkillDeck Add Skill to review the occupied target.',
          _ => 'The operation could not be completed.',
        },
        details: {if (failure.screen != null) 'screen': failure.screen},
      );
      firstError ??= commandError;
      lastFailed = true;
      record(skill, cancelled ? 'cancelled' : 'failed', error: commandError);
    }
  }

  CommandResult finish() {
    final cancelled = cancellation.isCancelled;
    final requiresAction =
        (command == 'install' || command == 'update') &&
        firstError?.details['screen'] != null;
    final successfulItem = results.any(
      (r) =>
          r['outcome'] == 'succeeded' ||
          r['outcome'] == 'committedFinalizationPending',
    );
    CommandError? error = firstError;
    if (cancelled) {
      error = CommandError(
        code: 'operationCancelled',
        message: 'The command was cancelled.',
      );
    } else if (command == 'update' && data['check'] == true) {
      if (results.any(
        (r) => r['outcome'] == 'updateAvailable' || r['outcome'] == 'upToDate',
      )) {
        error = null;
      }
    } else if (error != null) {
      if (committed &&
          (command != 'update' || !requiresAction || successfulItem)) {
        error = CommandError(
          code: 'partialBatch',
          message: 'Changes committed before a failure.',
          details: {'cause': error.code, ...error.details},
        );
      } else if (requiresAction) {
        error = CommandError(
          code: 'actionRequired',
          message: error.message,
          details: {'cause': error.code, ...error.details},
        );
      }
    }
    return CommandResult(
      ok: error == null,
      command: command,
      results: results,
      data: {'dryRun': dryRun, ...data},
      error: error,
    );
  }
}
