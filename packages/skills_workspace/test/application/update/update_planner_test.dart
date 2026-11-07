import 'dart:async';

import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/application/update/update_planner.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/source/source_acquisition_fakes.dart';
import '../../support/update/update_fakes.dart';

void main() {
  late FakeSourceAcquisitionPorts sources;
  late RecordingUpdateDraftInspector drafts;
  late RecordingUpdateRevisionStateReader states;
  late RecordingSlotMigrationInspector slotMigrations;
  late UpdatePlanner planner;

  setUp(() {
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: AcquiredSource(
              canonicalSource: source,
              skills: [_incomingSkill(source)],
            ),
          ),
    );
    drafts = RecordingUpdateDraftInspector();
    states = RecordingUpdateRevisionStateReader(_revisionState());
    slotMigrations = RecordingSlotMigrationInspector();
    planner = _planner(
      sources: sources,
      drafts: drafts,
      states: states,
      slotMigrations: slotMigrations,
    );
  });

  Future<UpdatePlanningResult<PlannedUpdate>> planWithIncomingProvenance({
    required SourceDescriptor persisted,
    required SourceDescriptor incoming,
    String hashCharacter = 'b',
  }) async {
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: AcquiredSource(
              canonicalSource: persisted,
              skills: [_incomingSkill(incoming, hashCharacter: hashCharacter)],
            ),
          ),
    );
    planner = _planner(
      sources: sources,
      drafts: drafts,
      states: states,
      slotMigrations: slotMigrations,
    );
    return planner.planUpdate(
      snapshot: _snapshot(source: persisted),
      managedSkillId: _skillId,
    );
  }

  void expectSelectionContinuityLost(
    UpdatePlanningResult<PlannedUpdate> result,
  ) {
    expect(
      result.failureOrNull?.code,
      UpdatePlanningFailureCode.sourceContinuityLost,
    );
    expect(result.failureOrNull?.context, <String, Object?>{
      'reason': 'selectedSkillIdentityChanged',
      'matchingSelectionCount': 0,
    });
    expect(sources.calls, hasLength(1));
    expect(slotMigrations.calls, 0);
  }

  test('Dirty Draft rejects Update before source and revision work', () async {
    drafts.result = const UpdateDraftInspection.dirty();

    final result = await planner.planUpdate(
      snapshot: _snapshot(draft: _draft(isDirty: false)),
      managedSkillId: _skillId,
    );

    expect(
      result.failureOrNull?.code,
      UpdatePlanningFailureCode.dirtyDraftResolutionRequired,
    );
    expect(drafts.calls, 1);
    expect(states.calls, 0);
    expect(sources.calls, isEmpty);
    expect(slotMigrations.calls, 0);
  });

  test('batch barrier inspects Drafts without acquiring any Source', () async {
    drafts.result = const UpdateDraftInspection.dirty();

    final result = await planner.validateUpdateBarrier(
      snapshot: _snapshot(draft: _draft(isDirty: false)),
      managedSkillId: _skillId,
    );

    expect(
      result.failureOrNull?.code,
      UpdatePlanningFailureCode.dirtyDraftResolutionRequired,
    );
    expect(drafts.calls, 1);
    expect(states.calls, 0);
    expect(sources.calls, isEmpty);
  });

  test(
    'batch barrier preserves cancellation requested during Draft inspection',
    () async {
      final cancellation = CancellationSource();
      final entered = Completer<void>();
      final release = Completer<void>();
      drafts.onInspect = ({required skill, required cancellationToken}) async {
        entered.complete();
        await release.future;
        return UpdateDraftInspectionFailure(
          cancellationToken.isCancelled
              ? 'operationCancelled'
              : 'draftInspectionFailed',
        );
      };

      final pending = planner.validateUpdateBarrier(
        snapshot: _snapshot(draft: _draft(isDirty: false)),
        managedSkillId: _skillId,
        cancellationToken: cancellation.token,
      );
      await entered.future;
      await cancellation.cancel();
      release.complete();
      final result = await pending;

      expect(
        result.failureOrNull?.code,
        UpdatePlanningFailureCode.operationCancelled,
      );
      expect(states.calls, 0);
      expect(sources.calls, isEmpty);
    },
  );

  test('Update preserves cancellation during Draft inspection', () async {
    final cancellation = CancellationSource();
    final entered = Completer<void>();
    final release = Completer<void>();
    drafts.onInspect = ({required skill, required cancellationToken}) async {
      entered.complete();
      await release.future;
      return UpdateDraftInspectionFailure(
        cancellationToken.isCancelled
            ? 'operationCancelled'
            : 'draftInspectionFailed',
      );
    };

    final pending = planner.planUpdate(
      snapshot: _snapshot(draft: _draft(isDirty: false)),
      managedSkillId: _skillId,
      cancellationToken: cancellation.token,
    );
    await entered.future;
    await cancellation.cancel();
    release.complete();
    final result = await pending;

    expect(
      result.failureOrNull?.code,
      UpdatePlanningFailureCode.operationCancelled,
    );
    expect(states.calls, 0);
    expect(sources.calls, isEmpty);
  });

  test(
    'existing Update Candidate rejects before Draft, source, and revision work',
    () async {
      final result = await planner.planUpdate(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
      );

      expect(
        result.failureOrNull?.code,
        UpdatePlanningFailureCode.updateCandidateResolutionRequired,
      );
      expect(drafts.calls, 0);
      expect(states.calls, 0);
      expect(sources.calls, isEmpty);
      expect(slotMigrations.calls, 0);
    },
  );

  test(
    'read-only update check may run while Draft and Session exist',
    () async {
      final result = await planner.checkUpdate(
        snapshot: _snapshot(
          draft: _draft(isDirty: true),
          updateCandidate: _candidateSummary(),
        ),
        managedSkillId: _skillId,
      );

      final check = result.valueOrNull!;
      expect(check.changed, isTrue);
      expect(check.incomingContentHash, _hash('b'));
      expect(drafts.calls, 0);
      expect(states.calls, 1);
      expect(sources.calls, hasLength(1));
      expect(slotMigrations.calls, 0);
    },
  );

  group('Source continuity', () {
    test(
      'check rejects a canonical Source identity change before comparison',
      () async {
        final persisted = _localSource();
        sources = FakeSourceAcquisitionPorts(
          (source, selection, options, cancellationToken) async =>
              SourceAcquisitionSuccess<AcquiredSource>(
                value: AcquiredSource(
                  canonicalSource: LocalSourceDescriptor(
                    locator: '/moved-source',
                    skillPath: 'one',
                  ),
                  skills: [_incomingSkill(persisted)],
                ),
              ),
        );
        planner = _planner(
          sources: sources,
          drafts: drafts,
          states: states,
          slotMigrations: slotMigrations,
        );

        final result = await planner.checkUpdate(
          snapshot: _snapshot(source: persisted),
          managedSkillId: _skillId,
        );

        expect(
          result.failureOrNull?.code,
          UpdatePlanningFailureCode.sourceContinuityLost,
        );
        expect(result.failureOrNull?.context, <String, Object?>{
          'reason': 'canonicalSourceIdentityChanged',
        });
        expect(sources.calls, [persisted]);
        expect(slotMigrations.calls, 0);
      },
    );

    test(
      'Update rejects a canonical Source identity change before preparation',
      () async {
        final persisted = _localSource();
        sources = FakeSourceAcquisitionPorts(
          (source, selection, options, cancellationToken) async =>
              SourceAcquisitionSuccess<AcquiredSource>(
                value: AcquiredSource(
                  canonicalSource: LocalSourceDescriptor(
                    locator: '/moved-source',
                    skillPath: 'one',
                  ),
                  skills: [_incomingSkill(persisted)],
                ),
              ),
        );
        planner = _planner(
          sources: sources,
          drafts: drafts,
          states: states,
          slotMigrations: slotMigrations,
        );

        final result = await planner.planUpdate(
          snapshot: _snapshot(source: persisted),
          managedSkillId: _skillId,
        );

        expect(
          result.failureOrNull?.code,
          UpdatePlanningFailureCode.sourceContinuityLost,
        );
        expect(result.failureOrNull?.context, <String, Object?>{
          'reason': 'canonicalSourceIdentityChanged',
        });
        expect(sources.calls, [persisted]);
        expect(slotMigrations.calls, 0);
      },
    );

    test('check rejects a changed selected-Skill provenance', () async {
      final persisted = _localSource();
      final unrelated = LocalSourceDescriptor(
        locator: '/unrelated',
        skillPath: 'one',
      );
      sources = FakeSourceAcquisitionPorts(
        (source, selection, options, cancellationToken) async =>
            SourceAcquisitionSuccess<AcquiredSource>(
              value: AcquiredSource(
                canonicalSource: persisted,
                skills: [_incomingSkill(unrelated)],
              ),
            ),
      );
      planner = _planner(
        sources: sources,
        drafts: drafts,
        states: states,
        slotMigrations: slotMigrations,
      );

      final result = await planner.checkUpdate(
        snapshot: _snapshot(source: persisted),
        managedSkillId: _skillId,
      );

      expect(
        result.failureOrNull?.code,
        UpdatePlanningFailureCode.sourceContinuityLost,
      );
      expect(result.failureOrNull?.context, <String, Object?>{
        'reason': 'selectedSkillIdentityChanged',
        'matchingSelectionCount': 0,
      });
      expect(sources.calls, [persisted]);
      expect(slotMigrations.calls, 0);
    });

    test(
      'similar Skill path cannot replace the persisted Source selection',
      () async {
        final persisted = _localSource();
        final similarName = LocalSourceDescriptor(
          locator: '/source',
          skillPath: 'one-copy',
        );

        final result = await planWithIncomingProvenance(
          persisted: persisted,
          incoming: similarName,
        );

        expectSelectionContinuityLost(result);
      },
    );

    test('identical content hash cannot establish Source continuity', () async {
      final persisted = _localSource();
      final sameBytesElsewhere = LocalSourceDescriptor(
        locator: '/other-source',
        skillPath: 'one',
      );

      final result = await planWithIncomingProvenance(
        persisted: persisted,
        incoming: sameBytesElsewhere,
        hashCharacter: 'a',
      );

      expectSelectionContinuityLost(result);
    });

    test('Git path rename heuristics cannot establish continuity', () async {
      final persisted = GitSourceDescriptor(
        locator: 'https://example.test/catalog.git',
        ref: 'main',
        repositorySubpath: 'skills',
        skillPath: 'one',
      );
      final renamed = GitSourceDescriptor(
        locator: 'https://example.test/catalog.git',
        ref: 'main',
        repositorySubpath: 'skills',
        skillPath: 'one-renamed',
      );

      final result = await planWithIncomingProvenance(
        persisted: persisted,
        incoming: renamed,
      );

      expectSelectionContinuityLost(result);
    });

    test('unrelated discovered path cannot establish continuity', () async {
      final persisted = _localSource();
      final unrelated = LocalSourceDescriptor(
        locator: '/unrelated',
        skillPath: 'other',
      );

      final result = await planWithIncomingProvenance(
        persisted: persisted,
        incoming: unrelated,
      );

      expectSelectionContinuityLost(result);
    });
  });

  test('content-identical Upstream is a no-op without preparation', () async {
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) async =>
          SourceAcquisitionSuccess<AcquiredSource>(
            value: AcquiredSource(
              canonicalSource: source,
              skills: [_incomingSkill(source, hashCharacter: 'a')],
            ),
          ),
    );
    planner = _planner(
      sources: sources,
      drafts: drafts,
      states: states,
      slotMigrations: slotMigrations,
    );

    final result = await planner.planUpdate(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
    );

    final plan = result.valueOrNull!;
    expect(plan, isA<UpdateNoChange>());
    expect(slotMigrations.calls, 0);
  });

  test('changed source emits a pure post-Journal preparation intent', () async {
    final result = await planner.planUpdate(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
    );

    final plan = result.valueOrNull! as UpdatePreparationRequired;
    expect(plan.intent.managedSkillId, _skillId);
    expect(plan.intent.sourceLineage, _lineage);
    expect(plan.intent.previousUpstream, _object('1'));
    expect(plan.intent.currentEffective, _object('2'));
    expect(plan.intent.incomingTree.contentHash, _hash('b'));
    expect(plan.intent.incomingDeclaredName, 'one');
    expect(plan.intent.incomingSlotKey, 'one');
    expect(plan.intent.hadCleanDraft, isFalse);
  });

  test(
    'verified source rename checks Slot Migration before preparation',
    () async {
      sources = FakeSourceAcquisitionPorts(
        (source, selection, options, cancellationToken) async =>
            SourceAcquisitionSuccess<AcquiredSource>(
              value: AcquiredSource(
                canonicalSource: source,
                skills: [
                  _incomingSkill(
                    source,
                    declaredName: 'Renamed Skill',
                    slotKey: 'renamed-skill',
                  ),
                ],
              ),
            ),
      );
      planner = _planner(
        sources: sources,
        drafts: drafts,
        states: states,
        slotMigrations: slotMigrations,
      );

      final result = await planner.planUpdate(
        snapshot: _snapshot(),
        managedSkillId: _skillId,
      );

      final intent = (result.valueOrNull! as UpdatePreparationRequired).intent;
      expect(slotMigrations.calls, 1);
      expect(slotMigrations.lastOldSlotKey, 'one');
      expect(slotMigrations.lastNewSlotKey, 'renamed-skill');
      expect(intent.incomingDeclaredName, 'Renamed Skill');
    },
  );

  group('prepared Update assembly', () {
    late UpdatePreparationRequired preflight;

    setUp(() async {
      preflight =
          (await planner.planUpdate(
                snapshot: _snapshot(activations: [_activation()]),
                managedSkillId: _skillId,
              )).valueOrNull!
              as UpdatePreparationRequired;
    });

    test('clean merge advances Upstream and Effective together', () {
      final result = const UpdatePlanAssembler().assembleUpdate(
        preflight: preflight,
        prepared: _preparedClean(),
      );

      final plan = result.valueOrNull!;
      expect(plan.kind, PreparedUpdatePlanKind.published);
      expect(plan.revisionSelectionChanges, hasLength(1));
      final selection = plan.revisionSelectionChanges.single;
      expect(selection.previousUpstream?.objectId, _object('1'));
      expect(selection.previousEffective?.objectId, _object('2'));
      expect(selection.intendedUpstream?.objectId, _object('4'));
      expect(selection.intendedEffective?.objectId, _object('6'));
      expect(
        plan.businessChanges.mutations.whereType<PutUpdateCandidateSession>(),
        isEmpty,
      );
      expect(
        plan.materializationIntents
            .whereType<UpdateRepositoryMaterializationIntent>(),
        hasLength(1),
      );
      expect(
        plan.materializationIntents
            .whereType<UpdateActivationMaterializationIntent>(),
        hasLength(1),
      );
    });

    test('incoming Upstream must have old Upstream as its sole parent', () {
      final invalid = _preparedClean(
        incomingRequest: RevisionCommitRequest(
          tree: _object('3'),
          parents: [_object('2')],
          kind: RevisionCommitKind.upstream,
        ),
      );

      final result = const UpdatePlanAssembler().assembleUpdate(
        preflight: preflight,
        prepared: invalid,
      );

      expect(
        result.failureOrNull?.code,
        UpdatePlanningFailureCode.invalidPreparedEvidence,
      );
    });

    test(
      'conflict persists one resumable Session and leaves Pointers unchanged',
      () {
        final result = const UpdatePlanAssembler().assembleUpdate(
          preflight: preflight,
          prepared: _preparedSession(
            outcome: PreparedUpdateConflict(
              candidateObjectId: _object('5'),
              candidateTree: _tree('c'),
              conflicts: [
                WorkspaceUpdateCandidateItem(
                  path: 'SKILL.md',
                  kind: WorkspaceUpdateCandidateItemKind.text,
                  state: WorkspaceUpdateCandidateItemState.unresolved,
                  baseObjectId: null,
                  oursObjectId: null,
                  theirsObjectId: null,
                ),
              ],
            ),
          ),
        );

        final plan = result.valueOrNull!;
        expect(plan.kind, PreparedUpdatePlanKind.sessionCreated);
        expect(plan.revisionSelectionChanges, isEmpty);
        expect(
          plan.businessChanges.mutations.whereType<PutUpdateCandidateSession>(),
          hasLength(1),
        );
        expect(
          plan.materializationIntents
              .whereType<UpdateCandidateDraftMaterializationIntent>(),
          hasLength(1),
        );
        expect(
          plan.materializationIntents
              .whereType<UpdateRepositoryMaterializationIntent>(),
          isEmpty,
        );
      },
    );

    test('post-merge validation failure uses the same Session type', () {
      final result = const UpdatePlanAssembler().assembleUpdate(
        preflight: preflight,
        prepared: _preparedSession(
          outcome: PreparedUpdateValidationFailure(
            candidateObjectId: _object('5'),
            candidateTree: _tree('c'),
            validationCode: 'missingSkillFrontmatter',
          ),
        ),
      );

      final plan = result.valueOrNull!;
      expect(plan.kind, PreparedUpdatePlanKind.sessionCreated);
      final session = plan.businessChanges.mutations
          .whereType<PutUpdateCandidateSession>()
          .single;
      expect(session.status, WorkspaceUpdateCandidateStatus.validationFailed);
      expect(session.validationCode, 'missingSkillFrontmatter');
      expect(plan.revisionSelectionChanges, isEmpty);
    });
  });

  group('Update Candidate lifecycle', () {
    late RecordingUpdateCandidateStateReader candidateStates;
    late UpdateCandidatePlanner candidatePlanner;

    setUp(() {
      candidateStates = RecordingUpdateCandidateStateReader(_candidateState());
      candidatePlanner = UpdateCandidatePlanner(
        states: candidateStates,
        slotMigrations: slotMigrations,
        clock: () => DateTime.utc(2026, 8, 17),
      );
    });

    test(
      'Publish rejects unresolved conflict items before preparation',
      () async {
        final result = await candidatePlanner.planPublish(
          snapshot: _snapshot(updateCandidate: _candidateSummary()),
          managedSkillId: _skillId,
        );

        expect(
          result.failureOrNull?.code,
          UpdatePlanningFailureCode.unresolvedUpdateConflicts,
        );
      },
    );

    test('explicit conflict resolution creates one typed mutation', () async {
      final result = await candidatePlanner.planResolution(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
        path: 'SKILL.md',
        resolutionState: UpdateConflictResolutionState.resolved,
      );

      final plan = result.valueOrNull!;
      expect(plan.changed, isTrue);
      final mutation =
          plan.businessChanges.mutations.single
              as SetUpdateCandidateItemResolution;
      expect(mutation.path, 'SKILL.md');
      expect(mutation.state, WorkspaceUpdateCandidateItemState.resolved);
    });

    test('repeating the same conflict resolution is a no-op', () async {
      candidateStates.state = _candidateState(allResolved: true);

      final result = await candidatePlanner.planResolution(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
        path: 'SKILL.md',
        resolutionState: UpdateConflictResolutionState.resolved,
      );

      expect(result.valueOrNull?.changed, isFalse);
      expect(result.valueOrNull?.businessChanges.isEmpty, isTrue);
    });

    test('unknown conflict path is rejected without mutation', () async {
      final result = await candidatePlanner.planResolution(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
        path: 'missing.md',
        resolutionState: UpdateConflictResolutionState.resolved,
      );

      expect(
        result.failureOrNull?.code,
        UpdatePlanningFailureCode.updateConflictNotFound,
      );
    });

    test('Publish intent requires the incoming source Declared Name', () async {
      candidateStates.state = _candidateState(allResolved: true);

      final result = await candidatePlanner.planPublish(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
      );

      final plan = result.valueOrNull!;
      expect(plan.intent.requiredDeclaredName, 'one');
      expect(plan.intent.previousEffective, _object('2'));
      expect(plan.intent.incomingUpstream, _object('4'));
    });

    test('Publish revalidates a source-driven Slot Migration', () async {
      candidateStates.state = _candidateState(
        allResolved: true,
        incomingDeclaredName: 'Renamed Skill',
        incomingSlotKey: 'renamed-skill',
      );

      final result = await candidatePlanner.planPublish(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
      );

      expect(result.valueOrNull, isNotNull);
      expect(slotMigrations.calls, 1);
      expect(slotMigrations.lastNewSlotKey, 'renamed-skill');
    });

    test(
      'Publish rejects a prepared Draft that changes Declared Name',
      () async {
        candidateStates.state = _candidateState(allResolved: true);
        final preflight = (await candidatePlanner.planPublish(
          snapshot: _snapshot(updateCandidate: _candidateSummary()),
          managedSkillId: _skillId,
        )).valueOrNull!;

        final result = const UpdatePlanAssembler().assembleCandidatePublish(
          preflight: preflight,
          prepared: _preparedCandidatePublish(declaredName: 'other'),
        );

        expect(
          result.failureOrNull?.code,
          UpdatePlanningFailureCode.declaredNameChangeNotAllowed,
        );
      },
    );

    test('Publish advances both Pointers and deletes the Session', () async {
      candidateStates.state = _candidateState(allResolved: true);
      final preflight = (await candidatePlanner.planPublish(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
      )).valueOrNull!;

      final result = const UpdatePlanAssembler().assembleCandidatePublish(
        preflight: preflight,
        prepared: _preparedCandidatePublish(),
      );

      final plan = result.valueOrNull!;
      expect(plan.revisionSelectionChanges, hasLength(1));
      expect(
        plan.businessChanges.mutations
            .whereType<DeleteUpdateCandidateSession>(),
        hasLength(1),
      );
      expect(
        plan.revisionSelectionChanges.single.intendedUpstream?.objectId,
        _object('4'),
      );
      expect(
        plan.revisionSelectionChanges.single.intendedEffective?.objectId,
        _object('6'),
      );
    });

    test('abandon deletes Session and Draft without Pointer changes', () async {
      final result = await candidatePlanner.planAbandon(
        snapshot: _snapshot(updateCandidate: _candidateSummary()),
        managedSkillId: _skillId,
      );

      final plan = result.valueOrNull!;
      expect(plan.revisionSelectionChanges, isEmpty);
      expect(
        plan.businessChanges.mutations
            .whereType<DeleteUpdateCandidateSession>(),
        hasLength(1),
      );
      expect(
        plan.businessChanges.mutations.whereType<DeleteDraftWorkspace>(),
        hasLength(1),
      );
      expect(plan.cleanupIntent.previousUpstream, _object('1'));
      expect(plan.cleanupIntent.previousEffective, _object('2'));
      expect(plan.cleanupIntent.retainedPublishedRoots, <RevisionObjectId>[
        _object('1'),
        _object('2'),
      ]);
      expect(
        plan.cleanupIntent.retainedPublishedRoots,
        isNot(containsAll(<RevisionObjectId>[_object('4'), _object('5')])),
      );
    });
  });
}

