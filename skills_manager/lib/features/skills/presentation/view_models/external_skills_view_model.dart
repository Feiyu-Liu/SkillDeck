import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';

const _externalFailureUnset = Object();

final externalSkillsViewModelProvider =
    NotifierProvider<ExternalSkillsViewModel, ExternalSkillsState>(
      ExternalSkillsViewModel.new,
    );

enum ExternalSkillsStatus {
  idle,
  scanning,
  ready,
  confirming,
  adopting,
  success,

  /// Some Skills were adopted; others failed or were not reached.
  partial,
  failure,
  cancelled,
}

/// One Skill of a batch that could not be adopted. It stays in the review.
final class ExternalSkillAdoptionFailure {
  const ExternalSkillAdoptionFailure({
    required this.slotKey,
    required this.name,
    required this.failure,
  });

  final String slotKey;

  /// The declared name, or the slot key when the review has none.
  final String name;
  final AppFailure failure;
}

/// Failures that are not about one Skill. Every later Skill would fail the
/// same way, so the batch stops instead of trying them.
const Set<String> _batchStoppingCodes = {
  'repositoryBusy',
  'repositoryNotOpen',
  'agentRootOwnership',
  'unsupportedStateVersion',
  'unsupportedJournalVersion',
  'stateCorrupt',
  'journalCorrupt',
  'journalMaintenanceFailed',
  'migrationFailed',
  'controlPlaneCorrupt',
  'revisionStoreCorrupt',
  'finalizationRecoveryFailed',
  'rollbackFailed',
  'recoveryFailed',
};

final class ExternalSkillsState {
  const ExternalSkillsState({
    this.status = ExternalSkillsStatus.idle,
    this.discovery,
    this.selectedSlotKeys = const {},
    this.authoritativeLocations = const {},
    this.completedSlotKeys = const [],
    this.failedAdoptions = const [],
    this.adoptionTotal = 0,
    this.activeSlotKey,
    this.failure,
    this.operation = const WorkspaceOperationState(),
    this.rescannedAfterChange = false,
  });

  final ExternalSkillsStatus status;
  final ExternalSkillsDiscovery? discovery;
  final Set<String> selectedSlotKeys;
  final Map<String, String> authoritativeLocations;
  final List<String> completedSlotKeys;

  /// The Skills of the last batch that could not be adopted, in batch order.
  final List<ExternalSkillAdoptionFailure> failedAdoptions;
  final int adoptionTotal;
  final String? activeSlotKey;
  final AppFailure? failure;
  final WorkspaceOperationState operation;

  /// Whether the review was refreshed because the Agent folders changed
  /// after the user reviewed them, so the user must confirm the new list.
  final bool rescannedAfterChange;

  bool get scanning => status == ExternalSkillsStatus.scanning;
  bool get adopting => status == ExternalSkillsStatus.adopting;
  bool get busy => scanning || adopting;
  int get unmanagedSlotCount => discovery?.uniqueSlotCount ?? 0;
  bool get scanFailed =>
      status == ExternalSkillsStatus.failure &&
      failure?.operationKey ==
          WorkspaceOperationKind.discoverExternalSkills.name;

  bool get canConfirm {
    if (selectedSlotKeys.isEmpty) return false;
    final conflicts = {
      for (final conflict in discovery?.conflicts ?? const [])
        conflict.slotKey: conflict,
    };
    for (final slotKey in selectedSlotKeys) {
      final conflict = conflicts[slotKey];
      if (conflict != null &&
          !conflict.locations.contains(authoritativeLocations[slotKey])) {
        return false;
      }
      if (authoritativeLocations[slotKey]?.trim().isEmpty ?? true) return false;
    }
    return true;
  }

