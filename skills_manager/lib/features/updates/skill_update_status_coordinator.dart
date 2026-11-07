import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/data/update_sweep_store.dart';
import 'package:skills_manager/features/updates/models/skill_update_state.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

/// How long a completed full sweep suppresses the next automatic startup sweep.
const skillUpdateSweepTtl = Duration(hours: 24);

/// Concurrent check requests allowed while a manual request is outstanding.
///
/// A request covers every queued Skill sharing one Git fetch and spawns at most
/// one system `git` subprocess at a time, so this is a subprocess bound, not
/// just a socket bound.
const skillUpdateManualConcurrency = 6;

/// Concurrent check requests allowed for the background startup sweep.
///
/// Deliberately more conservative than the manual bound so first-frame
/// rendering and initial materialization win the contention.
const skillUpdateStartupConcurrency = 2;

final skillUpdateSweepStoreProvider = Provider<UpdateSweepStore>(
  (ref) =>
      RepositoryUpdateSweepStore(ref.watch(skillsUpdateCheckStoreProvider)),
);

/// The single App-session authority for Skill update reports.
///
/// Both the Updates page and the Skill detail page read this state, and nothing
/// else calls `checkUpdates`. Concentrating the calls here is required, not
/// stylistic: the previous ViewModel-local guards could not observe each other,
/// so a click during a background sweep issued a second in-flight request for a
/// Skill already being checked and ran both concurrency budgets at once.
final skillUpdateStatusProvider =
    NotifierProvider<SkillUpdateStatusCoordinator, SkillUpdateStatus>(
      SkillUpdateStatusCoordinator.new,
    );

final class SkillUpdateStatus {
  const SkillUpdateStatus({
    this.states = const {},
    this.sweeping = false,
    this.sweepCompleted = 0,
    this.sweepTotal = 0,
    this.warnings = const [],
    this.sweptThisSession = false,
  });

  /// Per-Skill state. A missing key means [SkillUpdateNotChecked].
  final Map<WorkspaceSkillId, SkillUpdateState> states;

  /// Whether a full sweep is currently running.
  final bool sweeping;

  /// Progress of the running or last sweep, computed App-side.
  ///
  /// With N independent per-Skill operations there is no single
  /// `completed/total` stream to forward, so the page counts finished Skills
  /// over enqueued Skills instead of preserving handler granularity.
  final int sweepCompleted;
  final int sweepTotal;

  /// Warnings aggregated across the individual checks of the current sweep.
  final List<WorkspaceWarning> warnings;

  /// Whether a full sweep has completed since the App started.
  final bool sweptThisSession;

  SkillUpdateState stateOf(WorkspaceSkillId skillId) =>
      states[skillId] ?? const SkillUpdateNotChecked();

  bool isChecking(WorkspaceSkillId skillId) =>
      stateOf(skillId) is SkillUpdateChecking;

  double? get sweepFraction =>
      sweepTotal == 0 ? null : sweepCompleted / sweepTotal;

  Set<WorkspaceSkillId> get availableSkillIds => {
    for (final entry in states.entries)
      if (entry.value.updateAvailable) entry.key,
  };

  SkillUpdateStatus copyWith({
    Map<WorkspaceSkillId, SkillUpdateState>? states,
    bool? sweeping,
    int? sweepCompleted,
    int? sweepTotal,
    List<WorkspaceWarning>? warnings,
    bool? sweptThisSession,
  }) => SkillUpdateStatus(
    states: states ?? this.states,
    sweeping: sweeping ?? this.sweeping,
    sweepCompleted: sweepCompleted ?? this.sweepCompleted,
    sweepTotal: sweepTotal ?? this.sweepTotal,
    warnings: warnings ?? this.warnings,
    sweptThisSession: sweptThisSession ?? this.sweptThisSession,
  );
}

final class SkillUpdateStatusCoordinator extends Notifier<SkillUpdateStatus> {
  final Map<WorkspaceSkillId, SkillUpdateState> _states = {};
  final Map<WorkspaceSkillId, SkillUpdateBasis> _bases = {};

