import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/data/services/directory_picker.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

final rawSkillsWorkspaceRepositoryProvider =
    Provider<SkillsWorkspaceRepository>((ref) {
      throw UnimplementedError(
        'A raw SkillsWorkspaceRepository override is required.',
      );
    });

final skillsWorkspaceRepositoryProvider = Provider<SkillsWorkspaceRepository>((
  ref,
) {
  throw UnimplementedError('A SkillsWorkspaceRepository override is required.');
});

final skillsUpdateCheckStoreProvider = Provider<SkillsUpdateCheckStore>((ref) {
  final repository = ref.watch(skillsWorkspaceRepositoryProvider);
  if (repository case final SkillsUpdateCheckStore store) return store;
  return InMemorySkillsUpdateCheckStore();
});

final class InMemorySkillsUpdateCheckStore implements SkillsUpdateCheckStore {
  final Map<WorkspaceSkillId, WorkspaceUpdateCacheRecord> _records = {};
  DateTime? _lastFullSweepAt;

  @override
  Future<WorkspaceUpdateCacheSnapshot> readUpdateCache() async =>
      WorkspaceUpdateCacheSnapshot(
        records: _records.values.toList(growable: false),
        lastFullSweepAt: _lastFullSweepAt,
      );

  @override
  Future<void> upsertUpdateCache(WorkspaceUpdateCacheRecord record) async {
    _records[record.skillId] = record;
  }

  @override
  Future<void> removeUpdateCache(WorkspaceSkillId skillId) async {
    _records.remove(skillId);
  }

  @override
  Future<void> writeLastFullUpdateSweepAt(DateTime value) async {
    _lastFullSweepAt = value.toUtc();
  }
}

final directoryPickerProvider = Provider<DirectoryPicker>(
  (ref) => NativeDirectoryPicker(),
);

final skillBrowserRepositoryProvider = Provider<SkillBrowserRepository>((ref) {
  throw UnimplementedError('A SkillBrowserRepository override is required.');
});

final skillAcquisitionRepositoryProvider =
    Provider<SkillAcquisitionRepository?>((ref) => null);
