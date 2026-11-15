import '../protocol/codec.dart';
import '../protocol/models.dart';
import '../protocol/content_manifest.dart';
import '../http/transport.dart';

/// The authoritative local Workspace identity, never inferred from a path.
final class CloudWorkspaceIdentity {
  const CloudWorkspaceIdentity({
    required this.workspaceId,
    required this.recoveryIncarnation,
  });
  final String workspaceId;
  final String recoveryIncarnation;
  @override
  bool operator ==(Object other) =>
      other is CloudWorkspaceIdentity &&
      workspaceId == other.workspaceId &&
      recoveryIncarnation == other.recoveryIncarnation;
  @override
  int get hashCode => Object.hash(workspaceId, recoveryIncarnation);
  @override
  String toString() => 'CloudWorkspaceIdentity([redacted])';
}

/// A ready authoritative capture supplied by the trusted Workspace adapter.
final class CloudWorkspaceCapture {
  const CloudWorkspaceCapture({
    required this.identity,
    required this.revision,
    required this.recoveryComplete,
    required this.finalizationComplete,
    required this.isComplete,
    this.localLineageFingerprints = const {},
  });
  final CloudWorkspaceIdentity identity;
  final String revision;
  final bool recoveryComplete, finalizationComplete, isComplete;
  final Map<String, String> localLineageFingerprints;
  bool get ready => recoveryComplete && finalizationComplete && isComplete;
  @override
  String toString() => 'CloudWorkspaceCapture(ready: $ready, [redacted])';
}

/// The immutable account/device/Workspace namespace for a synchronization scope.
final class CloudSyncScope {
  CloudSyncScope({
    required this.accountId,
    required this.deviceId,
    required this.workspaceIdentity,
  }) {
    identifier(accountId);
    identifier(deviceId);
    identifier(workspaceIdentity.workspaceId);
    identifier(workspaceIdentity.recoveryIncarnation);
  }
  final String accountId, deviceId;
  final CloudWorkspaceIdentity workspaceIdentity;
  @override
  String toString() => 'CloudSyncScope([redacted])';
}

/// Explicit user consent to selected Skills; global personal tags are vocabulary.
final class CloudSyncSelection {
  CloudSyncSelection({
    Set<String> cloudLineageIds = const {},
    Set<String> localSkillIds = const {},
  }) : cloudLineageIds = Set.unmodifiable(cloudLineageIds),
       localSkillIds = Set.unmodifiable(localSkillIds) {
    for (final id in [...cloudLineageIds, ...localSkillIds]) {
      identifier(id);
    }
  }
  final Set<String> cloudLineageIds, localSkillIds;
  bool get isEmpty => cloudLineageIds.isEmpty && localSkillIds.isEmpty;
}

/// Why a durable inbox item remains unapplied.
enum CloudPendingReason {
  dirtyDraft,
  divergence,
  unknownOutcome,
  metadataProofUnavailable,
  unsupportedReplacement,
  needsReconciliation,
  unavailable,
  selectionRequired,
  needsReupload,
  nameConflict,
  unsupportedNormalization,
  desiredRemovalRetry,
  receiptConflict,
  metadataConflict,
}

/// Received/applied progress; advancing reception never implies local mutation.
final class CloudSyncProgress {
  CloudSyncProgress({
    required this.scope,
    required this.expectedRevision,
    required this.received,
    required this.applied,
    required this.needsReconciliation,
    this.isEnabled = true,
    required this.pendingCount,
    required this.selection,
    this.snapshotId,
    this.snapshotCursor,
    this.snapshotHighWatermark,
    this.traversalHighWatermark,
  });
  final CloudSyncScope scope;
  final String expectedRevision;
  final CloudSequence received, applied;
  final bool needsReconciliation;
  final bool isEnabled;
  final int pendingCount;
  final CloudSyncSelection selection;
  final String? snapshotId, snapshotCursor;
  final CloudSequence? snapshotHighWatermark;

  /// The fixed bound while continuing a received changes traversal.
  final CloudSequence? traversalHighWatermark;
  @override
  String toString() =>
      'CloudSyncProgress(received: $received, applied: $applied, pending: $pendingCount)';
}

