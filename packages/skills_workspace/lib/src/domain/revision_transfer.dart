import 'dart:typed_data';

import 'identifiers.dart';
import 'public_models.dart';
import 'source_descriptor.dart';

/// Durable local Workspace identity and recovery incarnation, without accounts.
final class WorkspaceIdentity {
  WorkspaceIdentity({
    required this.workspaceId,
    required this.recoveryIncarnation,
  }) {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    if (workspaceId.length != 36 ||
        recoveryIncarnation.length != 36 ||
        !uuid.hasMatch(workspaceId) ||
        !uuid.hasMatch(recoveryIncarnation)) {
      throw ArgumentError('Invalid Workspace identity.');
    }
  }
  final String workspaceId;
  final String recoveryIncarnation;
  @override
  bool operator ==(Object other) =>
      other is WorkspaceIdentity &&
      other.workspaceId == workspaceId &&
      other.recoveryIncarnation == recoveryIncarnation;
  @override
  int get hashCode => Object.hash(workspaceId, recoveryIncarnation);
}

/// A coherent full-scope read under local writer/recovery coordination.
/// Absence is usable only when all three proof flags are true and the consumer
/// independently matches Workspace/account/sync scope. A snapshot alone is not
/// deletion evidence. Recovery changes the incarnation even at the same path.
final class AuthoritativeWorkspaceCapture {
  const AuthoritativeWorkspaceCapture({
    required this.identity,
    required this.snapshot,
    required this.recoveryComplete,
    required this.finalizationComplete,
    required this.isComplete,
    this.localLineageFingerprints = const {},
  });
  final WorkspaceIdentity identity;
  final RepositorySnapshot snapshot;
  final bool recoveryComplete;
  final bool finalizationComplete;
  final bool isComplete;
  final Map<ManagedSkillId, String> localLineageFingerprints;
}

final class CaptureAuthoritativeStateRequest {
  const CaptureAuthoritativeStateRequest();
}

/// Opaque, content-addressed revision identity for transfer preconditions.
///
/// This fingerprint is not a Git object ID or a content hash of the Skill tree.
final class CommittedRevisionReference {
  CommittedRevisionReference(this.fingerprint) {
    if (fingerprint.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      throw ArgumentError('Invalid revision fingerprint.');
    }
  }
  final String fingerprint;

  @override
  bool operator ==(Object other) =>
      other is CommittedRevisionReference && other.fingerprint == fingerprint;
  @override
  int get hashCode => fingerprint.hashCode;
}

/// Receiver-issued local binding; contains no Cloud event/account identity.
final class IncomingRevisionCommandBinding {
  const IncomingRevisionCommandBinding({
    required this.operationId,
    required this.requestFingerprint,
    required this.targetManagedSkillId,
    required this.localLineageFingerprint,
    required this.expectedIdentity,
    this.previousLocalLineageFingerprint,
    this.previousEffectiveReference,
  });
  final OperationId operationId;
  final String requestFingerprint;
  final ManagedSkillId targetManagedSkillId;
  final String localLineageFingerprint;
  final WorkspaceIdentity expectedIdentity;
  final String? previousLocalLineageFingerprint;
  final CommittedRevisionReference? previousEffectiveReference;
}

/// A published/restorable event descriptor; never a local Operation Record.
final class CommittedRevisionHistoryDescriptor {
  const CommittedRevisionHistoryDescriptor({
    required this.eventFingerprint,
    required this.revision,
    required this.kind,
    required this.contentHash,
    required this.publishedAt,
  });
  final String eventFingerprint;
  final CommittedRevisionReference revision;
  final WorkspaceOperationKind kind;
  final String contentHash;
  final DateTime publishedAt;
}

/// Immutable, short-lived in-memory transfer data.
///
/// The versioned wire manifest and object payloads are separate. Callers may
/// forward the opaque manifest without interpreting storage details. No path,
/// credential or account state is exposed. Workspace-owned disk artifacts are
/// removed before export completes; this is not a persistent network lease.
final class CommittedRevisionBatch {
  CommittedRevisionBatch({
    required this.identity,
    required this.source,
    required this.slotKey,
    required this.contentHash,
    required this.currentUpstream,
    required this.currentEffective,
    required List<CommittedRevisionHistoryDescriptor> publishedHistory,
    required this.packSha256,
    required this.indexSha256,
    this.localCommand,
    required List<int> wireManifest,
    required List<int> packBytes,
    required List<int> indexBytes,
  }) : publishedHistory = List.unmodifiable(publishedHistory),
       wireManifest = Uint8List.fromList(wireManifest).asUnmodifiableView(),
       packBytes = Uint8List.fromList(packBytes).asUnmodifiableView(),
       indexBytes = Uint8List.fromList(indexBytes).asUnmodifiableView();
  final WorkspaceIdentity identity;
  final SourceDescriptor source;
  final String slotKey;
  final String contentHash;
  final CommittedRevisionReference currentUpstream;
  final CommittedRevisionReference currentEffective;
  final List<CommittedRevisionHistoryDescriptor> publishedHistory;
  final IncomingRevisionCommandBinding? localCommand;
  final String packSha256;
  final String indexSha256;
  final Uint8List wireManifest;
  final Uint8List packBytes;
  final Uint8List indexBytes;
}

