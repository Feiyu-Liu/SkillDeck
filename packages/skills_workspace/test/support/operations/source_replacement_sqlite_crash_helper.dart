import 'destructive_sqlite_crash_harness.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    throw ArgumentError('Expected workspace root and crash point.');
  }
  await runSourceReplacementSqliteCrashChild(
    workspaceRoot: arguments[0],
    crashPoint: DestructiveSqliteCrashPoint.values.byName(arguments[1]),
  );
}
