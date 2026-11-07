import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/revision_content.dart';
import '../revision_store/revision_store_access_models.dart';

/// Reads the current Effective tree at one gate-protected Pointer
/// linearization point. This port deliberately exposes no Store paths,
/// or Revision object IDs to command handlers.
abstract interface class CurrentEffectiveRevisionContentPort {
  Future<NormalizedSkillTree> readCurrentEffective(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  });
}

/// SQLite-owned Pointer reads.
abstract interface class RevisionPointerReaderPort {
  Future<CurrentEffectiveRevisionSelection?> readCurrentEffective(
    ManagedSkillId managedSkillId,
  );
}

typedef RevisionStorePathResolver = String Function(ManagedSkillId skillId);
