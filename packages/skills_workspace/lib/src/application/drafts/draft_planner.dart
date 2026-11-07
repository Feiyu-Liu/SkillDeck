import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../operations/workspace_business_changes.dart';
import 'draft_models.dart';
import 'draft_ports.dart';

final class DraftPlanner {
  const DraftPlanner({
    required DraftWorkspaceStatePort states,
    required DateTime Function() clock,
  }) : _states = states,
       _clock = clock;

  final DraftWorkspaceStatePort _states;
  final DateTime Function() _clock;

  Future<DraftPlanningResult<DraftSummary?>> inspect({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) return _failure(DraftPlanningFailureCode.skillNotFound);
    if (skill.draft == null) {
      return const DraftPlanningSuccess<DraftSummary?>(null);
    }
    if (token.isCancelled) return _cancelled();
    final state = await _states.readDraftState(managedSkillId);
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(DraftPlanningFailureCode.revisionStateUnavailable);
    }
    return _states.inspectDraft(
      skill: skill,
      state: state,
      cancellationToken: token,
    );
  }

  Future<DraftPlanningResult<PlannedEnsureDraft>> planEnsure({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) return _failure(DraftPlanningFailureCode.skillNotFound);
    if (skill.draft != null) {
      final inspected = await inspect(
        snapshot: snapshot,
        managedSkillId: managedSkillId,
        cancellationToken: token,
      );
      final failure = inspected.failureOrNull;
      if (failure != null) {
        return DraftPlanningFailure<PlannedEnsureDraft>(
          code: failure.code,
          context: failure.context,
        );
      }
      final summary = inspected.valueOrNull;
      if (summary == null) {
        return _failure(DraftPlanningFailureCode.invalidPreparedEvidence);
      }
      return DraftPlanningSuccess<PlannedEnsureDraft>(ExistingDraft(summary));
    }
    if (token.isCancelled) return _cancelled();
    final state = await _states.readDraftState(managedSkillId);
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(DraftPlanningFailureCode.revisionStateUnavailable);
    }
    return DraftPlanningSuccess<PlannedEnsureDraft>(
      EnsureDraftPreparationRequired(
        snapshotRevision: snapshot.revision,
        plannedAtMicros: _nowMicros(),
        skill: skill,
        state: state,
      ),
    );
  }

  Future<DraftPlanningResult<DiscardDraftPlan>> planDiscard({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) return _failure(DraftPlanningFailureCode.skillNotFound);
    if (skill.updateCandidate != null) {
      return _failure(
        DraftPlanningFailureCode.updateCandidateResolutionRequired,
      );
    }
    if (skill.draft == null) {
      return _failure(DraftPlanningFailureCode.draftNotFound);
    }
    if (token.isCancelled) return _cancelled();
    final state = await _states.readDraftState(managedSkillId);
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(DraftPlanningFailureCode.revisionStateUnavailable);
    }
    return DraftPlanningSuccess<DiscardDraftPlan>(
      DiscardDraftPlan(
        snapshotRevision: snapshot.revision,
        skill: skill,
        state: state,
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            DeleteDraftWorkspace(managedSkillId),
          ],
        ),
      ),
    );
  }

  Future<DraftPlanningResult<PublishDraftPreparationRequired>> planPublish({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) return _failure(DraftPlanningFailureCode.skillNotFound);
    if (skill.updateCandidate != null) {
      return _failure(
        DraftPlanningFailureCode.updateCandidateResolutionRequired,
      );
    }
    if (skill.draft == null) {
      return _failure(DraftPlanningFailureCode.draftNotFound);
    }
    if (token.isCancelled) return _cancelled();
    final state = await _states.readDraftState(managedSkillId);
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(DraftPlanningFailureCode.revisionStateUnavailable);
    }
    return DraftPlanningSuccess<PublishDraftPreparationRequired>(
      PublishDraftPreparationRequired(
        snapshotRevision: snapshot.revision,
        plannedAtMicros: _nowMicros(),
        skill: skill,
        state: state,
      ),
    );
  }

  int _nowMicros() => _clock().toUtc().microsecondsSinceEpoch;
}

DraftPlanningFailure<T> _cancelled<T>() =>
    _failure(DraftPlanningFailureCode.operationCancelled);

DraftPlanningFailure<T> _failure<T>(
  DraftPlanningFailureCode code, {
  Map<String, Object?> context = const <String, Object?>{},
}) => DraftPlanningFailure<T>(code: code, context: context);