  /// Queued but not yet started, in service order. Manual requests go to the
  /// front so a single-Skill check never waits behind a long background queue.
  /// This is a deque, not a priority system.
  final ListQueue<WorkspaceSkillId> _order = ListQueue();
  final Map<WorkspaceSkillId, _PendingCheck> _pending = {};
  final Map<WorkspaceSkillId, _PendingCheck> _running = {};

  /// In-flight requests. The concurrency bound counts these, not Skills.
  final Set<_RunningCheck> _checks = {};
  var _holdPump = false;

  /// Skills whose outstanding request came from an explicit user action. While
  /// this is non-empty the concurrency bound is raised; it returns to the
  /// startup value once every manual request settles.
  final Set<WorkspaceSkillId> _manual = {};

  final List<WorkspaceWarning> _sweepWarnings = [];
  final Set<Object> _sweepWarningKeys = {};

  Completer<void>? _sweep;
  int _sweepCompleted = 0;
  int _sweepTotal = 0;
  var _sweptThisSession = false;
  var _sweepCancelled = false;
  var _built = false;
  var _restored = false;
  Future<void>? _restoreFuture;
  var _disposed = false;

  @override
  SkillUpdateStatus build() {
    ref.listen<AsyncValue<SkillsWorkspaceSnapshot>>(workspaceSnapshotProvider, (
      _,
      next,
    ) {
      final snapshot = next.value;
      if (snapshot != null) _observeSnapshot(snapshot);
    }, fireImmediately: true);
    ref.onDispose(() {
      _disposed = true;
      _order.clear();
      _pending.clear();
      for (final running in _checks.toList()) {
        unawaited(running.cancel());
      }
    });
    // The Snapshot listener fires synchronously during build, before `state`
    // exists, so every publication is composed from fields rather than read
    // back from `state`.
    _built = true;
    _restoreFuture = _restorePersistedState();
    unawaited(_restoreFuture!);
    return _compose();
  }

  Future<void> restorePersistedState() =>
      _restoreFuture ??= _restorePersistedState();

  Future<void> _restorePersistedState() async {
    try {
      final snapshot = await ref.read(workspaceSnapshotProvider.future);
      final cache = await ref
          .read(skillsUpdateCheckStoreProvider)
          .readUpdateCache();
      if (_disposed) return;
      final present = {for (final skill in snapshot.skills) skill.id: skill};
      final staleIds = <WorkspaceSkillId>[];
      for (final record in cache.records) {
        final skill = present[record.skillId];
        if (skill == null ||
            SkillUpdateBasis.of(skill).fingerprint != record.basisFingerprint ||
            record.report.status == WorkspaceUpdateStatus.resolutionRequired) {
          staleIds.add(record.skillId);
          continue;
        }
        _bases[record.skillId] = SkillUpdateBasis.of(skill);
        _states[record.skillId] = SkillUpdateChecked(record.report);
      }
      await Future.wait([
        for (final skillId in staleIds)
          ref.read(skillsUpdateCheckStoreProvider).removeUpdateCache(skillId),
      ]);
      _restored = true;
      _publish();
    } on Object {
      // A corrupt or unavailable cache must never block the Workspace.
      _restored = true;
    }
  }

  SkillUpdateStatus _compose() => SkillUpdateStatus(
    states: Map.unmodifiable(_states),
    sweeping: _sweep != null,
    sweepCompleted: _sweepCompleted,
    sweepTotal: _sweepTotal,
    warnings: List.unmodifiable(_sweepWarnings),
    sweptThisSession: _sweptThisSession,
  );

  int get _concurrencyBound => _manual.isEmpty
      ? skillUpdateStartupConcurrency
      : skillUpdateManualConcurrency;

  /// Runs the startup sweep unless a completed sweep is still within the TTL.
  ///
  /// This never delays rendering, navigation, the installed list, or Skill
  /// content, and its failures stay silent: they update state only. Reusing the
  /// notification path here would raise a failure toast on every offline launch.
  Future<void> startupSweep() async {
    if (_disposed) return;
    await restorePersistedState();
    if (_disposed) return;
    if (_sweptThisSession || _sweep != null) return;
    final lastSweepAt = await ref
        .read(skillUpdateSweepStoreProvider)
        .readLastSweepAt();
    if (_disposed) return;
    if (lastSweepAt != null &&
        DateTime.now().toUtc().difference(lastSweepAt) < skillUpdateSweepTtl) {
      return;
    }
    await sweep();
  }

