import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
  final timestamp = DateTime.utc(2026, 8, 17);

  ManagedSkill skill({
    SkillNote? note,
    DraftSummary? draft,
    UpdateCandidateSummary? updateCandidate,
  }) => ManagedSkill(
    id: skillId,
    slotKey: 'reviewer',
    declaredName: 'reviewer',
    displayName: 'Reviewer',
    description: 'Reviews a Skill.',
    source: GitSourceDescriptor(locator: 'https://example.com/repo.git'),
    currentRevision: ManagedSkillRevisionSummary(
      contentHash: hash,
      fileCount: 2,
      byteSize: 128,
      publishedAt: timestamp,
    ),
    favorite: SkillFavorite(isFavorite: true, changedAt: timestamp),
    note: note,
    personalTagIds: const ['work'],
    activations: [
      SkillActivation(
        location: '/tmp/skills/reviewer',
        scope: ActivationScope.global,
        mode: ActivationMode.copy,
        agentIds: const ['claude'],
      ),
    ],
    draft: draft,
    updateCandidate: updateCandidate,
  );

  test('snapshot exposes explicit immutable workspace projections', () {
    final note = SkillNote(
      text: 'Use for release review.',
      updatedAt: timestamp,
    );
    final draft = DraftSummary(
      purpose: DraftPurpose.customization,
      path: '/tmp/drafts/reviewer',
      isDirty: true,
      updatedAt: timestamp,
    );
    final managedSkills = <ManagedSkill>[skill(note: note, draft: draft)];
    final projectRoots = <ProjectRoot>[
      ProjectRoot(id: 'project', path: '/tmp/project'),
    ];
    final tags = <PersonalTag>[
      PersonalTag(
        id: 'work',
        name: 'Work',
        color: '#FFCC00',
        createdAt: timestamp,
        updatedAt: timestamp,
      ),
    ];
    final snapshot = RepositorySnapshot(
      revision: RepositoryRevision(7),
      managedSkills: managedSkills,
      projectRoots: projectRoots,
      personalTags: tags,
    );

    managedSkills.clear();
    projectRoots.clear();
    tags.clear();

    expect(snapshot.findSkill(skillId)?.note, note);
    expect(snapshot.findSkillBySlotKey('reviewer')?.draft, draft);
    expect(snapshot.findProjectRoot('project')?.path, '/tmp/project');
    expect(snapshot.findPersonalTag('work')?.name, 'Work');
    expect(snapshot.managedSkills, hasLength(1));
    expect(() => snapshot.managedSkills.clear(), throwsUnsupportedError);
    expect(() => snapshot.personalTags.clear(), throwsUnsupportedError);
  });

  test('snapshot rejects duplicate stable IDs and Slot Keys', () {
    final first = skill();
    final duplicate = skill();

    expect(
      () => RepositorySnapshot(
        revision: RepositoryRevision(1),
        managedSkills: [first, duplicate],
      ),
      throwsArgumentError,
    );
  });

  test('integrity distinguishes one blocked Skill from workspace health', () {
    final integrity = WorkspaceIntegrity(
      status: WorkspaceIntegrityStatus.healthy,
      skills: [
        ManagedSkillIntegrity(
          managedSkillId: skillId,
          status: SkillIntegrityStatus.revisionStoreCorrupt,
        ),
      ],
    );
    final snapshot = RepositorySnapshot(
      revision: RepositoryRevision(3),
      managedSkills: [skill()],
      integrity: integrity,
    );

    expect(snapshot.integrity.status, WorkspaceIntegrityStatus.healthy);
    expect(snapshot.integrity.skills.single.mutationBlocked, isTrue);
  });

  test('history and diff select content through OperationSubjectReference', () {
    final operationId = OperationId('123e4567-e89b-42d3-b456-426614174001');
    final reference = OperationSubjectReference(
      operationId: operationId,
      subjectId: '123e4567-e89b-42d3-8456-426614174002',
    );
    final history = PublishedHistoryPage(
      revisions: [
        PublishedRevisionSummary(
          reference: reference,
          managedSkillId: skillId,
          kind: WorkspaceOperationKind.publishDraft,
          publishedAt: timestamp,
          contentHash: hash,
        ),
      ],
    );
    final diff = SkillDiff(
      managedSkillId: skillId,
      to: reference,
      files: [
        SkillFileDiff(
          path: 'SKILL.md',
          status: DiffFileStatus.modified,
          isBinary: false,
          additions: 1,
          deletions: 1,
          hunks: [
            DiffHunk(
              header: '@@ -1 +1 @@',
              lines: const [
                DiffLine(kind: DiffLineKind.deletion, text: 'old'),
                DiffLine(kind: DiffLineKind.addition, text: 'new'),
              ],
            ),
          ],
        ),
      ],
    );

    expect(history.revisions.single.reference, reference);
    expect(diff.to, reference);
    expect(diff.files.single.hunks.single.lines, hasLength(2));
  });
}