UpdatePlanner _planner({
  required FakeSourceAcquisitionPorts sources,
  required RecordingUpdateDraftInspector drafts,
  required RecordingUpdateRevisionStateReader states,
  required RecordingSlotMigrationInspector slotMigrations,
}) => UpdatePlanner(
  sourceAcquisition: SourceAcquisitionCoordinator(
    local: sources,
    git: sources,
    wellKnown: sources,
  ),
  drafts: drafts,
  states: states,
  slotMigrations: slotMigrations,
  clock: () => DateTime.utc(2026, 8, 17),
);

RepositorySnapshot _snapshot({
  DraftSummary? draft,
  UpdateCandidateSummary? updateCandidate,
  List<SkillActivation> activations = const [],
  SourceDescriptor? source,
}) => RepositorySnapshot(
  revision: RepositoryRevision(9),
  managedSkills: [
    _managedSkill(
      draft: draft,
      updateCandidate: updateCandidate,
      activations: activations,
      source: source,
    ),
  ],
);

ManagedSkill _managedSkill({
  DraftSummary? draft,
  UpdateCandidateSummary? updateCandidate,
  List<SkillActivation> activations = const [],
  SourceDescriptor? source,
}) => ManagedSkill(
  id: _skillId,
  slotKey: 'one',
  declaredName: 'one',
  displayName: 'One',
  description: 'Old description',
  source: source ?? _localSource(),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: _hash('e'),
    fileCount: 1,
    byteSize: 3,
    publishedAt: DateTime.utc(2026, 8, 1),
  ),
  activations: activations,
  draft: draft,
  updateCandidate: updateCandidate,
);

