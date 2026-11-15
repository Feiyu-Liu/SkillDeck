import 'destructive_sqlite_crash_harness.dart';

Future<void> main(List<String> args) =>
    recoverDestructiveAtCompletedCheckpoint(args[0], args[1]);
