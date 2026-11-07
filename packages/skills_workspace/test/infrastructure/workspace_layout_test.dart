import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

void main() {
  final skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
  final operationId = OperationId('123e4567-e89b-42d3-a456-426614174001');

  test('keeps every managed artifact under one absolute private root', () {
    final root = path.join(path.current, 'workspace');
    final layout = WorkspaceLayout(root);

    final paths = [
      layout.databasePath,
      layout.runtimeOwnershipLockPath,
      layout.operationWriterLockPath,
      layout.repositoryCopyPath('sample-skill'),
      layout.draftPath(skillId),
      layout.revisionStorePath(skillId),
      layout.revisionBundlePath(skillId),
      layout.operationStagingPath(operationId),
      layout.operationRecoveryPath(operationId),
      layout.operationRevisionCandidateRoot(operationId, skillId),
      layout.operationBundleCandidatePath(operationId, skillId),
      layout.operationTreeCandidatePath(operationId, skillId),
      layout.operationDraftCandidatePath(operationId, skillId),
      layout.controlPlaneBackupPath(
        destructionEpoch: 2,
        repositoryRevision: RepositoryRevision(9),
      ),
      layout.backupEligibilityPath,
    ];

    for (final artifactPath in paths) {
      expect(path.isWithin(layout.rootPath, artifactPath), isTrue);
    }
    expect(
      layout.runtimeOwnershipLockPath,
      isNot(layout.operationWriterLockPath),
    );
    expect(
      path.basename(layout.revisionStorePath(skillId)),
      '${skillId.value}.git',
    );
    expect(path.basename(layout.revisionBundlePath(skillId)), skillId.value);
  });

  test('keeps transient Revision candidates compact on Windows paths', () {
    final root = path.join(
      path.current,
      'a-very-long-application-support-directory-name-for-windows',
      'agent-skills',
      'workspace',
    );
    final layout = WorkspaceLayout(root);
    final candidate = layout.operationRevisionCandidateRoot(
      operationId,
      skillId,
    );

    expect(
      path.isWithin(layout.operationStagingPath(operationId), candidate),
      isTrue,
    );
    expect(candidate, isNot(contains(skillId.value)));
    expect(path.basename(candidate), hasLength(24));
    expect(candidate.length, lessThanOrEqualTo(root.length + 70));
  });

  test('rejects path injection and invalid backup identity', () {
    final layout = WorkspaceLayout(path.join(path.current, 'workspace'));

    expect(() => layout.repositoryCopyPath('../escape'), throwsArgumentError);
    expect(
      () => layout.controlPlaneBackupPath(
        destructionEpoch: -1,
        repositoryRevision: RepositoryRevision.initial(),
      ),
      throwsArgumentError,
    );
  });
}
