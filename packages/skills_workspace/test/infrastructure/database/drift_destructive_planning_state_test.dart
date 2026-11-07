import 'dart:io';

import 'package:drift/drift.dart';
import 'package:skills_workspace/src/application/destructive/destructive_operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/destructive_operation_ports.dart';
import 'package:skills_workspace/src/application/ports/update_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_destructive_planning_state.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart'
    hide ManagedSkill;
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceDatabase database;
  late _DraftInspection drafts;
  late DriftDestructivePlanningState state;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-destructive-state-',
    );
    database = WorkspaceDatabase.forFile(
      File('${temporaryDirectory.path}/workspace.sqlite'),
    );
    await database.workspaceMetadata.select().getSingle();
    await _seed(database);
    drafts = _DraftInspection();
    state = DriftDestructivePlanningState(
      database: database,
      draftInspection: drafts,
    );
  });

  tearDown(() async {
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test(
    'enriches the reviewed Snapshot with complete SQLite authority',
    () async {
      drafts.inspection = const UpdateDraftInspection.dirty();

      final result = await state.readPlanningSnapshot(
        publicSnapshot: _snapshot(),
        purpose: DestructivePlanningPurpose.sourceReplacement,
        targetManagedSkillIds: <ManagedSkillId>{_skillId},
        cancellationToken: CancellationToken.none(),
      );

      final skill = result.managedSkills.single;
      expect(result.repositoryRevision, RepositoryRevision.initial());
      expect(skill.activeSourceLineage, _activeLineage);
      expect(skill.currentUpstream.objectId, _object('2'));
      expect(skill.currentEffective.objectId, _object('3'));
      expect(skill.currentContentHash, _hashC);
      expect(skill.activationIds, [_activationId]);
      expect(skill.draftState, DestructiveDraftState.dirty);
      expect(skill.hasUpdateCandidateSession, isTrue);
      expect(drafts.calls, 1);
    },
  );

  test('fails closed when the reviewed public revision is stale', () async {
    final stale = RepositorySnapshot(
      revision: RepositoryRevision(1),
      managedSkills: _snapshot().managedSkills,
    );

    await expectLater(
      state.readPlanningSnapshot(
        publicSnapshot: stale,
        purpose: DestructivePlanningPurpose.sourceReplacement,
        targetManagedSkillIds: <ManagedSkillId>{_skillId},
        cancellationToken: CancellationToken.none(),
      ),
      throwsStateError,
    );
    expect(drafts.calls, 0);
  });

  test('honors cancellation before projecting internal state', () async {
    final source = CancellationSource();
    await source.cancel();

    await expectLater(
      state.readPlanningSnapshot(
        publicSnapshot: _snapshot(),
        purpose: DestructivePlanningPurpose.removal,
        targetManagedSkillIds: <ManagedSkillId>{_skillId},
        cancellationToken: source.token,
      ),
      throwsA(
        isA<DestructivePlanningStateException>().having(
          (failure) => failure.code,
          'code',
          DestructivePlanningStateFailureCode.operationCancelled,
        ),
      ),
    );
    expect(drafts.calls, 0);
  });

  test('Source Replacement inspects only its targeted Skill Draft', () async {
    drafts.failures[_unrelatedSkillId] = 'revisionStoreUnavailable';

    final result = await state.readPlanningSnapshot(
      publicSnapshot: _snapshot(includeUnrelated: true),
      purpose: DestructivePlanningPurpose.sourceReplacement,
      targetManagedSkillIds: <ManagedSkillId>{_skillId},
      cancellationToken: CancellationToken.none(),
    );

    expect(result.findSkill(_skillId)?.draftState, DestructiveDraftState.clean);
    expect(
      result.findSkill(_unrelatedSkillId)?.draftState,
      DestructiveDraftState.clean,
    );
    expect(drafts.inspectedSkillIds, <ManagedSkillId>[_skillId]);
  });

  test(
    'Removal uses Draft presence without inspecting corrupt bytes',
    () async {
      drafts.failures[_skillId] = 'revisionStoreUnavailable';

      final result = await state.readPlanningSnapshot(
        publicSnapshot: _snapshot(),
        purpose: DestructivePlanningPurpose.removal,
        targetManagedSkillIds: <ManagedSkillId>{_skillId},
        cancellationToken: CancellationToken.none(),
      );

      expect(
        result.findSkill(_skillId)?.draftState,
        DestructiveDraftState.clean,
      );
      expect(drafts.calls, 0);
    },
  );

  test(
    'preserves cancellation returned by targeted Draft inspection',
    () async {
      drafts.failures[_skillId] = 'operationCancelled';

      await expectLater(
        state.readPlanningSnapshot(
          publicSnapshot: _snapshot(),
          purpose: DestructivePlanningPurpose.sourceReplacement,
          targetManagedSkillIds: <ManagedSkillId>{_skillId},
          cancellationToken: CancellationToken.none(),
        ),
        throwsA(
          isA<DestructivePlanningStateException>().having(
            (failure) => failure.code,
            'code',
            DestructivePlanningStateFailureCode.operationCancelled,
          ),
        ),
      );
    },
  );
}

final class _DraftInspection implements UpdateDraftInspectionPort {
  UpdateDraftInspection inspection = const UpdateDraftInspection.clean();
  final failures = <ManagedSkillId, String>{};
  final inspectedSkillIds = <ManagedSkillId>[];
  var calls = 0;

  @override
  Future<UpdateDraftInspectionResult> inspectForUpdate({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  }) async {
    calls += 1;
    inspectedSkillIds.add(skill.id);
    if (failures[skill.id] case final reason?) {
      return UpdateDraftInspectionFailure(reason);
    }
    return UpdateDraftInspectionSuccess(inspection);
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
            activeSourceLineageId: _activeLineage.encoded,
            createdAtMicros: 1,
            updatedAtMicros: 2,
          ),
        );
    for (final entry in <(SourceLineageReference, int)>[
      (_oldLineage, 1),
      (_activeLineage, 2),
    ]) {
      await database
          .into(database.sourceLineages)
          .insert(
            SourceLineagesCompanion.insert(
              id: entry.$1.encoded,
              managedSkillId: _skillId.value,
              objectFormat: 'sha1',
              createdAtMicros: entry.$2,
            ),
          );
    }
    for (final entry in <(String, String)>[
      ('2', _hashB),
      ('3', _hashC),
      ('4', _hashD),
    ]) {
      await database
          .into(database.revisionMetadata)
          .insert(
            RevisionMetadataCompanion.insert(
              sourceLineageId: _activeLineage.encoded,
              objectId: _object(entry.$1).value,
              contentHash: entry.$2,
              fileCount: 1,
              byteSize: 1,
              declaredName: 'one',
              validationState: entry.$1 == '4' ? 'invalid' : 'valid',
              validationCode: entry.$1 == '4'
                  ? const Value('conflict')
                  : const Value.absent(),
              createdAtMicros: 2,
            ),
          );
    }
    await database
        .into(database.currentRevisionSelection)
        .insert(
          CurrentRevisionSelectionCompanion.insert(
            managedSkillId: _skillId.value,
            sourceLineageId: _activeLineage.encoded,
            upstreamObjectId: _object('2').value,
            effectiveObjectId: _object('3').value,
          ),
        );
    await database
        .into(database.draftWorkspaces)
        .insert(
          DraftWorkspacesCompanion.insert(
            managedSkillId: _skillId.value,
            sourceLineageId: _activeLineage.encoded,
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
            sourceLineageId: _activeLineage.encoded,
            previousUpstreamObjectId: _object('2').value,
            previousEffectiveObjectId: _object('3').value,
            incomingUpstreamObjectId: _object('2').value,
            candidateObjectId: _object('4').value,
            status: 'conflicted',
            createdAtMicros: 3,
            updatedAtMicros: 3,
          ),
        );
    await database
        .into(database.activationLocations)
        .insert(
          ActivationLocationsCompanion.insert(
            id: _activationId,
            managedSkillId: _skillId.value,
            canonicalPath: '/agents/one',
            scope: 'global',
            mode: 'copy',
            createdAtMicros: 2,
          ),
        );
    await _seedUnrelated(database);
  });
}