/// A durable event staged from a full page before any Workspace mutation.
final class CloudInboxItem {
  const CloudInboxItem({
    required this.id,
    required this.eventKey,
    required this.change,
    this.pendingReason,
  });
  final int id;
  final String eventKey;
  final CloudChange change;
  final CloudPendingReason? pendingReason;
  @override
  String toString() =>
      'CloudInboxItem(id: $id, kind: ${change.kind}, [redacted])';
}

/// A persistent local-skill relation that can be retired without resurrection.
final class CloudLineageMapping {
  const CloudLineageMapping({
    required this.lineageId,
    required this.generation,
    required this.localSkillId,
    required this.retired,
    required this.lastSequence,
    this.localLineageFingerprint,
  });
  final String lineageId, localSkillId;
  final int generation;
  final bool retired;
  final CloudSequence lastSequence;
  final String? localLineageFingerprint;
}

/// A candidate upload intention that does not transmit or publish automatically.
final class CloudOutboxCandidate {
  const CloudOutboxCandidate({
    required this.operationId,
    required this.localSkillId,
    required this.sourceLineageIdentity,
    required this.historyIdentity,
    required this.state,
    this.firstAttemptUtc,
  });
  final String operationId,
      localSkillId,
      sourceLineageIdentity,
      historyIdentity;
  final CloudOutboxState state;
  final DateTime? firstAttemptUtc;
  @override
  String toString() => 'CloudOutboxCandidate(state: ${state.name}, [redacted])';
}

enum CloudOutboxState { candidate, pending, needsReconciliation, retired }

/// A durable caller-bound local apply identity fixed before crossing a port.
final class CloudApplyBinding {
  const CloudApplyBinding({
    required this.operationId,
    required this.eventKey,
    required this.desiredFingerprint,
    this.localTargetId,
    this.workspaceRequestFingerprint,
    this.localLineageFingerprint,
    this.preexistingTarget,
  });
  final String operationId, eventKey, desiredFingerprint;
  final String? localTargetId;

  /// Receiver-computed command fingerprint, distinct from the remote event digest.
  final String? workspaceRequestFingerprint;
  final bool? preexistingTarget;

  /// Receiver-local lineage binding returned by the public preparation seam.
  final String? localLineageFingerprint;
  @override
  String toString() => 'CloudApplyBinding([redacted])';
}

/// A one-to-one Cloud vocabulary/local Personal Tag binding.
final class CloudPersonalTagMapping {
  const CloudPersonalTagMapping({
    required this.cloudTagId,
    required this.localTagId,
    required this.deleted,
    required this.name,
    this.color,
  });
  final String cloudTagId, localTagId, name;
  final String? color;
  final bool deleted;
}

/// Confirmed remote state used to detect only actual local field changes.
final class CloudPublisherBaseline {
  const CloudPublisherBaseline({
    required this.localSkillId,
    required this.lineageId,
    required this.generation,
    required this.localLineageFingerprint,
    required this.contentManifest,
    required this.favoriteKnown,
    required this.noteKnown,
    required this.favorite,
    required this.note,
    required this.localTagIds,
    required this.retired,
    this.initialLink = false,
  });
  final String localSkillId, lineageId, localLineageFingerprint;
  final int generation;
  final CloudContentManifest? contentManifest;
  final bool favoriteKnown, noteKnown, favorite, retired, initialLink;
  final String? note;
  final Set<String> localTagIds;
}

/// One stable outbound intent; current local edits never replace pending data.
final class CloudOutboundTask {
  CloudOutboundTask({
    required this.kind,
    required this.subjectId,
    required this.operationId,
    required Map<String, Object?> data,
    required Map<String, Object?> localContext,
    required this.acknowledged,
  }) : data = freezeMap(data),
       localContext = freezeMap(localContext);
  final String kind, subjectId, operationId;
  final Map<String, Object?> data, localContext;
  final bool acknowledged;
  @override
  String toString() =>
      'CloudOutboundTask(kind: $kind, acknowledged: $acknowledged, [redacted])';
}

/// Observed Cloud object availability; this never proves a local operation.
final class CloudIntegrityState {
  const CloudIntegrityState({
    required this.lineageId,
    required this.generation,
    required this.sequence,
    required this.status,
    required this.manifest,
  });
  final String lineageId;
  final int generation;
  final CloudSequence sequence;
  final CloudContentStatus status;
  final CloudContentManifest? manifest;
}