AcquiredSourceSkill _incomingSkill(
  SourceDescriptor source, {
  String declaredName = 'one',
  String slotKey = 'one',
  String hashCharacter = 'b',
}) => AcquiredSourceSkill(
  provenance: source,
  declaredName: declaredName,
  description: 'Incoming description',
  slotKey: slotKey,
  skillPath: 'one',
  frontmatter: {'name': declaredName},
  tree: _tree(hashCharacter),
);

UpdateRevisionState _revisionState() => UpdateRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  previousUpstream: _object('1'),
  currentEffective: _object('2'),
  previousUpstreamContentHash: _hash('a'),
  managedSkillCreatedAtMicros: DateTime.utc(2026, 7, 1).microsecondsSinceEpoch,
  draftCreatedAtMicros: null,
);

PreparedUpdateRevision _preparedClean({
  RevisionCommitRequest? incomingRequest,
}) => PreparedUpdateRevision(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  incomingTreeObjectId: _object('3'),
  incomingUpstreamObjectId: _object('4'),
  incomingRequest:
      incomingRequest ??
      RevisionCommitRequest(
        tree: _object('3'),
        parents: [_object('1')],
        kind: RevisionCommitKind.upstream,
      ),
  outcome: PreparedUpdateClean(
    effectiveObjectId: _object('6'),
    mergedTreeObjectId: _object('5'),
    effectiveRequest: RevisionCommitRequest(
      tree: _object('5'),
      parents: [_object('2'), _object('4')],
      kind: RevisionCommitKind.effectiveUpdate,
    ),
    mergedTree: _tree('c'),
    declaredName: 'one',
    description: 'Merged description',
    draftDisposition: UpdateDraftDisposition.noDraft,
    capturedDraftFingerprint: null,
  ),
  candidateRecoveryReference: RecoveryReference('update-candidate'),
  bundleRecoveryReference: RecoveryReference('update-bundle'),
  materializationRecoveryReference: RecoveryReference('update-materialization'),
  draftRecoveryReference: RecoveryReference('update-draft'),
);

