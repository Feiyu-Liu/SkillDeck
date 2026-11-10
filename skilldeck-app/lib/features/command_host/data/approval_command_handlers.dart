import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';

import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';

import 'command_approval.dart';
import 'command_cancellation.dart';
import 'skill_json.dart';
import 'skills_lock_reader.dart';
import 'source_command_support.dart';
import 'command_approval_registry.dart';
import 'command_host_dispatcher.dart';
import 'skill_selector_resolver.dart';

Map<String, CommandHostHandler> approvalCommandHandlers({
  required SkillsLockReader? Function() skillsLock,
  required CommandApprovalRegistry registry,
  required SkillsWorkspaceRepository Function() repository,
  required SkillsWorkspaceSnapshot? Function() snapshot,
  required SkillUpdateStatus Function() updates,
  required Future<List<WorkspaceAgentInfo>> Function() agents,
}) => {
  'source relink': (request) => _relinkSource(
    request,
    registry,
    repository,
    snapshot,
    updates,
    skillsLock,
  ),
  'source replace': (request) =>
      _replaceSource(request, registry, repository, snapshot, updates),
  for (final command in [
    'remove',
    'tag delete',
    'approvals wait',
    'approvals status',
    'approvals cancel',
  ])
    command: (request) async {
      final args = request.arguments;
      final control = command.startsWith('approvals ');
      late final int seconds;
      late final bool dryRun;
      SkillSelection? selection;
      String? tagName;
      String? id;
      try {
        final allowed = control
            ? {'id', if (command == 'approvals wait') 'approvalTimeout'}
            : {
                'dryRun',
                'wait',
                'approvalTimeout',
                if (command == 'remove') 'selection' else 'tag',
              };
        if (args.keys.any((k) => !allowed.contains(k))) {
          throw const FormatException();
        }
        seconds = args['approvalTimeout'] as int? ?? 90;
        if (seconds < 0 || seconds > 600 || (args['wait'] as int? ?? 30) < 0) {
          throw const FormatException();
        }
        dryRun = args['dryRun'] as bool? ?? false;
        if (control) {
          id = args['id'] as String;
          if (id.isEmpty) throw const FormatException();
        } else if (command == 'remove') {
          selection = SkillSelection.fromJson(
            args['selection'] as Map<String, Object?>,
          );
        } else {
          tagName = (args['tag'] as String).trim();
          if (tagName.isEmpty) throw const FormatException();
        }
      } on Object {
        throw const SkillSelectionFailure('usage');
      }
      final timeout = Duration(seconds: seconds);
      if (control) {
        return switch (command) {
          'approvals wait' => registry.wait(id!, timeout: timeout),
          'approvals cancel' => registry.cancel(id!),
          _ => registry.status(id!),
        };
      }
      final current = snapshot();
      if (current == null ||
          current.integrity == WorkspaceIntegrityStatus.corrupt) {
        throw const SkillSelectionFailure('workspaceUnavailable');
      }
      if (command == 'tag delete') {
        final tag = current.personalTags
            .where((t) => t.name.toLowerCase() == tagName!.toLowerCase())
            .firstOrNull;
        if (tag == null) throw const SkillSelectionFailure('tagNotFound');
        if (dryRun) {
          return CommandResult(
            ok: true,
            command: command,
            data: {
              'dryRun': true,
              'tag': tag.name,
              'assignedSkillCount': current.skills
                  .where((s) => s.personalTagIds.contains(tag.id))
                  .length,
            },
          );
        }
        return registry.request(
          command: command,
          subject: CommandApprovalDeleteTag(tagId: tag.id),
          items: const [],
          timeout: timeout,
        );
      }
      final selected = resolveSkillSelection(
        current,
        selection!,
        availableUpdateIds: updates().availableSkillIds,
      );
      if (dryRun) {
        final catalog = selected.isEmpty
            ? <WorkspaceAgentInfo>[]
            : await agents();
        return CommandResult(
          ok: true,
          command: command,
          results: [
            for (final skill in selected)
              {
                'id': skill.id.value,
                'slotKey': skill.slotKey,
                'outcome': 'wouldSucceed',
                'activatedAgents': [
                  for (final id
                      in skill.activations.expand((a) => a.agentIds).toSet())
                    catalog.where((a) => a.id == id).firstOrNull?.displayName ??
                        id,
                ],
                'unpublishedDraft': skill.draft != null,
              },
          ],
          data: const {'dryRun': true},
        );
      }
      if (selected.isEmpty) return CommandResult(ok: true, command: command);
      return registry.request(
        command: command,
        subject: CommandApprovalRemoveSkills(
          selected.map((s) => s.id.value).toList(),
        ),
        items: [
          for (final skill in selected)
            (id: skill.id.value, slotKey: skill.slotKey),
        ],
        timeout: timeout,
      );
    },
};

