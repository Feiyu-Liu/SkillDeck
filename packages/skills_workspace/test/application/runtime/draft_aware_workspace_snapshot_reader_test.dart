import 'package:skills_workspace/src/application/ports/draft_dirty_state_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/draft_aware_workspace_snapshot_reader.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  test('every read injects full authoritative Draft comparisons', () async {
    final first = _skill(0);
    final second = _skill(1);
    final projection = _Projection([
      _ProjectionState(7, [first, second]),
      _ProjectionState(7, [first, second]),
    ]);
    final inspection = _Inspection({first.id: true, second.id: false});
    final reader = DraftAwareWorkspaceSnapshotReader(
      projection: projection,
      draftInspection: inspection,
    );

    final snapshot = await reader.read();

    expect(inspection.inspectedIds, [first.id, second.id]);
    expect(projection.receivedDirtyStates, [
      isEmpty,
      {first.id: true, second.id: false},
    ]);
    expect(snapshot.findSkill(first.id)?.draft?.isDirty, isTrue);
    expect(snapshot.findSkill(second.id)?.draft?.isDirty, isFalse);
  });

  test('a racing control-plane revision retries the complete scan', () async {
    final skill = _skill(0);
    final projection = _Projection([
      _ProjectionState(2, [skill]),
      _ProjectionState(3, [skill]),
      _ProjectionState(3, [skill]),
      _ProjectionState(3, [skill]),
    ]);
    final inspection = _Inspection({skill.id: true});
    final reader = DraftAwareWorkspaceSnapshotReader(
      projection: projection,
      draftInspection: inspection,
    );

    final snapshot = await reader.read();

    expect(snapshot.revision, RepositoryRevision(3));
    expect(inspection.inspectedIds, [skill.id, skill.id]);
    expect(projection.receivedDirtyStates, hasLength(4));
  });

  test(
    'a transient Draft selection race retries instead of projecting clean',
    () async {
      final skill = _skill(0);
      final projection = _Projection([
        _ProjectionState(4, [skill]),
        _ProjectionState(4, [skill]),
        _ProjectionState(4, [skill]),
      ]);
      final inspection = _Inspection(
        {skill.id: true},
        failures: <String>['draftStateChanged'],
      );
      final reader = DraftAwareWorkspaceSnapshotReader(
        projection: projection,
        draftInspection: inspection,
      );

      final snapshot = await reader.read();

      expect(snapshot.findSkill(skill.id)?.draft?.isDirty, isTrue);
      expect(inspection.inspectedIds, [skill.id, skill.id]);
    },
  );

  test('an inspection failure fails closed without a false-clean Snapshot', () {
    final skill = _skill(0);
    final reader = DraftAwareWorkspaceSnapshotReader(
      projection: _Projection([
        _ProjectionState(1, [skill]),
      ]),
      draftInspection: _Inspection(
        {skill.id: false},
        failures: <String>['ioFailure'],
      ),
    );

    expect(
      reader.read(),
      throwsA(
        isA<DraftAwareSnapshotReadException>()
            .having(
              (error) => error.code,
              'code',
              DraftAwareSnapshotReadFailureCode.dirtyStateUnavailable,
            )
            .having((error) => error.reason, 'reason', 'ioFailure'),
      ),
    );
  });

  test('an isolated corrupt Draft is conservatively dirty', () async {
    final skill = _skill(0);
    final integrity = WorkspaceIntegrity(
      skills: <ManagedSkillIntegrity>[
        ManagedSkillIntegrity(
          managedSkillId: skill.id,
          status: SkillIntegrityStatus.revisionStoreCorrupt,
        ),
      ],
    );
    final projection = _Projection([
      _ProjectionState(1, [skill]),
      _ProjectionState(1, [skill]),
    ]);
    final inspection = _Inspection({skill.id: false});
    final reader = DraftAwareWorkspaceSnapshotReader(
      projection: projection,
      draftInspection: inspection,
    );

    final snapshot = await reader.read(integrity: integrity);

    expect(inspection.inspectedIds, isEmpty);
    expect(snapshot.findSkill(skill.id)?.draft?.isDirty, isTrue);
  });

  test('bounded consistency retries fail with a stable code', () {
    final skill = _skill(0);
    final reader = DraftAwareWorkspaceSnapshotReader(
      projection: _Projection([
        _ProjectionState(1, [skill]),
        _ProjectionState(2, [skill]),
      ]),
      draftInspection: _Inspection({skill.id: false}),
      maximumConsistencyAttempts: 1,
    );

    expect(
      reader.read(),
      throwsA(
        isA<DraftAwareSnapshotReadException>().having(
          (error) => error.code,
          'code',
          DraftAwareSnapshotReadFailureCode.snapshotChangedRepeatedly,
        ),
      ),
    );
    expect(
      () => DraftAwareWorkspaceSnapshotReader(
        projection: _Projection(const <_ProjectionState>[]),
        draftInspection: _Inspection(const <ManagedSkillId, bool>{}),
        maximumConsistencyAttempts: 0,
      ),
      throwsArgumentError,
    );
  });
}

