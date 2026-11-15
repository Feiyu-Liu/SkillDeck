import '../protocol/codec.dart';
import '../protocol/models.dart';
import '../protocol/content_manifest.dart';
import 'models.dart';
import 'workspace_port.dart';

/// Durable scope, inbox, mapping and outbox state with no credential values.
abstract interface class CloudSyncStore {
  Future<void> initializeOptInScope({
    required CloudSyncScope scope,
    required CloudWorkspaceCapture capture,
    required CloudSyncSelection selection,
    required CloudSequence initialCursor,
  });
  Future<CloudOutboundTask> stageOutboundTask(
    CloudSyncScope scope, {
    required String kind,
    required String subjectId,
    required Map<String, Object?> data,
    required Map<String, Object?> localContext,
  });
  Future<List<CloudOutboundTask>> pendingOutboundTasks(CloudSyncScope scope);
  Future<CloudOutboundTask?> outboundTask(
    CloudSyncScope scope,
    String kind,
    String subjectId,
  );

  /// Atomically acknowledges original desired state, never a later local edit.
  Future<void> completeOutboundTask(
    CloudSyncScope scope,
    CloudOutboundTask task,
    Map<String, Object?> result,
    CloudWorkspaceCapture capture,
  );
  Future<void> setEnabled(CloudSyncScope scope, bool enabled);
  Future<CloudPublisherBaseline?> publisherBaseline(
    CloudSyncScope scope,
    String localSkillId,
  );
  Future<void> linkOutboundCommit(
    CloudSyncScope scope, {
    required String localSkillId,
    required String localLineageFingerprint,
    required CloudContentManifest manifest,
    required CloudCommitReceipt receipt,
    required CloudWorkspaceCapture capture,
  });
  Future<void> acknowledgeOutboundFields(
    CloudSyncScope scope,
    String localSkillId,
    Map<String, Object?> patch,
  );
  Future<void> bindOutboundPersonalTag(
    CloudSyncScope scope, {
    required String cloudTagId,
    required String localTagId,
    required String name,
    String? color,
  });
  Future<void> acknowledgeOutboundAssignment(
    CloudSyncScope scope, {
    required String localSkillId,
    required String localTagId,
    required bool assigned,
  });
  Future<void> acknowledgeOutboundRemoval(
    CloudSyncScope scope,
    String localSkillId,
  );
  Future<bool> hasPendingVocabulary(CloudSyncScope scope);
  Future<bool> hasPendingLineageConflict(
    CloudSyncScope scope,
    String lineageId,
  );
  Future<List<CloudIntegrityState>> integrityStates(CloudSyncScope scope);
  Future<CloudSyncProgress> progress(CloudSyncScope scope);
  Future<String> ensureSnapshotRequestKey(CloudSyncScope scope);
  Future<void> clearSnapshotRequestKey(
    CloudSyncScope scope,
    String expectedKey,
  );

  /// Updates only the monotonic revision baseline from an authoritative capture.
  Future<void> observeCapture(
    CloudSyncScope scope,
    CloudWorkspaceCapture capture,
  );

  /// Fixes an operation ID/fingerprint, then optionally binds a prepared target.
  Future<CloudApplyBinding> bindApplyIntent(
    CloudSyncScope scope,
    CloudInboxItem item, {
    String? localTargetId,
    String? workspaceRequestFingerprint,
    String? localLineageFingerprint,
    bool? preexistingTarget,
  });

  /// Clears an unknown boundary only with an affirmative not-started proof.
  Future<void> recordDesiredRemovalRetry(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudRetryDesiredRemovalAllowed proof,
  );
  Future<void> recordNotStarted(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudConfirmedNotStarted proof,
  );

  /// Stages a whole page and the received cursor in one SQLite transaction.
  Future<void> stageChangesPage(CloudSyncScope scope, CloudChangesPage page);

  /// Advances received to H only after every snapshot page is persisted.
  Future<void> stageSnapshotPage(CloudSyncScope scope, CloudSnapshotPage page);

  /// Discards only an expired, unapplied partial bootstrap staging set.
  Future<void> discardIncompleteSnapshot(
    CloudSyncScope scope,
    String snapshotId,
  );
  Future<List<CloudInboxItem>> pendingItems(
    CloudSyncScope scope, {
    int maximum = 100,
  });
  Future<List<CloudPersonalTagMapping>> personalTagMappings(
    CloudSyncScope scope,
  );
  Future<CloudPersonalTagMapping?> personalTagMapping(
    CloudSyncScope scope,
    String cloudTagId,
  );
  Future<CloudLineageMapping?> mapping(CloudSyncScope scope, String lineageId);
  Future<void> recordPending(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudPendingReason reason,
  );

  /// Records only exact event/identity proofs; this is not same-hash matching.
  Future<void> recordApplyProof(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudApplyResult proof,
  );
  Future<void> requireReconciliation(CloudSyncScope scope);
  Future<void> stageOutboxCandidate(
    CloudSyncScope scope,
    CloudOutboxCandidate candidate,
  );
  Future<List<CloudOutboxCandidate>> outboxCandidates(
    CloudSyncScope scope, {
    int maximum = 100,
  });
}
