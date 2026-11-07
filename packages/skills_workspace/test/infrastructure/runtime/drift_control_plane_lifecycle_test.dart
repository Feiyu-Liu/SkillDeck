import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/runtime/drift_control_plane_lifecycle.dart';
import 'package:test/test.dart';

void main() {
  test(
    'opens schema v3 once and closes the Drift executor idempotently',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'control-plane-lifecycle-',
      );
      final database = WorkspaceDatabase.forFile(
        File(path.join(temporary.path, 'workspace.sqlite')),
      );
      final lifecycle = DriftControlPlaneLifecycle(database);
      addTearDown(() async {
        await lifecycle.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      await lifecycle.open();
      await lifecycle.open();
      expect(lifecycle.isOpen, isTrue);
      expect((await database.liveIdentity()).repositoryRevision, 0);

      await lifecycle.close();
      await lifecycle.close();
      expect(lifecycle.isOpen, isFalse);
      await expectLater(lifecycle.open(), throwsStateError);
    },
  );

  test(
    'construction and direct close never create the background executor',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'control-plane-lazy-close-',
      );
      var executorCreations = 0;
      final database = WorkspaceDatabase.forFile(
        File(path.join(temporary.path, 'workspace.sqlite')),
        backgroundExecutorFactory: () {
          executorCreations += 1;
          return NativeDatabase.memory();
        },
      );
      final lifecycle = DriftControlPlaneLifecycle(database);
      addTearDown(() async {
        await lifecycle.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      expect(executorCreations, 0);

      await lifecycle.close();
      await lifecycle.close();

      expect(executorCreations, 0);
      await expectLater(lifecycle.open(), throwsStateError);
    },
  );

  test(
    'failed open closes the partially acquired executor exactly once',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'control-plane-failed-open-',
      );
      var executorCreations = 0;
      final observer = _FailingOpenInterceptor();
      final database = WorkspaceDatabase.forFile(
        File(path.join(temporary.path, 'workspace.sqlite')),
        backgroundExecutorFactory: () {
          executorCreations += 1;
          return NativeDatabase.memory().interceptWith(observer);
        },
      );
      final lifecycle = DriftControlPlaneLifecycle(database);
      addTearDown(() async {
        await lifecycle.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      await expectLater(lifecycle.open(), throwsStateError);

      expect(executorCreations, 1);
      expect(observer.openAttempts, 1);
      expect(observer.closeCalls, 1);
      expect(lifecycle.isOpen, isFalse);

      await lifecycle.close();
      expect(observer.closeCalls, 1);
      await expectLater(lifecycle.open(), throwsStateError);
    },
  );
}

final class _FailingOpenInterceptor extends QueryInterceptor {
  int openAttempts = 0;
  int closeCalls = 0;

  @override
  Future<bool> ensureOpen(
    QueryExecutor executor,
    QueryExecutorUser user,
  ) async {
    openAttempts += 1;
    throw StateError('injected open failure');
  }

  @override
  Future<void> close(QueryExecutor inner) async {
    closeCalls += 1;
    await inner.close();
  }
}
