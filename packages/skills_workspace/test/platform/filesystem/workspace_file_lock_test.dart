import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/platform/filesystem/workspace_file_lock.dart';
import 'package:test/test.dart';

import '../../support/process/direct_dart_process.dart';

void main() {
  late Directory temporary;
  late String lockPath;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-file-lock-',
    );
    lockPath = path.join(temporary.path, 'locks', 'workspace.lock');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'Workspace Writer Lock is exclusive and releases idempotently',
    () async {
      final first = WorkspaceFileLock(lockPath: lockPath);
      final samePath = WorkspaceFileLock(
        lockPath: path.join(
          temporary.path,
          'locks',
          'nested',
          '..',
          'workspace.lock',
        ),
      );
      final held = await first.acquire();

      await expectLater(
        samePath.acquire(),
        throwsA(
          isA<FilesystemLockException>().having(
            (error) => error.failure,
            'failure',
            FilesystemLockFailure.busy,
          ),
        ),
      );

      await held.release();
      await held.release();
      final acquired = await samePath.acquire();
      await acquired.release();
    },
  );

  test('wait policy times out and observes cancellation', () async {
    final lock = WorkspaceFileLock(lockPath: lockPath);
    final held = await lock.acquire();

    await expectLater(
      lock.acquireMode(
        mode: FilesystemLockMode.exclusive,
        waitPolicy: FilesystemLockWaitPolicy.wait(
          timeout: const Duration(milliseconds: 20),
          pollInterval: const Duration(milliseconds: 2),
        ),
      ),
      throwsA(
        isA<FilesystemLockException>().having(
          (error) => error.failure,
          'failure',
          FilesystemLockFailure.busy,
        ),
      ),
    );

    var cancelled = false;
    final waiting = lock.acquireMode(
      mode: FilesystemLockMode.exclusive,
      waitPolicy: FilesystemLockWaitPolicy.wait(
        pollInterval: const Duration(milliseconds: 2),
      ),
      isCancelled: () => cancelled,
    );
    cancelled = true;
    await expectLater(
      waiting,
      throwsA(
        isA<FilesystemLockException>().having(
          (error) => error.failure,
          'failure',
          FilesystemLockFailure.cancelled,
        ),
      ),
    );
    await held.release();
  });

  test(
    'Workspace lock contends across processes and recovers after kill',
    () async {
      final child = await Process.start(
        Platform.resolvedExecutable,
        directDartScriptArguments('test/support/filesystem/lock_holder.dart', [
          lockPath,
          'exclusive',
        ]),
        workingDirectory: Directory.current.path,
      );
      addTearDown(() async {
        child.kill();
        await child.exitCode;
      });
      final lockedLine = await child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.trim().endsWith('locked'))
          .timeout(const Duration(seconds: 30));
      expect(lockedLine.trim(), endsWith('locked'));

      final lock = WorkspaceFileLock(lockPath: lockPath);
      await expectLater(
        lock.acquire(),
        throwsA(
          isA<FilesystemLockException>().having(
            (error) => error.failure,
            'failure',
            FilesystemLockFailure.busy,
          ),
        ),
      );

      child.kill();
      await child.exitCode;
      final recovered = await lock.acquireMode(
        mode: FilesystemLockMode.exclusive,
        waitPolicy: FilesystemLockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
          pollInterval: const Duration(milliseconds: 10),
        ),
      );
      await recovered.release();
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
