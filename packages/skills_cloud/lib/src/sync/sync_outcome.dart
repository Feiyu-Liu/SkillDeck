import '../api/cloud_result.dart';
import '../api/metadata_values.dart';

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
  const WaitingToUpload({this.retryAfter});
  final Duration? retryAfter;
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

enum MetadataAttentionReason { noteConflict, noteTooLarge }

final class SyncMetadataAttention {
  const SyncMetadataAttention(
    this.reason, {
    this.note,
    this.localNote,
    this.hasUnsubmittedLocalNote = false,
  });
  final MetadataAttentionReason reason;
  final CloudNote? note;
  final String? localNote;
  final bool hasUnsubmittedLocalNote;
}
