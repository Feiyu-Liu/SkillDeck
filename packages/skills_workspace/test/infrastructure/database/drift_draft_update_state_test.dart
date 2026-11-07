import 'dart:io';

import 'package:drift/drift.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/update_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/update/update_candidate_content_port.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_draft_update_state.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart'
    hide ManagedSkill;
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceDatabase database;
  late _DraftInspection drafts;
  late _CandidateContent candidateContent;
  late DriftDraftUpdateState states;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-draft-update-state-',
    );
    database = WorkspaceDatabase.forFile(
      File('${temporaryDirectory.path}/workspace.sqlite'),
    );
    await database.workspaceMetadata.select().getSingle();
    await _seed(database);
    drafts = _DraftInspection();
    candidateContent = _CandidateContent();
    states = DriftDraftUpdateState(
      database: database,
      draftInspection: drafts,
      candidateContent: candidateContent,
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'projects current Draft and Update pointer state from one lineage',
    () async {
      final draft = await states.readDraftState(_skillId);
      final update = await states.readUpdateState(_skillId);

      expect(draft?.currentUpstream, _object('1'));
      expect(draft?.currentEffective, _object('2'));
      expect(draft?.draftCreatedAtMicros, 3);
      expect(update?.previousUpstreamContentHash, _hashA);
    },
  );

  test(
    'Draft summary replaces cached dirty hint with authoritative result',
    () async {
      drafts.result = const UpdateDraftInspection.dirty();

      final result = await states.inspectDraft(
        skill: _skill(),
        state: (await states.readDraftState(_skillId))!,
        cancellationToken: CancellationToken.none(),
      );

      expect(result.valueOrNull?.isDirty, isTrue);
      expect(drafts.calls, 1);
    },
  );

  test(
    'candidate state combines SQLite ancestry with Store metadata',
    () async {
      final state = await states.readCandidateState(
        _skillId,
        cancellationToken: CancellationToken.none(),
      );

      expect(state?.previousUpstream, _object('1'));
      expect(state?.previousEffective, _object('2'));
      expect(state?.incomingUpstream, _object('3'));
      expect(state?.candidateObjectId, _object('4'));
      expect(state?.incomingDeclaredName, 'renamed');
      expect(state?.incomingSlotKey, 'renamed');
      expect(state?.incomingDescription, 'Incoming description');
      expect(state?.retainedPublishedRoots, <RevisionObjectId>[
        _object('1'),
        _object('2'),
      ]);
      expect(
        state?.retainedPublishedRoots,
        isNot(containsAll(<RevisionObjectId>[_object('3'), _object('4')])),
      );
      expect(
        state?.conflicts.single.state,
        WorkspaceUpdateCandidateItemState.resolved,
      );
      expect(candidateContent.calls, 1);
    },
  );
}

final class _DraftInspection implements UpdateDraftInspectionPort {
  UpdateDraftInspection result = const UpdateDraftInspection.clean();
  var calls = 0;

  @override
  Future<UpdateDraftInspectionResult> inspectForUpdate({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    return UpdateDraftInspectionSuccess(result);
  }
}

final class _CandidateContent implements UpdateCandidateContentPort {
  var calls = 0;

