import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/history/history_ports.dart';
import 'package:skills_workspace/src/application/history/history_service.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  late _HistoryContent content;
  late WorkspaceHistoryService history;

  setUp(() {
    content = _HistoryContent();
    history = WorkspaceHistoryService(
      content: content,
      clock: () => DateTime.utc(2026, 8, 17, 12),
    );
  });

  test('diff rejects a Subject that does not exist for the Skill', () async {
    content.selections.clear();

    final result = await history.inspectDiff(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
      from: null,
      to: _to,
    );

    expect(
      result.failureOrNull?.code,
      HistoryFailureCode.historicalRevisionNotFound,
    );
    expect(content.compareCalls, 0);
  });

  test('diff rejects comparisons across Source Lineages', () async {
    content.selections[_from] = _selection(
      reference: _from,
      lineage: SourceLineageReference('retired-lineage'),
    );

    final result = await history.inspectDiff(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
      from: _from,
      to: _to,
    );

    expect(
      result.failureOrNull?.code,
      HistoryFailureCode.historicalRevisionOutsideCurrentLineage,
    );
    expect(content.compareCalls, 0);
  });

  test('diff rejects a target from a retired Source Lineage', () async {
    content.selections[_to] = _selection(
      reference: _to,
      lineage: SourceLineageReference('retired-lineage'),
    );

    final result = await history.inspectDiff(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
      from: null,
      to: _to,
    );

    expect(
      result.failureOrNull?.code,
      HistoryFailureCode.historicalRevisionOutsideCurrentLineage,
    );
    expect(content.compareCalls, 0);
  });

  test('diff delegates only validated current-lineage selections', () async {
    final result = await history.inspectDiff(
      snapshot: _snapshot(),
      managedSkillId: _skillId,
      from: _from,
      to: _to,
    );

    expect(result.valueOrNull, content.diff);
    expect(content.compareCalls, 1);
  });

  test('Restore is blocked by a Dirty ordinary Draft', () async {
    content.draftDirty = true;

    final result = await history.planRestore(
      snapshot: _snapshot(draft: _draft()),
      managedSkillId: _skillId,
      selectedRevision: _to,
    );

    expect(
      result.failureOrNull?.code,
      HistoryFailureCode.dirtyDraftResolutionRequired,
    );
    expect(content.resolveCalls, 0);
  });

  test(
    'Restore rejects historical Declared Name changes before Journal',
    () async {
      content.selections[_to] = _selection(
        reference: _to,
        declaredName: 'other',
      );

      final result = await history.planRestore(
        snapshot: _snapshot(),
        managedSkillId: _skillId,
        selectedRevision: _to,
      );

      expect(
        result.failureOrNull?.code,
        HistoryFailureCode.historicalNameMismatch,
      );
    },
  );

  test(
    'Restore preflight retains current Upstream and Effective facts',
    () async {
      final result = await history.planRestore(
        snapshot: _snapshot(draft: _draft()),
        managedSkillId: _skillId,
        selectedRevision: _to,
      );

      final preflight = result.valueOrNull!;
      expect(preflight.state.currentUpstream, _object('1'));
      expect(preflight.state.currentEffective, _object('2'));
      expect(preflight.selected.objectId, _object('4'));
      expect(preflight.hadCleanDraft, isTrue);
    },
  );
}

final class _HistoryContent implements WorkspaceHistoryContentPort {
  _HistoryContent() {
    selections[_from] = _selection(reference: _from, object: _object('3'));
    selections[_to] = _selection(reference: _to, object: _object('4'));
  }

  final selections = <OperationSubjectReference, HistoricalRevisionSelection>{};
  final diff = SkillDiff(
    managedSkillId: _skillId,
    from: _from,
    to: _to,
    files: const <SkillFileDiff>[],
  );
  var draftDirty = false;
  var resolveCalls = 0;
  var compareCalls = 0;

  @override
  Future<HistoricalRevisionSelection?> resolvePublishedRevision({
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference reference,
  }) async {
    resolveCalls += 1;
    return selections[reference];
  }

  @override
  Future<HistoryResult<SkillDiff>> compare({
    required ManagedSkillId managedSkillId,
    required HistoricalRevisionSelection? from,
    required HistoricalRevisionSelection to,
    required CancellationToken cancellationToken,
  }) async {
    compareCalls += 1;
    return HistorySuccess<SkillDiff>(diff);
  }

  @override
  Future<HistoryResult<bool>> inspectDraftDirty({
    required ManagedSkill skill,
    required RestoreRevisionState state,
    required CancellationToken cancellationToken,
  }) async => HistorySuccess<bool>(draftDirty);

  @override
  Future<RestoreRevisionState?> readRestoreState(
    ManagedSkillId managedSkillId,
  ) async => RestoreRevisionState(
    managedSkillId: _skillId,
    sourceLineage: _lineage,
    currentUpstream: _object('1'),
    currentEffective: _object('2'),
    managedSkillCreatedAtMicros: 1,
    draftCreatedAtMicros: 2,
  );
}

const _skillValue = '123e4567-e89b-42d3-a456-426614174000';
const _operation1 = '123e4567-e89b-42d3-8456-426614174001';
const _operation2 = '123e4567-e89b-42d3-8456-426614174002';
const _subject1 = '123e4567-e89b-42d3-9456-426614174003';
const _subject2 = '123e4567-e89b-42d3-9456-426614174004';
final _skillId = ManagedSkillId(_skillValue);
final _lineage = SourceLineageReference('lineage-1');
final _from = OperationSubjectReference(
  operationId: OperationId(_operation1),
  subjectId: _subject1,
);
final _to = OperationSubjectReference(
  operationId: OperationId(_operation2),
  subjectId: _subject2,
);

HistoricalRevisionSelection _selection({
  required OperationSubjectReference reference,
  SourceLineageReference? lineage,
  RevisionObjectId? object,
  String declaredName = 'one',
}) => HistoricalRevisionSelection(
  reference: reference,
  managedSkillId: _skillId,
  sourceLineage: lineage ?? _lineage,
  objectId: object ?? _object('4'),
  contentHash: 'a' * 64,
  declaredName: declaredName,
);

RepositorySnapshot _snapshot({DraftSummary? draft}) => RepositorySnapshot(
  revision: RepositoryRevision(5),
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
        byteSize: 1,
        publishedAt: DateTime.utc(2026, 8, 1),
      ),
      draft: draft,
    ),
  ],
);

DraftSummary _draft() => DraftSummary(
  purpose: DraftPurpose.customization,
  path: '/drafts/$_skillValue',
  isDirty: false,
  updatedAt: DateTime.utc(2026, 8, 17),
);

RevisionObjectId _object(String character) => RevisionObjectId(character * 40);
