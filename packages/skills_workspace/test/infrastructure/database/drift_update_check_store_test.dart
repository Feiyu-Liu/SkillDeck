import 'package:drift/native.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_update_check_store.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:test/test.dart';

void main() {
  late WorkspaceDatabase database;
  late DriftUpdateCheckStore store;

  setUp(() async {
    database = WorkspaceDatabase.forTesting(NativeDatabase.memory());
    store = DriftUpdateCheckStore(database);
    await database.select(database.skillUpdateCheckMetadata).getSingle();
  });

  tearDown(() => database.close());

  test('persists and reads the full-sweep timestamp', () async {
    final timestamp = DateTime.utc(2026, 9, 18, 10, 30);

    await store.writeLastFullSweepAt(timestamp);

    final snapshot = await store.read();
    expect(snapshot.records, isEmpty);
    expect(snapshot.lastFullSweepAt, timestamp);
  });

  test('a missing metadata row is recreated safely', () async {
    await database.delete(database.skillUpdateCheckMetadata).go();

    await store.writeLastFullSweepAt(DateTime.utc(2026, 9, 18));

    expect((await store.read()).lastFullSweepAt, DateTime.utc(2026, 9, 18));
  });
}