  ExternalSkillsState copyWith({
    ExternalSkillsStatus? status,
    ExternalSkillsDiscovery? discovery,
    Set<String>? selectedSlotKeys,
    Map<String, String>? authoritativeLocations,
    List<String>? completedSlotKeys,
    List<ExternalSkillAdoptionFailure>? failedAdoptions,
    int? adoptionTotal,
    Object? activeSlotKey = _externalFailureUnset,
    Object? failure = _externalFailureUnset,
    WorkspaceOperationState? operation,
    bool? rescannedAfterChange,
  }) => ExternalSkillsState(
    status: status ?? this.status,
    discovery: discovery ?? this.discovery,
    selectedSlotKeys: Set.unmodifiable(
      selectedSlotKeys ?? this.selectedSlotKeys,
    ),
    authoritativeLocations: Map.unmodifiable(
      authoritativeLocations ?? this.authoritativeLocations,
    ),
    completedSlotKeys: List.unmodifiable(
      completedSlotKeys ?? this.completedSlotKeys,
    ),
    failedAdoptions: List.unmodifiable(failedAdoptions ?? this.failedAdoptions),
    adoptionTotal: adoptionTotal ?? this.adoptionTotal,
    activeSlotKey: identical(activeSlotKey, _externalFailureUnset)
        ? this.activeSlotKey
        : activeSlotKey as String?,
    failure: identical(failure, _externalFailureUnset)
        ? this.failure
        : failure as AppFailure?,
    operation: operation ?? this.operation,
    rescannedAfterChange: rescannedAfterChange ?? this.rescannedAfterChange,
  );
}

final class ExternalSkillsViewModel extends Notifier<ExternalSkillsState> {
  late final WorkspaceOperationTracker _operationTracker;
  Future<void>? _scanFuture;

  @override
  ExternalSkillsState build() {
    _operationTracker = WorkspaceOperationTracker(
      onChanged: (operation) {
        if (ref.mounted) state = state.copyWith(operation: operation);
      },
      warningsOf: (progress) => progress.warnings,
      warningKey: workspaceWarningKey,
    );
    ref.onDispose(() => unawaited(_operationTracker.dispose()));
    return const ExternalSkillsState();
  }

  /// Scans again. A review already on screen stays usable while the scan
  /// runs, and the choices made on it carry over to the new result.
  Future<void> scan() =>
      _startScan(preserveReview: !(state.discovery?.isEmpty ?? true));

  Future<void> _startScan({required bool preserveReview}) {
    if (state.adopting) return Future.value();
    final existing = _scanFuture;
    if (existing != null) return existing;
    final future = _scan(preserveReview: preserveReview);
    _scanFuture = future;
    return future.whenComplete(() {
      if (identical(_scanFuture, future)) _scanFuture = null;
    });
  }

  /// Rescans after the Agent catalog was reconfigured.
  ///
  /// A custom Agent moves where external Skills can live, and adoption
  /// re-resolves locations against the new catalog, so a review taken before
  /// the change would only fail as stale. Before the first scan, and while
  /// the user is confirming or an operation runs, nothing happens: the next
  /// open of the review scans anyway.
  void agentCatalogChanged() {
    if (state.status == ExternalSkillsStatus.idle ||
        state.status == ExternalSkillsStatus.confirming ||
        state.busy) {
      return;
    }
    unawaited(scan());
  }

  void setSelected(String slotKey, {required bool selected}) {
    if (state.adopting) return;
    final selectedSlotKeys = {...state.selectedSlotKeys};
    if (selected) {
      selectedSlotKeys.add(slotKey);
    } else {
      selectedSlotKeys.remove(slotKey);
    }
    state = state.copyWith(
      status: state.scanning ? null : ExternalSkillsStatus.ready,
      selectedSlotKeys: selectedSlotKeys,
      failure: null,
      rescannedAfterChange: false,
    );
  }

  void selectAuthority(String slotKey, String location) {
    if (state.adopting) return;
    state = state.copyWith(
      status: state.scanning ? null : ExternalSkillsStatus.ready,
      selectedSlotKeys: {...state.selectedSlotKeys, slotKey},
      authoritativeLocations: {
        ...state.authoritativeLocations,
        slotKey: location,
      },
      failure: null,
      rescannedAfterChange: false,
    );
  }

  void reviewConfirmation() {
    if (!state.canConfirm || state.busy) return;
    state = state.copyWith(
      status: ExternalSkillsStatus.confirming,
      rescannedAfterChange: false,
    );
  }

  void returnToReview() {
    if (state.busy) return;
    state = state.copyWith(status: ExternalSkillsStatus.ready, failure: null);
  }

