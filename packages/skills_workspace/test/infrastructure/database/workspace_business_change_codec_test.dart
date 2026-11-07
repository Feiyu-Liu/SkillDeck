import 'dart:convert';

import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_business_change_codec.dart';
import 'package:test/test.dart';

const _skillId = '123e4567-e89b-42d3-a456-426614174100';
const _lineageId = '123e4567-e89b-42d3-b456-426614174101';
const _activationId = '123e4567-e89b-42d3-8456-426614174102';
const _tagId = '123e4567-e89b-42d3-9456-426614174103';
const _oldObject = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newObject = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _hash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

void main() {
  const codec = WorkspaceBusinessChangeSetCodec();

  test('round-trips every typed mutation without losing plan data', () {
    final skillId = ManagedSkillId(_skillId);
    final changes = WorkspaceBusinessChangeSet(
      incrementsDestructionEpoch: true,
      mutations: [
        PutManagedSkill(
          managedSkillId: skillId,
          slotKey: 'reviewer',
          declaredName: 'reviewer',
          displayName: 'Reviewer',
          description: 'Reviews code.',
          activeSourceLineageId: _lineageId,
          createdAtMicros: 1,
          updatedAtMicros: 2,
        ),
        DeleteManagedSkill(skillId),
        PutSourceLineage(
          sourceLineageId: _lineageId,
          managedSkillId: skillId,
          objectFormat: WorkspaceObjectFormat.sha256,
          createdAtMicros: 3,
        ),
        DeleteSourceLineage(_lineageId),
        PutSkillSource(
          sourceLineageId: _lineageId,
          kind: WorkspaceSourceKind.git,
          payloadSchemaVersion: 1,
          payloadJson: '{"url":"https://example.invalid/repo.git"}',
        ),
        PutRevisionMetadata(
          sourceLineageId: _lineageId,
          objectId: _newObject,
          contentHash: _hash,
          fileCount: 2,
          byteSize: 42,
          declaredName: 'reviewer',
          validationState: WorkspaceRevisionValidationState.invalid,
          validationCode: 'nameMismatch',
          createdAtMicros: 4,
        ),
        PutProjectRoot(
          projectRootId: 'project-root',
          canonicalPath: '/workspace/project',
          createdAtMicros: 5,
          updatedAtMicros: 6,
        ),
        DeleteProjectRoot('project-root'),
        PutActivation(
          activationId: _activationId,
          managedSkillId: skillId,
          canonicalPath: '/agents/skills/reviewer',
          scope: WorkspaceActivationScope.project,
          mode: WorkspaceActivationMode.symbolicLink,
          projectRootId: 'project-root',
          projectRootPath: '/workspace/project',
          agentIds: const ['claude', 'codex'],
          createdAtMicros: 7,
        ),
        DeleteActivation(_activationId),
        PutSkillUserData(
          managedSkillId: skillId,
          favorite: true,
          favoriteChangedAtMicros: 8,
          note: 'Use for reviews',
          noteUpdatedAtMicros: 9,
        ),
        DeleteSkillUserData(skillId),
        PutPersonalTag(
          personalTagId: _tagId,
          normalizedKey: 'work',
          displayName: 'Work',
          color: '#123ABC',
          createdAtMicros: 10,
          updatedAtMicros: 11,
        ),
        DeletePersonalTag(_tagId),
        PutSkillTagAssignment(
          managedSkillId: skillId,
          personalTagId: _tagId,
          createdAtMicros: 12,
        ),
        DeleteSkillTagAssignment(
          managedSkillId: skillId,
          personalTagId: _tagId,
        ),
        PutDraftWorkspace(
          managedSkillId: skillId,
          sourceLineageId: _lineageId,
          baseObjectId: _oldObject,
          purpose: WorkspaceDraftPurpose.updateCandidateResolution,
          createdAtMicros: 13,
          updatedAtMicros: 14,
        ),
        DeleteDraftWorkspace(skillId),
        PutUpdateCandidateSession(
          managedSkillId: skillId,
          sourceLineageId: _lineageId,
          previousUpstreamObjectId: _oldObject,
          previousEffectiveObjectId: _oldObject,
          incomingUpstreamObjectId: _newObject,
          candidateObjectId: 'candidate-tree',
          status: WorkspaceUpdateCandidateStatus.conflicted,
          validationCode: null,
          items: [
            WorkspaceUpdateCandidateItem(
              path: 'SKILL.md',
              kind: WorkspaceUpdateCandidateItemKind.text,
              state: WorkspaceUpdateCandidateItemState.unresolved,
              baseObjectId: _oldObject,
              oursObjectId: _oldObject,
              theirsObjectId: _newObject,
            ),
          ],
          createdAtMicros: 15,
          updatedAtMicros: 16,
        ),
        DeleteUpdateCandidateSession(skillId),
        SetUpdateCandidateItemResolution(
          managedSkillId: skillId,
          path: 'SKILL.md',
          state: WorkspaceUpdateCandidateItemState.resolved,
          updatedAtMicros: 17,
        ),
      ],
    );

    final encoded = codec.encode(changes);
    final decoded = codec.decode(encoded);

    expect(jsonEncode(codec.encode(decoded)), jsonEncode(encoded));
    expect(decoded.mutations, hasLength(21));
    expect(decoded.incrementsDestructionEpoch, isTrue);
  });

  test('rejects unknown schemas and mutation discriminators', () {
    expect(
      () => codec.decode({
        'schemaVersion': 99,
        'incrementsDestructionEpoch': false,
        'mutations': <Object?>[],
      }),
      throwsA(_reason('unsupportedSchemaVersion')),
    );
    expect(
      () => codec.decode({
        'schemaVersion': WorkspaceBusinessChangeSet.currentSchemaVersion,
        'incrementsDestructionEpoch': false,
        'mutations': [
          {'kind': 'futureMutation'},
        ],
      }),
      throwsA(_reason('unknownMutation')),
    );
  });
}

Matcher _reason(String reason) => isA<WorkspaceBusinessChangeCodecException>()
    .having((error) => error.reason, 'reason', reason);
