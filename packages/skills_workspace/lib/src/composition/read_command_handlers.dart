import '../api/composite_command_dispatcher.dart';
import '../api/default_skills_repository.dart';
import '../api/finalization_recovery_command.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/discovery/external_discovery_models.dart';
import '../application/discovery/external_skill_scanner.dart';
import '../application/ports/history_ports.dart';
import '../application/operations/finalization_recovery_service.dart';
import '../application/operations/operation_models.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/source/source_acquisition_coordinator.dart';
import '../application/source/source_acquisition_models.dart';
import '../domain/public_models.dart';

/// Builds the read-only public command slice. None of these handlers creates a
/// Journal, changes the Repository Revision, or marks a Business Commit Point.
List<SkillsCommandHandler> buildReadCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required WorkspaceFinalizationRecoveryPort finalizationRecovery,
  required SourceAcquisitionCoordinator sources,
  required ExternalSkillScanner Function() externalSkills,
  required WorkspaceHistoryPort history,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<
    ResumeFinalizationRecoveryCommand,
    RepositorySnapshot
  >(
    kind: WorkspaceOperationKind.resumeFinalizationRecovery,
    handle: (_, context) async {
      context.reportProgress(OperationProgressPhase.finalizing);
      try {
        final report = await finalizationRecovery.resumeFinalizationRecovery();
        if (report.operations.any(
          (operation) =>
              operation.disposition ==
              RecoveredOperationDisposition.retryRequired,
        )) {
          return SkillsFailure<RepositorySnapshot>(
            code: SkillsErrorCode.finalizationRecoveryFailed,
          );
        }
        final snapshot = await snapshots.reload();
        return SkillsSuccess<RepositorySnapshot>(
          value: snapshot,
          changed: report.operations.isNotEmpty,
        );
      } on Object {
        return SkillsFailure<RepositorySnapshot>(
          code: SkillsErrorCode.finalizationRecoveryFailed,
        );
      }
    },
  ),
  TypedSkillsCommandHandler<RefreshWorkspaceCommand, RepositorySnapshot>(
    kind: WorkspaceOperationKind.refresh,
    handle: (_, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      try {
        final snapshot = await snapshots.reload();
        return SkillsSuccess<RepositorySnapshot>(
          value: snapshot,
          changed: false,
        );
      } on Object {
        return SkillsFailure<RepositorySnapshot>(
          code: SkillsErrorCode.stateCorrupt,
        );
      }
    },
  ),
  TypedSkillsCommandHandler<InspectSourceRequest, SourceInspection>(
    kind: WorkspaceOperationKind.inspectSource,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final result = await sources.inspect(
        source: request.source,
        options: SourceAcquisitionOptions(
          includeInternal: request.includeInternal,
          fullDepth: request.fullDepth,
        ),
        cancellationToken: context.cancellationToken,
      );
      final inspection = result.valueOrNull;
      if (inspection != null) {
        return SkillsSuccess<SourceInspection>(
          value: inspection,
          warnings: _sourceWarnings(result.warnings),
        );
      }
      final failure = result.failureOrNull!;
      return SkillsFailure<SourceInspection>(
        code: _sourceFailure(failure.code),
        context: failure.context,
        warnings: _sourceWarnings(failure.warnings),
      );
    },
  ),
  TypedSkillsCommandHandler<
    DiscoverExternalSkillsRequest,
    ExternalSkillsDiscovery
  >(
    kind: WorkspaceOperationKind.discoverExternalSkills,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final snapshot = snapshots.current;
      final scanner = externalSkills();
      final ExternalDiscoveryResult<ExternalSkillScan> result;
      if (request.scanAllKnownLocations) {
        final resolved = scanner.resolveAllLocations(snapshot);
        final targets = resolved.valueOrNull;
        if (targets == null) {
          return _externalFailure<ExternalSkillsDiscovery>(
            resolved.failureOrNull!,
          );
        }
        result = await scanner.scanTargets(
          targets,
          snapshot: snapshot,
          includeInternal: request.includeInternal,
          cancellationToken: context.cancellationToken,
        );
      } else {
        result = await scanner.scanSelection(
          selection: request.selection,
          snapshot: snapshot,
          includeInternal: request.includeInternal,
          cancellationToken: context.cancellationToken,
        );
      }
      final scan = result.valueOrNull;
      if (scan == null) {
        return _externalFailure<ExternalSkillsDiscovery>(result.failureOrNull!);
      }
      return SkillsSuccess<ExternalSkillsDiscovery>(
        value: scan.discovery,
        warnings: _externalWarnings(result.warnings),
      );
    },
  ),
  TypedSkillsCommandHandler<
    InspectUpdateCandidateRequest,
    UpdateCandidateSummary?
  >(
    kind: WorkspaceOperationKind.inspectUpdateCandidate,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      final skill = snapshots.current.findSkill(request.managedSkillId);
      if (skill == null) {
        return SkillsFailure<UpdateCandidateSummary?>(
          code: SkillsErrorCode.skillNotFound,
        );
      }
      return SkillsSuccess<UpdateCandidateSummary?>(
        value: skill.updateCandidate,
      );
    },
  ),
  TypedSkillsCommandHandler<OperationHistoryRequest, OperationHistoryPage>(
    kind: WorkspaceOperationKind.inspectOperationHistory,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      if (request.managedSkillId != null &&
          snapshots.current.findSkill(request.managedSkillId!) == null) {
        return SkillsFailure<OperationHistoryPage>(
          code: SkillsErrorCode.skillNotFound,
        );
      }
      try {
        return SkillsSuccess<OperationHistoryPage>(
          value: await history.readOperationHistory(
            managedSkillId: request.managedSkillId,
            cursor: request.cursor,
            limit: request.limit,
          ),
        );
      } on ArgumentError {
        return SkillsFailure<OperationHistoryPage>(
          code: SkillsErrorCode.invalidSkill,
          context: const <String, Object?>{'reason': 'invalidCursor'},
        );
      }
    },
  ),
  TypedSkillsCommandHandler<PublishedHistoryRequest, PublishedHistoryPage>(
    kind: WorkspaceOperationKind.inspectPublishedHistory,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      if (snapshots.current.findSkill(request.managedSkillId) == null) {
        return SkillsFailure<PublishedHistoryPage>(
          code: SkillsErrorCode.skillNotFound,
        );
      }
      try {
        return SkillsSuccess<PublishedHistoryPage>(
          value: await history.readPublishedHistory(
            managedSkillId: request.managedSkillId,
            cursor: request.cursor,
            limit: request.limit,
          ),
        );
      } on ArgumentError {
        return SkillsFailure<PublishedHistoryPage>(
          code: SkillsErrorCode.invalidSkill,
          context: const <String, Object?>{'reason': 'invalidCursor'},
        );
      }
    },
  ),
];

