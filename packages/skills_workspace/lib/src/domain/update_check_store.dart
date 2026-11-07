import 'identifiers.dart';
import 'public_models.dart';

/// Durable cache for the last successful update check of each managed Skill.
///
/// These records are deliberately outside [RepositorySnapshot]: they describe
/// an external observation, not a Workspace business mutation.
abstract interface class UpdateCheckStore {
  Future<UpdateCheckCacheSnapshot> read();

  Future<void> upsert(UpdateCheckRecord record);

  Future<void> remove(ManagedSkillId managedSkillId);

  Future<void> writeLastFullSweepAt(DateTime value);
}