  Future<void> adoptSelected() async {
    // Adoption uses the scan's content hashes, so it waits for a running scan.
    if (state.adopting || state.scanning || !state.canConfirm) return;
    final requests = _selectedRequests();
    final names = {
      for (final candidate
          in state.discovery?.candidates ?? const <ExternalSkillCandidate>[])
        candidate.slotKey: candidate.declaredName,
    };
    final analytics = ref.read(appAnalyticsProvider);
    final stopwatch = Stopwatch()..start();
    final completed = <String>[];
    final failed = <ExternalSkillAdoptionFailure>[];
    state = state.copyWith(
      status: ExternalSkillsStatus.adopting,
      completedSlotKeys: const [],
      failedAdoptions: const [],
      adoptionTotal: requests.length,
      activeSlotKey: requests.first.slotKey,
      failure: null,
    );
    _operationTracker.clear();

    void recordFailure(String slotKey, AppFailure failure) {
      failed.add(
        ExternalSkillAdoptionFailure(
          slotKey: slotKey,
          name: names[slotKey] ?? slotKey,
          failure: failure,
        ),
      );
      state = state.copyWith(failedAdoptions: failed);
    }

    // A failure that stops the batch. A failure about one Skill does not: it
    // is recorded, the Skill stays in the review, and the next one runs, so
    // one Skill that cannot be adopted never blocks the others.
    AppFailure? terminalFailure;
    var cancelled = false;
    ({String operationId, int committedRevision})? finalizationPending;
    try {
      for (final request in requests) {
        if (!ref.mounted) return;
        state = state.copyWith(activeSlotKey: request.slotKey);
        final completion = await ref
            .read(skillsWorkspaceRepositoryProvider)
            .adopt(request)
            .trackedCompletionBy(_operationTracker);
        if (!ref.mounted) return;
        switch (completion) {
          case WorkspaceCompleted():
            completed.add(request.slotKey);
            _removeAdoptedSlot(request.slotKey);
            state = state.copyWith(completedSlotKeys: completed);
          case WorkspaceCommittedPending(
            :final operationId,
            :final committedRevision,
          ):
            // The adoption committed; only its finalization is pending. The
            // Skill is managed now, so it must leave the review like a
            // completed one, or a retry would try to adopt it again.
            completed.add(request.slotKey);
            _removeAdoptedSlot(request.slotKey);
            finalizationPending = (
              operationId: operationId,
              committedRevision: committedRevision,
            );
            break;
          case WorkspaceFailed(:final failure):
            final captured = _captureFailure(
              failure,
              StackTrace.current,
              WorkspaceOperationKind.adopt,
            );
            if (captured.message == AppFailureMessage.operationCancelled) {
              terminalFailure = captured;
              cancelled = true;
              break;
            }
            recordFailure(request.slotKey, captured);
            // A changed folder makes every remaining reviewed hash
            // untrustworthy, and a repository-wide failure would repeat for
            // every remaining Skill.
            if (captured.codeKey == WorkspaceErrorCode.staleSnapshot.name ||
                _batchStoppingCodes.contains(captured.codeKey)) {
              terminalFailure = captured;
            }
        }
        if (terminalFailure != null || finalizationPending != null) break;
      }
    } on Object catch (error, stackTrace) {
      terminalFailure = _captureFailure(
        error,
        stackTrace,
        WorkspaceOperationKind.adopt,
      );
      cancelled =
          terminalFailure.message == AppFailureMessage.operationCancelled;
      final slotKey = state.activeSlotKey;
      if (!cancelled && slotKey != null) {
        recordFailure(slotKey, terminalFailure);
      }
    }

    if (!ref.mounted) return;
    stopwatch.stop();
    final notifications = ref.read(appNotificationControllerProvider.notifier);
    final firstFailure = failed.firstOrNull?.failure;
    analytics.track(
      AppAnalyticsEvent.externalAdoption(
        outcome: finalizationPending != null
            ? ExternalAdoptionAnalyticsOutcome.finalizationPending
            : cancelled
            ? ExternalAdoptionAnalyticsOutcome.cancelled
            : firstFailure == null
            ? ExternalAdoptionAnalyticsOutcome.success
            : completed.isEmpty
            ? ExternalAdoptionAnalyticsOutcome.failed
            : ExternalAdoptionAnalyticsOutcome.partial,
        duration: stopwatch.elapsed,
        itemCount: requests.length,
        adoptedCount: completed.length,
        errorCode: appAnalyticsErrorCode(
          cancelled ? terminalFailure : firstFailure,
        ),
      ),
    );
    if (finalizationPending case final pending?) {
      state = state.copyWith(
        status: ExternalSkillsStatus.ready,
        completedSlotKeys: completed,
        activeSlotKey: null,
        failure: null,
      );
      _publishFinalizationPending(
        pending.operationId,
        pending.committedRevision,
      );
      return;
    }
    if (terminalFailure?.codeKey == WorkspaceErrorCode.staleSnapshot.name) {
      // The Agent folders changed between the scan and the adoption. That is
      // ordinary while Agents run, so rescan, keep what the user chose where
      // it still applies, and ask for one more confirmation. Nothing is
      // adopted without the user seeing the current content.
      state = state.copyWith(
        status: ExternalSkillsStatus.ready,
        completedSlotKeys: completed,
        activeSlotKey: null,
        failure: null,
      );
      await _startScan(preserveReview: true);
      if (!ref.mounted) return;
      if (state.status == ExternalSkillsStatus.ready) {
        state = state.copyWith(rescannedAfterChange: true);
        return;
      }
      if (state.failure == null) return;
      notifications.publish(AppNotification.failure(state.failure!));
      return;
    }
    if (cancelled) {
      state = state.copyWith(
        status: ExternalSkillsStatus.cancelled,
        completedSlotKeys: completed,
        activeSlotKey: null,
        failure: null,
      );
      notifications.info(AppNotificationMessage.operationCancelled);
      return;
    }
    if (firstFailure != null) {
      state = state.copyWith(
        status: completed.isEmpty
            ? ExternalSkillsStatus.failure
            : ExternalSkillsStatus.partial,
        completedSlotKeys: completed,
        activeSlotKey: null,
        failure: firstFailure,
      );
      if (completed.isEmpty) {
        notifications.publish(AppNotification.failure(firstFailure));
      } else {
        notifications.warning(
          AppNotificationMessage.externalSkillsPartiallyAdopted,
        );
      }
      return;
    }

    state = state.copyWith(
      status: ExternalSkillsStatus.success,
      completedSlotKeys: completed,
      activeSlotKey: null,
      failure: null,
    );
    if (state.operation.warnings.isEmpty) {
      notifications.success(AppNotificationMessage.externalSkillsAdopted);
    } else {
      notifications.warning(AppNotificationMessage.completedWithWarnings);
    }
  }

