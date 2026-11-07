import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/operations/filesystem_operation_recovery.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';

const _operationId = '123e4567-e89b-42d3-a456-426614174310';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 || arguments.length > 3) {
    throw ArgumentError('Expected workspace root and crash point.');
  }
  final layout = WorkspaceLayout(arguments[0]);
  final crashPoint = arguments[1];
  final operationId = OperationId(_operationId);
  final target = path.join(layout.repositoryCopiesRoot, 'reviewer');
  final intended = path.join(layout.operationStagingPath(operationId), 'main');
  await Directory(target).create(recursive: true);
  final occupant = arguments.length == 3 ? arguments[2] : null;
  if (occupant == 'link') {
    await Directory(target).delete();
    await Link(target).create('missing');
  } else if (occupant != 'empty') {
    await File(path.join(target, 'SKILL.md')).writeAsString('old', flush: true);
  }
  await Directory(path.join(intended, 'scripts')).create(recursive: true);
  await File(path.join(intended, 'SKILL.md')).writeAsString('new', flush: true);
  final executable = File(path.join(intended, 'scripts', 'run.sh'));
  await executable.writeAsString('#!/bin/sh', flush: true);
  if (!Platform.isWindows) {
    await Process.run('chmod', ['755', executable.path], runInShell: false);
  }

  final prepareReference = operationRecoveryReference(operationId, 'evidence');
  final applyReference = operationRecoveryReference(operationId, 'apply-main');
  final registry = OperationRecoverySpecRegistry()
    ..register(
      OperationRecoveryBundleSpec(
        context: OperationRecoveryContext(
          operationId: operationId,
          expectedRepositoryRevision: RepositoryRevision(0),
          committedRepositoryRevision: RepositoryRevision(1),
          destructive: false,
        ),
        entries: [
          OperationRecoveryEntrySpec(
            requiresInertBeforeImage: occupant != null,
            entryId: 'main',
            targetPath: target,
            intendedSourcePath: intended,
            intendedKind: OperationRecoveryEntryKind.directory,
          ),
        ],
        bindings: [
          OperationRecoveryStepBinding(
            reference: prepareReference,
            action: OperationRecoveryAction.prepareEvidence,
          ),
          OperationRecoveryStepBinding(
            reference: applyReference,
            action: OperationRecoveryAction.applyEntry,
            entryId: 'main',
          ),
        ],
      ),
    );
  final requestedBarrier = crashPoint == 'prepared'
      ? null
      : DurablePathMutationBarrier.values.byName(crashPoint);
  final filesystem = PlatformDurableWorkspaceFilesystem();
  final mutationTarget = await filesystem.resolveMutationPath(target);
  final recovery = FilesystemOperationRecovery(
    layout: layout,
    filesystem: filesystem,
    registry: registry,
    onMutationBarrier: (barrier, destinationPath) async {
      if (barrier != requestedBarrier ||
          !path.equals(destinationPath, mutationTarget)) {
        return;
      }
      stdout.writeln('READY:$crashPoint');
      await stdout.flush();
      await _waitForTermination();
    },
  );
  await recovery.prepareStep(
    PreparationOperationStep(
      stepId: 'prepare-evidence',
      recoveryReference: prepareReference,
      kind: PreparationStepKind.recoveryEvidence,
    ),
    CancellationToken.none(),
  );
  if (crashPoint == 'prepared') {
    stdout.writeln('READY:$crashPoint');
    await stdout.flush();
    await _waitForTermination();
  }
  await recovery.applyStep(
    ApplyingOperationStep(
      stepId: 'apply-main',
      recoveryReference: applyReference,
      kind: ApplyingStepKind.materializationReplacement,
    ),
    CancellationToken.none(),
  );
  throw StateError('The requested crash barrier was not reached.');
}

Future<Never> _waitForTermination() async {
  while (true) {
    await Future<void>.delayed(const Duration(seconds: 30));
  }
}
