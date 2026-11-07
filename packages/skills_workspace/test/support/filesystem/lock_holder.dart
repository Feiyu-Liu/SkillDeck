import 'dart:convert';
import 'dart:io';

import 'package:skills_workspace/src/platform/filesystem/workspace_file_lock.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: lock_holder.dart <lock-path> <shared|exclusive>');
    exitCode = 64;
    return;
  }
  final Future<void> Function() release;
  switch (arguments[1]) {
    case 'shared':
    case 'exclusive':
      final lock = WorkspaceFileLock(lockPath: arguments[0]);
      final lease = await lock.acquireMode(
        mode: arguments[1] == 'shared'
            ? FilesystemLockMode.shared
            : FilesystemLockMode.exclusive,
        waitPolicy: const FilesystemLockWaitPolicy.failFast(),
      );
      release = lease.release;
      break;
    default:
      stderr.writeln('invalid lock mode');
      exitCode = 64;
      return;
  }
  stdout.writeln('locked');
  await stdout.flush();
  await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  await release();
}
