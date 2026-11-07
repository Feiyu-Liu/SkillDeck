import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/library/library_mutation_planner.dart';
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/ports/external_discovery_ports.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/project_roots/project_root_planner.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/metadata_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../support/activation/activation_fakes.dart';
import '../support/discovery/discovery_fakes.dart';
import '../support/operations/operation_fakes.dart';

void main() {
  late _SnapshotReader reader;
  late WorkspaceSnapshotPublisher snapshots;
  late OperationHarness operations;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;

  setUp(() async {
    reader = _SnapshotReader(_snapshot());
    snapshots = WorkspaceSnapshotPublisher(reader: reader);
    await snapshots.publishInitial(reader.value);
    operations = OperationHarness();
    dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildMetadataCommandHandlers(
        snapshots: snapshots,
        operations: operations.createCoordinator(),
        plans: OperationPlanAssembler(
          subjectIdentities: _SubjectIds(),
          recoveryPlans: const _RecoveryPlans(),
        ),
        projectRoots: ProjectRootPlanner(
          pathPort: _ProjectRootPaths(),
          locationIdentity: const PosixActivationLocationIdentity(),
          idPort: FakeProjectRootIdPort('generated'),
          clock: FixedWorkspaceClock(_now),
        ),
        library: LibraryMutationPlanner(tagIds: () => _newTagId),
        clock: FixedWorkspaceClock(_now),
      ),
    );
  });

  tearDown(() => snapshots.close());

  test('registers a Project Root through the common BCP and reloads', () async {
    reader.value = _snapshot(
      revision: 1,
      projectRoots: <ProjectRoot>[
        ProjectRoot(id: 'generated', path: '/workspace'),
      ],
    );

    final result = await _execute<MutationReport>(
      dispatcher,
      WorkspaceOperationKind.registerProjectRoot,
      RegisterProjectRootRequest(path: '/workspace'),
    );

    expect(result.valueOrNull?.snapshot, reader.value);
    expect(result.valueOrNull?.affectedSkillIds, isEmpty);
    expect(result, isA<SkillsSuccess<MutationReport>>());
    expect(
      operations.log.events,
      containsAllInOrder(<String>[
        'control.prepared',
        'control.commit',
        'control.complete',
      ]),
    );
  });

  group('SQLite-only metadata mutations', () {
    for (final scenario in _mutationScenarios()) {
      test(
        '${scenario.name} commits its direct success and history plan',
        () async {
          await _publishPlanningSnapshot(
            reader: reader,
            snapshots: snapshots,
            snapshot: scenario.planningSnapshot,
          );
          reader.value = scenario.committedSnapshot;
          OperationPlan? committedPlan;

          final result = await _execute<Object?>(
            dispatcher,
            scenario.kind,
            scenario.request,
            markBusinessCommitted: () {
              committedPlan = operations.controlPlane.journals.single.plan;
            },
          );

          expect(result, isA<SkillsSuccess<Object?>>());
          expect((result as SkillsSuccess<Object?>).changed, isTrue);
          scenario.expectValue(result.value, scenario.committedSnapshot);
          expect(snapshots.current, scenario.committedSnapshot);
          expect(
            operations.controlPlane.repositoryRevision,
            RepositoryRevision(1),
          );
          expect(
            operations.log.events,
            containsAllInOrder(<String>[
              'control.prepared',
              'control.commit',
              'control.complete',
            ]),
          );
          _expectHistoryPlan(committedPlan!, scenario);
        },
      );
    }
  });

  group('typed planning failures', () {
    for (final scenario in _failureScenarios()) {
      test(scenario.name, () async {
        await _publishPlanningSnapshot(
          reader: reader,
          snapshots: snapshots,
          snapshot: scenario.snapshot,
        );

        final result = await _execute<Object?>(
          dispatcher,
          scenario.kind,
          scenario.request,
        );

        expect(result.failureOrNull?.code, scenario.code);
        expect(operations.log.events, isEmpty);
        expect(operations.controlPlane.journals, isEmpty);
      });
    }
  });

  group('idempotent metadata requests', () {
    for (final scenario in _noOpScenarios()) {
      test('${scenario.name} creates neither Journal nor revision', () async {
        await _publishPlanningSnapshot(
          reader: reader,
          snapshots: snapshots,
          snapshot: scenario.snapshot,
        );

        final result = await _execute<Object?>(
          dispatcher,
          scenario.kind,
          scenario.request,
        );

        expect(result, isA<SkillsSuccess<Object?>>());
        expect((result as SkillsSuccess<Object?>).changed, isFalse);
        scenario.expectValue(result.value, scenario.snapshot);
        expect(operations.log.events, isEmpty);
        expect(
          operations.controlPlane.repositoryRevision,
          RepositoryRevision(0),
        );
        expect(operations.controlPlane.journals, isEmpty);
      });
    }
  });

  group('metadata transaction boundary matrix', () {
    for (final scenario in _mutationScenarios()) {
      test('${scenario.name} honors pre-cancellation before Journal', () async {
        await _publishPlanningSnapshot(
          reader: reader,
          snapshots: snapshots,
          snapshot: scenario.planningSnapshot,
        );
        final cancellation = CancellationSource();
        await cancellation.cancel();

        final result = await _execute<Object?>(
          dispatcher,
          scenario.kind,
          scenario.request,
          cancellationToken: cancellation.token,
        );

        expect(result.failureOrNull?.code, SkillsErrorCode.operationCancelled);
        expect(operations.log.events, isNot(contains('control.prepared')));
        expect(
          operations.controlPlane.repositoryRevision,
          RepositoryRevision(0),
        );
        expect(operations.controlPlane.journals, isEmpty);
      });

      test(
        '${scenario.name} rejects a stale revision before Journal',
        () async {
          await _publishPlanningSnapshot(
            reader: reader,
            snapshots: snapshots,
            snapshot: scenario.planningSnapshot,
          );
          operations.controlPlane.repositoryRevision = RepositoryRevision(2);

          final result = await _execute<Object?>(
            dispatcher,
            scenario.kind,
            scenario.request,
          );

          expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
          expect(result.failureOrNull?.context['actualRepositoryRevision'], 2);
          expect(operations.log.events, isNot(contains('control.prepared')));
          expect(operations.controlPlane.journals, isEmpty);
        },
      );

      test('${scenario.name} exposes post-BCP finalization pending', () async {
        await _publishPlanningSnapshot(
          reader: reader,
          snapshots: snapshots,
          snapshot: scenario.planningSnapshot,
        );
        reader.value = scenario.committedSnapshot;
        operations.failures.failures.add('recovery.finalize:finalize');
        OperationPlan? committedPlan;

        final result = await _execute<Object?>(
          dispatcher,
          scenario.kind,
          scenario.request,
          markBusinessCommitted: () {
            committedPlan = operations.controlPlane.journals.single.plan;
          },
        );

        expect(result.isCommittedFinalizationPending, isTrue);
        expect(
          result.warnings.single.code,
          SkillsWarningCode.finalizationDeferred,
        );
        expect(
          result.finalizationPendingOrNull?.committedRepositoryRevision,
          RepositoryRevision(1),
        );
        expect(snapshots.current, scenario.committedSnapshot);
        _expectHistoryPlan(committedPlan!, scenario);
      });
    }
  });

  test(
    'an idempotent Favorite does not create a Journal or revision',
    () async {
      final result = await _execute<RepositorySnapshot>(
        dispatcher,
        WorkspaceOperationKind.setFavorite,
        SetFavoriteRequest(managedSkillId: _skillId, isFavorite: false),
      );

      expect(result.valueOrNull, snapshots.current);
      expect((result as SkillsSuccess<RepositorySnapshot>).changed, isFalse);
      expect(operations.log.events, isEmpty);
    },
  );

  test('Favorite mutation records a Skill subject and marks the BCP', () async {
    reader.value = _snapshot(revision: 1, favorite: true);
    var committed = false;

    final result = await _execute<RepositorySnapshot>(
      dispatcher,
      WorkspaceOperationKind.setFavorite,
      SetFavoriteRequest(managedSkillId: _skillId, isFavorite: true),
      markBusinessCommitted: () => committed = true,
    );

    expect(result.valueOrNull, reader.value);
    expect(committed, isTrue);
    expect(operations.controlPlane.repositoryRevision, RepositoryRevision(1));
    expect(operations.log.events, contains('control.commit'));
  });

  test('duplicate Personal Tag is a stable typed failure', () async {
    reader.value = snapshots.current;
    final result = await _execute<PersonalTag>(
      dispatcher,
      WorkspaceOperationKind.createPersonalTag,
      CreatePersonalTagRequest(name: ' Existing '),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.duplicatePersonalTag);
    expect(operations.log.events, isEmpty);
  });

  test('stale write fails before a Prepared Journal', () async {
    operations.controlPlane.repositoryRevision = RepositoryRevision(2);

    final result = await _execute<RepositorySnapshot>(
      dispatcher,
      WorkspaceOperationKind.setFavorite,
      SetFavoriteRequest(managedSkillId: _skillId, isFavorite: true),
    );

    expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
    expect(operations.log.events, isNot(contains('control.prepared')));
  });

  test('post-BCP failure returns committed-finalization-pending', () async {
    operations.failures.failures.add('recovery.finalize:finalize');
    reader.value = _snapshot(revision: 1, favorite: true);

    final result = await _execute<RepositorySnapshot>(
      dispatcher,
      WorkspaceOperationKind.setFavorite,
      SetFavoriteRequest(managedSkillId: _skillId, isFavorite: true),
    );

    expect(result.isCommittedFinalizationPending, isTrue);
    expect(result.warnings.single.code, SkillsWarningCode.finalizationDeferred);
    expect(snapshots.current, reader.value);
  });
}

