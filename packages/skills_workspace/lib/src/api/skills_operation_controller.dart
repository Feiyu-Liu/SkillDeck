import 'dart:async';

import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import 'result.dart';
import 'skills_repository.dart';

/// Internal producer for the public [SkillsOperation] contract.
///
/// The progress stream is always closed before the terminal Future resolves,
/// so consumers can finish progress presentation without racing the result.
final class SkillsOperationController<T> {
  SkillsOperationController({
    required OperationId operationId,
    required WorkspaceOperationKind kind,
  }) : _kind = kind,
       _cancellation = CancellationSource(),
       _progress = StreamController<OperationProgress>.broadcast(),
       _completion = Completer<SkillsResult<T>>() {
    operation = _ControlledSkillsOperation<T>._(
      operationId: operationId,
      progress: _progress.stream,
      completed: _completion.future,
      cancel: _cancellation.cancel,
    );
  }

  final WorkspaceOperationKind _kind;
  final CancellationSource _cancellation;
  final StreamController<OperationProgress> _progress;
  final Completer<SkillsResult<T>> _completion;
  late final SkillsOperation<T> operation;
  OperationProgressPhase? _lastPhase;
  bool _finished = false;

  CancellationToken get cancellationToken => _cancellation.token;

  void emit(
    OperationProgressPhase phase, {
    String? currentItem,
    int completed = 0,
    int? total,
  }) {
    if (_finished) {
      throw StateError('A completed operation cannot emit progress.');
    }
    if (completed < 0 || total != null && (total < 0 || completed > total)) {
      throw ArgumentError('Progress counts must form a valid bounded range.');
    }
    if (_lastPhase != null && phase.index < _lastPhase!.index) {
      throw StateError('Operation progress cannot move backwards.');
    }
    _lastPhase = phase;
    _progress.add(
      OperationProgress(
        operationId: operation.operationId,
        kind: _kind,
        phase: phase,
        currentItem: currentItem,
        completed: completed,
        total: total,
      ),
    );
  }

  Future<void> finish(SkillsResult<T> result) async {
    if (_finished) {
      throw StateError('An operation can only complete once.');
    }
    _finished = true;
    await _progress.close();
    _completion.complete(result);
  }
}

final class _ControlledSkillsOperation<T> implements SkillsOperation<T> {
  _ControlledSkillsOperation._({
    required this.operationId,
    required this.progress,
    required this.completed,
    required Future<void> Function() cancel,
  }) : _cancel = cancel;

  @override
  final OperationId operationId;

  @override
  final Stream<OperationProgress> progress;

  @override
  final Future<SkillsResult<T>> completed;

  final Future<void> Function() _cancel;
  Future<void>? _cancellation;

  @override
  Future<void> cancel() => _cancellation ??= _cancel();
}