final class _Projection implements WorkspaceSnapshotProjectionReaderPort {
  _Projection(this.states);

  final List<_ProjectionState> states;
  final List<Map<ManagedSkillId, bool>> receivedDirtyStates = [];
  var _index = 0;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) =>
      readWithDraftDirtyStates(
        draftDirtyStates: const <ManagedSkillId, bool>{},
        integrity: integrity,
      );

  @override
  Future<RepositorySnapshot> readWithDraftDirtyStates({
    required Map<ManagedSkillId, bool> draftDirtyStates,
    WorkspaceIntegrity? integrity,
  }) async {
    receivedDirtyStates.add(Map<ManagedSkillId, bool>.of(draftDirtyStates));
    final state = states[_index < states.length ? _index++ : states.length - 1];
    return RepositorySnapshot(
      revision: RepositoryRevision(state.revision),
      managedSkills: <ManagedSkill>[
        for (final skill in state.skills)
          _copySkill(skill, isDirty: draftDirtyStates[skill.id] ?? false),
      ],
      integrity: integrity,
    );
  }
}

final class _ProjectionState {
  const _ProjectionState(this.revision, this.skills);

  final int revision;
  final List<ManagedSkill> skills;
}

final class _Inspection implements DraftDirtyStateInspectionPort {
  _Inspection(this.dirtyStates, {List<String> failures = const <String>[]})
    : failures = List<String>.of(failures);

  final Map<ManagedSkillId, bool> dirtyStates;
  final List<String> failures;
  final List<ManagedSkillId> inspectedIds = [];

  @override
  Future<DraftDirtyStateInspectionResult> inspectDraftDirtyState({
    required ManagedSkill skill,
    required CancellationToken cancellationToken,
  }) async {
    inspectedIds.add(skill.id);
    if (failures.isNotEmpty) {
      return DraftDirtyStateInspectionFailure(failures.removeAt(0));
    }
    return DraftDirtyStateInspectionSuccess(isDirty: dirtyStates[skill.id]!);
  }
}

ManagedSkill _skill(int index) {
  final id = ManagedSkillId(
    '123e4567-e89b-42d3-a456-${(426614174000 + index).toString().padLeft(12, '0')}',
  );
  return ManagedSkill(
    id: id,
    slotKey: 'skill-$index',
    declaredName: 'skill-$index',
    displayName: 'Skill $index',
    description: 'Description $index',
    source: GitSourceDescriptor(locator: 'https://example.com/repo.git'),
    currentRevision: ManagedSkillRevisionSummary(
      contentHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      fileCount: 1,
      byteSize: 10,
      publishedAt: DateTime.utc(2026, 8, 20),
    ),
    draft: DraftSummary(
      purpose: DraftPurpose.customization,
      path: '/tmp/drafts/skill-$index',
      isDirty: false,
      updatedAt: DateTime.utc(2026, 8, 20),
    ),
  );
}

ManagedSkill _copySkill(ManagedSkill skill, {required bool isDirty}) =>
    ManagedSkill(
      id: skill.id,
      slotKey: skill.slotKey,
      declaredName: skill.declaredName,
      displayName: skill.displayName,
      description: skill.description,
      source: skill.source,
      currentRevision: skill.currentRevision,
      favorite: skill.favorite,
      note: skill.note,
      personalTagIds: skill.personalTagIds,
      activations: skill.activations,
      draft: skill.draft == null
          ? null
          : DraftSummary(
              purpose: skill.draft!.purpose,
              path: skill.draft!.path,
              isDirty: isDirty,
              updatedAt: skill.draft!.updatedAt,
            ),
      updateCandidate: skill.updateCandidate,
    );