Future<CommandResult> _replaceSource(
  CommandRequest request,
  CommandApprovalRegistry registry,
  SkillsWorkspaceRepository Function() repository,
  SkillsWorkspaceSnapshot? Function() snapshot,
  SkillUpdateStatus Function() updates,
) async {
  final args = request.arguments;
  late final SkillSelection selection;
  late final bool dryRun;
  late final bool keepGoing;
  late final int seconds;
  late final String? ref;
  late final String? name;
  try {
    const allowed = {
      'selection',
      'to',
      'ref',
      'skill',
      'dryRun',
      'keepGoing',
      'wait',
      'approvalTimeout',
    };
    if (args.keys.any((k) => !allowed.contains(k))) {
      throw const FormatException();
    }
    selection = SkillSelection.fromJson(
      args['selection'] as Map<String, Object?>,
    );
    dryRun = args['dryRun'] as bool? ?? false;
    keepGoing = args['keepGoing'] as bool? ?? false;
    seconds = args['approvalTimeout'] as int? ?? 90;
    ref = args['ref'] as String?;
    name = args['skill'] as String?;
    if (seconds < 0 ||
        seconds > 600 ||
        (args['wait'] as int? ?? 30) < 0 ||
        name != null && name.trim().isEmpty) {
      throw const FormatException();
    }
  } on Object {
    throw const SkillSelectionFailure('usage');
  }
  final current = snapshot();
  if (current == null ||
      current.integrity == WorkspaceIntegrityStatus.corrupt) {
    throw const SkillSelectionFailure('workspaceUnavailable');
  }
  final selected = resolveSkillSelection(
    current,
    selection,
    availableUpdateIds: updates().availableSkillIds,
  );
  if (selected.isEmpty) {
    return CommandResult(ok: true, command: request.command);
  }
  if (name != null && selected.length != 1) {
    throw const SkillSelectionFailure('usage');
  }
  final parsed = parseSourceArgument(args['to'], ref: ref);
  final inspection = await inspectSourceForCommand(
    repository(),
    parsed.source,
    parsed.detection,
    CommandCancellation.current ?? CommandCancellation(),
  );
  final items = <CommandApprovalReplaceSourceItem>[];
  final planned = <Map<String, Object?>>[];
  final preResolved = <Map<String, Object?>>[];
  final rows = <Map<String, Object?>>[];
  var stopped = false;
  for (final skill in selected) {
    final source = inspection.source;
    final row = <String, Object?>{
      'id': skill.id.value,
      'slotKey': skill.slotKey,
      'from': {
        'kind': skill.source.kind.name,
        'locator': stripLocatorUserinfo(skill.source.locator),
      },
      'to': _sourceJson(source),
    };
    rows.add(row);
    if (stopped) {
      row['outcome'] = 'skipped';
      preResolved.add(row);
      continue;
    }
    // Slot Key first; a lone Skill may also take the Source's only candidate
    // (a rename), or the one named with --skill.
    final candidates = inspection.candidates;
    final bySlotKey = candidates
        .where((c) => c.slotKey == skill.slotKey)
        .toList();
    final wanted = name?.toLowerCase();
    final matches = wanted != null
        ? candidates
              .where(
                (c) =>
                    c.declaredName.toLowerCase() == wanted ||
                    c.slotKey.toLowerCase() == wanted,
              )
              .toList()
        : bySlotKey.isNotEmpty || selected.length > 1
        ? bySlotKey
        : candidates;
    if (matches.length != 1) {
      final code = matches.isEmpty
          ? 'replacementCandidateNotFound'
          : 'replacementCandidateAmbiguous';
      row.addAll({
        'outcome': 'failed',
        'error': CommandError(
          code: code,
          message: matches.isEmpty
              ? 'No replacement candidate matches this Skill.'
              : 'Several replacement candidates match this Skill.',
          details: {
            if (matches.length > 1)
              'candidates': [
                for (final c in matches.take(200))
                  {'name': c.declaredName, 'slotKey': c.slotKey},
              ],
          },
        ).toJson(),
      });
      preResolved.add(row);
      stopped = !keepGoing;
      continue;
    }
    final item = _planItem(skill, source, matches.single, row);
    if (item == null) {
      preResolved.add(row);
    } else {
      planned.add(row);
      items.add(item);
    }
  }
  if (dryRun || stopped || items.isEmpty) {
    return sourceReplacementResult(
      rows,
      command: request.command,
      dryRun: dryRun,
      data: {
        'source': {
          'kind': inspection.source.kind.name,
          'locator': stripLocatorUserinfo(inspection.source.locator),
        },
      },
    );
  }
  return registry.request(
    command: request.command,
    subject: CommandApprovalReplaceSource(items),
    items: [
      for (final row in planned)
        (id: row['id']! as String, slotKey: row['slotKey']! as String),
    ],
    itemDetails: planned,
    preResolved: preResolved,
    timeout: Duration(seconds: seconds),
    keepGoing: keepGoing,
  );
}

