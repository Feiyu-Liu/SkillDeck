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

SkillsCommandHandler buildRevisionPackImportCommand({
  required Future<CurrentEffectiveRevisionSelection?> Function(ManagedSkillId)
  readCurrentEffective,
  required ManagedSkillRevisionAccessGate accessGate,
  required WorkspaceLayout layout,
  required Future<RevisionPackStageResult> Function({
    required String repositoryPath,
    required String stagingObjectsPath,
    required String packPath,
    required List<RevisionObjectId> revisions,
  })
  stagePack,
}) => TypedSkillsCommandHandler<ImportRevisionPackRequest, RevisionPackImport>(
  kind: WorkspaceOperationKind.importRevisionPack,
  handle: (request, context) async {
    final token = context.cancellationToken;
    final skillId = request.managedSkillId;
    context.reportProgress(OperationProgressPhase.inspecting);
    if (token.isCancelled) return _cancelled();

    try {
      final permit = await accessGate.acquireRead(
        skillId,
        cancellationToken: token,
      );
      try {
        final selected = await readCurrentEffective(skillId);
        if (token.isCancelled) return _cancelled();
        if (selected == null) {
          return SkillsFailure(code: SkillsErrorCode.skillNotFound);
        }
        final source = request.packPath;
        if (source.isEmpty || source.contains('\u0000')) return _unreadable();
        final packPath = path.normalize(path.absolute(source));
        if (!await _isInputFile(packPath)) {
          return token.isCancelled ? _cancelled() : _unreadable();
        }
        if (token.isCancelled) return _cancelled();

        final work = await Directory(
          layout.revisionStoresRoot,
        ).createTemp('.pack-');
        var published = false;
        try {
          await Directory(path.join(work.path, 'pack')).create();
          context.reportProgress(OperationProgressPhase.preparing);
          if (token.isCancelled) return _cancelled();
          final result = await stagePack(
            repositoryPath: layout.revisionStorePath(skillId),
            stagingObjectsPath: work.path,
            packPath: packPath,
            revisions: [
              for (final revision in request.revisions)
                RevisionObjectId(revision.value),
            ],
          );
          if (token.isCancelled) return _cancelled();
          switch (result.failure) {
            case RevisionPackStageFailure.malformed:
              return SkillsSuccess(value: RevisionPackImport.malformed);
            case RevisionPackStageFailure.incomplete:
              return SkillsSuccess(value: RevisionPackImport.incomplete);
            case RevisionPackStageFailure.unreadable:
              return _unreadable();
            case null:
              if (result.packName case final name?) {
                published = _publish(
                  work,
                  layout.revisionPackStagingPath(skillId),
                  name,
                );
              }
              return SkillsSuccess(value: RevisionPackImport.imported);
          }
        } finally {
          if (!published) await work.delete(recursive: true);
        }
      } finally {
        await permit.release();
      }
    } on ManagedSkillRevisionAccessCancelled {
      return _cancelled();
    } on FileSystemException {
      return SkillsFailure(
        code: token.isCancelled
            ? SkillsErrorCode.operationCancelled
            : SkillsErrorCode.ioFailure,
      );
    }
  },
);

Future<bool> _isInputFile(String packPath) async {
  try {
    return await FileSystemEntity.type(packPath) == FileSystemEntityType.file;
  } on FileSystemException {
    return false;
  }
}

bool _publish(Directory work, String stagingRoot, String name) {
  final destination = path.join(stagingRoot, name);
  final prefix = path.join(destination, 'pack', 'pack-$name');
  bool alreadyStaged() =>
      File('$prefix.pack').existsSync() && File('$prefix.idx').existsSync();

  if (alreadyStaged()) return false;
  Directory(stagingRoot).createSync(recursive: true);
  try {
    // Publish the validated pack and index together. A concurrent import of
    // the same bytes may already have won the rename.
    work.renameSync(destination);
    return true;
  } on FileSystemException {
    if (alreadyStaged()) return false;
    rethrow;
  }
}

SkillsFailure<RevisionPackImport> _cancelled() =>
    SkillsFailure(code: SkillsErrorCode.operationCancelled);

SkillsFailure<RevisionPackImport> _unreadable() => SkillsFailure(
  code: SkillsErrorCode.ioFailure,
  context: const {'reason': 'packUnreadable'},
);
