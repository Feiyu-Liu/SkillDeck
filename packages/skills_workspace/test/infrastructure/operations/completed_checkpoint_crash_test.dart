import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_process.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../../support/operations/destructive_sqlite_crash_harness.dart';
import '../../support/process/direct_dart_process.dart';

void main() {
  for (final replacement in [false, true]) {
    for (final phase in [
      'beforeTerminal',
      'afterTerminal',
      'afterCleanup',
      'afterClean',
    ]) {
      test(
        '${replacement ? 'Replacement' : 'Removal'} survives $phase kill and primary corruption',
        () async {
          final root = await Directory.systemTemp.createTemp(
            'completed-checkpoint-crash-',
          );
          addTearDown(() async {
            if (Platform.isWindows) {
              await Process.run('attrib', [
                '-R',
                path.join(root.path, '*'),
                '/S',
                '/D',
              ]);
            } else {
              await Process.run('chmod', ['-R', 'u+w', root.path]);
            }
            await root.delete(recursive: true);
          });
          await _crash(
            root.path,
            replacement
                ? 'test/support/operations/source_replacement_sqlite_crash_helper.dart'
                : 'test/support/operations/destructive_sqlite_crash_helper.dart',
            ['beforeJournalCompletion'],
            () async {
              final marker = File(
                path.join(root.path, '.destructive-crash-ready'),
              );
              return await marker.exists() &&
                  await marker.readAsString() == 'beforeJournalCompletion';
            },
          );
          await _crash(
            root.path,
            'test/support/operations/completed_checkpoint_crash_helper.dart',
            [phase],
            () async => File(
              path.join(root.path, 'completed-checkpoint-$phase.marker'),
            ).exists(),
          );
          final primary = path.join(root.path, 'workspace.sqlite');
          final crashed = sqlite3.open(primary, mode: OpenMode.readOnly);
          final operationId =
              crashed
                      .select('SELECT operation_id FROM operation_journals')
                      .single['operation_id']!
                  as String;
          expect(
            crashed
                .select('SELECT phase FROM operation_journals')
                .single['phase'],
            'completed',
          );
          crashed.close();
          final evidence = Directory(
            path.join(root.path, 'recovery', operationId),
          );
          if (phase == 'beforeTerminal' || phase == 'afterTerminal') {
            expect(await evidence.exists(), isTrue);
          } else {
            expect(await evidence.exists(), isFalse);
          }
          // The independent checkpoint must recover even after live SQL is lost.
          await File(
            primary,
          ).writeAsString('corrupt fixture primary', flush: true);
          for (final suffix in ['-wal', '-shm']) {
            final sidecar = File('$primary$suffix');
            if (await sidecar.exists()) await sidecar.delete();
          }
          final recovered = await recoverDestructiveSqliteCrash(root.path);
          expect(recovered, isA<ControlPlanePrimaryRestored>());
          final database = sqlite3.open(primary, mode: OpenMode.readOnly);
          try {
            expect(
              database.select('SELECT * FROM operation_journals'),
              isEmpty,
            );
            expect(
              database.select('SELECT * FROM operation_journal_steps'),
              isEmpty,
            );
            expect(
              database.select('SELECT * FROM managed_skills').length,
              replacement ? 1 : 0,
            );
            expect(database.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            database.close();
          }
          final backupRoot = Directory(
            path.join(root.path, 'control-plane-backups'),
          );
          expect(
            await Directory(path.join(backupRoot.path, '0')).exists(),
            isFalse,
          );
          for (final entity
              in backupRoot.listSync(recursive: true).whereType<File>()) {
            final bytes = latin1.decode(await entity.readAsBytes());
            expect(bytes, isNot(contains(destructiveCrashLineageId)));
            expect(bytes, isNot(contains('a' * 40)));
            if (!replacement) {
              expect(bytes, isNot(contains(destructiveCrashSkillId)));
            }
            if (path.basename(entity.path) == 'workspace.sqlite') {
              final backup = sqlite3.open(entity.path, mode: OpenMode.readOnly);
              expect(
                backup.select('SELECT * FROM operation_journals'),
                isEmpty,
              );
              backup.close();
            }
          }
        },
        timeout: const Timeout(Duration(seconds: 90)),
      );
    }
  }
}

Future<void> _crash(
  String root,
  String script,
  List<String> args,
  Future<bool> Function() reached,
) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    directDartScriptArguments(script, [root, ...args]),
    environment: Platform.environment,
    includeParentEnvironment: false,
  );
  final errors = StringBuffer();
  final stderr = process.stderr.transform(utf8.decoder).listen(errors.write);
  final stdout = process.stdout.drain<void>();
  try {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!await reached()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Checkpoint helper did not reach its owned window. $errors');
      }
      final exited = await Future.any([
        process.exitCode.then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 20), () => false),
      ]);
      if (exited) fail('Checkpoint helper exited before its window. $errors');
    }
  } finally {
    await PlatformGitProcessTreeTerminator.current().terminate(process.pid);
    await process.exitCode.timeout(const Duration(seconds: 5));
    await stderr.cancel();
    await stdout;
  }
}
