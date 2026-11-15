import '../cancellation.dart';
import 'models.dart';

/// An opaque incoming handle whose ownership/verification belongs to an adapter.
abstract interface class CloudIncomingHandle {
  /// The prepared target identity, including a receiver-minted new-install ID.
  String? get localTargetId;
  String? get workspaceRequestFingerprint;
  String? get localLineageFingerprint;

  /// Releases bounded temporary bytes, even when apply is cancelled or pending.
  Future<void> dispose();
}

/// Receiver-prepared initial content work targeting a Skill that already existed.
abstract interface class CloudInitialExistingIncomingHandle
    implements CloudIncomingHandle {
  bool get preexistingTarget;
}

/// A proof bound to the exact staged event and authoritative Workspace result.
sealed class CloudApplyResult {
  const CloudApplyResult();
}

/// A caller-bound application proof, not an inference from equal content hashes.
final class CloudApplied extends CloudApplyResult {
  const CloudApplied({
    required this.eventKey,
    required this.operationId,
    required this.desiredFingerprint,
    required this.capture,
    required this.localSkillId,
    required this.proofId,
  });
  final String operationId, desiredFingerprint;
  final String eventKey, localSkillId, proofId;
  final CloudWorkspaceCapture capture;
}

/// A fresh initial snapshot whose desired content already exists locally.
/// This proves desired state only; it never claims an operation executed.
final class CloudStateAlreadySatisfied extends CloudApplyResult {
  const CloudStateAlreadySatisfied({
    required this.eventKey,
    required this.operationId,
    required this.desiredFingerprint,
    required this.capture,
    required this.localSkillId,
    required this.localLineageFingerprint,
    required this.proofId,
  });
  final String eventKey,
      operationId,
      desiredFingerprint,
      localSkillId,
      localLineageFingerprint,
      proofId;
  final CloudWorkspaceCapture capture;
}

/// A target absence proof including completed destructive cleanup.
final class CloudTargetAbsent extends CloudApplyResult {
  const CloudTargetAbsent({
    required this.eventKey,
    required this.operationId,
    required this.desiredFingerprint,
    required this.capture,
    required this.localSkillId,
    required this.cleanupComplete,
    required this.proofId,
  });
  final String operationId, desiredFingerprint;
  final String eventKey, localSkillId, proofId;
  final CloudWorkspaceCapture capture;
  final bool cleanupComplete;
}

/// A proof that later local lifecycle work retired this exact prior lineage.
final class CloudSuperseded extends CloudApplyResult {
  const CloudSuperseded({
    required this.eventKey,
    required this.operationId,
    required this.desiredFingerprint,
    required this.capture,
    required this.localSkillId,
    required this.retiredGeneration,
    required this.proofId,
  });
  final String operationId, desiredFingerprint;
  final String eventKey, localSkillId, proofId;
  final int retiredGeneration;
  final CloudWorkspaceCapture capture;
}

/// A safe pending result that never publishes, overwrites or fabricates success.
final class CloudApplyPending extends CloudApplyResult {
  const CloudApplyPending(this.reason);
  final CloudPendingReason reason;
}

/// The trusted App seam; implementations use only public Workspace operations.
abstract interface class CloudWorkspacePort {
  Future<CloudWorkspaceCapture> capture();
  Future<CloudIncomingHandle> prepareIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  });

  /// Reserves a caller-bound metadata/lifecycle command without applying it.
  Future<CloudIncomingHandle> prepareStateChange({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  });
  Future<CloudApplyResult> applyIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  });

  /// Applies metadata/vocabulary atomically only when its public seam can prove it.
  Future<CloudApplyResult> applyMetadata({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  });

  /// Applies a lifecycle intent only through a proven local transaction.
  Future<CloudApplyResult> applyLifecycle({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  });

  /// Resolves a caller-bound unknown outcome without blindly applying again.
  Future<CloudApplyResult> resolveOutcome({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  });
}

/// An affirmative caller-bound proof that the local operation never started.
final class CloudConfirmedNotStarted extends CloudApplyResult {
  const CloudConfirmedNotStarted({
    required this.eventKey,
    required this.operationId,
    required this.proofId,
    required this.capture,
  });
  final String eventKey, operationId, proofId;
  final CloudWorkspaceCapture capture;
}

/// An explicitly permitted repeat of the same guarded desired-absence request.
/// This does not claim that a prior operation never started.
final class CloudRetryDesiredRemovalAllowed extends CloudApplyResult {
  const CloudRetryDesiredRemovalAllowed({
    required this.eventKey,
    required this.operationId,
    required this.capture,
    required this.localTargetId,
    required this.localLineageFingerprint,
  });
  final String eventKey, operationId, localTargetId, localLineageFingerprint;
  final CloudWorkspaceCapture capture;
}