final class ExportCommittedRevisionRequest {
  const ExportCommittedRevisionRequest({
    required this.managedSkillId,
    required this.expectedRevision,
    this.maximumBytes = 64 * 1024 * 1024,
  });
  final ManagedSkillId managedSkillId;
  final RepositoryRevision expectedRevision;
  final int maximumBytes;
}

/// Builds an incoming local batch from a server content manifest and raw pack.
/// Network work completes before this bounded, short-lived owned staging step.
final class PrepareIncomingRevisionRequest {
  PrepareIncomingRevisionRequest({
    this.managedSkillId,
    this.localOperationId,
    this.replaceExistingLineage = false,
    required this.expectedIdentity,
    required this.expectedRevision,
    required List<int> contentManifest,
    required List<int> packBytes,
  }) : contentManifest = Uint8List.fromList(
         contentManifest,
       ).asUnmodifiableView(),
       packBytes = Uint8List.fromList(packBytes).asUnmodifiableView();
  final ManagedSkillId? managedSkillId;
  final OperationId? localOperationId;
  final bool replaceExistingLineage;
  final WorkspaceIdentity expectedIdentity;
  final RepositoryRevision expectedRevision;
  final Uint8List contentManifest;
  final Uint8List packBytes;
}

final class ApplyIncomingRevisionRequest {
  const ApplyIncomingRevisionRequest({
    required this.managedSkillId,
    required this.expectedRevision,
    required this.expectedIdentity,
    required this.expectedEffective,
    required this.incoming,
  });
  final ManagedSkillId managedSkillId;
  final RepositoryRevision expectedRevision;
  final WorkspaceIdentity expectedIdentity;
  final CommittedRevisionReference expectedEffective;
  final CommittedRevisionBatch incoming;
}

final class InstallIncomingRevisionRequest {
  const InstallIncomingRevisionRequest({
    required this.expectedIdentity,
    required this.expectedRevision,
    required this.incoming,
  });
  final WorkspaceIdentity expectedIdentity;
  final RepositoryRevision expectedRevision;
  final CommittedRevisionBatch incoming;
}

final class ReplaceIncomingRevisionRequest {
  const ReplaceIncomingRevisionRequest({
    required this.managedSkillId,
    required this.expectedIdentity,
    required this.expectedRevision,
    required this.expectedLocalLineageFingerprint,
    required this.expectedEffective,
    required this.incoming,
  });
  final ManagedSkillId managedSkillId;
  final WorkspaceIdentity expectedIdentity;
  final RepositoryRevision expectedRevision;
  final String expectedLocalLineageFingerprint;
  final CommittedRevisionReference expectedEffective;
  final CommittedRevisionBatch incoming;
}

enum IncomingRevisionOutcomeStatus {
  confirmedNotStarted,
  rolledBack,
  inProgress,
  committedFinalizationPending,
  applied,
  targetAbsent,
  superseded,
  unknown,
  conflict,
}

final class IncomingRevisionOutcome {
  const IncomingRevisionOutcome({
    required this.status,
    required this.binding,
    this.capture,
    this.committedRevision,
  });
  final IncomingRevisionOutcomeStatus status;
  final IncomingRevisionCommandBinding binding;
  final AuthoritativeWorkspaceCapture? capture;
  final RepositoryRevision? committedRevision;
}

final class InspectIncomingRevisionOutcomeRequest {
  const InspectIncomingRevisionOutcomeRequest({required this.binding});
  final IncomingRevisionCommandBinding binding;
}

final class IncomingRevisionReplayed extends IncomingRevisionApplyResult {
  const IncomingRevisionReplayed(this.proof);
  final IncomingRevisionOutcome proof;
}

enum IncomingRevisionPendingReason {
  skillNotFound,
  stale,
  dirtyDraft,
  existingSession,
  diverged,
  sourceMismatch,
  slotMismatch,
  invalidPayload,
  invalidSkill,
  limitExceeded,
  baselineMismatch,
  historyRetentionRequired,
  slotConflict,
}

sealed class IncomingRevisionApplyResult {
  const IncomingRevisionApplyResult();
}

final class IncomingRevisionApplied extends IncomingRevisionApplyResult {
  const IncomingRevisionApplied(this.report);
  final MutationReport report;
}

final class IncomingRevisionInstalled extends IncomingRevisionApplyResult {
  const IncomingRevisionInstalled({
    required this.managedSkillId,
    required this.report,
  });
  final ManagedSkillId managedSkillId;
  final MutationReport report;
}

/// Proves only the currently selected target state, not prior operation success.
final class IncomingRevisionUnchanged extends IncomingRevisionApplyResult {
  const IncomingRevisionUnchanged(this.snapshot);
  final RepositorySnapshot snapshot;
}

final class IncomingRevisionPending extends IncomingRevisionApplyResult {
  const IncomingRevisionPending(this.reason);
  final IncomingRevisionPendingReason reason;
}
