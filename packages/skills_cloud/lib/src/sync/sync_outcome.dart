import '../api/cloud_result.dart';

sealed class SyncOutcome {
  const SyncOutcome();
}

final class SkillSynced extends SyncOutcome {
  const SkillSynced();
}

final class SkillDeviceOnly extends SyncOutcome {
  const SkillDeviceOnly();
}

final class SkillRemoved extends SyncOutcome {
  const SkillRemoved();
}

final class WaitingToUpload extends SyncOutcome {
  const WaitingToUpload();
}

enum AttentionReason {
  incomingDraft,
  syncMergeConflict,
  removedWithDraft,
  tooLarge,
  slotOccupied,
  missingAfterReset,
  sourceReplacedWithLocalChanges,
}

final class SyncNeedsAttention extends SyncOutcome {
  const SyncNeedsAttention(this.reason, {this.deviceName, this.occupant});
  final AttentionReason reason;
  final String? deviceName, occupant;
}

final class SyncAccountCondition extends SyncOutcome {
  const SyncAccountCondition(this.condition);
  final CloudApiError condition;
}