final _now = DateTime.utc(2026, 8, 17, 12);
final _earlier = DateTime.utc(2026, 8, 16, 12);
const _skillValue = '123e4567-e89b-42d3-a456-426614174000';
const _tagId = '123e4567-e89b-42d3-b456-426614174001';
const _newTagId = '123e4567-e89b-42d3-b456-426614174009';
const _otherTagId = '123e4567-e89b-42d3-b456-426614174010';
const _operationValue = '123e4567-e89b-42d3-8456-426614174002';
const _subjectValue = '123e4567-e89b-42d3-9456-426614174003';
final _skillId = ManagedSkillId(_skillValue);

RepositorySnapshot _snapshot({
  int revision = 0,
  bool favorite = false,
  bool includeSkill = true,
  String? note,
  DateTime? noteUpdatedAt,
  List<String> personalTagIds = const <String>[],
  List<ProjectRoot> projectRoots = const <ProjectRoot>[],
  List<PersonalTag>? personalTags,
}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: includeSkill
      ? <ManagedSkill>[
          ManagedSkill(
            id: _skillId,
            slotKey: 'example',
            declaredName: 'example',
            displayName: 'Example',
            description: 'Example Skill',
            source: LocalSourceDescriptor(locator: '/source/example'),
            currentRevision: ManagedSkillRevisionSummary(
              contentHash: 'a' * 64,
              fileCount: 1,
              byteSize: 1,
              publishedAt: _now,
            ),
            favorite: SkillFavorite(
              isFavorite: favorite,
              changedAt: favorite ? _now : null,
            ),
            note: note == null
                ? null
                : SkillNote(text: note, updatedAt: noteUpdatedAt ?? _earlier),
            personalTagIds: personalTagIds,
          ),
        ]
      : const <ManagedSkill>[],
  projectRoots: projectRoots,
  personalTags: personalTags ?? <PersonalTag>[_existingTag()],
);

