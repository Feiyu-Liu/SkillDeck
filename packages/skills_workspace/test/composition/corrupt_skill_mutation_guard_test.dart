import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/destructive_intent.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/corrupt_skill_mutation_guard.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  late WorkspaceSnapshotPublisher snapshots;

  tearDown(() async {
    await snapshots.close();
  });

  test('keeps metadata mutations available for a corrupt Skill', () async {
    snapshots = await _publisher(_snapshot());
    final favorite = _RecordingHandler(WorkspaceOperationKind.setFavorite);
    final dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      guardCorruptSkillMutations(
        handlers: <SkillsCommandHandler>[favorite],
        snapshots: snapshots,
      ),
    );

    final blocked = await _execute<RepositorySnapshot>(
      dispatcher,
      WorkspaceOperationKind.setFavorite,
      SetFavoriteRequest(managedSkillId: _corruptSkillId, isFavorite: true),
    );
    final healthy = await _execute<RepositorySnapshot>(
      dispatcher,
      WorkspaceOperationKind.setFavorite,
      SetFavoriteRequest(managedSkillId: _healthySkillId, isFavorite: true),
    );

    expect(blocked, isA<SkillsSuccess<RepositorySnapshot>>());
    expect(healthy, isA<SkillsSuccess<RepositorySnapshot>>());
    expect(favorite.calls, 2);
  });

  test('keeps explicit Source Replacement and Removal available', () async {
    snapshots = await _publisher(_snapshot());
    final replacement = _RecordingHandler(WorkspaceOperationKind.replaceSource);
    final removal = _RecordingHandler(WorkspaceOperationKind.remove);
    final dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      guardCorruptSkillMutations(
        handlers: <SkillsCommandHandler>[replacement, removal],
        snapshots: snapshots,
      ),
    );
    final intent = DestructiveIntent(
      reviewedRevision: RepositoryRevision.initial(),
    );

    final replacementResult = await _execute<Object?>(
      dispatcher,
      WorkspaceOperationKind.replaceSource,
      ReplaceSourceRequest(
        managedSkillId: _corruptSkillId,
        source: LocalSourceDescriptor(locator: '/replacement'),
        intent: intent,
      ),
    );
    final removalResult = await _execute<Object?>(
      dispatcher,
      WorkspaceOperationKind.remove,
      RemoveRequest(
        managedSkillIds: <ManagedSkillId>{_corruptSkillId},
        intent: intent,
      ),
    );

    expect(replacementResult, isA<SkillsSuccess<Object?>>());
    expect(removalResult, isA<SkillsSuccess<Object?>>());
    expect(replacement.calls, 1);
    expect(removal.calls, 1);
  });
}

Future<WorkspaceSnapshotPublisher> _publisher(
  RepositorySnapshot snapshot,
) async {
  final publisher = WorkspaceSnapshotPublisher(
    reader: _SnapshotReader(snapshot),
  );
  await publisher.publishInitial(snapshot);
  return publisher;
}

Future<SkillsResult<T>> _execute<T>(
  CompositeSkillsRepositoryCommandDispatcher dispatcher,
  WorkspaceOperationKind kind,
  Object request,
) => dispatcher.execute<T>(
  operationId: _operationId,
  kind: kind,
  request: request,
  cancellationToken: CancellationToken.none(),
  markBusinessCommitted: () {},
  reportProgress: (phase, {currentItem, completed = 0, total}) {},
);

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  const _SnapshotReader(this.snapshot);

  final RepositorySnapshot snapshot;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      snapshot;
}

final class _RecordingHandler implements SkillsCommandHandler {
  _RecordingHandler(this.kind);

  @override
  final WorkspaceOperationKind kind;
  var calls = 0;

  @override
  Future<SkillsResult<Object?>> execute(
    Object request,
    SkillsCommandContext context,
  ) async {
    calls += 1;
    return SkillsSuccess<Object?>(
      value: RepositorySnapshot.empty(),
      changed: true,
    );
  }
}

RepositorySnapshot _snapshot() => RepositorySnapshot(
  revision: RepositoryRevision.initial(),
  managedSkills: <ManagedSkill>[
    _skill(_corruptSkillId, 'corrupt'),
    _skill(_healthySkillId, 'healthy'),
  ],
  integrity: WorkspaceIntegrity(
    skills: <ManagedSkillIntegrity>[
      ManagedSkillIntegrity(
        managedSkillId: _corruptSkillId,
        status: SkillIntegrityStatus.revisionStoreCorrupt,
      ),
    ],
  ),
);

ManagedSkill _skill(ManagedSkillId id, String name) => ManagedSkill(
  id: id,
  slotKey: name,
  declaredName: name,
  displayName: name,
  description: '$name Skill',
  source: LocalSourceDescriptor(locator: '/source/$name'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: name == 'corrupt' ? 'a' * 64 : 'b' * 64,
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026, 8, 24),
  ),
);

final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174099');
final _corruptSkillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174001');
final _healthySkillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174002');