Map<String, Object?> _sourceJson(SkillSourceInput source) => {
  'kind': source.kind.name,
  'locator': stripLocatorUserinfo(source.locator),
  'ref': ?source.ref,
  'repositorySubpath': source.repositorySubpath,
  'skillPath': source.skillPath,
};

Future<CommandResult> _relinkSource(
  CommandRequest request,
  CommandApprovalRegistry registry,
  SkillsWorkspaceRepository Function() repository,
  SkillsWorkspaceSnapshot? Function() snapshot,
  SkillUpdateStatus Function() updates,
  SkillsLockReader? Function() skillsLock,
) async {
  final args = request.arguments;
  late final SkillSelection? selection;
  late final bool dryRun;
  late final bool keepGoing;
  late final int seconds;
  try {
    const allowed = {
      'selection',
      'fromSkillsLock',
      'dryRun',
      'keepGoing',
      'wait',
      'approvalTimeout',
    };
    if (args.keys.any((k) => !allowed.contains(k)) ||
        args['fromSkillsLock'] != true) {
      throw const FormatException();
    }
    selection = args.containsKey('selection')
        ? SkillSelection.fromJson(args['selection'] as Map<String, Object?>)
        : null;
    dryRun = args['dryRun'] as bool? ?? false;
    keepGoing = args['keepGoing'] as bool? ?? true;
    seconds = args['approvalTimeout'] as int? ?? 90;
    if (seconds < 0 || seconds > 600 || (args['wait'] as int? ?? 30) < 0) {
      throw const FormatException();
    }
  } on Object {
    throw const SkillSelectionFailure('usage');
  }
  final current = snapshot();
  if (current == null ||
      current.integrity == WorkspaceIntegrityStatus.corrupt) {
    throw const SkillSelectionFailure('workspaceUnavailable');
  }
  final selected = selection == null
      ? current.skills
            .where((s) => s.source.kind == WorkspaceSourceKind.adoptedSnapshot)
            .toList()
      : resolveSkillSelection(
          current,
          selection,
          availableUpdateIds: updates().availableSkillIds,
        );
  final refs = {...?selection?.refs};
  bool named(WorkspaceSkill skill) =>
      refs.contains(skill.id.value) || refs.contains(skill.slotKey);
  final reader = skillsLock();
  if (reader == null) throw const SkillSelectionFailure('lockUnavailable');
  final lock = await reader.read();

  // First-seen repository order, with each repository's rows kept together.
  // Rows with no usable Source retain their own position in that order.
  final groups = <List<WorkspaceSkill>>[];
  final byLocator = <String, List<WorkspaceSkill>>{};
  for (final skill in selected) {
    final entry = lock[skill.slotKey];
    if (skill.source.kind != WorkspaceSourceKind.adoptedSnapshot ||
        entry == null ||
        entry.sourceType != 'github') {
      groups.add([skill]);
    } else {
      final locator = stripLocatorUserinfo(entry.sourceUrl);
      final group = byLocator.putIfAbsent(locator, () {
        final group = <WorkspaceSkill>[];
        groups.add(group);
        return group;
      });
      group.add(skill);
    }
  }
  final items = <CommandApprovalReplaceSourceItem>[];
  final planned = <Map<String, Object?>>[];
  final preResolved = <Map<String, Object?>>[];
  final rows = <Map<String, Object?>>[];
  final sources = <String>[];
  var stopped = false;
  for (final group in groups) {
    WorkspaceSourceInspection? inspection;
    String? inspectionCode;
    final firstEntry = lock[group.first.slotKey];
    if (!stopped &&
        group.first.source.kind == WorkspaceSourceKind.adoptedSnapshot &&
        firstEntry != null &&
        firstEntry.sourceType == 'github') {
      try {
        final parsed = parseSourceArgument(
          stripLocatorUserinfo(firstEntry.sourceUrl),
        );
        sources.add(stripLocatorUserinfo(parsed.source.locator));
        inspection = await inspectSourceForCommand(
          repository(),
          parsed.source,
          parsed.detection,
          CommandCancellation.current ?? CommandCancellation(),
        );
      } on SkillSelectionFailure catch (failure) {
        if (failure.code == 'operationCancelled') rethrow;
        inspectionCode = failure.code;
      }
    }
    for (final skill in group) {
      final entry = lock[skill.slotKey];
      final row = <String, Object?>{
        'id': skill.id.value,
        'slotKey': skill.slotKey,
        'from': {
          'kind': skill.source.kind.name,
          'locator': stripLocatorUserinfo(skill.source.locator),
        },
        if (inspection != null) 'to': _sourceJson(inspection.source),
        if (entry != null)
          'lock': {
            'source': stripLocatorUserinfo(entry.sourceUrl),
            'skillPath': entry.skillPath,
          },
      };
      rows.add(row);
      String? code;
      if (skill.source.kind != WorkspaceSourceKind.adoptedSnapshot) {
        row['outcome'] = 'skipped';
        row['reason'] = CommandError(
          code: 'notAdopted',
          message: 'This Skill does not have an Adopted Snapshot Source.',
        ).toJson();
        preResolved.add(row);
        continue;
      }
      if (stopped) {
        row['outcome'] = 'skipped';
        preResolved.add(row);
        continue;
      }
      if (entry == null) {
        code = 'lockEntryMissing';
      } else if (entry.sourceType != 'github') {
        code = 'lockSourceUnsupported';
      } else if (inspectionCode != null) {
        code = inspectionCode;
      } else {
        final wanted = _lockSkillDirectory(entry.skillPath);
        final matches = inspection!.candidates
            .where((c) => c.skillPath == wanted)
            .toList();
        if (matches.length != 1) {
          code = matches.isEmpty
              ? 'replacementCandidateNotFound'
              : 'replacementCandidateAmbiguous';
        } else {
          final item = _planItem(skill, inspection.source, matches.single, row);
          if (item == null) {
            preResolved.add(row);
          } else {
            planned.add(row);
            items.add(item);
          }
          continue;
        }
      }
      final reason = CommandError(
        code: code,
        message: 'This Skill could not be reconnected.',
        details: {
          if (code == 'replacementCandidateNotFound')
            'lockSkillPath': entry!.skillPath,
        },
      ).toJson();
      preResolved.add(row);
      // A bulk relink reaches every adopted Skill, and some never had a
      // usable lock hint; those are skipped, not failures. A Skill the user
      // named still fails, and so does anything transient, like the network.
      if (!named(skill) && _expectedRelinkSkips.contains(code)) {
        row['outcome'] = 'skipped';
        row['reason'] = reason;
        continue;
      }
      row['outcome'] = 'failed';
      row['error'] = reason;
      stopped = !keepGoing;
    }
  }
  if (dryRun || stopped || items.isEmpty) {
    return sourceReplacementResult(
      rows,
      command: request.command,
      dryRun: dryRun,
      data: {'sources': sources},
    );
  }
  final result = await registry.request(
    command: request.command,
    subject: CommandApprovalReplaceSource(items),
    items: [
      for (final row in planned)
        (id: row['id']! as String, slotKey: row['slotKey']! as String),
    ],
    itemDetails: planned,
    preResolved: preResolved,
    timeout: Duration(seconds: seconds),
    keepGoing: keepGoing,
  );
  return CommandResult(
    ok: result.ok,
    command: result.command,
    results: result.results,
    error: result.error,
    data: {...result.data, 'sources': sources},
  );
}

