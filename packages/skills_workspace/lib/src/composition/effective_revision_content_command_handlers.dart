import 'dart:typed_data';

import '../api/composite_command_dispatcher.dart';
import '../api/requests.dart';
import '../api/result.dart';
import '../application/ports/revision_store_access_ports.dart';
import '../application/revision_store/revision_store_access_models.dart';
import '../application/runtime/workspace_snapshot_publisher.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../domain/revision_content.dart';
import 'skill_integrity_coordinator.dart';

/// Read-only handlers for the immutable current Effective Revision.
///
/// [CurrentEffectiveRevisionContentPort] owns the SQLite Pointer, Store
/// per-Skill read admission, and post-admission Pointer revalidation. The handlers only
/// project a validated tree into the public, path-safe file query contract.
List<SkillsCommandHandler> buildEffectiveRevisionContentCommandHandlers({
  required WorkspaceSnapshotPublisher snapshots,
  required CurrentEffectiveRevisionContentPort content,
  SkillIntegrityCoordinator? integrity,
}) => <SkillsCommandHandler>[
  TypedSkillsCommandHandler<
    ListEffectiveFilesRequest,
    EffectiveSkillFileManifest
  >(
    kind: WorkspaceOperationKind.listEffectiveFiles,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      if (context.cancellationToken.isCancelled) {
        return _cancelled<EffectiveSkillFileManifest>();
      }
      if (snapshots.current.findSkill(request.managedSkillId) == null) {
        return SkillsFailure<EffectiveSkillFileManifest>(
          code: SkillsErrorCode.skillNotFound,
        );
      }
      final tree = await _readTree(
        content: content,
        managedSkillId: request.managedSkillId,
        cancellationToken: context.cancellationToken,
      );
      if (tree.failureCode case final failureCode?) {
        if (failureCode == SkillsErrorCode.revisionStoreCorrupt) {
          await integrity?.markRevisionStoreCorrupt(request.managedSkillId);
        }
        return SkillsFailure<EffectiveSkillFileManifest>(
          code: failureCode,
          context: tree.context,
        );
      }
      final value = tree.value!;
      if (!_treePathsAreSafe(value)) {
        return SkillsFailure<EffectiveSkillFileManifest>(
          code: SkillsErrorCode.revisionStoreCorrupt,
          context: const <String, Object?>{'reason': 'invalidTreePath'},
        );
      }
      return SkillsSuccess<EffectiveSkillFileManifest>(
        value: EffectiveSkillFileManifest(
          managedSkillId: request.managedSkillId,
          contentHash: value.contentHash,
          files: value.files
              .map(
                (file) => EffectiveSkillFileEntry(
                  relativePath: file.relativePath,
                  byteSize: file.bytes.length,
                  isExecutable: file.isExecutable,
                ),
              )
              .toList(growable: false),
        ),
      );
    },
  ),
  TypedSkillsCommandHandler<
    ReadEffectiveFileRequest,
    EffectiveSkillFileContent
  >(
    kind: WorkspaceOperationKind.readEffectiveFile,
    handle: (request, context) async {
      context.reportProgress(OperationProgressPhase.inspecting);
      if (context.cancellationToken.isCancelled) {
        return _cancelled<EffectiveSkillFileContent>();
      }
      final pathFailure = _validateRelativeFilePath(request.relativePath);
      if (pathFailure != null) {
        return SkillsFailure<EffectiveSkillFileContent>(
          code: SkillsErrorCode.invalidEffectiveFilePath,
          context: <String, Object?>{'reason': pathFailure},
        );
      }
      if (!_isContentHash(request.expectedContentHash)) {
        return SkillsFailure<EffectiveSkillFileContent>(
          code: SkillsErrorCode.staleSnapshot,
          context: const <String, Object?>{'reason': 'invalidContentHash'},
        );
      }
      final skill = snapshots.current.findSkill(request.managedSkillId);
      if (skill == null) {
        return SkillsFailure<EffectiveSkillFileContent>(
          code: SkillsErrorCode.skillNotFound,
        );
      }
      if (skill.currentRevision.contentHash != request.expectedContentHash) {
        return SkillsFailure<EffectiveSkillFileContent>(
          code: SkillsErrorCode.staleSnapshot,
          context: const <String, Object?>{'reason': 'contentHashChanged'},
        );
      }
      final tree = await _readTree(
        content: content,
        managedSkillId: request.managedSkillId,
        cancellationToken: context.cancellationToken,
      );
      if (tree.failureCode case final failureCode?) {
        if (failureCode == SkillsErrorCode.revisionStoreCorrupt) {
          await integrity?.markRevisionStoreCorrupt(request.managedSkillId);
        }
        return SkillsFailure<EffectiveSkillFileContent>(
          code: failureCode,
          context: tree.context,
        );
      }
      final value = tree.value!;
      if (value.contentHash != request.expectedContentHash) {
        return SkillsFailure<EffectiveSkillFileContent>(
          code: SkillsErrorCode.staleSnapshot,
          context: const <String, Object?>{'reason': 'contentHashChanged'},
        );
      }
      if (!_treePathsAreSafe(value)) {
        return SkillsFailure<EffectiveSkillFileContent>(
          code: SkillsErrorCode.revisionStoreCorrupt,
          context: const <String, Object?>{'reason': 'invalidTreePath'},
        );
      }
      final file = _findFile(value.files, request.relativePath);
      if (file == null) {
        return SkillsFailure<EffectiveSkillFileContent>(
          code: SkillsErrorCode.effectiveFileNotFound,
          context: <String, Object?>{'relativePath': request.relativePath},
        );
      }
      return SkillsSuccess<EffectiveSkillFileContent>(
        value: EffectiveSkillFileContent(
          managedSkillId: request.managedSkillId,
          contentHash: value.contentHash,
          relativePath: file.relativePath,
          bytes: Uint8List.fromList(file.bytes),
        ),
      );
    },
  ),
];