PersonalTag _existingTag({
  String name = 'Existing',
  String? color,
  DateTime? updatedAt,
}) => PersonalTag(
  id: _tagId,
  name: name,
  color: color,
  createdAt: _earlier,
  updatedAt: updatedAt ?? _earlier,
);

PersonalTag _newTag() => PersonalTag(
  id: _newTagId,
  name: 'New Tag',
  color: '#112233',
  createdAt: _now,
  updatedAt: _now,
);

PersonalTag _otherTag() => PersonalTag(
  id: _otherTagId,
  name: 'Other',
  createdAt: _earlier,
  updatedAt: _earlier,
);

List<_MetadataMutationScenario>
_mutationScenarios() => <_MetadataMutationScenario>[
  _MetadataMutationScenario(
    name: 'Unregister Project Root',
    kind: WorkspaceOperationKind.unregisterProjectRoot,
    request: UnregisterProjectRootRequest(id: 'root'),
    planningSnapshot: _snapshot(
      projectRoots: <ProjectRoot>[ProjectRoot(id: 'root', path: '/workspace')],
    ),
    committedSnapshot: _snapshot(revision: 1),
    expectValue: (value, committed) {
      expect(value, isA<MutationReport>());
      final report = value! as MutationReport;
      expect(report.snapshot, committed);
      expect(report.affectedSkillIds, isEmpty);
    },
  ),
  _MetadataMutationScenario(
    name: 'Save Note',
    kind: WorkspaceOperationKind.saveNote,
    request: SaveNoteRequest(managedSkillId: _skillId, text: ' Working notes '),
    planningSnapshot: _snapshot(),
    committedSnapshot: _snapshot(
      revision: 1,
      note: 'Working notes',
      noteUpdatedAt: _now,
    ),
    expectedSubjectIds: <ManagedSkillId>{_skillId},
    expectValue: _expectSnapshotValue,
  ),
  _MetadataMutationScenario(
    name: 'Delete Note',
    kind: WorkspaceOperationKind.deleteNote,
    request: DeleteNoteRequest(managedSkillId: _skillId),
    planningSnapshot: _snapshot(note: 'Old note'),
    committedSnapshot: _snapshot(revision: 1),
    expectedSubjectIds: <ManagedSkillId>{_skillId},
    expectValue: _expectSnapshotValue,
  ),
  _MetadataMutationScenario(
    name: 'Create Personal Tag',
    kind: WorkspaceOperationKind.createPersonalTag,
    request: CreatePersonalTagRequest(name: ' New Tag ', color: '#112233'),
    planningSnapshot: _snapshot(),
    committedSnapshot: _snapshot(
      revision: 1,
      personalTags: <PersonalTag>[_existingTag(), _newTag()],
    ),
    expectValue: (value, committed) {
      expect(value, committed.findPersonalTag(_newTagId));
    },
  ),
  _MetadataMutationScenario(
    name: 'Update Personal Tag',
    kind: WorkspaceOperationKind.updatePersonalTag,
    request: UpdatePersonalTagRequest(
      tagId: _tagId,
      name: ' Renamed ',
      color: '#445566',
    ),
    planningSnapshot: _snapshot(),
    committedSnapshot: _snapshot(
      revision: 1,
      personalTags: <PersonalTag>[
        _existingTag(name: 'Renamed', color: '#445566', updatedAt: _now),
      ],
    ),
    expectValue: (value, committed) {
      expect(value, committed.findPersonalTag(_tagId));
    },
  ),
  _MetadataMutationScenario(
    name: 'Delete Personal Tag',
    kind: WorkspaceOperationKind.deletePersonalTag,
    request: DeletePersonalTagRequest(tagId: _tagId),
    planningSnapshot: _snapshot(personalTagIds: <String>[_tagId]),
    committedSnapshot: _snapshot(
      revision: 1,
      personalTags: const <PersonalTag>[],
    ),
    expectedSubjectIds: <ManagedSkillId>{_skillId},
    expectValue: _expectSnapshotValue,
  ),
  _MetadataMutationScenario(
    name: 'Assign Personal Tag',
    kind: WorkspaceOperationKind.assignPersonalTag,
    request: AssignPersonalTagRequest(managedSkillId: _skillId, tagId: _tagId),
    planningSnapshot: _snapshot(),
    committedSnapshot: _snapshot(revision: 1, personalTagIds: <String>[_tagId]),
    expectedSubjectIds: <ManagedSkillId>{_skillId},
    expectValue: _expectSnapshotValue,
  ),
  _MetadataMutationScenario(
    name: 'Unassign Personal Tag',
    kind: WorkspaceOperationKind.unassignPersonalTag,
    request: UnassignPersonalTagRequest(
      managedSkillId: _skillId,
      tagId: _tagId,
    ),
    planningSnapshot: _snapshot(personalTagIds: <String>[_tagId]),
    committedSnapshot: _snapshot(revision: 1),
    expectedSubjectIds: <ManagedSkillId>{_skillId},
    expectValue: _expectSnapshotValue,
  ),
];