  /// Sweeps every Skill, or attaches to a sweep already running.
  ///
  /// Opening a page is not a request to refresh, so an entry point that has a
  /// usable in-session result must call this and get a no-op rather than
  /// forcing work.
  Future<void> sweep({bool force = false}) {
    final running = _sweep;
    if (running != null) return running.future;
    if (!force && _sweptThisSession) return Future<void>.value();
    final sweep = Completer<void>();
    // Claimed synchronously so a concurrent request attaches to this sweep
    // instead of starting a second one while the Snapshot is still opening.
    _sweep = sweep;
    unawaited(_runSweep(sweep));
    return sweep.future;
  }

  /// Forces a full refresh. Only a completed forced sweep resets the TTL.
  Future<void> forceSweep() => sweep(force: true);

  /// Requests a check for one Skill and completes with its settled state.
  ///
  /// A request for a Skill already in flight attaches to that check instead of
  /// issuing a second one, and still returns its outcome.
  Future<SkillUpdateState> checkSkill(
    WorkspaceSkillId skillId, {
    bool manual = true,
  }) => _enqueue(skillId, manual: manual, sweepMember: false);

  Future<SkillUpdateState> _enqueue(
    WorkspaceSkillId skillId, {
    required bool manual,
    required bool sweepMember,
  }) {
    if (_disposed) return Future.value(_stateOf(skillId));
    if (manual) _manual.add(skillId);

    final running = _running[skillId];
    if (running != null) {
      running.sweepMember |= sweepMember;
      if (manual) _pump();
      return running.settled.future;
    }

    final pending = _pending[skillId];
    if (pending != null) {
      pending.sweepMember |= sweepMember;
      if (manual && !pending.manual) {
        pending.manual = true;
        _order.remove(skillId);
        _order.addFirst(skillId);
      }
      _pump();
      return pending.settled.future;
    }

    final queued = _PendingCheck(
      skillId: skillId,
      manual: manual,
      sweepMember: sweepMember,
    );
    _pending[skillId] = queued;
    if (manual) {
      _order.addFirst(skillId);
    } else {
      _order.addLast(skillId);
    }
    _pump();
    return queued.settled.future;
  }

  /// Derives the post-Update state of a Skill from the committed Snapshot.
  ///
  /// A successful Update must not be mapped unconditionally to
  /// `checked(current)`. A merge conflict or post-merge validation failure is
  /// also a *successful* mutation: the planner commits an Update Candidate
  /// Session through the same success path. Writing `current` blindly would
  /// hide a required resolution workflow.
  void deriveAfterUpdate(WorkspaceSkillId skillId) {
    if (_disposed) return;
    final skill = ref
        .read(workspaceSnapshotProvider)
        .value
        ?.findSkillById(skillId);
    if (skill == null) {
      _states.remove(skillId);
      _bases.remove(skillId);
      unawaited(
        ref.read(skillsUpdateCheckStoreProvider).removeUpdateCache(skillId),
      );
      _publish();
      return;
    }
    _bases[skillId] = SkillUpdateBasis.of(skill);
    _states[skillId] = SkillUpdateChecked(
      WorkspaceUpdateReport(
        skillId: skillId,
        status: skillRequiresUpdateResolution(skill)
            ? WorkspaceUpdateStatus.resolutionRequired
            : WorkspaceUpdateStatus.current,
        currentContentHash: skill.currentRevision.contentHash,
      ),
    );
    unawaited(
      ref.read(skillsUpdateCheckStoreProvider).removeUpdateCache(skillId),
    );
    _publish();
  }

  /// Cancels every running and queued check. Cancellation exists only for
  /// disposal and explicit user cancellation; forcing a refresh requeues Skills
  /// and never cancels work already in progress.
  Future<void> cancelAll() async {
    if (_sweep != null) _sweepCancelled = true;
    _order.clear();
    for (final pending in _pending.values.toList()) {
      // Clear the manual marker too, or the raised bound would outlive every
      // request that justified it.
      _manual.remove(pending.skillId);
      _states.remove(pending.skillId);
      _settle(pending, const SkillUpdateNotChecked());
    }
    _pending.clear();
    await Future.wait([
      for (final running in _checks.toList()) running.cancel(),
    ]);
  }

