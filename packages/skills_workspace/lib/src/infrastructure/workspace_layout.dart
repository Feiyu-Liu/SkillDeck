import 'dart:convert';

import 'package:path/path.dart' as path;

import '../application/ports/operation_ports.dart';
import '../domain/identifiers.dart';

/// Private physical layout for one local Skill Workspace.
///
/// Business code addresses Skills and revisions by typed identity. Only this
/// adapter turns those identities into App-owned filesystem paths.
final class WorkspaceLayout implements OperationRecoveryLayoutPort {
  WorkspaceLayout(String rootPath)
    : rootPath = path.normalize(path.absolute(rootPath)) {
    if (!path.isAbsolute(rootPath) || path.isRootRelative(rootPath)) {
      throw ArgumentError.value(
        rootPath,
        'rootPath',
        'must be a fully qualified absolute path',
      );
    }
  }

  final String rootPath;

  String get databasePath => path.join(rootPath, 'workspace.sqlite');
  String get runtimeOwnershipLockPath =>
      path.join(rootPath, 'runtime-ownership.lock');
  String get operationWriterLockPath =>
      path.join(rootPath, 'operation-writer.lock');
  String get repositoryCopiesRoot => path.join(rootPath, 'repository-copies');
  String get revisionStoresRoot => path.join(rootPath, 'revision-stores');
  String get revisionBundlesRoot => path.join(rootPath, 'revision-bundles');
  String get draftsRoot => path.join(rootPath, 'drafts');
  @override
  String get stagingRoot => path.join(rootPath, 'staging');
  @override
  String get recoveryRoot => path.join(rootPath, 'recovery');
  String get controlPlaneBackupsRoot =>
      path.join(rootPath, 'control-plane-backups');
  String get backupEligibilityPath =>
      path.join(rootPath, 'backup-eligibility.json');

  String repositoryCopyPath(String slotKey) =>
      path.join(repositoryCopiesRoot, _safeSegment(slotKey, 'slotKey'));

  String draftPath(ManagedSkillId managedSkillId) =>
      path.join(draftsRoot, managedSkillId.value);

  String revisionStorePath(ManagedSkillId managedSkillId) =>
      path.join(revisionStoresRoot, '${managedSkillId.value}.git');

  String revisionBundlePath(ManagedSkillId managedSkillId) =>
      path.join(revisionBundlesRoot, managedSkillId.value);

  @override
  String operationStagingPath(OperationId operationId) =>
      path.join(stagingRoot, operationId.value);

  @override
  String operationRecoveryPath(OperationId operationId) =>
      path.join(recoveryRoot, operationId.value);

  String operationSourceReplacementRoot(OperationId operationId) =>
      path.join(operationStagingPath(operationId), 'source-replacement');

  String operationSourceReplacementStore(OperationId operationId) =>
      path.join(operationSourceReplacementRoot(operationId), 'store.git');

  String operationSourceReplacementBundle(OperationId operationId) =>
      path.join(operationSourceReplacementRoot(operationId), 'bundle');

  /// Short operation-private path for a prepared Revision Store.
  ///
  /// Windows Git object paths append multiple internal segments. Keeping the
  /// transient managed identity compact preserves path budget without changing
  /// the durable business identity or recovery reference.
  String operationRevisionCandidateRoot(
    OperationId operationId,
    ManagedSkillId managedSkillId,
  ) => path.join(
    operationStagingPath(operationId),
    'r-${_compactUuid(managedSkillId.value)}',
  );

  String operationBundleCandidatePath(
    OperationId operationId,
    ManagedSkillId managedSkillId,
  ) => path.join(
    operationStagingPath(operationId),
    'b-${_compactUuid(managedSkillId.value)}',
  );

  String operationTreeCandidatePath(
    OperationId operationId,
    ManagedSkillId managedSkillId,
  ) => path.join(
    operationStagingPath(operationId),
    't-${_compactUuid(managedSkillId.value)}',
  );

  String operationDraftCandidatePath(
    OperationId operationId,
    ManagedSkillId managedSkillId,
  ) => path.join(
    operationStagingPath(operationId),
    'd-${_compactUuid(managedSkillId.value)}',
  );

  String controlPlaneBackupPath({
    required int destructionEpoch,
    required RepositoryRevision repositoryRevision,
  }) => path.join(
    controlPlaneBackupsRoot,
    '${_nonNegative(destructionEpoch, 'destructionEpoch')}',
    '${repositoryRevision.value}',
  );
}

String _compactUuid(String value) {
  final hex = value.replaceAll('-', '');
  final bytes = <int>[
    for (var index = 0; index < hex.length; index += 2)
      int.parse(hex.substring(index, index + 2), radix: 16),
  ];
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _safeSegment(String value, String argumentName) {
  if (value.trim().isEmpty ||
      value == '.' ||
      value == '..' ||
      value.contains('/') ||
      value.contains(r'\') ||
      value.contains('\u0000')) {
    throw ArgumentError.value(
      value,
      argumentName,
      'must be one non-empty path segment',
    );
  }
  return value;
}

int _nonNegative(int value, String argumentName) {
  if (value < 0) {
    throw ArgumentError.value(value, argumentName, 'must not be negative');
  }
  return value;
}