List<_MetadataFailureScenario> _failureScenarios() =>
    <_MetadataFailureScenario>[
      _MetadataFailureScenario(
        name: 'Unregister Project Root reports a missing root',
        kind: WorkspaceOperationKind.unregisterProjectRoot,
        request: UnregisterProjectRootRequest(id: 'missing'),
        snapshot: _snapshot(),
        code: SkillsErrorCode.projectRootNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Save Note reports a missing Skill',
        kind: WorkspaceOperationKind.saveNote,
        request: SaveNoteRequest(managedSkillId: _skillId, text: 'note'),
        snapshot: _snapshot(includeSkill: false),
        code: SkillsErrorCode.skillNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Delete Note reports a missing Skill',
        kind: WorkspaceOperationKind.deleteNote,
        request: DeleteNoteRequest(managedSkillId: _skillId),
        snapshot: _snapshot(includeSkill: false),
        code: SkillsErrorCode.skillNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Create Personal Tag reports a normalized duplicate',
        kind: WorkspaceOperationKind.createPersonalTag,
        request: CreatePersonalTagRequest(name: ' existing '),
        snapshot: _snapshot(),
        code: SkillsErrorCode.duplicatePersonalTag,
      ),
      _MetadataFailureScenario(
        name: 'Update Personal Tag reports a missing tag',
        kind: WorkspaceOperationKind.updatePersonalTag,
        request: UpdatePersonalTagRequest(tagId: 'missing', name: 'tag'),
        snapshot: _snapshot(),
        code: SkillsErrorCode.personalTagNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Update Personal Tag reports a normalized duplicate',
        kind: WorkspaceOperationKind.updatePersonalTag,
        request: UpdatePersonalTagRequest(tagId: _tagId, name: ' other '),
        snapshot: _snapshot(
          personalTags: <PersonalTag>[_existingTag(), _otherTag()],
        ),
        code: SkillsErrorCode.duplicatePersonalTag,
      ),
      _MetadataFailureScenario(
        name: 'Delete Personal Tag reports a missing tag',
        kind: WorkspaceOperationKind.deletePersonalTag,
        request: DeletePersonalTagRequest(tagId: 'missing'),
        snapshot: _snapshot(),
        code: SkillsErrorCode.personalTagNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Assign Personal Tag reports a missing Skill',
        kind: WorkspaceOperationKind.assignPersonalTag,
        request: AssignPersonalTagRequest(
          managedSkillId: _skillId,
          tagId: _tagId,
        ),
        snapshot: _snapshot(includeSkill: false),
        code: SkillsErrorCode.skillNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Assign Personal Tag reports a missing tag',
        kind: WorkspaceOperationKind.assignPersonalTag,
        request: AssignPersonalTagRequest(
          managedSkillId: _skillId,
          tagId: 'missing',
        ),
        snapshot: _snapshot(),
        code: SkillsErrorCode.personalTagNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Unassign Personal Tag reports a missing Skill',
        kind: WorkspaceOperationKind.unassignPersonalTag,
        request: UnassignPersonalTagRequest(
          managedSkillId: _skillId,
          tagId: _tagId,
        ),
        snapshot: _snapshot(includeSkill: false),
        code: SkillsErrorCode.skillNotFound,
      ),
      _MetadataFailureScenario(
        name: 'Unassign Personal Tag reports a missing tag',
        kind: WorkspaceOperationKind.unassignPersonalTag,
        request: UnassignPersonalTagRequest(
          managedSkillId: _skillId,
          tagId: 'missing',
        ),
        snapshot: _snapshot(),
        code: SkillsErrorCode.personalTagNotFound,
      ),
    ];