  SkillUpdateState _stateOf(WorkspaceSkillId skillId) =>
      _states[skillId] ?? const SkillUpdateNotChecked();

  /// Re-derives every entry from the Snapshot.
  ///
  /// Invalidation is not wired at mutation call sites. Observing the Snapshot
  /// resolves entry invalidation, removal, and Snapshot-derivable resolution
  /// state with one mechanism, and needs no ViewModel to forward
  /// `WorkspaceMutationReceipt.affectedSkillIds` — which every call site
  /// currently discards anyway.
  void _observeSnapshot(SkillsWorkspaceSnapshot snapshot) {
    var changed = false;
    final present = <WorkspaceSkillId>{};
    for (final skill in snapshot.skills) {
      present.add(skill.id);
      final basis = SkillUpdateBasis.of(skill);
      if (_bases[skill.id] == basis) continue;
      _bases[skill.id] = basis;
      final derived = skillRequiresUpdateResolution(skill)
          ? SkillUpdateChecked(
              WorkspaceUpdateReport(
                skillId: skill.id,
                status: WorkspaceUpdateStatus.resolutionRequired,
                currentContentHash: skill.currentRevision.contentHash,
              ),
            )
          : const SkillUpdateNotChecked();
      if (derived is SkillUpdateNotChecked) {
        if (_states.remove(skill.id) != null) changed = true;
        if (_restored) {
          unawaited(
            ref
                .read(skillsUpdateCheckStoreProvider)
                .removeUpdateCache(skill.id),
          );
        }
      } else {
        _states[skill.id] = derived;
        changed = true;
      }
    }
    for (final skillId in _bases.keys.toList()) {
      if (present.contains(skillId)) continue;
      _bases.remove(skillId);
      if (_states.remove(skillId) != null) changed = true;
      if (_restored) {
        unawaited(
          ref.read(skillsUpdateCheckStoreProvider).removeUpdateCache(skillId),
        );
      }
      _order.remove(skillId);
      final pending = _pending.remove(skillId);
      if (pending != null) _settle(pending, const SkillUpdateNotChecked());
    }
    if (changed) _publish();
  }

  Future<void> _runSweep(Completer<void> sweep) async {
    _sweepCompleted = 0;
    _sweepTotal = 0;
    _sweepCancelled = false;
    _sweepWarnings.clear();
    _sweepWarningKeys.clear();
    _publish();

    // The work list comes from the Snapshot, so the sweep must wait for the
    // first ready Snapshot rather than treating a still-opening Workspace as
    // an empty one and marking the session swept.
    final List<WorkspaceSkill> skills;
    try {
      skills = (await ref.read(workspaceSnapshotProvider.future)).skills;
    } on Object {
      await _finishSweep(sweep);
      return;
    }
    if (_disposed || _sweep != sweep) return;

    final skillIds = [for (final skill in skills) skill.id];
    _sweepTotal = skillIds.length;
    _publish();
    // Queue the whole sweep before starting anything, so every Skill sharing a
    // Git fetch is still queued when the first of them starts.
    _holdPump = true;
    final settled = [
      for (final skillId in skillIds)
        _enqueue(skillId, manual: false, sweepMember: true),
    ];
    _holdPump = false;
    _pump();
    try {
      await Future.wait(settled);
    } on Object {
      // Individual outcomes are already recorded as per-Skill state.
    }
    await _finishSweep(sweep);
  }

  Future<void> _finishSweep(Completer<void> sweep) async {
    if (_sweep != sweep) return;
    _sweep = null;
    if (_disposed) {
      if (!sweep.isCompleted) sweep.complete();
      return;
    }
    // A cancelled sweep is not a completed one: it must neither suppress the
    // next startup sweep nor count as this session's usable result.
    final cancelled = _sweepCancelled;
    _sweepCancelled = false;
    if (cancelled) {
      _publish();
      if (!sweep.isCompleted) sweep.complete();
      return;
    }
    _sweptThisSession = true;
    _publish();
    try {
      await ref
          .read(skillUpdateSweepStoreProvider)
          .writeLastSweepAt(DateTime.now().toUtc());
    } on Object {
      // A cache write failure must not turn a successful check into a failed
      // Workspace operation; the next startup will simply check again.
    }
    if (!sweep.isCompleted) sweep.complete();
  }

