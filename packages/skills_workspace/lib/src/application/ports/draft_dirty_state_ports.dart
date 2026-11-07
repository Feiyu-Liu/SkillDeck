import '../../domain/cancellation.dart';
import '../../domain/public_models.dart';

sealed class DraftDirtyStateInspectionResult {
  const DraftDirtyStateInspectionResult();
}

final class DraftDirtyStateInspectionSuccess
    extends DraftDirtyStateInspectionResult {
  const DraftDirtyStateInspectionSuccess({required this.isDirty});

  final bool isDirty;
}

final class DraftDirtyStateInspectionFailure
    extends DraftDirtyStateInspectionResult {
  const DraftDirtyStateInspectionFailure(this.reason);

  final String reason;
}

/// Computes presentation dirty state from the complete normalized Draft and
/// its immutable Draft Base.
///
/// File-watcher events and previously projected [DraftSummary.isDirty] values
/// must never influence the result.
abstract interface class DraftDirtyStateInspectionPort {
  Future<DraftDirtyStateInspectionResult> inspectDraftDirtyState({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  });
}