List<_MetadataNoOpScenario> _noOpScenarios() => <_MetadataNoOpScenario>[
  _MetadataNoOpScenario(
    name: 'Save Note with unchanged normalized text',
    kind: WorkspaceOperationKind.saveNote,
    request: SaveNoteRequest(managedSkillId: _skillId, text: ' Same note '),
    snapshot: _snapshot(note: 'Same note'),
    expectValue: _expectSnapshotValue,
  ),
  _MetadataNoOpScenario(
    name: 'Delete Note without an existing note',
    kind: WorkspaceOperationKind.deleteNote,
    request: DeleteNoteRequest(managedSkillId: _skillId),
    snapshot: _snapshot(),
    expectValue: _expectSnapshotValue,
  ),
  _MetadataNoOpScenario(
    name: 'Update Personal Tag without changed fields',
    kind: WorkspaceOperationKind.updatePersonalTag,
    request: UpdatePersonalTagRequest(tagId: _tagId, name: ' Existing '),
    snapshot: _snapshot(),
    expectValue: (value, snapshot) {
      expect(value, snapshot.findPersonalTag(_tagId));
    },
  ),
  _MetadataNoOpScenario(
    name: 'Assign an already assigned Personal Tag',
    kind: WorkspaceOperationKind.assignPersonalTag,
    request: AssignPersonalTagRequest(managedSkillId: _skillId, tagId: _tagId),
    snapshot: _snapshot(personalTagIds: <String>[_tagId]),
    expectValue: _expectSnapshotValue,
  ),
  _MetadataNoOpScenario(
    name: 'Unassign an already unassigned Personal Tag',
    kind: WorkspaceOperationKind.unassignPersonalTag,
    request: UnassignPersonalTagRequest(
      managedSkillId: _skillId,
      tagId: _tagId,
    ),
    snapshot: _snapshot(),
    expectValue: _expectSnapshotValue,
  ),
];

