import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/revision_store_access_ports.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/application/revision_store/revision_store_access_models.dart';
import 'package:skills_workspace/src/application/revision_store/revision_store_access_service.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:test/test.dart';

const _objectA = '1111111111111111111111111111111111111111';
const _objectB = '2222222222222222222222222222222222222222';
const _storePath = '/stores/skill.git';
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');

void main() {
  late _FakePointers pointers;
  late ManagedSkillRevisionAccessGate gate;
  late _FakeRevisionEngine engine;
  late RevisionStoreAccessService service;

  setUp(() {
    pointers = _FakePointers(<CurrentEffectiveRevisionSelection>[_selectionA]);
    gate = ManagedSkillRevisionAccessGate();
    engine = _FakeRevisionEngine();
    service = RevisionStoreAccessService(
      pointers: pointers,
      accessGate: gate,
      storePath: (_) => _storePath,
      revisionEngine: engine,
    );
  });

  test(
    'stale Pointer releases admission and retries canonical Store',
    () async {
      pointers.selections = <CurrentEffectiveRevisionSelection>[
        _selectionA,
        _selectionB,
        _selectionB,
      ];

      final tree = await service.readCurrentEffective(_skillId);

      expect(tree, same(engine.tree));
      expect(engine.reads, [(_storePath, RevisionObjectId(_objectB))]);
    },
  );

  test('bounded Pointer instability fails without reading the Store', () async {
    pointers.selections = <CurrentEffectiveRevisionSelection>[
      _selectionA,
      _selectionB,
      _selectionA,
      _selectionB,
      _selectionA,
      _selectionB,
    ];

    await expectLater(
      service.readCurrentEffective(_skillId),
      throwsA(
        isA<RevisionStoreAccessException>().having(
          (error) => error.code,
          'code',
          RevisionStoreAccessFailureCode.selectionChangedRepeatedly,
        ),
      ),
    );
    expect(engine.reads, isEmpty);
  });

  test('read failures release shared admission', () async {
    engine.readFailure = const RevisionEngineException(
      RevisionEngineFailureCode.storeUnavailable,
    );

    await expectLater(
      service.readCurrentEffective(_skillId),
      throwsA(isA<RevisionEngineException>()),
    );

    final exclusive = await gate.acquireExclusive(_skillId);
    await exclusive.release();
  });

  test('cancellation before selection performs no Store read', () async {
    final source = CancellationSource();
    await source.cancel();

    await expectLater(
      service.readCurrentEffective(_skillId, cancellationToken: source.token),
      throwsA(
        isA<RevisionStoreAccessException>().having(
          (error) => error.code,
          'code',
          RevisionStoreAccessFailureCode.cancelled,
        ),
      ),
    );
    expect(engine.reads, isEmpty);
  });
}

final _selectionA = CurrentEffectiveRevisionSelection(
  sourceLineage: SourceLineageReference('lineage-a'),
  objectId: RevisionObjectId(_objectA),
);
final _selectionB = CurrentEffectiveRevisionSelection(
  sourceLineage: SourceLineageReference('lineage-b'),
  objectId: RevisionObjectId(_objectB),
);

final class _FakePointers implements RevisionPointerReaderPort {
  _FakePointers(this.selections);

  List<CurrentEffectiveRevisionSelection> selections;

  @override
  Future<CurrentEffectiveRevisionSelection?> readCurrentEffective(
    ManagedSkillId managedSkillId,
  ) async {
    if (selections.isEmpty) return null;
    if (selections.length == 1) return selections.single;
    return selections.removeAt(0);
  }
}

final class _FakeRevisionEngine implements RevisionEnginePort {
  final tree = NormalizedSkillTree(
    files: const <NormalizedSkillFile>[],
    contentHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    byteSize: 0,
  );
  final List<(String, RevisionObjectId)> reads = [];
  RevisionEngineException? readFailure;

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) async {
    reads.add((repositoryPath, commit));
    final failure = readFailure;
    if (failure != null) throw failure;
    return tree;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
