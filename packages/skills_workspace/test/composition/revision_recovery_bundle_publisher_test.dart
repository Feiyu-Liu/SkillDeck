import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/revision_bundle_worker_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/composition/revision_recovery_bundle_publisher.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

void main() {
  for (final worker in [false, true]) {
    for (final code in RevisionEngineFailureCode.values.where(
      (code) => code != RevisionEngineFailureCode.objectUnavailable,
    )) {
      test(
        '${worker ? 'worker' : 'direct'} propagates $code without retry',
        () async {
          final temporary = await Directory.systemTemp.createTemp(
            'bundle-failure-',
          );
          addTearDown(() => temporary.delete(recursive: true));
          final engine = worker ? _FailingWorker(code) : _FailingEngine(code);
          final publisher = RevisionRecoveryBundlePublisher(
            revisions: engine,
            filesystem: PlatformDurableWorkspaceFilesystem(),
            readCommittedRoots: (_, {includeDraftAndSession = true}) async =>
                {},
          );
          final root = RevisionObjectId('a' * 40);

          await expectLater(
            publisher.publish(
              repositoryPath: path.join(temporary.path, 'store.git'),
              bundlePath: path.join(temporary.path, 'bundle'),
              operationStagingRoot: temporary.path,
              sourceLineage: SourceLineageReference(
                '123e4567-e89b-42d3-8456-426614174001',
              ),
              currentUpstream: root,
              currentEffective: root,
              retainedPublishedRoots: [root],
            ),
            throwsA(
              isA<RevisionEngineException>().having(
                (error) => error.code,
                'code',
                code,
              ),
            ),
          );
          expect(engine.historyAttempts, [true]);
        },
      );
    }
  }
}

class _FailingEngine implements RevisionEnginePort {
  _FailingEngine(this.code);

  final RevisionEngineFailureCode code;
  final List<bool> historyAttempts = [];

  @override
  Future<void> createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
    bool includeHistory = false,
  }) async {
    historyAttempts.add(includeHistory);
    throw RevisionEngineException(code);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FailingWorker extends _FailingEngine
    implements RevisionBundleWorkerPort {
  _FailingWorker(super.code);

  @override
  Future<void> buildRevisionBundleArtifacts({
    required String repositoryPath,
    required String bundlePath,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedRoots,
    bool includeHistory = false,
  }) async {
    historyAttempts.add(includeHistory);
    throw RevisionEngineException(code);
  }
}
