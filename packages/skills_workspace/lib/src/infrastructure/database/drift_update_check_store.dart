import 'package:drift/drift.dart';

import '../../domain/identifiers.dart';
import '../../domain/public_models.dart' as domain;
import '../../domain/update_check_store.dart';
import 'workspace_database.dart';

final class DriftUpdateCheckStore implements UpdateCheckStore {
  const DriftUpdateCheckStore(this._database);

  final WorkspaceDatabase _database;

  @override
  Future<domain.UpdateCheckCacheSnapshot> read() async {
    final rows = await _database
        .select(_database.skillUpdateCheckRecords)
        .get();
    final metadata = await _database
        .select(_database.skillUpdateCheckMetadata)
        .getSingleOrNull();
    return domain.UpdateCheckCacheSnapshot(
      records: [for (final row in rows) _recordFromRow(row)],
      lastFullSweepAt: metadata?.lastFullSweepAtMicros == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(
              metadata!.lastFullSweepAtMicros!,
              isUtc: true,
            ),
    );
  }

  @override
  Future<void> upsert(domain.UpdateCheckRecord record) => _database
      .into(_database.skillUpdateCheckRecords)
      .insertOnConflictUpdate(
        SkillUpdateCheckRecordsCompanion.insert(
          managedSkillId: record.managedSkillId.value,
          basisFingerprint: record.basisFingerprint,
          status: record.status.name,
          currentContentHash: Value(record.currentContentHash),
          availableContentHash: Value(record.availableContentHash),
          resolvedSourceRevision: Value(record.resolvedSourceRevision),
          checkedAtMicros: record.checkedAt.toUtc().microsecondsSinceEpoch,
        ),
      );

  @override
  Future<void> remove(ManagedSkillId managedSkillId) => (_database.delete(
    _database.skillUpdateCheckRecords,
  )..where((row) => row.managedSkillId.equals(managedSkillId.value))).go();

  @override
  Future<void> writeLastFullSweepAt(DateTime value) async {
    final micros = value.toUtc().microsecondsSinceEpoch;
    final changed =
        await (_database.update(
          _database.skillUpdateCheckMetadata,
        )..where((row) => row.singleton.equals(1))).write(
          SkillUpdateCheckMetadataCompanion(
            lastFullSweepAtMicros: Value(micros),
          ),
        );
    if (changed == 0) {
      await _database
          .into(_database.skillUpdateCheckMetadata)
          .insert(
            SkillUpdateCheckMetadataCompanion.insert(
              singleton: const Value(1),
              lastFullSweepAtMicros: Value(micros),
            ),
          );
    }
  }

  domain.UpdateCheckRecord _recordFromRow(SkillUpdateCheckRecord row) =>
      domain.UpdateCheckRecord(
        managedSkillId: ManagedSkillId(row.managedSkillId),
        basisFingerprint: row.basisFingerprint,
        status: _status(row.status),
        currentContentHash: row.currentContentHash,
        availableContentHash: row.availableContentHash,
        resolvedSourceRevision: row.resolvedSourceRevision,
        checkedAt: DateTime.fromMicrosecondsSinceEpoch(
          row.checkedAtMicros,
          isUtc: true,
        ),
      );

  domain.UpdateStatus _status(String value) => switch (value) {
    'current' => domain.UpdateStatus.current,
    'updateAvailable' => domain.UpdateStatus.updateAvailable,
    'sourceUnavailable' => domain.UpdateStatus.sourceUnavailable,
    'updateUnsupported' => domain.UpdateStatus.updateUnsupported,
    'resolutionRequired' => domain.UpdateStatus.resolutionRequired,
    _ => throw StateError('Unsupported persisted update status: $value'),
  };
}