void _expectSnapshotValue(Object? value, RepositorySnapshot snapshot) {
  expect(value, snapshot);
}

Future<void> _publishPlanningSnapshot({
  required _SnapshotReader reader,
  required WorkspaceSnapshotPublisher snapshots,
  required RepositorySnapshot snapshot,
}) async {
  reader.value = snapshot;
  await snapshots.reload();
}

void _expectHistoryPlan(
  OperationPlan plan,
  _MetadataMutationScenario scenario,
) {
  expect(plan.record.kind, scenario.kind.name);
  expect(plan.expectedRepositoryRevision, RepositoryRevision(0));
  expect(plan.committedRepositoryRevision, RepositoryRevision(1));
  expect(plan.businessChanges.isEmpty, isFalse);
  expect(
    plan.record.subjects.map((subject) => subject.managedSkillId).toSet(),
    scenario.expectedSubjectIds,
  );
  expect(
    plan.record.retainWithoutSubjects,
    scenario.expectedSubjectIds.isEmpty,
  );
  for (final subject in plan.record.subjects) {
    expect(subject.displayName, 'Example');
    expect(subject.beforeContentHash, 'a' * 64);
    expect(subject.afterContentHash, 'a' * 64);
  }
}

typedef _ValueExpectation =
    void Function(Object? value, RepositorySnapshot snapshot);