PreparedUpdateRevision _preparedSession({
  required PreparedUpdateOutcome outcome,
}) => PreparedUpdateRevision(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  incomingTreeObjectId: _object('3'),
  incomingUpstreamObjectId: _object('4'),
  incomingRequest: RevisionCommitRequest(
    tree: _object('3'),
    parents: [_object('1')],
    kind: RevisionCommitKind.upstream,
  ),
  outcome: outcome,
  candidateRecoveryReference: RecoveryReference('update-candidate'),
  bundleRecoveryReference: RecoveryReference('update-bundle'),
  materializationRecoveryReference: RecoveryReference('update-materialization'),
  draftRecoveryReference: RecoveryReference('update-draft'),
);

UpdateCandidateState _candidateState({
  bool allResolved = false,
  String incomingDeclaredName = 'one',
  String incomingSlotKey = 'one',
}) => UpdateCandidateState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  previousUpstream: _object('1'),
  previousEffective: _object('2'),
  incomingUpstream: _object('4'),
  candidateObjectId: _object('5'),
  incomingDeclaredName: incomingDeclaredName,
  incomingSlotKey: incomingSlotKey,
  incomingDescription: 'Incoming description',
  managedSkillCreatedAtMicros: DateTime.utc(2026, 7, 1).microsecondsSinceEpoch,
  draftCreatedAtMicros: DateTime.utc(2026, 8, 16).microsecondsSinceEpoch,
  retainedPublishedRoots: <RevisionObjectId>[_object('1'), _object('2')],
  conflicts: [
    WorkspaceUpdateCandidateItem(
      path: 'SKILL.md',
      kind: WorkspaceUpdateCandidateItemKind.text,
      state: allResolved
          ? WorkspaceUpdateCandidateItemState.resolved
          : WorkspaceUpdateCandidateItemState.unresolved,
      baseObjectId: null,
      oursObjectId: null,
      theirsObjectId: null,
    ),
  ],
);