Future<_EffectiveTreeRead> _readTree({
  required CurrentEffectiveRevisionContentPort content,
  required ManagedSkillId managedSkillId,
  required CancellationToken cancellationToken,
}) async {
  try {
    return _EffectiveTreeRead.success(
      await content.readCurrentEffective(
        managedSkillId,
        cancellationToken: cancellationToken,
      ),
    );
  } on RevisionStoreAccessException catch (error) {
    return _EffectiveTreeRead.failure(
      switch (error.code) {
        RevisionStoreAccessFailureCode.cancelled =>
          SkillsErrorCode.operationCancelled,
        RevisionStoreAccessFailureCode.selectionChangedRepeatedly =>
          SkillsErrorCode.staleSnapshot,
        RevisionStoreAccessFailureCode.selectionUnavailable =>
          SkillsErrorCode.skillNotFound,
      },
      context: <String, Object?>{'reason': error.code.name},
    );
  } on RevisionEngineException catch (error) {
    return _EffectiveTreeRead.failure(
      SkillsErrorCode.revisionStoreCorrupt,
      context: <String, Object?>{'reason': error.code.name},
    );
  } on Object {
    return const _EffectiveTreeRead.failure(SkillsErrorCode.ioFailure);
  }
}

final class _EffectiveTreeRead {
  const _EffectiveTreeRead.success(this.value)
    : failureCode = null,
      context = const <String, Object?>{};

  const _EffectiveTreeRead.failure(
    this.failureCode, {
    this.context = const <String, Object?>{},
  }) : value = null;

  final NormalizedSkillTree? value;
  final SkillsErrorCode? failureCode;
  final Map<String, Object?> context;
}

SkillsFailure<T> _cancelled<T>() =>
    SkillsFailure<T>(code: SkillsErrorCode.operationCancelled);

NormalizedSkillFile? _findFile(
  List<NormalizedSkillFile> files,
  String relativePath,
) {
  for (final file in files) {
    if (file.relativePath == relativePath) return file;
  }
  return null;
}

bool _treePathsAreSafe(NormalizedSkillTree tree) => tree.files.every(
  (file) => _validateRelativeFilePath(file.relativePath) == null,
);

bool _isContentHash(String value) => RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

String? _validateRelativeFilePath(String value) {
  if (value.isEmpty) return 'empty';
  if (!_hasWellFormedUtf16(value)) return 'malformedUnicode';
  if (value.contains('\u0000')) return 'nulByte';
  if (value.startsWith('/') ||
      value.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value)) {
    return 'absolutePath';
  }
  if (value.contains(r'\')) return 'platformSeparator';
  final segments = value.split('/');
  if (segments.any(
    (segment) => segment.isEmpty || segment == '.' || segment == '..',
  )) {
    return 'pathTraversal';
  }
  return null;
}

bool _hasWellFormedUtf16(String value) {
  for (var index = 0; index < value.length; index += 1) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (index + 1 >= value.length) return false;
      final next = value.codeUnitAt(index + 1);
      if (next < 0xdc00 || next > 0xdfff) return false;
      index += 1;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
