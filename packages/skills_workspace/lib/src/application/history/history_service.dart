import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import 'history_models.dart';
import 'history_ports.dart';

final class WorkspaceHistoryService {
  const WorkspaceHistoryService({
    required WorkspaceHistoryContentPort content,
    required DateTime Function() clock,
  }) : _content = content,
       _clock = clock;

  final WorkspaceHistoryContentPort _content;
  final DateTime Function() _clock;

  Future<HistoryResult<SkillDiff>> inspectDiff({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference? from,
    required OperationSubjectReference to,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) return _failure(HistoryFailureCode.skillNotFound);
    if (token.isCancelled) return _cancelled();
    final target = await _content.resolvePublishedRevision(
      managedSkillId: managedSkillId,
      reference: to,
    );
    if (target == null) {
      return _failure(HistoryFailureCode.historicalRevisionNotFound);
    }
    final current = await _content.readRestoreState(managedSkillId);
    if (current == null || current.managedSkillId != managedSkillId) {
      return _failure(HistoryFailureCode.revisionStateUnavailable);
    }
    if (target.sourceLineage != current.sourceLineage) {
      return _failure(
        HistoryFailureCode.historicalRevisionOutsideCurrentLineage,
      );
    }
    HistoricalRevisionSelection? base;
    if (from != null) {
      base = await _content.resolvePublishedRevision(
        managedSkillId: managedSkillId,
        reference: from,
      );
      if (base == null) {
        return _failure(HistoryFailureCode.historicalRevisionNotFound);
      }
      if (base.sourceLineage != target.sourceLineage) {
        return _failure(
          HistoryFailureCode.historicalRevisionOutsideCurrentLineage,
        );
      }
    }
    if (token.isCancelled) return _cancelled();
    return _content.compare(
      managedSkillId: managedSkillId,
      from: base,
      to: target,
      cancellationToken: token,
    );
  }

  Future<HistoryResult<RestorePublishPreflight>> planRestore({
    required RepositorySnapshot snapshot,
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference selectedRevision,
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final skill = snapshot.findSkill(managedSkillId);
    if (skill == null) return _failure(HistoryFailureCode.skillNotFound);
    if (skill.updateCandidate != null) {
      return _failure(HistoryFailureCode.updateCandidateResolutionRequired);
    }
    if (token.isCancelled) return _cancelled();
    final state = await _content.readRestoreState(managedSkillId);
    if (state == null || state.managedSkillId != managedSkillId) {
      return _failure(HistoryFailureCode.revisionStateUnavailable);
    }
    var hadCleanDraft = false;
    if (skill.draft != null) {
      final inspected = await _content.inspectDraftDirty(
        skill: skill,
        state: state,
        cancellationToken: token,
      );
      final inspectionFailure = inspected.failureOrNull;
      if (inspectionFailure != null) {
        return HistoryFailure<RestorePublishPreflight>(
          code: inspectionFailure.code,
          context: inspectionFailure.context,
        );
      }
      if (inspected.valueOrNull!) {
        return _failure(HistoryFailureCode.dirtyDraftResolutionRequired);
      }
      hadCleanDraft = true;
    }
    if (token.isCancelled) return _cancelled();
    final selected = await _content.resolvePublishedRevision(
      managedSkillId: managedSkillId,
      reference: selectedRevision,
    );
    if (selected == null) {
      return _failure(HistoryFailureCode.historicalRevisionNotFound);
    }
    if (selected.sourceLineage != state.sourceLineage) {
      return _failure(
        HistoryFailureCode.historicalRevisionOutsideCurrentLineage,
      );
    }
    if (selected.declaredName != skill.declaredName) {
      return _failure(HistoryFailureCode.historicalNameMismatch);
    }
    return HistorySuccess<RestorePublishPreflight>(
      RestorePublishPreflight(
        snapshotRevision: snapshot.revision,
        plannedAtMicros: _clock().toUtc().microsecondsSinceEpoch,
        skill: skill,
        selected: selected,
        state: state,
        hadCleanDraft: hadCleanDraft,
      ),
    );
  }
}

HistoryFailure<T> _cancelled<T>() =>
    _failure(HistoryFailureCode.operationCancelled);

HistoryFailure<T> _failure<T>(HistoryFailureCode code) =>
    HistoryFailure<T>(code: code);