Future<void> _seedUnrelated(WorkspaceDatabase database) async {
  await database
      .into(database.managedSkills)
      .insert(
        ManagedSkillsCompanion.insert(
          id: _unrelatedSkillId.value,
          slotKey: 'two',
          declaredName: 'two',
          displayName: 'Two',
          description: 'Two Skill',
          activeSourceLineageId: _unrelatedLineage.encoded,
          createdAtMicros: 1,
          updatedAtMicros: 2,
        ),
      );
  await database
      .into(database.sourceLineages)
      .insert(
        SourceLineagesCompanion.insert(
          id: _unrelatedLineage.encoded,
          managedSkillId: _unrelatedSkillId.value,
          objectFormat: 'sha1',
          createdAtMicros: 1,
        ),
      );
  await database
      .into(database.revisionMetadata)
      .insert(
        RevisionMetadataCompanion.insert(
          sourceLineageId: _unrelatedLineage.encoded,
          objectId: _object('5').value,
          contentHash: _hashE,
          fileCount: 1,
          byteSize: 1,
          declaredName: 'two',
          validationState: 'valid',
          createdAtMicros: 2,
        ),
      );
  await database
      .into(database.currentRevisionSelection)
      .insert(
        CurrentRevisionSelectionCompanion.insert(
          managedSkillId: _unrelatedSkillId.value,
          sourceLineageId: _unrelatedLineage.encoded,
          upstreamObjectId: _object('5').value,
          effectiveObjectId: _object('5').value,
        ),
      );
  await database
      .into(database.draftWorkspaces)
      .insert(
        DraftWorkspacesCompanion.insert(
          managedSkillId: _unrelatedSkillId.value,
          sourceLineageId: _unrelatedLineage.encoded,
          baseObjectId: _object('5').value,
          purpose: 'customization',
          createdAtMicros: 3,
          updatedAtMicros: 3,
        ),
      );
}