SkillsErrorCode _sourceFailure(
  SourceAcquisitionFailureCode code,
) => switch (code) {
  SourceAcquisitionFailureCode.sourceUnavailable =>
    SkillsErrorCode.sourceUnavailable,
  SourceAcquisitionFailureCode.sourceAuthenticationRequired =>
    SkillsErrorCode.sourceAuthenticationRequired,
  SourceAcquisitionFailureCode.gitUnavailable => SkillsErrorCode.gitUnavailable,
  SourceAcquisitionFailureCode.gitFailed ||
  SourceAcquisitionFailureCode.gitTimedOut => SkillsErrorCode.gitFailed,
  SourceAcquisitionFailureCode.developerToolsRequired =>
    SkillsErrorCode.developerToolsRequired,
  SourceAcquisitionFailureCode.transportRejected =>
    SkillsErrorCode.transportRejected,
  SourceAcquisitionFailureCode.httpFailure => SkillsErrorCode.httpFailure,
  SourceAcquisitionFailureCode.digestMismatch => SkillsErrorCode.digestMismatch,
  SourceAcquisitionFailureCode.archiveInvalid => SkillsErrorCode.archiveInvalid,
  SourceAcquisitionFailureCode.skillNotFound => SkillsErrorCode.skillNotFound,
  SourceAcquisitionFailureCode.invalidSkill => SkillsErrorCode.invalidSkill,
  SourceAcquisitionFailureCode.unsupportedSkillName =>
    SkillsErrorCode.unsupportedSkillName,
  SourceAcquisitionFailureCode.skillContentLimitExceeded =>
    SkillsErrorCode.skillContentLimitExceeded,
  SourceAcquisitionFailureCode.duplicateSkillSlot =>
    SkillsErrorCode.duplicateSkillSlot,
  SourceAcquisitionFailureCode.updateUnsupported =>
    SkillsErrorCode.updateUnsupported,
  SourceAcquisitionFailureCode.operationCancelled =>
    SkillsErrorCode.operationCancelled,
  SourceAcquisitionFailureCode.ioFailure => SkillsErrorCode.ioFailure,
};

List<SkillsWarning> _sourceWarnings(List<SourceAcquisitionWarning> warnings) =>
    warnings
        .map(
          (warning) => SkillsWarning(
            code: SkillsWarningCode.sourceEntrySkipped,
            context: warning.context,
          ),
        )
        .toList(growable: false);

SkillsFailure<T> _externalFailure<T>(
  ExternalDiscoveryFailure<Object?> failure,
) => SkillsFailure<T>(
  code: switch (failure.code) {
    ExternalDiscoveryFailureCode.agentNotFound => SkillsErrorCode.agentNotFound,
    ExternalDiscoveryFailureCode.activationUnsupported =>
      SkillsErrorCode.activationUnsupported,
    ExternalDiscoveryFailureCode.projectRootNotFound =>
      SkillsErrorCode.projectRootNotFound,
    ExternalDiscoveryFailureCode.sourceUnavailable =>
      SkillsErrorCode.sourceUnavailable,
    ExternalDiscoveryFailureCode.invalidSkill => SkillsErrorCode.invalidSkill,
    ExternalDiscoveryFailureCode.contentLimitExceeded =>
      SkillsErrorCode.skillContentLimitExceeded,
    ExternalDiscoveryFailureCode.operationCancelled =>
      SkillsErrorCode.operationCancelled,
    ExternalDiscoveryFailureCode.ioFailure => SkillsErrorCode.ioFailure,
  },
  context: failure.context,
  warnings: _externalWarnings(failure.warnings),
);

List<SkillsWarning> _externalWarnings(
  List<ExternalDiscoveryWarning> warnings,
) => warnings
    .map(
      (warning) => SkillsWarning(
        code: switch (warning.code) {
          ExternalDiscoveryWarningCode.noActivationTarget =>
            SkillsWarningCode.noActivationTarget,
          ExternalDiscoveryWarningCode.projectSymbolicLinkPortability =>
            SkillsWarningCode.projectSymbolicLinkPortability,
          ExternalDiscoveryWarningCode.duplicateExposure =>
            SkillsWarningCode.duplicateExposure,
          ExternalDiscoveryWarningCode.activationTargetSkipped =>
            SkillsWarningCode.activationTargetSkipped,
          ExternalDiscoveryWarningCode.sourceEntrySkipped =>
            SkillsWarningCode.sourceEntrySkipped,
          ExternalDiscoveryWarningCode.sharedActivationLocation =>
            SkillsWarningCode.sharedActivationLocation,
        },
        context: warning.context,
      ),
    )
    .toList(growable: false);
