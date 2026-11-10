import 'dart:async';

import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/services/agent_root_ownership_repair_service.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

abstract interface class AgentRootOwnershipReviewPresenter {
  Future<Set<String>?> review(WorkspaceAgentRootOwnershipAudit audit);
}

final class AgentRootOwnershipCoordinator {
  AgentRootOwnershipCoordinator({
    required SkillsWorkspaceRepository repository,
    required AgentRootOwnershipRepairService repairService,
    required AgentRootOwnershipReviewPresenter reviewPresenter,
  }) : _repository = repository,
       _repairService = repairService,
       _reviewPresenter = reviewPresenter;

  final SkillsWorkspaceRepository _repository;
  final AgentRootOwnershipRepairService _repairService;
  final AgentRootOwnershipReviewPresenter _reviewPresenter;

  static final _nonInteractiveKey = Object();

  /// Opt-in for remote command callers; never joins an interactive GUI review.
  static T withoutInteractiveRepair<T>(T Function() action) =>
      runZoned(action, zoneValues: {_nonInteractiveKey: true});

  bool _verified = false;
  Future<WorkspaceFailure?>? _inspection;

  void invalidate() {
    _verified = false;
  }

  Future<WorkspaceFailure?> ensureReady(WorkspaceOperationKind operation) {
    if (_verified) return Future<WorkspaceFailure?>.value();
    if (Zone.current[_nonInteractiveKey] == true) {
      return _inspectWithoutRepair(operation);
    }
    return _inspection ??= _inspectAndRepair(operation).whenComplete(() {
      _inspection = null;
    });
  }

  Future<WorkspaceFailure?> _inspectWithoutRepair(
    WorkspaceOperationKind operation,
  ) async {
    final completion = await _repository.inspectAgentRootOwnership().completed;
    switch (completion) {
      case WorkspaceCompleted(:final value):
        if (!value.supported || value.isClean) return null;
        return _failure(operation, 'agentRootOwnershipRepairRequired');
      case WorkspaceFailed(:final failure):
        return _forOperation(failure, operation);
      case WorkspaceCommittedPending():
        return _failure(operation, 'ownershipInspectionUnexpectedCommit');
    }
  }

  Future<WorkspaceFailure?> _inspectAndRepair(
    WorkspaceOperationKind operation,
  ) async {
    final initial = await _repository.inspectAgentRootOwnership().completed;
    final WorkspaceAgentRootOwnershipAudit initialAudit;
    switch (initial) {
      case WorkspaceCompleted(:final value):
        initialAudit = value;
      case WorkspaceFailed(:final failure):
        return _forOperation(failure, operation);
      case WorkspaceCommittedPending():
        return _failure(operation, 'ownershipInspectionUnexpectedCommit');
    }
    if (!initialAudit.supported || initialAudit.isClean) {
      _verified = true;
      return null;
    }
    if (initialAudit.blockedIssues.isNotEmpty) {
      return _issueFailure(
        operation,
        'agentRootOwnershipBlocked',
        initialAudit.blockedIssues,
      );
    }

    final expectedRoots = {
      for (final issue in initialAudit.repairableIssues) issue.rootPath,
    };
    final reviewedRoots = await _reviewPresenter.review(initialAudit);
    if (reviewedRoots == null) {
      return WorkspaceFailure(
        code: WorkspaceErrorCode.operationCancelled,
        operation: operation,
        context: const {'reason': 'agentRootOwnershipRepairCancelled'},
      );
    }
    if (reviewedRoots.length != expectedRoots.length ||
        !reviewedRoots.containsAll(expectedRoots)) {
      return _failure(operation, 'agentRootOwnershipReviewIncomplete');
    }

    final repair = await _repairService.repair(
      audit: initialAudit,
      reviewedRootPaths: reviewedRoots,
    );
    switch (repair) {
      case AgentRootOwnershipRepairOutcome.succeeded:
        break;
      case AgentRootOwnershipRepairOutcome.cancelled:
        return WorkspaceFailure(
          code: WorkspaceErrorCode.operationCancelled,
          operation: operation,
          context: const {'reason': 'agentRootOwnershipAuthorizationCancelled'},
        );
      case AgentRootOwnershipRepairOutcome.unsupported:
        return _failure(operation, 'agentRootOwnershipUnsupported');
      case AgentRootOwnershipRepairOutcome.rejected:
        return _failure(operation, 'agentRootOwnershipAuthorizationRejected');
      case AgentRootOwnershipRepairOutcome.failed:
        return _failure(operation, 'agentRootOwnershipRepairFailed');
      case AgentRootOwnershipRepairOutcome.invalidReview:
        return _failure(operation, 'agentRootOwnershipInvalidReview');
    }

    final verified = await _repository.inspectAgentRootOwnership().completed;
    final WorkspaceAgentRootOwnershipAudit verifiedAudit;
    switch (verified) {
      case WorkspaceCompleted(:final value):
        verifiedAudit = value;
      case WorkspaceFailed(:final failure):
        return _forOperation(failure, operation);
      case WorkspaceCommittedPending():
        return _failure(operation, 'ownershipInspectionUnexpectedCommit');
    }
    if (!verifiedAudit.supported) {
      return _failure(operation, 'agentRootOwnershipUnsupported');
    }
    if (!verifiedAudit.isClean) {
      return _issueFailure(
        operation,
        'agentRootOwnershipStillInvalid',
        verifiedAudit.issues,
      );
    }
    _verified = true;
    return null;
  }

  WorkspaceFailure _forOperation(
    WorkspaceFailure failure,
    WorkspaceOperationKind operation,
  ) => WorkspaceFailure(
    code: failure.code,
    operation: operation,
    context: failure.context,
    diagnostic: failure.diagnostic,
    warnings: failure.warnings,
  );

  WorkspaceFailure _issueFailure(
    WorkspaceOperationKind operation,
    String reason,
    List<WorkspaceAgentRootOwnershipIssue> issues,
  ) {
    final first = issues.first;
    return _failure(
      operation,
      reason,
      context: <String, Object?>{
        'issueReason': first.reason.name,
        'rootPath': first.rootPath,
        'issueCount': issues.length,
        // Every issue, so the user sees each folder to fix. Local display
        // only: analytics reports the error code alone.
        'issues': <Map<String, String>>[
          for (final issue in issues)
            {'issueReason': issue.reason.name, 'rootPath': issue.rootPath},
        ],
      },
    );
  }

  WorkspaceFailure _failure(
    WorkspaceOperationKind operation,
    String reason, {
    Map<String, Object?> context = const <String, Object?>{},
  }) => WorkspaceFailure(
    code: WorkspaceErrorCode.agentRootOwnership,
    operation: operation,
    context: <String, Object?>{'reason': reason, ...context},
  );
}
