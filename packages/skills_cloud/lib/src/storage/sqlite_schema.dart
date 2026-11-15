import 'package:sqlite3/sqlite3.dart';

import '../errors.dart';
import 'sync_schema.dart';

const cloudApplicationId = 1396982577;
const _columns = {
  'cloud_device_scope': ['origin', 'account_id', 'device_id', 'ready'],
  'cloud_workspace_scope': [
    'origin',
    'account_id',
    'device_id',
    'workspace_id',
    'ready',
  ],
  'cloud_operation': [
    'origin',
    'account_id',
    'device_id',
    'workspace_id',
    'operation_id',
    'version',
    'family',
    'origin_utc',
    'observed_utc',
    'phases',
    'upload_id',
  ],
};
int _application(Database db) =>
    db.select('PRAGMA application_id').single.values.single as int;
List<String> _objects(Database db) => db
    .select("SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'")
    .map((row) => row['name'] as String)
    .toList();
bool _newEmpty(Database db) =>
    _application(db) == 0 && db.userVersion == 0 && _objects(db).isEmpty;
void _identified(Database db, {required int version}) {
  final columns = {..._columns, if (version == 2) ...syncSchemaColumns};
  if (_application(db) != cloudApplicationId ||
      db.userVersion != version ||
      _objects(db).toSet().difference(columns.keys.toSet()).isNotEmpty) {
    throw const CloudException(CloudErrorCode.needsReconciliation);
  }
  for (final table in columns.entries) {
    final info = db.select('PRAGMA table_info(${table.key})');
    if (info.length != table.value.length ||
        !info.indexed.every(
          (entry) => entry.$2['name'] == table.value[entry.$1],
        )) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final keys = info
        .where((row) => (row['pk'] as int) > 0)
        .map((row) => row['name'])
        .toList();
    final expected =
        syncSchemaPrimaryKeys[table.key] ??
        (table.key == 'cloud_operation'
            ? <String>['origin', 'account_id', 'operation_id']
            : table.value
                  .take(table.key == 'cloud_workspace_scope' ? 4 : 3)
                  .toList());
    if (keys.length != expected.length ||
        !keys.indexed.every((entry) => entry.$2 == expected[entry.$1])) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }
}

/// Validates a recognized existing database without schema writes.
void verifyCloudSchemaReadOnly(Database database) =>
    _identified(database, version: 2);

/// Initializes only a brand-new empty database, with all schema stamps atomic.
///
/// Internal entry point also permits real SQLITE_FULL fault qualification in
/// tests without adding a production failure-injection option.
void initializeCloudSchema(Database database) {
  if (!_newEmpty(database)) {
    if (database.userVersion == 2) {
      _identified(database, version: 2);
      return;
    }
    _identified(database, version: 1);
  }
  var active = false;
  try {
    database.execute('BEGIN IMMEDIATE');
    active = true;
    if (database.userVersion == 2) {
      _identified(database, version: 2);
      database.execute('COMMIT');
      return;
    }
    if (_newEmpty(database)) {
      database.execute("""
        CREATE TABLE cloud_device_scope(origin TEXT NOT NULL,account_id TEXT NOT NULL,device_id TEXT NOT NULL,ready INTEGER NOT NULL,PRIMARY KEY(origin,account_id,device_id));
        CREATE TABLE cloud_workspace_scope(origin TEXT NOT NULL,account_id TEXT NOT NULL,device_id TEXT NOT NULL,workspace_id TEXT NOT NULL,ready INTEGER NOT NULL,PRIMARY KEY(origin,account_id,device_id,workspace_id));
        CREATE TABLE cloud_operation(origin TEXT NOT NULL,account_id TEXT NOT NULL,device_id TEXT NOT NULL,workspace_id TEXT NOT NULL,operation_id TEXT NOT NULL,version INTEGER NOT NULL,family TEXT NOT NULL,origin_utc TEXT,observed_utc TEXT,phases TEXT NOT NULL,upload_id TEXT,PRIMARY KEY(origin,account_id,operation_id));
        PRAGMA application_id=1396982577;
        PRAGMA user_version=1;
      """);
    }
    _identified(database, version: 1);
    database.execute(syncSchemaSQL);
    database.execute('PRAGMA user_version=2');
    _identified(database, version: 2);
    database.execute('COMMIT');
    active = false;
  } catch (_) {
    if (active) {
      try {
        database.execute('ROLLBACK');
      } catch (_) {}
    }
    throw const CloudException(CloudErrorCode.needsReconciliation);
  }
}
