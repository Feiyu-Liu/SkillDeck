import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/lock_wait_policy.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

void main() {
  test(
    'routes one request without changing generic result or operation ID',
    () async {
      OperationId? observed;
      final dispatcher = CompositeSkillsRepositoryCommandDispatcher([
        TypedSkillsCommandHandler<SetFavoriteRequest, RepositorySnapshot>(
          kind: WorkspaceOperationKind.setFavorite,
          handle: (request, context) async {
            observed = context.operationId;
            expect(request.isFavorite, isTrue);
            return SkillsSuccess<RepositorySnapshot>(
              value: RepositorySnapshot.empty(),
              changed: true,
            );
          },
        ),
      ]);
      final operationId = OperationId('123e4567-e89b-42d3-a456-426614174000');

      final result = await dispatcher.execute<RepositorySnapshot>(
        operationId: operationId,
        kind: WorkspaceOperationKind.setFavorite,
        request: SetFavoriteRequest(
          managedSkillId: ManagedSkillId(
            '123e4567-e89b-42d3-b456-426614174001',
          ),
          isFavorite: true,
        ),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      );

      expect(result.valueOrNull, RepositorySnapshot.empty());
      expect(observed, operationId);
    },
  );

  test('rejects duplicate handlers and mismatched request contracts', () async {
    final handler =
        TypedSkillsCommandHandler<SetFavoriteRequest, RepositorySnapshot>(
          kind: WorkspaceOperationKind.setFavorite,
          handle: (_, _) async => SkillsSuccess<RepositorySnapshot>(
            value: RepositorySnapshot.empty(),
          ),
        );
    expect(
      () => CompositeSkillsRepositoryCommandDispatcher([handler, handler]),
      throwsArgumentError,
    );

    final dispatcher = CompositeSkillsRepositoryCommandDispatcher([handler]);
    await expectLater(
      dispatcher.execute<RepositorySnapshot>(
        operationId: OperationId('123e4567-e89b-42d3-a456-426614174000'),
        kind: WorkspaceOperationKind.setFavorite,
        request: DeleteNoteRequest(
          managedSkillId: ManagedSkillId(
            '123e4567-e89b-42d3-b456-426614174001',
          ),
        ),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: (phase, {currentItem, completed = 0, total}) {},
      ),
      throwsStateError,
    );
  });

  test('extracts only the mutation request lock policy into context', () async {
    final skillId = ManagedSkillId('123e4567-e89b-42d3-b456-426614174001');
    final policy = LockWaitPolicy.wait(
      timeout: const Duration(seconds: 2),
      pollInterval: const Duration(milliseconds: 5),
    );
    LockWaitPolicy? observed;
    final dispatcher = CompositeSkillsRepositoryCommandDispatcher([
      TypedSkillsCommandHandler<UpdateRequest, MutationReport>(
        kind: WorkspaceOperationKind.update,
        handle: (_, context) async {
          observed = context.lockWaitPolicy;
          return SkillsSuccess<MutationReport>(
            value: MutationReport(
              snapshot: RepositorySnapshot.empty(),
              affectedSkillIds: <ManagedSkillId>{skillId},
            ),
          );
        },
      ),
    ]);

    await dispatcher.execute<MutationReport>(
      operationId: OperationId('123e4567-e89b-42d3-a456-426614174000'),
      kind: WorkspaceOperationKind.update,
      request: UpdateRequest(
        managedSkillIds: <ManagedSkillId>{skillId},
        lockWaitPolicy: policy,
      ),
      cancellationToken: CancellationToken.none(),
      markBusinessCommitted: () {},
      reportProgress: (phase, {currentItem, completed = 0, total}) {},
    );

    expect(observed, policy);
  });
}