PreparedUpdateCandidatePublish _preparedCandidatePublish({
  String declaredName = 'one',
}) => PreparedUpdateCandidatePublish(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  effectiveObjectId: _object('6'),
  publishedTreeObjectId: _object('7'),
  effectiveRequest: RevisionCommitRequest(
    tree: _object('7'),
    parents: [_object('2'), _object('4')],
    kind: RevisionCommitKind.effectiveUpdate,
  ),
  publishedTree: _tree('d'),
  declaredName: declaredName,
  description: 'Resolved description',
  draftDisposition: UpdateDraftDisposition.deleteUnchanged,
  capturedDraftFingerprint: DraftFingerprint(const []),
  candidateRecoveryReference: RecoveryReference('publish-candidate'),
  bundleRecoveryReference: RecoveryReference('publish-bundle'),
  materializationRecoveryReference: RecoveryReference(
    'publish-materialization',
  ),
  draftRecoveryReference: RecoveryReference('publish-draft'),
);

DraftSummary _draft({required bool isDirty}) => DraftSummary(
  purpose: DraftPurpose.customization,
  path: '/workspace/draft',
  isDirty: isDirty,
  updatedAt: DateTime.utc(2026, 8, 17),
);

UpdateCandidateSummary _candidateSummary() => UpdateCandidateSummary(
  status: UpdateCandidateStatus.conflicted,
  conflicts: [
    UpdateConflict(
      path: 'SKILL.md',
      kind: ConflictKind.text,
      resolutionState: UpdateConflictResolutionState.unresolved,
    ),
  ],
  createdAt: DateTime.utc(2026, 8, 17),
);

SkillActivation _activation() => SkillActivation(
  location: '/agent/skills',
  scope: ActivationScope.global,
  mode: ActivationMode.copy,
  agentIds: ['agent'],
);

NormalizedSkillTree _tree(String character) => NormalizedSkillTree(
  files: [
    NormalizedSkillFile(
      relativePath: 'SKILL.md',
      bytes: [character.codeUnitAt(0)],
      isExecutable: false,
    ),
  ],
  contentHash: _hash(character),
  byteSize: 1,
);

String _hash(String character) => character * 64;

RevisionObjectId _object(String character) => RevisionObjectId(character * 40);

final _skillId = ManagedSkillId('00000000-0000-4000-8000-000000000001');
final _lineage = SourceLineageReference('00000000-0000-4000-8000-000000000101');

LocalSourceDescriptor _localSource() =>
    LocalSourceDescriptor(locator: '/source', skillPath: 'one');
