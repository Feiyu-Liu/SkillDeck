import 'dart:async';
import 'dart:math';

import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_coordinator.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import 'command_approval.dart';
import 'command_cancellation.dart';
import 'write_command_handlers.dart';

/// Owns destructive intent for the App session, independently of connections.
final class CommandApprovalRegistry {
  CommandApprovalRegistry({
    required CommandApprovalPresenter presenter,
    required SkillsWorkspaceRepository Function() repository,
    this.activity,
    DateTime Function()? clock,
    Timer Function(Duration, void Function())? timer,
    String Function()? nextId,
  }) : _presenter = presenter,
       _repository = repository,
       _clock = clock ?? DateTime.now,
       _timer = timer ?? Timer.new,
       _nextId = nextId ?? _randomId;

  final CommandApprovalPresenter _presenter;
  final SkillsWorkspaceRepository Function() _repository;
  final WriteActivityReporter? activity;
  final DateTime Function() _clock;
  final Timer Function(Duration, void Function()) _timer;
  final String Function() _nextId;
  final _entries = <String, _Approval>{};
  _Approval? _active;
  bool _closed = false;

  static String _randomId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz234567';
    final random = Random.secure();
    return 'ap_${List.generate(8, (_) => alphabet[random.nextInt(32)]).join()}';
  }

  Future<CommandResult> request({
    required String command,
    required CommandApprovalSubject subject,
    required List<WriteActivityItem> items,
    required Duration timeout,
    bool keepGoing = false,
    List<Map<String, Object?>> preResolved = const [],
    List<Map<String, Object?>> itemDetails = const [],
  }) {
    if (_closed) {
      return Future.value(
        CommandResult.failure(
          command,
          'workspaceUnavailable',
          'The Workspace is unavailable.',
        ),
      );
    }
    // Reserve through execution: a stale operation needs this same sheet again
    // and must never replace another request's review.
    if (_active case final active?) {
      return Future.value(
        CommandResult(
          ok: false,
          command: command,
          error: CommandError(
            code: 'approvalAlreadyPending',
            message: 'An approval is already awaiting completion in SkillDeck.',
            details: {'id': active.request.id},
          ),
        ),
      );
    }
    var id = _nextId();
    while (_entries.containsKey(id)) {
      id = _nextId();
    }
    final entry = _Approval(
      command,
      CommandApprovalRequest(
        id: id,
        subject: subject,
        expiresAt: _clock().toUtc().add(const Duration(minutes: 10)),
      ),
      List.unmodifiable(items),
      keepGoing: keepGoing,
      preResolved: preResolved,
      itemDetails: itemDetails,
    );
    _entries[id] = entry;
    _active = entry;
    entry.expiry = _timer(const Duration(minutes: 10), () {
      if (entry.state == 'pending') _withdraw(entry, 'approvalExpired');
    });
    // EOF/SIGINT belongs to the connection, not the eventual transaction.
    unawaited(entry.cancellation.run(() => _review(entry)));
    return wait(id, timeout: timeout, command: command);
  }

  CommandResult status(String id, {String command = 'approvals status'}) {
    final entry = _entries[id];
    if (entry == null) return _notFound(command);
    final result = entry.result;
    return CommandResult(
      ok: result?.ok ?? true,
      command: command,
      results: result?.results ?? const [],
      error: result?.error,
      data: {
        'id': id,
        'expiresAt': entry.request.expiresAt.toIso8601String(),
        'state': entry.state,
        if (result != null) 'result': result.toJson(),
      },
    );
  }

  Future<CommandResult> wait(
    String id, {
    required Duration timeout,
    String command = 'approvals wait',
  }) async {
    final entry = _entries[id];
    if (entry == null) return _notFound(command);
    if (entry.result == null) {
      final elapsed = Completer<void>();
      final timer = _timer(timeout, () => elapsed.complete());
      try {
        await Future.any<void>([
          entry.done.future.then((_) {}),
          elapsed.future,
        ]);
      } finally {
        timer.cancel();
      }
    }
    if (entry.result case final result?) {
      return command == entry.command ? result : status(id, command: command);
    }
    return CommandResult(
      ok: false,
      command: command,
      error: CommandError(
        code: 'approvalPending',
        message:
            'Waiting for approval in SkillDeck… (approval $id; '
            'resume with: skilldeck approvals wait $id)',
        details: {
          'id': id,
          'expiresAt': entry.request.expiresAt.toIso8601String(),
        },
      ),
    );
  }

  Future<CommandResult> cancel(String id) async {
    final entry = _entries[id];
    if (entry == null) return _notFound('approvals cancel');
    if (entry.state == 'pending') {
      _withdraw(entry, 'approvalCancelled');
    } else if (entry.state == 'executing') {
      // Preserve the actual commit outcome once execution has started.
      await entry.cancellation.cancel();
      await entry.done.future;
    }
    return status(id, command: 'approvals cancel');
  }

  Future<void> close() async {
    _closed = true;
    final active = _active;
    if (active != null) await cancel(active.request.id);
  }

  CommandResult _notFound(String command) => CommandResult.failure(
    command,
    'approvalNotFound',
    'The approval request was not found.',
  );

  void _finish(_Approval entry, CommandResult result) {
    if (entry.result != null) return;
    entry.expiry?.cancel();
    if (entry.request.subject is CommandApprovalReplaceSource &&
        result.results.isEmpty &&
        result.error != null) {
      final finished = entry.resolved.map((r) => r['id']).toSet();
      result = CommandResult(
        ok: false,
        command: entry.command,
        error: result.error,
        data: const {'dryRun': false},
        results: [
          ...entry.resolved,
          for (final item in entry.items.where((i) => !finished.contains(i.id)))
            {
              ...?entry.itemDetails[item.id],
              'id': item.id,
              'slotKey': item.slotKey,
              'outcome': 'skipped',
            },
        ],
      );
    }
    entry.result = result;
    entry.state = 'terminal';
    if (identical(_active, entry)) _active = null;
    entry.done.complete(result);
  }

  void _withdraw(_Approval entry, String code) {
    _finish(
      entry,
      CommandResult.failure(entry.command, code, switch (code) {
        'approvalExpired' => 'The approval request expired.',
        _ => 'The approval request was cancelled.',
      }),
    );
    _presenter.withdraw(entry.request.id);
  }

  Future<void> _review(_Approval entry) async {
    try {
      while (entry.result == null) {
        if (!_clock().isBefore(entry.request.expiresAt)) {
          _withdraw(entry, 'approvalExpired');
          return;
        }
        entry.state = 'pending';
        final decision = await _presenter.present(entry.request);
        if (entry.result != null) return;
        if (!_clock().isBefore(entry.request.expiresAt)) {
          _withdraw(entry, 'approvalExpired');
          return;
        }
        if (decision is! CommandApprovalApproved) {
          _finish(
            entry,
            CommandResult.failure(
              entry.command,
              decision is CommandApprovalDenied
                  ? 'approvalDenied'
                  : 'approvalCancelled',
              decision is CommandApprovalDenied
                  ? 'The approval request was denied.'
                  : 'The approval request was cancelled.',
            ),
          );
          return;
        }
        entry.state = 'executing';
        final result = await AppDiagnostics.withoutDetails(
          () => AgentRootOwnershipCoordinator.withoutInteractiveRepair(
            () => _execute(entry, decision.reviewedRevision),
          ),
        );
        if (result.error?.code == 'staleSnapshot') {
          if (entry.cancellation.isCancelled) {
            _finish(
              entry,
              CommandResult.failure(
                entry.command,
                'operationCancelled',
                'The command was cancelled.',
              ),
            );
            return;
          }
          entry.request = entry.request.asStale();
          continue;
        }
        _finish(entry, result);
      }
    } on Object {
      _finish(
        entry,
        CommandResult.failure(
          entry.command,
          'operationFailed',
          'The operation could not be completed.',
        ),
      );
      _presenter.withdraw(entry.request.id);
    }
  }

  Future<CommandResult> _execute(_Approval entry, int revision) async {
    final subject = entry.request.subject;
    if (subject is CommandApprovalReplaceSource) {
      return _executeReplacement(entry, subject, revision);
    }
    final report = subject is CommandApprovalRemoveSkills
        ? activity?.begin(
            command: 'remove',
            favorite: true,
            agentIds: const [],
            items: entry.items,
            cancel: () => unawaited(entry.cancellation.cancel()),
          )
        : null;
    String outcome = 'failed';
    String? operationId;
    CommandError? error;
    try {
      for (final item in entry.items) {
        report?.start(item.id);
      }
      final repo = _repository();
      final WorkspaceTask<Object?> task = switch (subject) {
        CommandApprovalRemoveSkills(:final skillIds) => repo.remove(
          skillIds: skillIds.map(WorkspaceSkillId.new).toSet(),
          expectedRevision: revision,
        ),
        CommandApprovalDeleteTag(:final tagId) => repo.deletePersonalTag(tagId),
        CommandApprovalReplaceSource() => throw StateError('Unreachable'),
      };
      operationId = task.current.operationId;
      final completion = await entry.cancellation.complete(task);
      switch (completion) {
        case WorkspaceCompleted():
          outcome = 'succeeded';
        case WorkspaceCommittedPending(operationId: final committedId):
          outcome = 'committedFinalizationPending';
          operationId = committedId;
        case WorkspaceFailed(:final failure):
          final code = switch (failure.code) {
            WorkspaceErrorCode.personalTagNotFound => 'tagNotFound',
            WorkspaceErrorCode.agentRootOwnership =>
              'agentRootOwnershipRepairRequired',
            _ => failure.code.name,
          };
          outcome = code == 'operationCancelled' ? 'cancelled' : 'failed';
          error = CommandError(
            code: code,
            message: 'The operation could not be completed.',
          );
      }
    } on Object {
      error = CommandError(
        code: 'operationFailed',
        message: 'The operation could not be completed.',
      );
    } finally {
      for (final item in entry.items) {
        report?.finish(item.id, outcome, errorCode: error?.code);
      }
      report?.end();
    }
    return CommandResult(
      ok: error == null,
      command: entry.command,
      results: [
        for (final item in entry.items)
          {
            'id': item.id,
            'slotKey': item.slotKey,
            'outcome': outcome,
            'operationId': ?operationId,
            if (error != null) 'error': error.toJson(),
          },
      ],
      data: {'dryRun': false, 'outcome': outcome},
      error: error,
    );
  }

  Future<CommandResult> _executeReplacement(
    _Approval entry,
    CommandApprovalReplaceSource subject,
    int revision,
  ) async {
    final remainingIds = subject.items.map((i) => i.skillId).toSet();
    final report = activity?.begin(
      command: entry.command,
      favorite: true,
      agentIds: const [],
      items: entry.items.where((i) => remainingIds.contains(i.id)).toList(),
      cancel: () => unawaited(entry.cancellation.cancel()),
    );
    var stopped = false;
    try {
      for (final (index, item) in subject.items.indexed) {
        final row = <String, Object?>{
          ...?entry.itemDetails[item.skillId],
          'id': item.skillId,
          'slotKey': entry.items
              .firstWhere((i) => i.id == item.skillId)
              .slotKey,
        }..remove('outcome');
        if (stopped || entry.cancellation.isCancelled) {
          row['outcome'] = entry.cancellation.isCancelled
              ? 'cancelled'
              : 'skipped';
          if (entry.cancellation.isCancelled) {
            row['error'] = CommandError(
              code: 'operationCancelled',
              message: 'The command was cancelled.',
            ).toJson();
          }
        } else {
          report?.start(item.skillId);
          try {
            final task = _repository().replaceSource(
              skillId: WorkspaceSkillId(item.skillId),
              source: item.source,
              expectedRevision: revision,
            );
            row['operationId'] = task.current.operationId;
            final completion = await entry.cancellation.complete(
              task,
              observe: (p) => row['operationId'] = p.operationId,
            );
            switch (completion) {
              case WorkspaceCompleted(:final value):
                row['outcome'] = 'succeeded';
                revision = value.snapshot.revision;
              case WorkspaceCommittedPending(
                :final committedRevision,
                :final operationId,
              ):
                row['outcome'] = 'committedFinalizationPending';
                row['operationId'] = operationId;
                revision = committedRevision;
              case WorkspaceFailed(:final failure):
                if (failure.code == WorkspaceErrorCode.staleSnapshot) {
                  entry.request = CommandApprovalRequest(
                    id: entry.request.id,
                    expiresAt: entry.request.expiresAt,
                    subject: CommandApprovalReplaceSource(
                      subject.items.sublist(index),
                    ),
                  ).asStale();
                  return CommandResult.failure(
                    entry.command,
                    'staleSnapshot',
                    'Review the remaining Skills again in SkillDeck.',
                  );
                }
                final screen = switch (failure.code) {
                  WorkspaceErrorCode.agentRootOwnership => 'settings',
                  WorkspaceErrorCode.dirtyDraftResolutionRequired =>
                    'skillDetail',
                  WorkspaceErrorCode.updateCandidateResolutionRequired =>
                    'updates',
                  _ => null,
                };
                final code = switch (failure.code) {
                  WorkspaceErrorCode.agentRootOwnership =>
                    'agentRootOwnershipRepairRequired',
                  WorkspaceErrorCode.dirtyDraftResolutionRequired ||
                  WorkspaceErrorCode.updateCandidateResolutionRequired =>
                    'actionRequired',
                  _ => failure.code.name,
                };
                row['outcome'] = code == 'operationCancelled'
                    ? 'cancelled'
                    : 'failed';
                row['error'] = CommandError(
                  code: code,
                  message: switch (screen) {
                    'settings' => 'Open SkillDeck Settings to review Agent Root Ownership Repair.',
                    'skillDetail' =>
                      'Open SkillDeck Skill Detail to resolve this item.',
                    'updates' => 'Open SkillDeck Updates to resolve this item.',
                    _ => 'The operation could not be completed.',
                  },
                  details: {
                    'screen': ?screen,
                    if (code == 'actionRequired') 'cause': failure.code.name,
                  },
                ).toJson();
            }
          } on Object {
            row['outcome'] = 'failed';
            row['error'] = CommandError(
              code: 'operationFailed',
              message: 'The operation could not be completed.',
            ).toJson();
          }
          if (row['error'] != null && !entry.keepGoing) stopped = true;
        }
        entry.resolved.add(row);
        report?.finish(
          item.skillId,
          row['outcome'] == 'skipped'
              ? 'notAttempted'
              : row['outcome']! as String,
          errorCode: (row['error'] as Map?)?['code'] as String?,
        );
      }
    } finally {
      report?.end();
    }
    return sourceReplacementResult(
      entry.resolved,
      command: entry.command,
      dryRun: false,
    );
  }
}

