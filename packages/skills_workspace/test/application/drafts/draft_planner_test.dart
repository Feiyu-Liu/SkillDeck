import 'package:skills_workspace/src/application/drafts/draft_models.dart';
import 'package:skills_workspace/src/application/drafts/draft_planner.dart';
import 'package:skills_workspace/src/application/drafts/draft_ports.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  late _DraftStates states;
  late DraftPlanner planner;

  setUp(() {
    states = _DraftStates(_state());
    planner = DraftPlanner(
      states: states,
      clock: () => DateTime.utc(2026, 8, 17, 12),
    );
  });

  test('inspect derives dirty state through the authoritative port', () async {
    states.inspection = DraftPlanningSuccess<DraftSummary?>(
      _draft(isDirty: true),
    );

    final result = await planner.inspect(
      snapshot: _snapshot(draft: _draft(isDirty: false)),
      managedSkillId: _skillId,
    );

    expect(result.valueOrNull?.isDirty, isTrue);
    expect(states.inspectCalls, 1);
  });

  test('ensure returns an existing Draft without mutation preflight', () async {
    final result = await planner.planEnsure(
      snapshot: _snapshot(draft: _draft(isDirty: false)),
      managedSkillId: _skillId,
    );

    expect(result.valueOrNull, isA<ExistingDraft>());
    expect(states.readCalls, 1);
  });

  test('ensure captures the current Effective as Draft base intent', () async {
    final result = await planner.planEnsure(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
    );

    final preflight = result.valueOrNull! as EnsureDraftPreparationRequired;
    expect(preflight.snapshotRevision, RepositoryRevision(4));
    expect(preflight.state.currentEffective, _object('2'));
    expect(preflight.plannedAtMicros, 1786968000000000);
  });

  test('direct Publish is blocked by an Update Candidate', () async {
    final result = await planner.planPublish(
      snapshot: _snapshot(
        draft: _draft(isDirty: true),
        updateCandidate: _candidate(),
      ),
      managedSkillId: _skillId,
    );

    expect(
      result.failureOrNull?.code,
      DraftPlanningFailureCode.updateCandidateResolutionRequired,
    );
    expect(states.readCalls, 0);
  });

  test('discard deletes only an ordinary Draft row', () async {
    final result = await planner.planDiscard(
      snapshot: _snapshot(draft: _draft(isDirty: true)),
      managedSkillId: _skillId,
    );

    final plan = result.valueOrNull!;
    expect(plan.businessChanges.mutations, hasLength(1));
    expect(
      plan.businessChanges.mutations.single.runtimeType.toString(),
      'DeleteDraftWorkspace',
    );
  });

  test('missing Draft is rejected without state access', () async {
    final result = await planner.planPublish(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
    );

    expect(result.failureOrNull?.code, DraftPlanningFailureCode.draftNotFound);
    expect(states.readCalls, 0);
  });
}

final class _DraftStates implements DraftWorkspaceStatePort {
  _DraftStates(this.state);

  DraftRevisionState? state;
  DraftPlanningResult<DraftSummary?> inspection =
      DraftPlanningSuccess<DraftSummary?>(_draft(isDirty: false));
  var readCalls = 0;
  var inspectCalls = 0;

  @override
  Future<DraftRevisionState?> readDraftState(
    ManagedSkillId managedSkillId,
  ) async {
    readCalls += 1;
    return state;
  }

  @override
  Future<DraftPlanningResult<DraftSummary?>> inspectDraft({
    required ManagedSkill skill,
    required DraftRevisionState state,
    required CancellationToken cancellationToken,
  }) async {
    inspectCalls += 1;
    return inspection;
  }
}

const _skillValue = '123e4567-e89b-42d3-a456-426614174000';
final _skillId = ManagedSkillId(_skillValue);
final _lineage = SourceLineageReference('lineage-1');

DraftRevisionState _state() => DraftRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  currentUpstream: _object('1'),
  currentEffective: _object('2'),
  managedSkillCreatedAtMicros: 1,
  draftCreatedAtMicros: 2,
);

RepositorySnapshot _snapshot({
  DraftSummary? draft,
  UpdateCandidateSummary? updateCandidate,
}) => RepositorySnapshot(
  revision: RepositoryRevision(4),
  managedSkills: <ManagedSkill>[
    ManagedSkill(
      id: _skillId,
      slotKey: 'one',
      declaredName: 'one',
      displayName: 'One',
      description: 'One Skill',
      source: LocalSourceDescriptor(locator: '/source/one'),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: 'a' * 64,
        fileCount: 1,
        byteSize: 3,
        publishedAt: DateTime.utc(2026, 8, 1),
      ),
      draft: draft,
      updateCandidate: updateCandidate,
    ),
  ],
);

DraftSummary _draft({required bool isDirty}) => DraftSummary(
  purpose: DraftPurpose.customization,
  path: '/drafts/$_skillValue',
  isDirty: isDirty,
  updatedAt: DateTime.utc(2026, 8, 17),
);

UpdateCandidateSummary _candidate() => UpdateCandidateSummary(
  status: UpdateCandidateStatus.validationFailed,
  conflicts: const <UpdateConflict>[],
  validationCode: 'invalidSkill',
  createdAt: DateTime.utc(2026, 8, 17),
);

RevisionObjectId _object(String character) => RevisionObjectId(character * 40);
