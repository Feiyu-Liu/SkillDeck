import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../process/direct_dart_process.dart';

Future<void> crashRemoteApply(
  List<String> arguments, {
  required bool committed,
}) async {
  final helper = await Process.start(
    Platform.resolvedExecutable,
    directDartScriptArguments(
      'test/support/operations/remote_content_crash_helper.dart',
      [...arguments, committed ? 'afterCommit' : 'beforeCommit'],
    ),
  );
  final output = [helper.stdout.drain<void>(), helper.stderr.drain<void>()];
  final code = await helper.exitCode.timeout(
    const Duration(seconds: 60),
    onTimeout: () {
      helper.kill();
      throw StateError('The remote apply crash point was not reached in time.');
    },
  );
  await Future.wait(output);
  expect(code, committed ? 72 : 71);
}

Map<String, List<Map<String, Object?>>> readOperationDatabaseRows(
  String databasePath,
) {
  final database = sqlite3.open(databasePath, mode: OpenMode.readOnly);
  try {
    final tables = database.select(
      "SELECT name FROM sqlite_schema WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    );
    return {
      for (final {'name': name as String} in tables)
        name: database
            .select('SELECT * FROM "$name" ORDER BY rowid')
            .map((row) => Map<String, Object?>.of(row))
            .toList(),
    };
  } finally {
    database.close();
  }
}