  Future<void> cancelOperation() => _operationTracker.cancel();

  Future<void> _scan({required bool preserveReview}) async {
    state = state.copyWith(
      status: ExternalSkillsStatus.scanning,
      failedAdoptions: const [],
      failure: null,
      rescannedAfterChange: false,
    );
    _operationTracker.clear();
    try {
      final completion = await ref
          .read(skillsWorkspaceRepositoryProvider)
          .discoverExternalSkills()
          .trackedCompletionBy(_operationTracker);
      if (!ref.mounted) return;
      switch (completion) {
        case WorkspaceCompleted(:final value):
          // Read the review when the scan ends, not when it starts: the user
          // keeps choosing while it runs.
          _applyDiscovery(
            value,
            status: ExternalSkillsStatus.ready,
            previousSelection: preserveReview ? state.selectedSlotKeys : null,
            previousAuthorities: preserveReview
                ? state.authoritativeLocations
                : null,
          );
        case WorkspaceFailed(:final failure):
          state = state.copyWith(
            status: ExternalSkillsStatus.failure,
            failure: _captureFailure(
              failure,
              StackTrace.current,
              WorkspaceOperationKind.discoverExternalSkills,
            ),
          );
        case WorkspaceCommittedPending(
          :final operationId,
          :final committedRevision,
        ):
          _publishFinalizationPending(operationId, committedRevision);
          state = state.copyWith(status: ExternalSkillsStatus.ready);
      }
    } on Object catch (error, stackTrace) {
      if (!ref.mounted) return;
      state = state.copyWith(
        status: ExternalSkillsStatus.failure,
        failure: _captureFailure(
          error,
          stackTrace,
          WorkspaceOperationKind.discoverExternalSkills,
        ),
      );
    }
  }