RepositorySnapshot _snapshot({bool includeUnrelated = false}) =>
    RepositorySnapshot(
      revision: RepositoryRevision.initial(),
      managedSkills: [
        ManagedSkill(
          id: _skillId,
          slotKey: 'one',
          declaredName: 'one',
          displayName: 'One',
          description: 'One Skill',
          source: LocalSourceDescriptor(locator: '/source/one'),
          currentRevision: ManagedSkillRevisionSummary(
            contentHash: _hashC,
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
        ),
        if (includeUnrelated)
          ManagedSkill(
            id: _unrelatedSkillId,
            slotKey: 'two',
            declaredName: 'two',
            displayName: 'Two',
            description: 'Two Skill',
            source: LocalSourceDescriptor(locator: '/source/two'),
            currentRevision: ManagedSkillRevisionSummary(
              contentHash: _hashE,
              fileCount: 1,
              byteSize: 1,
              publishedAt: DateTime.utc(2026, 8, 17),
            ),
            draft: DraftSummary(
              purpose: DraftPurpose.customization,
              path: '/drafts/${_unrelatedSkillId.value}',
              isDirty: false,
              updatedAt: DateTime.utc(2026, 8, 17),
            ),
          ),
      ],
    );

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _unrelatedSkillId = ManagedSkillId(
  '123e4567-e89b-42d3-a456-426614174020',
);
const _activationId = '123e4567-e89b-42d3-8456-426614174010';
final _oldLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174001',
);
final _activeLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174002',
);
final _unrelatedLineage = SourceLineageReference(
  '123e4567-e89b-42d3-8456-426614174022',
);
RevisionObjectId _object(String character) => RevisionObjectId(character * 40);
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _hashC =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const _hashD =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
const _hashE =
    'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
