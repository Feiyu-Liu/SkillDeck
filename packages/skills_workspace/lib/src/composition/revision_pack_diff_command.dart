import 'dart:io';

import 'package:path/path.dart' as path;

import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/revision_store/revision_store_access_models.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../infrastructure/workspace_layout.dart';
import '../native/revision_worker/revision_worker_runtime.dart';
import 'remote_revision_store.dart';

SkillsCommandHandler buildRevisionPackDiffCommand({
  required Future<CurrentEffectiveRevisionSelection?> Function(ManagedSkillId)
  readCurrentEffective,
  required ManagedSkillRevisionAccessGate accessGate,
  required WorkspaceLayout layout,
  required RevisionWorkerRuntime revisions,
  required Future<List<SkillFileDiff>> Function(
    String storePath,
    RevisionObjectId local,
    RevisionObjectId incoming,
  )
  compare,
}) =>
    TypedSkillsCommandHandler<InspectRevisionPackDiffRequest, RevisionPackDiff>(
      kind: WorkspaceOperationKind.inspectRevisionPackDiff,
      handle: (request, context) async {
        final token = context.cancellationToken;
        final skillId = request.managedSkillId;
        context.reportProgress(OperationProgressPhase.inspecting);
        if (token.isCancelled) {
          return _failure(SkillsErrorCode.operationCancelled);
        }
        if (!path.isAbsolute(request.packPath) ||
            request.packPath.contains('\u0000')) {
          return _failure(SkillsErrorCode.ioFailure);
        }
        try {
          final permit = await accessGate.acquireRead(
            skillId,
            cancellationToken: token,
          );
          try {
            final selected = await readCurrentEffective(skillId);
            if (token.isCancelled) {
              return _failure(SkillsErrorCode.operationCancelled);
            }
            if (selected == null) {
              return _failure(SkillsErrorCode.skillNotFound);
            }
            if (selected.objectId.value != request.expectedEffective.value) {
              return _failure(SkillsErrorCode.staleSnapshot);
            }
            final incoming = RevisionObjectId(request.incomingEffective.value);
            final staging = Directory(
              layout.operationStagingPath(context.operationId),
            );
            try {
              context.reportProgress(OperationProgressPhase.preparing);
              final prepared = await prepareRemoteRevisionStore(
                layout: layout,
                revisions: revisions,
                operationId: context.operationId,
                managedSkillId: skillId,
                targetRevisions: [
                  incoming,
                  if (request.incomingUpstream case final upstream?)
                    RevisionObjectId(upstream.value),
                ],
                packPath: request.packPath,
                cancellationToken: token,
                usePreviouslyStagedPacks: false,
              );
              switch (prepared.packFailure) {
                case RevisionPackStageFailure.malformed ||
                    RevisionPackStageFailure.incomplete:
                  return _failure(SkillsErrorCode.archiveInvalid);
                case RevisionPackStageFailure.unreadable:
                  return _failure(SkillsErrorCode.ioFailure);
                case null:
                  break;
              }
              final files = await compare(
                prepared.storePath,
                selected.objectId,
                incoming,
              );
              final stillSelected = await readCurrentEffective(skillId);
              if (token.isCancelled) {
                return _failure(SkillsErrorCode.operationCancelled);
              }
              if (stillSelected != selected) {
                return _failure(SkillsErrorCode.staleSnapshot);
              }
              return SkillsSuccess(
                value: RevisionPackDiff(
                  managedSkillId: skillId,
                  from: request.expectedEffective,
                  to: request.incomingEffective,
                  files: files,
                ),
              );
            } finally {
              if (await staging.exists()) await staging.delete(recursive: true);
            }
          } finally {
            await permit.release();
          }
        } on ManagedSkillRevisionAccessCancelled {
          return _failure(SkillsErrorCode.operationCancelled);
        } on ManagedRemoteStoreCancelled {
          return _failure(SkillsErrorCode.operationCancelled);
        } on RevisionEngineException {
          return _failure(SkillsErrorCode.revisionStoreCorrupt);
        } on FileSystemException {
          return _failure(
            token.isCancelled
                ? SkillsErrorCode.operationCancelled
                : SkillsErrorCode.ioFailure,
          );
        }
      },
    );

SkillsFailure<RevisionPackDiff> _failure(SkillsErrorCode code) =>
    SkillsFailure(code: code);