  /// Applies a scan. With [previousSelection], the user's earlier choices
  /// carry over to Skills that are still present, and an authority carries
  /// over only while that location still holds the Skill.
  void _applyDiscovery(
    ExternalSkillsDiscovery discovery, {
    required ExternalSkillsStatus status,
    Set<String>? previousSelection,
    Map<String, String>? previousAuthorities,
  }) {
    final selected = <String>{};
    final authorities = <String, String>{};
    // Only a Skill the user saw and unchecked stays unchecked; one the new
    // scan found for the first time starts selected, like on a fresh review.
    final previouslyShown = {
      for (final candidate in state.discovery?.candidates ?? const [])
        candidate.slotKey,
      for (final conflict in state.discovery?.conflicts ?? const [])
        conflict.slotKey,
    };
    final candidates = [...discovery.candidates]
      ..sort((left, right) => left.slotKey.compareTo(right.slotKey));
    for (final candidate in candidates) {
      final locations = [...candidate.locations]..sort();
      if (locations.isEmpty) continue;
      if (previousSelection != null &&
          previouslyShown.contains(candidate.slotKey) &&
          !previousSelection.contains(candidate.slotKey)) {
        continue;
      }
      selected.add(candidate.slotKey);
      final previous = previousAuthorities?[candidate.slotKey];
      authorities[candidate.slotKey] =
          previous != null && locations.contains(previous)
          ? previous
          : locations.first;
    }
    if (previousSelection != null) {
      for (final conflict in discovery.conflicts) {
        final previous = previousAuthorities?[conflict.slotKey];
        if (previousSelection.contains(conflict.slotKey) &&
            previous != null &&
            conflict.locations.contains(previous)) {
          selected.add(conflict.slotKey);
          authorities[conflict.slotKey] = previous;
        }
      }
    }
    state = state.copyWith(
      status: status,
      discovery: discovery,
      selectedSlotKeys: selected,
      authoritativeLocations: authorities,
      failure: null,
    );
  }

  List<ExternalSkillAdoptionRequest> _selectedRequests() {
    final activationMethod = ref.read(globalActivationMethodProvider);
    final requests = [
      for (final slotKey in state.selectedSlotKeys)
        ExternalSkillAdoptionRequest(
          slotKey: slotKey,
          authoritativeLocation: state.authoritativeLocations[slotKey]!,
          reviewedContentHashByLocation: _reviewedHashes(slotKey),
          activationMethod: activationMethod,
        ),
    ]..sort((left, right) => left.slotKey.compareTo(right.slotKey));
    return requests;
  }

  Map<String, String> _reviewedHashes(String slotKey) {
    final discovery = state.discovery;
    if (discovery == null) {
      throw StateError('External Skills have not been scanned.');
    }
    for (final candidate in discovery.candidates) {
      if (candidate.slotKey != slotKey) continue;
      return <String, String>{
        for (final location in candidate.locations)
          location: candidate.contentHash,
      };
    }
    for (final conflict in discovery.conflicts) {
      if (conflict.slotKey == slotKey) {
        return conflict.contentHashByLocation;
      }
    }
    throw StateError('Selected external Skill is not in the reviewed scan.');
  }

  void _removeAdoptedSlot(String slotKey) {
    final discovery = state.discovery;
    if (discovery == null) return;
    final selectedSlotKeys = {...state.selectedSlotKeys}..remove(slotKey);
    final authoritativeLocations = {...state.authoritativeLocations}
      ..remove(slotKey);
    state = state.copyWith(
      discovery: ExternalSkillsDiscovery(
        candidates: [
          for (final candidate in discovery.candidates)
            if (candidate.slotKey != slotKey) candidate,
        ],
        conflicts: [
          for (final conflict in discovery.conflicts)
            if (conflict.slotKey != slotKey) conflict,
        ],
      ),
      selectedSlotKeys: selectedSlotKeys,
      authoritativeLocations: authoritativeLocations,
    );
  }

  AppFailure _captureFailure(
    Object error,
    StackTrace stackTrace,
    WorkspaceOperationKind operation,
  ) {
    final failure = ref
        .read(appFailureReporterProvider)
        .capture(error, stackTrace, operationKey: operation.name);
    _operationTracker.addWarnings(
      failure.warnings.whereType<WorkspaceWarning>(),
    );
    return failure;
  }

  void _publishFinalizationPending(String operationId, int committedRevision) =>
      ref
          .read(workspaceFinalizationCoordinatorProvider.notifier)
          .register(
            WorkspaceCommittedPending<void>(
              operationId: operationId,
              committedRevision: committedRevision,
              warnings: _operationTracker.state.warnings,
            ),
          );
}
