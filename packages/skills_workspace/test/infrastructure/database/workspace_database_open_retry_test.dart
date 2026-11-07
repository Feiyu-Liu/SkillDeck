import 'package:skills_workspace/src/infrastructure/database/workspace_database_open_retry.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  test('retries bounded Windows WAL truncation failures synchronously', () {
    final delays = <Duration>[];
    var attempts = 0;
    final policy = WorkspaceDatabaseOpenRetryPolicy(
      isWindows: true,
      timeout: const Duration(milliseconds: 7),
      initialDelay: const Duration(milliseconds: 2),
      maximumDelay: const Duration(milliseconds: 4),
    );

    final result = policy.runSync(() {
      attempts += 1;
      if (attempts < 3) {
        throw _sqlite(sqlite.SqlExtendedError.SQLITE_IOERR_TRUNCATE);
      }
      return 'opened';
    }, sleeper: delays.add);

    expect(result, 'opened');
    expect(attempts, 3);
    expect(delays, const <Duration>[
      Duration(milliseconds: 2),
      Duration(milliseconds: 4),
    ]);
  });

  test('retries bounded Windows lock failures asynchronously', () async {
    final delays = <Duration>[];
    var attempts = 0;
    final policy = WorkspaceDatabaseOpenRetryPolicy(
      isWindows: true,
      timeout: const Duration(milliseconds: 3),
      initialDelay: const Duration(milliseconds: 1),
      maximumDelay: const Duration(milliseconds: 2),
    );

    await expectLater(
      policy.runAsync<void>(() async {
        attempts += 1;
        throw _sqlite(sqlite.SqlError.SQLITE_BUSY);
      }, sleeper: (delay) async => delays.add(delay)),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(attempts, 3);
    expect(delays, const <Duration>[
      Duration(milliseconds: 1),
      Duration(milliseconds: 2),
    ]);
  });

  test('does not retry non-Windows or non-transient SQLite failures', () {
    for (final policy in <WorkspaceDatabaseOpenRetryPolicy>[
      const WorkspaceDatabaseOpenRetryPolicy(isWindows: false),
      const WorkspaceDatabaseOpenRetryPolicy(isWindows: true),
    ]) {
      var attempts = 0;
      expect(
        () => policy.runSync<void>(() {
          attempts += 1;
          throw _sqlite(
            policy.isWindows
                ? sqlite.SqlError.SQLITE_CORRUPT
                : sqlite.SqlExtendedError.SQLITE_IOERR_TRUNCATE,
          );
        }),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(attempts, 1);
    }
  });
}

sqlite.SqliteException _sqlite(int code) => sqlite.SqliteException(
  extendedResultCode: code,
  message: 'injected SQLite open failure',
);