final class _MetadataMutationScenario {
  _MetadataMutationScenario({
    required this.name,
    required this.kind,
    required this.request,
    required this.planningSnapshot,
    required this.committedSnapshot,
    required this.expectValue,
    Set<ManagedSkillId> expectedSubjectIds = const <ManagedSkillId>{},
  }) : expectedSubjectIds = Set.unmodifiable(expectedSubjectIds);

  final String name;
  final WorkspaceOperationKind kind;
  final Object request;
  final RepositorySnapshot planningSnapshot;
  final RepositorySnapshot committedSnapshot;
  final _ValueExpectation expectValue;
  final Set<ManagedSkillId> expectedSubjectIds;
}

final class _MetadataFailureScenario {
  const _MetadataFailureScenario({
    required this.name,
    required this.kind,
    required this.request,
    required this.snapshot,
    required this.code,
  });

  final String name;
  final WorkspaceOperationKind kind;
  final Object request;
  final RepositorySnapshot snapshot;
  final SkillsErrorCode code;
}

final class _MetadataNoOpScenario {
  const _MetadataNoOpScenario({
    required this.name,
    required this.kind,
    required this.request,
    required this.snapshot,
    required this.expectValue,
  });

  final String name;
  final WorkspaceOperationKind kind;
  final Object request;
  final RepositorySnapshot snapshot;
  final _ValueExpectation expectValue;
}

Future<SkillsResult<T>> _execute<T>(
  CompositeSkillsRepositoryCommandDispatcher dispatcher,
  WorkspaceOperationKind kind,
  Object request, {
  void Function()? markBusinessCommitted,
  CancellationToken? cancellationToken,
}) => dispatcher.execute<T>(
  operationId: OperationId(_operationValue),
  kind: kind,
  request: request,
  cancellationToken: cancellationToken ?? CancellationToken.none(),
  markBusinessCommitted: markBusinessCommitted ?? () {},
  reportProgress: (phase, {currentItem, completed = 0, total}) {},
);

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  _SnapshotReader(this.value);

  RepositorySnapshot value;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      value;
}

final class _ProjectRootPaths implements ProjectRootPathPort {
  @override
  Future<String?> canonicalizeExistingDirectory(String candidatePath) async =>
      candidatePath == '/workspace' ? candidatePath : null;
}

final class _SubjectIds implements OperationSubjectIdentityPort {
  @override
  String allocateOperationSubjectId() => _subjectValue;
}

final class _RecoveryPlans implements OperationRecoveryPlanFactoryPort {
  const _RecoveryPlans();

  @override
  List<PreparationOperationStep> createDestructiveEnvelope({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
  }) => const <PreparationOperationStep>[];

  @override
  OperationRecoveryPlanSteps createSqliteOnly({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required bool destructive,
  }) => OperationRecoveryPlanSteps(
    preparationSteps: <PreparationOperationStep>[
      PreparationOperationStep(
        stepId: 'prepare',
        recoveryReference: RecoveryReference('prepare'),
        kind: PreparationStepKind.recoveryEvidence,
      ),
    ],
    applyingSteps: const <ApplyingOperationStep>[],
    finalizationSteps: <FinalizationOperationStep>[
      FinalizationOperationStep(
        stepId: 'finalize',
        recoveryReference: RecoveryReference('finalize'),
        kind: FinalizationStepKind.backupRotation,
      ),
    ],
  );

  @override
  OperationRecoveryPlanSteps createDestructive({
    required OperationId operationId,
    required RepositoryRevision expectedRepositoryRevision,
    required RepositoryRevision committedRepositoryRevision,
    required DestructiveOperationRecoveryIntent intent,
  }) => throw UnsupportedError('not used');
}