/// Why a lock hint cannot reconnect a Skill, known before any approval: no
/// hint, an unsupported host, a repository without that Skill directory, or
/// one whose duplicate Skill names the Workspace cannot inspect.
const _expectedRelinkSkips = {
  'lockEntryMissing',
  'lockSourceUnsupported',
  'replacementCandidateNotFound',
  'replacementCandidateAmbiguous',
  'duplicateSkillSlot',
};

/// The lock names the `SKILL.md` file; inspection names its directory, with
/// a Skill at the repository root reported as the empty path.
String _lockSkillDirectory(String lockSkillPath) {
  final directory = p.posix.dirname(p.posix.normalize(lockSkillPath));
  return directory == '.' ? '' : directory;
}

/// Shared identity check and candidate disclosure for both replacement flows.
CommandApprovalReplaceSourceItem? _planItem(
  WorkspaceSkill skill,
  SkillSourceInput source,
  WorkspaceSourceCandidate candidate,
  Map<String, Object?> row,
) {
  final narrowed = SkillSourceInput(
    kind: source.kind,
    locator: source.locator,
    ref: source.ref,
    repositorySubpath: source.repositorySubpath,
    skillPath: candidate.skillPath,
  );
  row['to'] = _sourceJson(narrowed);
  row['candidate'] = {
    'declaredName': candidate.declaredName,
    'contentHash': candidate.contentHash,
    'fileCount': candidate.fileCount,
    'byteSize': candidate.byteSize,
  };
  final old = skill.source;
  final unchanged =
      old.kind == narrowed.kind &&
      old.locator == narrowed.locator &&
      old.ref == narrowed.ref &&
      old.repositorySubpath == narrowed.repositorySubpath &&
      old.skillPath == narrowed.skillPath;
  row['outcome'] = unchanged ? 'unchanged' : 'wouldSucceed';
  if (unchanged) return null;
  return CommandApprovalReplaceSourceItem(
    skillId: skill.id.value,
    source: narrowed,
    candidateDeclaredName: candidate.declaredName,
  );
}
