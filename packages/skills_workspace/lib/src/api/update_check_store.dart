export '../domain/update_check_store.dart';

import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../domain/update_check_store.dart';

final class InMemoryUpdateCheckStore implements UpdateCheckStore {
  final Map<ManagedSkillId, UpdateCheckRecord> _records = {};
  DateTime? _lastFullSweepAt;

  @override
  Future<UpdateCheckCacheSnapshot> read() async => UpdateCheckCacheSnapshot(
    records: _records.values.toList(growable: false),
    lastFullSweepAt: _lastFullSweepAt,
  );

  @override
  Future<void> upsert(UpdateCheckRecord record) async {
    _records[record.managedSkillId] = record;
  }

  @override
  Future<void> remove(ManagedSkillId managedSkillId) async {
    _records.remove(managedSkillId);
  }

  @override
  Future<void> writeLastFullSweepAt(DateTime value) async {
    _lastFullSweepAt = value.toUtc();
  }
}
