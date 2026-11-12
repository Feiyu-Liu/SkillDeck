import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/skill_integrity_coordinator.dart';
import 'package:skills_workspace/src/composition/validation_command_handlers.dart';
import 'package:test/test.dart';

import '../support/drift_test_support.dart';
import '../support/operations/operation_fakes.dart';

void main() {
  late _Fixture fixture;
  late List<Map<String, Object?>> events;
  late StreamSubscription<LogRecord> subscription;

  setUp(() async {
    fixture = await _Fixture.create();
    events = [];
    subscription = Logger('skills_workspace.performance').onRecord.listen((
      record,
    ) {
      expect(record.error, isNull);
      expect(record.stackTrace, isNull);
      events.add(jsonDecode(record.message) as Map<String, Object?>);
    });
  });
  tearDown(() async {
    await subscription.cancel();
    await fixture.snapshots.close();
  });

  test(
    'one coalesced Skill validation records only its actual reads',
    () async {
      fixture.materializations.block = Completer<void>();
      final id = fixture.ids.first;
      final first = fixture.integrity.validate(id);
      final second = fixture.integrity.validate(id);
      expect(identical(first, second), isTrue);
      await fixture.materializations.entered.future;
      fixture.materializations.block!.complete();
      expect((await first).status, SkillIntegrityStatus.healthy);
      await second;

      expect(fixture.materializations.selected, [
        {id},
      ]);
      expect(events, hasLength(1));
      _expectEvent(events.single, phase: 'skillValidation', checked: 1);
      expect(events.single['inspectedArtifactCount'], 5);
      expect(events.single['inspectedFileCount'], 50);
      expect(events.single['inspectedByteCount'], 1000);
      expect(events.single['repairedArtifactCount'], 0);
      expect(jsonEncode(events), isNot(contains(id.value)));
      expect(jsonEncode(events), isNot(contains('sample')));
    },
  );

  test(
    'full validation checks all 85 Skills and logs bounded summary',
    () async {
      final progress = <int>[];
      final result = await fixture.validate(progress: progress);
      expect(result.valueOrNull!.checkedSkillCount, 85);
      expect(result.valueOrNull!.healthySkillCount, 85);
      expect(fixture.materializations.selected, hasLength(85));
      expect(
        fixture.materializations.selected.expand((ids) => ids).toSet(),
        fixture.ids.toSet(),
      );
      expect(progress, [for (var count = 0; count <= 85; count++) count]);
      expect(
        events.where((event) => event['phase'] == 'skillValidation'),
        hasLength(85),
      );
      final summary = events.last;
      _expectEvent(summary, phase: 'workspaceValidation', checked: 85);
      expect(
        summary.keys,
        unorderedEquals([
          'phase',
          'elapsedMicros',
          'failed',
          'cancelled',
          'checkedSkillCount',
        ]),
      );
    },
  );

  test('cancellation stops scheduling after four in-flight Skills', () async {
    fixture.materializations.block = Completer<void>();
    final cancellation = CancellationSource();
    final run = fixture.validate(token: cancellation.token);
    await fixture.materializations.entered.future;
    // All bounded workers reach the same pending inspection before cancellation.
    await Future<void>.delayed(Duration.zero);
    expect(fixture.materializations.selected, hasLength(4));
    await cancellation.cancel();
    fixture.materializations.block!.complete();
    expect((await run).failureOrNull!.code, SkillsErrorCode.operationCancelled);
    expect(fixture.materializations.selected, hasLength(4));
    expect(events.last['phase'], 'workspaceValidation');
    expect(events.last['checkedSkillCount'], 4);
    expect(events.last['cancelled'], isTrue);
  });

  test(
    'failed inspection logs a failure without exception or path data',
    () async {
      fixture.materializations.fail = true;
      final result = await fixture.integrity.validate(fixture.ids.first);
      expect(result.status, SkillIntegrityStatus.repairFailed);
      expect(events.single['failed'], isTrue);
      expect(events.single['inspectedArtifactCount'], 0);
      expect(jsonEncode(events), isNot(contains('private')));
      expect(jsonEncode(events), isNot(contains('secret')));
    },
  );

  test(
    'missing projection counts inspection and repair passes separately',
    () async {
      fixture.materializations.missing = true;
      final result = await fixture.integrity.validate(fixture.ids.first);
      expect(result.repairedArtifactCount, 1);
      expect(fixture.materializations.selected, hasLength(2));
      expect(events.single['inspectedArtifactCount'], 10);
      expect(events.single['repairedArtifactCount'], 1);
    },
  );

  test('drift remains pending and never requests mismatching repair', () async {
    fixture.materializations.drift = true;
    final result = await fixture.integrity.validate(fixture.ids.first);
    expect(result.status, SkillIntegrityStatus.driftPending);
    expect(fixture.materializations.selected, hasLength(1));
    expect(events.single['repairedArtifactCount'], 0);
    expect(events.single['failed'], isFalse);
  });

  test(
    'known authoritative corruption stays blocked without projection reads',
    () async {
      await fixture.integrity.markRevisionStoreCorrupt(fixture.ids.first);
      final result = await fixture.integrity.validate(fixture.ids.first);
      expect(result.status, SkillIntegrityStatus.revisionStoreCorrupt);
      expect(fixture.materializations.selected, isEmpty);
      expect(events.single['failed'], isTrue);
      expect(events.single['inspectedArtifactCount'], 0);
    },
  );

  test(
    'invalid full selection logs failure without inspecting other Skills',
    () async {
      final result = await fixture.validate(
        selected: {ManagedSkillId('123e4567-e89b-42d3-a456-999999999999')},
      );
      expect(result.failureOrNull!.code, SkillsErrorCode.skillNotFound);
      expect(fixture.materializations.selected, isEmpty);
      expect(events.single['phase'], 'workspaceValidation');
      expect(events.single['checkedSkillCount'], 0);
      expect(events.single['failed'], isTrue);
    },
  );
}