final class _Approval {
  _Approval(
    this.command,
    this.request,
    this.items, {
    this.keepGoing = false,
    List<Map<String, Object?>> preResolved = const [],
    List<Map<String, Object?>> itemDetails = const [],
  }) : resolved = [for (final row in preResolved) Map.of(row)],
       itemDetails = {
         for (final row in itemDetails) row['id']! as String: Map.of(row),
       };
  final bool keepGoing;
  final List<Map<String, Object?>> resolved;
  final Map<String, Map<String, Object?>> itemDetails;
  final String command;
  CommandApprovalRequest request;
  final List<WriteActivityItem> items;
  final cancellation = CommandCancellation();
  final done = Completer<CommandResult>();
  String state = 'pending';
  Timer? expiry;
  CommandResult? result;
}

/// Aggregates replacement previews and approved execution using stable codes.
CommandResult sourceReplacementResult(
  List<Map<String, Object?>> rows, {
  required String command,
  required bool dryRun,
  Map<String, Object?> data = const {},
}) {
  final first = rows.where((r) => r['error'] != null).firstOrNull;
  CommandError? error = first == null
      ? null
      : CommandError.fromJson(first['error']! as Map<String, Object?>);
  if (error != null &&
      rows.any(
        (r) =>
            r['outcome'] == 'succeeded' ||
            r['outcome'] == 'committedFinalizationPending',
      )) {
    error = CommandError(
      code: 'partialBatch',
      message: 'Changes committed before a failure.',
      details: {'cause': error.code, ...error.details},
    );
  }
  return CommandResult(
    ok: error == null,
    command: command,
    results: rows,
    error: error,
    data: {'dryRun': dryRun, ...data},
  );
}
