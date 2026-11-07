import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../domain/lock_wait_policy.dart';
import '../domain/public_models.dart';
import 'default_skills_repository.dart';
import 'requests.dart';
import 'result.dart';

typedef TypedSkillsCommand<TRequest extends Object, TResult> =
    Future<SkillsResult<TResult>> Function(
      TRequest request,
      SkillsCommandContext context,
    );

final class SkillsCommandContext {
  const SkillsCommandContext({
    required this.operationId,
    required this.cancellationToken,
    required this.lockWaitPolicy,
    required this.markBusinessCommitted,
    required this.reportProgress,
  });

  final OperationId operationId;
  final CancellationToken cancellationToken;
  final LockWaitPolicy? lockWaitPolicy;
  final void Function() markBusinessCommitted;
  final SkillsProgressReporter reportProgress;
}

abstract interface class SkillsCommandHandler {
  WorkspaceOperationKind get kind;

  Future<SkillsResult<Object?>> execute(
    Object request,
    SkillsCommandContext context,
  );
}

final class TypedSkillsCommandHandler<TRequest extends Object, TResult>
    implements SkillsCommandHandler {
  const TypedSkillsCommandHandler({required this.kind, required this.handle});

  @override
  final WorkspaceOperationKind kind;
  final TypedSkillsCommand<TRequest, TResult> handle;

  @override
  Future<SkillsResult<Object?>> execute(
    Object request,
    SkillsCommandContext context,
  ) async {
    if (request is! TRequest) {
      throw StateError('The ${kind.name} command received the wrong request.');
    }
    final result = await handle(request, context);
    return result.fold<SkillsResult<Object?>>(
      onSuccess: (success) => SkillsSuccess<Object?>(
        value: success.value,
        changed: success.changed,
        warnings: success.warnings,
      ),
      onFailure: (failure) => SkillsFailure<Object?>(
        code: failure.code,
        context: failure.context,
        diagnostic: failure.diagnostic,
        warnings: failure.warnings,
      ),
      onCommittedFinalizationPending: (pending) =>
          SkillsCommittedFinalizationPending<Object?>(
            operationId: pending.operationId,
            committedRepositoryRevision: pending.committedRepositoryRevision,
            warnings: pending.warnings,
          ),
    );
  }
}

/// Routes each public operation to exactly one typed command handler.
final class CompositeSkillsRepositoryCommandDispatcher
    implements SkillsRepositoryCommandDispatcher {
  CompositeSkillsRepositoryCommandDispatcher(
    List<SkillsCommandHandler> handlers,
  ) : _handlers = _index(handlers);

  final Map<WorkspaceOperationKind, SkillsCommandHandler> _handlers;

  @override
  Future<SkillsResult<T>> execute<T>({
    required OperationId operationId,
    required WorkspaceOperationKind kind,
    required Object request,
    required CancellationToken cancellationToken,
    required void Function() markBusinessCommitted,
    required SkillsProgressReporter reportProgress,
  }) async {
    final handler = _handlers[kind];
    if (handler == null) {
      throw StateError('No command handler is registered for ${kind.name}.');
    }
    final result = await handler.execute(
      request,
      SkillsCommandContext(
        operationId: operationId,
        cancellationToken: cancellationToken,
        lockWaitPolicy: _lockWaitPolicyFor(request),
        markBusinessCommitted: markBusinessCommitted,
        reportProgress: reportProgress,
      ),
    );
    return result.fold<SkillsResult<T>>(
      onSuccess: (success) => SkillsSuccess<T>(
        value: success.value as T,
        changed: success.changed,
        warnings: success.warnings,
      ),
      onFailure: (failure) => SkillsFailure<T>(
        code: failure.code,
        context: failure.context,
        diagnostic: failure.diagnostic,
        warnings: failure.warnings,
      ),
      onCommittedFinalizationPending: (pending) =>
          SkillsCommittedFinalizationPending<T>(
            operationId: pending.operationId,
            committedRepositoryRevision: pending.committedRepositoryRevision,
            warnings: pending.warnings,
          ),
    );
  }
}

LockWaitPolicy? _lockWaitPolicyFor(Object request) => switch (request) {
  InstallRequest(:final lockWaitPolicy) ||
  ConfirmInstallTakeoverRequest(:final lockWaitPolicy) ||
  AdoptRequest(:final lockWaitPolicy) ||
  UpdateRequest(:final lockWaitPolicy) ||
  ReplaceSourceRequest(:final lockWaitPolicy) ||
  ActivateRequest(:final lockWaitPolicy) ||
  ConfirmActivationTakeoverRequest(:final lockWaitPolicy) ||
  DeactivateRequest(:final lockWaitPolicy) ||
  RemoveRequest(:final lockWaitPolicy) => lockWaitPolicy,
  _ => null,
};

Map<WorkspaceOperationKind, SkillsCommandHandler> _index(
  List<SkillsCommandHandler> handlers,
) {
  final indexed = <WorkspaceOperationKind, SkillsCommandHandler>{};
  for (final handler in handlers) {
    if (indexed.containsKey(handler.kind)) {
      throw ArgumentError.value(
        handlers,
        'handlers',
        'contains duplicate ${handler.kind.name} handlers',
      );
    }
    indexed[handler.kind] = handler;
  }
  return Map.unmodifiable(indexed);
}