void _expectEvent(
  Map<String, Object?> event, {
  required String phase,
  required int checked,
}) {
  expect(event['phase'], phase);
  expect(
    event['elapsedMicros'],
    isA<int>().having((value) => value, 'nonnegative', greaterThanOrEqualTo(0)),
  );
  expect(event['failed'], isFalse);
  expect(event['cancelled'], isFalse);
  expect(event['checkedSkillCount'], checked);
}

final class _Fixture {
  final materializations = _Materializations();
  late WorkspaceSnapshotPublisher snapshots;
  late SkillIntegrityCoordinator integrity;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;
  late List<ManagedSkillId> ids;

  static Future<_Fixture> create() async {
    final fixture = _Fixture();
    final template = driftSkill();
    fixture.ids = [
      for (var index = 0; index < 85; index++)
        ManagedSkillId(
          '123e4567-e89b-42d3-a456-${index.toString().padLeft(12, '0')}',
        ),
    ];
    final snapshot = RepositorySnapshot(
      revision: RepositoryRevision.initial(),
      managedSkills: [
        for (final id in fixture.ids)
          ManagedSkill(
            id: id,
            slotKey: id.value,
            declaredName: template.declaredName,
            displayName: template.displayName,
            description: template.description,
            source: template.source,
            currentRevision: template.currentRevision,
          ),
      ],
    );
    fixture.snapshots = WorkspaceSnapshotPublisher(reader: _Reader(snapshot));
    await fixture.snapshots.publishInitial(snapshot);
    fixture.integrity = SkillIntegrityCoordinator(
      snapshots: fixture.snapshots,
      materializations: fixture.materializations,
      writerLock: OperationHarness().writerLock,
    );
    fixture.dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildValidationCommandHandlers(
        snapshots: fixture.snapshots,
        integrity: fixture.integrity,
      ),
    );
    return fixture;
  }

  Future<SkillsResult<WorkspaceValidationReport>> validate({
    CancellationToken? token,
    List<int>? progress,
    Set<ManagedSkillId>? selected,
  }) => dispatcher.execute<WorkspaceValidationReport>(
    operationId: OperationId('123e4567-e89b-42d3-a456-426614174005'),
    kind: WorkspaceOperationKind.validateWorkspace,
    request: ValidateWorkspaceRequest(managedSkillIds: selected),
    cancellationToken: token ?? CancellationToken.none(),
    markBusinessCommitted: () {},
    reportProgress: (phase, {currentItem, completed = 0, total}) {
      progress?.add(completed);
    },
  );
}

final class _Reader implements WorkspaceSnapshotReaderPort {
  _Reader(this.snapshot);
  final RepositorySnapshot snapshot;
  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      snapshot;
}

final class _Materializations
    implements WorkspaceMaterializationReconciliationPort {
  final selected = <Set<ManagedSkillId>>[];
  final entered = Completer<void>();
  Completer<void>? block;
  bool fail = false;
  bool missing = false;
  bool drift = false;

  @override
  Future<WorkspaceMaterializationReconciliationReport>
  reconcileMaterializations({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
    bool repairMismatching = true,
    bool repairMissing = true,
  }) async {
    expect(repairMismatching, isFalse);
    expect(selectedSkillIds, hasLength(1));
    selected.add(Set.of(selectedSkillIds!));
    if (!entered.isCompleted) entered.complete();
    await block?.future;
    if (fail) throw StateError('/private/secret Skill content token=secret');
    return WorkspaceMaterializationReconciliationReport(
      inspectedArtifactCount: 5,
      inspectedFileCount: 50,
      inspectedByteCount: 1000,
      repairedArtifactCount: missing && repairMissing ? 1 : 0,
      missingArtifactCount: missing ? 1 : 0,
      missingSkillIds: missing ? selectedSkillIds.toList() : const [],
      mismatchingArtifactCount: drift ? 1 : 0,
      mismatchingSkillIds: drift ? selectedSkillIds.toList() : const [],
      inspectionElapsed: Duration.zero,
      repairElapsed: Duration.zero,
    );
  }

  @override
  Future<SkillMaterializationInspection> inspectSkillMaterializations(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  }) => throw UnimplementedError();
}
