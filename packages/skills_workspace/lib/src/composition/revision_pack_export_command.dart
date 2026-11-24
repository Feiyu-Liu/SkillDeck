import 'dart:io';

import 'package:path/path.dart' as path;

import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../infrastructure/workspace_layout.dart';

SkillsCommandHandler buildRevisionPackExportCommand({
  required Future<({RevisionObjectId effective, RevisionObjectId? upstream})?>
  Function(ManagedSkillId)
  readHeads,
  required ManagedSkillRevisionAccessGate accessGate,
  required WorkspaceLayout layout,
  required RevisionEnginePort revisions,
}) => TypedSkillsCommandHandler<ExportRevisionPackRequest, RevisionPackExport>(
  kind: WorkspaceOperationKind.exportRevisionPack,
  handle: (request, context) async {
    final token = context.cancellationToken;
    final managedSkillId = request.managedSkillId;
    context.reportProgress(OperationProgressPhase.inspecting);
    if (token.isCancelled) return _cancelled();

    File? created;
    var published = false;
    try {
      if (request.destinationPath.isEmpty) return _destinationUnavailable();
      final destination = path.normalize(
        path.absolute(request.destinationPath),
      );
      final parent = await Directory(
        path.dirname(destination),
      ).resolveSymbolicLinks();
      final workspaceRoot = await Directory(
        layout.rootPath,
      ).resolveSymbolicLinks();
      final target = File(path.join(parent, path.basename(destination)));
      if (path.equals(parent, workspaceRoot) ||
          path.isWithin(workspaceRoot, parent) ||
          await FileSystemEntity.type(target.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
        return _destinationUnavailable();
      }
      Directory? staging;
      late final File pack;
      final ({RevisionObjectId effective, RevisionObjectId? upstream}) heads;
      try {
        // A per-Skill read permit pins this Store against destructive changes
        // while the Revision Worker packs the heads selected by SQLite.
        final permit = await accessGate.acquireRead(
          managedSkillId,
          cancellationToken: token,
        );
        try {
          final selected = await readHeads(managedSkillId);
          if (token.isCancelled) return _cancelled();
          if (selected == null) {
            return SkillsFailure(code: SkillsErrorCode.skillNotFound);
          }
          heads = selected;
          final work = await Directory(
            layout.revisionStoresRoot,
          ).createTemp(WorkspaceLayout.revisionPackTemporaryPrefix);
          staging = work;
          pack = File(path.join(work.path, 'objects.pack'));
          context.reportProgress(OperationProgressPhase.preparing);
          await revisions.createRecoveryPack(
            repositoryPath: layout.revisionStorePath(managedSkillId),
            bundleStagingPath: work.path,
            retainedRoots: {
              heads.effective,
              ?heads.upstream,
            }.toList(growable: false),
            includeHistory: true,
          );
        } finally {
          await permit.release();
        }

        if (token.isCancelled) return _cancelled();
        await target.create(exclusive: true);
        created = target;
        final output = await target.open(mode: FileMode.writeOnlyAppend);
        try {
          await for (final chunk in pack.openRead()) {
            if (token.isCancelled) return _cancelled();
            await output.writeFrom(chunk);
          }
          await output.flush();
        } finally {
          await output.close();
        }
      } finally {
        await staging?.delete(recursive: true);
      }
      if (token.isCancelled) return _cancelled();

      final result = SkillsSuccess(
        value: RevisionPackExport(
          effective: RevisionId(heads.effective.value),
          upstream: switch (heads.upstream) {
            final upstream? => RevisionId(upstream.value),
            null => null,
          },
        ),
      );
      published = true;
      return result;
    } on ManagedSkillRevisionAccessCancelled {
      return _cancelled();
    } on RevisionEngineException catch (error) {
      if (token.isCancelled) return _cancelled();
      if (error.code == RevisionEngineFailureCode.objectUnavailable ||
          error.code == RevisionEngineFailureCode.storeUnavailable) {
        return SkillsFailure(code: SkillsErrorCode.revisionStoreCorrupt);
      }
      rethrow;
    } on FileSystemException {
      return token.isCancelled ? _cancelled() : _destinationUnavailable();
    } finally {
      if (!published) await created?.delete();
    }
  },
);

SkillsFailure<RevisionPackExport> _cancelled() =>
    SkillsFailure(code: SkillsErrorCode.operationCancelled);

SkillsFailure<RevisionPackExport> _destinationUnavailable() => SkillsFailure(
  code: SkillsErrorCode.ioFailure,
  context: const {'reason': 'destinationUnavailable'},
);