  @override
  Future<UpdateCandidateContent?> readCandidateContent({
    required ManagedSkillId managedSkillId,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId candidateObjectId,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    expect(managedSkillId, _skillId);
    expect(sourceLineage, _lineage);
    expect(candidateObjectId, _object('4'));
    return const UpdateCandidateContent(
      declaredName: 'renamed',
      slotKey: 'renamed',
      description: 'Incoming description',
    );
  }
}

Future<void> _seed(WorkspaceDatabase database) async {
  await database.transaction(() async {
    await database
        .into(database.managedSkills)
        .insert(
          ManagedSkillsCompanion.insert(
            id: _skillId.value,
            slotKey: 'one',
            declaredName: 'one',
            displayName: 'One',
            description: 'One Skill',
            activeSourceLineageId: _lineage.encoded,
            createdAtMicros: 1,
            updatedAtMicros: 2,
          ),
        );
    await database
        .into(database.sourceLineages)
        .insert(
          SourceLineagesCompanion.insert(
            id: _lineage.encoded,
            managedSkillId: _skillId.value,
            objectFormat: 'sha1',
            createdAtMicros: 1,
          ),
        );
    for (final entry in <(String, String, String)>[
      ('1', _hashA, 'one'),
      ('2', _hashB, 'one'),
      ('3', _hashC, 'renamed'),
      ('4', _hashD, 'renamed'),
    ]) {
      await database
          .into(database.revisionMetadata)
          .insert(
            RevisionMetadataCompanion.insert(
              sourceLineageId: _lineage.encoded,
              objectId: _object(entry.$1).value,
              contentHash: entry.$2,
              fileCount: 1,
              byteSize: 1,
              declaredName: entry.$3,
              validationState: entry.$1 == '4' ? 'invalid' : 'valid',
              validationCode: entry.$1 == '4'
                  ? const Value('updateMergeConflict')
                  : const Value.absent(),
              createdAtMicros: 1,
            ),
          );
    }
    await database
        .into(database.currentRevisionSelection)
        .insert(
          CurrentRevisionSelectionCompanion.insert(
            managedSkillId: _skillId.value,
            sourceLineageId: _lineage.encoded,
            upstreamObjectId: _object('1').value,
            effectiveObjectId: _object('2').value,
          ),
        );
    await database
        .into(database.draftWorkspaces)
        .insert(
          DraftWorkspacesCompanion.insert(
            managedSkillId: _skillId.value,
            sourceLineageId: _lineage.encoded,
            baseObjectId: _object('4').value,
            purpose: 'updateCandidateResolution',
            createdAtMicros: 3,
            updatedAtMicros: 3,
          ),
        );
    await database
        .into(database.updateCandidateSessions)
        .insert(
          UpdateCandidateSessionsCompanion.insert(
            managedSkillId: _skillId.value,
            sourceLineageId: _lineage.encoded,
            previousUpstreamObjectId: _object('1').value,
            previousEffectiveObjectId: _object('2').value,
            incomingUpstreamObjectId: _object('3').value,
            candidateObjectId: _object('4').value,
            status: 'conflicted',
            createdAtMicros: 3,
            updatedAtMicros: 3,
          ),
        );
    await database
        .into(database.updateCandidateItems)
        .insert(
          UpdateCandidateItemsCompanion.insert(
            managedSkillId: _skillId.value,
            path: 'SKILL.md',
            kind: WorkspaceUpdateCandidateItemKind.text.name,
            state: WorkspaceUpdateCandidateItemState.resolved.name,
          ),
        );
    await database
        .into(database.operationRecords)
        .insert(
          OperationRecordsCompanion.insert(
            operationId: '123e4567-e89b-42d3-a456-426614174010',
            kind: WorkspaceOperationKind.install.name,
            status: 'succeeded',
            startedAtMicros: 1,
            completedAtMicros: 1,
          ),
        );
    await database
        .into(database.operationSubjects)
        .insert(
          OperationSubjectsCompanion.insert(
            subjectId: '123e4567-e89b-42d3-b456-426614174010',
            operationId: '123e4567-e89b-42d3-a456-426614174010',
            managedSkillId: _skillId.value,
            sourceLineageId: Value(_lineage.encoded),
            afterObjectId: Value(_object('1').value),
            displayName: 'One',
          ),
        );
    await database
        .into(database.operationRecords)
        .insert(
          OperationRecordsCompanion.insert(
            operationId: '123e4567-e89b-42d3-a456-426614174011',
            kind: WorkspaceOperationKind.publishDraft.name,
            status: 'succeeded',
            startedAtMicros: 2,
            completedAtMicros: 2,
          ),
        );
    await database
        .into(database.operationSubjects)
        .insert(
          OperationSubjectsCompanion.insert(
            subjectId: '123e4567-e89b-42d3-b456-426614174011',
            operationId: '123e4567-e89b-42d3-a456-426614174011',
            managedSkillId: _skillId.value,
            sourceLineageId: Value(_lineage.encoded),
            beforeObjectId: Value(_object('1').value),
            afterObjectId: Value(_object('2').value),
            displayName: 'One',
          ),
        );
  });
}

ManagedSkill _skill() => ManagedSkill(
  id: _skillId,
  slotKey: 'one',
  declaredName: 'one',
  displayName: 'One',
  description: 'One Skill',
  source: LocalSourceDescriptor(locator: '/source/one'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: _hashB,
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026, 8, 17),
  ),
  draft: DraftSummary(
    purpose: DraftPurpose.updateCandidateResolution,
    path: '/drafts/${_skillId.value}',
    isDirty: false,
    updatedAt: DateTime.utc(2026, 8, 17),
  ),
);

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('123e4567-e89b-42d3-8456-426614174001');
RevisionObjectId _object(String character) => RevisionObjectId(character * 40);
const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _hashC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _hashD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