  void _pump() {
    if (_holdPump) return;
    while (_checks.length < _concurrencyBound && _order.isNotEmpty) {
      final skillId = _order.removeFirst();
      final pending = _pending.remove(skillId);
      if (pending == null) continue;
      _start(pending);
    }
  }

  /// Starts one check request for [first] and every queued Skill sharing its
  /// Git fetch, so the Workspace fetches that repository once. Each request
  /// still settles on its own, so a slow or failing repository never holds
  /// back results from the others.
  void _start(_PendingCheck first) {
    final snapshot = ref.read(workspaceSnapshotProvider).value;
    final group = [first];
    final firstSkill = snapshot?.findSkillById(first.skillId);
    final key = firstSkill == null ? null : _sharedFetchKey(firstSkill);
    if (key != null) {
      for (final skillId in _order.toList()) {
        final skill = snapshot!.findSkillById(skillId);
        if (skill == null || _sharedFetchKey(skill) != key) continue;
        final pending = _pending.remove(skillId);
        if (pending == null) continue;
        _order.remove(skillId);
        group.add(pending);
      }
    }

    final members = <_RunningMember>[];
    for (final pending in group) {
      final skillId = pending.skillId;
      final skill = snapshot?.findSkillById(skillId);
      if (skill == null) {
        _manual.remove(skillId);
        _settle(pending, const SkillUpdateNotChecked());
        continue;
      }
      // `checkUpdates` does not short-circuit for a Skill with an Update
      // Candidate Session or a dirty Draft -- it only short-circuits on the
      // Source's own eligibility -- so resolving this from the Snapshot avoids
      // a pointless network round trip, and stops a report-less check from
      // clobbering state the Snapshot already proves.
      if (skillRequiresUpdateResolution(skill)) {
        final derived = SkillUpdateChecked(
          WorkspaceUpdateReport(
            skillId: skillId,
            status: WorkspaceUpdateStatus.resolutionRequired,
            currentContentHash: skill.currentRevision.contentHash,
          ),
        );
        _states[skillId] = derived;
        _manual.remove(skillId);
        if (_sweep != null && pending.sweepMember) _sweepCompleted += 1;
        _settle(pending, derived);
        continue;
      }
      _states[skillId] = const SkillUpdateChecking();
      members.add(_RunningMember(pending, SkillUpdateBasis.of(skill)));
    }
    if (members.isEmpty) {
      _advance();
      return;
    }
    final task = ref
        .read(skillsWorkspaceRepositoryProvider)
        .checkUpdates(
          skillIds: {for (final member in members) member.pending.skillId},
        );
    final check = _RunningCheck(members: members, task: task);
    _checks.add(check);
    for (final member in members) {
      _running[member.pending.skillId] = member.pending;
    }
    _publish();
    unawaited(_awaitCheck(check));
  }

  Future<void> _awaitCheck(_RunningCheck check) async {
    WorkspaceCompletion<List<WorkspaceUpdateReport>>? completion;
    AppFailure? unexpectedFailure;
    try {
      completion = await check.task.completed;
      _collectWarnings(completion.warnings);
    } on Object catch (error, stackTrace) {
      unexpectedFailure = ref
          .read(appFailureReporterProvider)
          .capture(
            error,
            stackTrace,
            operationKey: WorkspaceOperationKind.checkUpdates.name,
          );
    }
    _checks.remove(check);

    for (final member in check.members) {
      final skillId = member.pending.skillId;
      final settled = unexpectedFailure != null
          ? SkillUpdateCheckFailed(unexpectedFailure)
          : switch (completion!) {
              WorkspaceCompleted(:final value) => _stateFromReports(
                skillId,
                value,
              ),
              WorkspaceFailed(:final failure) => SkillUpdateCheckFailed(
                failure,
              ),
              // `checkUpdates` takes no Workspace lock and writes no Journal,
              // so it cannot commit. Treat the impossible case as unchecked
              // rather than inventing a report.
              WorkspaceCommittedPending() => const SkillUpdateNotChecked(),
            };
      _running.remove(skillId);
      _manual.remove(skillId);
      if (_sweep != null && member.pending.sweepMember) _sweepCompleted += 1;

      // Stale-write guard. An in-flight check started before a Source
      // Replacement, Update, Removal, or Draft transition must not write its
      // obsolete report back over the invalidated entry.
      final current = ref
          .read(workspaceSnapshotProvider)
          .value
          ?.findSkillById(skillId);
      final basisHeld =
          current != null && SkillUpdateBasis.of(current) == member.basis;
      if (basisHeld) {
        _states[skillId] = settled;
        if (settled case SkillUpdateChecked(:final report)) {
          try {
            await _persistReport(current, member.basis, report);
          } on Object {
            // Keep the in-memory result usable if the optional cache is
            // locked or unavailable.
          }
        } else {
          try {
            await ref
                .read(skillsUpdateCheckStoreProvider)
                .removeUpdateCache(skillId);
          } on Object {
            // Cache invalidation is best effort after a report-less check.
          }
        }
      } else if (_states[skillId] is SkillUpdateChecking) {
        _states.remove(skillId);
      }
      _settle(member.pending, basisHeld ? settled : _stateOf(skillId));
    }
    _advance();
  }

  Future<void> _persistReport(
    WorkspaceSkill skill,
    SkillUpdateBasis basis,
    WorkspaceUpdateReport report,
  ) => ref
      .read(skillsUpdateCheckStoreProvider)
      .upsertUpdateCache(
        WorkspaceUpdateCacheRecord(
          skillId: skill.id,
          basisFingerprint: basis.fingerprint,
          report: report,
          checkedAt: DateTime.now().toUtc(),
        ),
      );

  void _advance() {
    if (_disposed) return;
    _pump();
    _publish();
  }

  SkillUpdateState _stateFromReports(
    WorkspaceSkillId skillId,
    List<WorkspaceUpdateReport> reports,
  ) {
    for (final report in reports) {
      if (report.skillId == skillId) return SkillUpdateChecked(report);
    }
    return const SkillUpdateNotChecked();
  }

  void _collectWarnings(List<WorkspaceWarning> warnings) {
    for (final warning in warnings) {
      if (_sweepWarningKeys.add(workspaceWarningKey(warning))) {
        _sweepWarnings.add(warning);
      }
    }
  }

  void _settle(_PendingCheck pending, SkillUpdateState settled) {
    if (pending.settled.isCompleted) return;
    pending.settled.complete(settled);
  }

  void _publish() {
    if (_disposed || !_built || !ref.mounted) return;
    state = _compose();
  }
}

final class _PendingCheck {
  _PendingCheck({
    required this.skillId,
    required this.manual,
    required this.sweepMember,
  });

  final WorkspaceSkillId skillId;
  final Completer<SkillUpdateState> settled = Completer();
  bool manual;
  bool sweepMember;
}

final class _RunningMember {
  const _RunningMember(this.pending, this.basis);

  final _PendingCheck pending;
  final SkillUpdateBasis basis;
}

/// One `checkUpdates` request covering every Skill that shares a Git fetch.
final class _RunningCheck {
  _RunningCheck({required this.members, required this.task});

  final List<_RunningMember> members;
  final WorkspaceTask<List<WorkspaceUpdateReport>> task;

  Future<void> cancel() => task.cancel();
}

/// Git Skills checked from one repository and ref share a single fetch; other
/// Sources have nothing to share. Raw locators are enough: two spellings of one
/// repository only cost an extra fetch, and the Workspace normalizes them.
(String, String?)? _sharedFetchKey(WorkspaceSkill skill) {
  final source = skill.source;
  return source.kind == WorkspaceSourceKind.git
      ? (source.locator, source.ref)
      : null;
}

extension SkillUpdateStatusFailureX on SkillUpdateState {
  AppFailure? get failure => this is SkillUpdateCheckFailed
      ? (this as SkillUpdateCheckFailed).failure
      : null;
}
