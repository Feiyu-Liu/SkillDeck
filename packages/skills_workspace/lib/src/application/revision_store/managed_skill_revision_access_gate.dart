import 'dart:async';

import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';

/// In-process shared/exclusive admission for one managed Skill's canonical
/// Revision Store.
///
/// The Workspace runtime ownership lock excludes a second serving process, so
/// Source Replacement needs no persistent sidecar lease. Waiting writers have
/// priority over later readers to ensure destructive operations can drain.
final class ManagedSkillRevisionAccessGate {
  final Map<ManagedSkillId, _GateState> _states = {};

  Future<ManagedSkillRevisionAccessPermit> acquireRead(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  }) => _acquire(
    managedSkillId,
    mode: _GateMode.read,
    cancellationToken: cancellationToken ?? CancellationToken.none(),
  );

  Future<ManagedSkillRevisionAccessPermit> acquireExclusive(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  }) => _acquire(
    managedSkillId,
    mode: _GateMode.exclusive,
    cancellationToken: cancellationToken ?? CancellationToken.none(),
  );

  Future<ManagedSkillRevisionAccessPermit> _acquire(
    ManagedSkillId managedSkillId, {
    required _GateMode mode,
    required CancellationToken cancellationToken,
  }) {
    if (cancellationToken.isCancelled) {
      return Future.error(const ManagedSkillRevisionAccessCancelled());
    }
    final state = _states.putIfAbsent(managedSkillId, _GateState.new);
    final request = _GateRequest(mode);
    state.waiters.add(request);
    _drain(managedSkillId, state);
    unawaited(
      cancellationToken.whenCancelled.then((_) {
        if (request.isCompleted) return;
        if (state.waiters.remove(request)) {
          request.cancel();
          _drain(managedSkillId, state);
        }
      }),
    );
    return request.completer.future;
  }

  void _drain(ManagedSkillId managedSkillId, _GateState state) {
    if (state.exclusiveHeld) return;
    if (state.activeReaders > 0) {
      _grantLeadingReaders(managedSkillId, state);
      return;
    }
    if (state.waiters.isEmpty) {
      _detach(managedSkillId, state);
      return;
    }

    if (state.waiters.first.mode == _GateMode.exclusive) {
      final request = state.waiters.removeAt(0);
      state.exclusiveHeld = true;
      request.grant(
        ManagedSkillRevisionAccessPermit._(() {
          state.exclusiveHeld = false;
          _drain(managedSkillId, state);
        }),
      );
      return;
    }

    _grantLeadingReaders(managedSkillId, state);
  }

  void _grantLeadingReaders(ManagedSkillId managedSkillId, _GateState state) {
    while (state.waiters.isNotEmpty &&
        state.waiters.first.mode == _GateMode.read) {
      final request = state.waiters.removeAt(0);
      state.activeReaders += 1;
      request.grant(
        ManagedSkillRevisionAccessPermit._(() {
          state.activeReaders -= 1;
          _drain(managedSkillId, state);
        }),
      );
    }
  }

  void _detach(ManagedSkillId managedSkillId, _GateState state) {
    if (!state.exclusiveHeld &&
        state.activeReaders == 0 &&
        state.waiters.isEmpty &&
        identical(_states[managedSkillId], state)) {
      _states.remove(managedSkillId);
    }
  }
}

final class ManagedSkillRevisionAccessPermit {
  ManagedSkillRevisionAccessPermit._(this._release);

  void Function()? _release;

  Future<void> release() async {
    final release = _release;
    if (release == null) return;
    _release = null;
    release();
  }
}

final class ManagedSkillRevisionAccessCancelled implements Exception {
  const ManagedSkillRevisionAccessCancelled();
}

enum _GateMode { read, exclusive }

final class _GateState {
  final List<_GateRequest> waiters = [];
  int activeReaders = 0;
  bool exclusiveHeld = false;
}

final class _GateRequest {
  _GateRequest(this.mode);

  final _GateMode mode;
  final Completer<ManagedSkillRevisionAccessPermit> completer = Completer();

  bool get isCompleted => completer.isCompleted;

  void grant(ManagedSkillRevisionAccessPermit permit) {
    if (!completer.isCompleted) completer.complete(permit);
  }

  void cancel() {
    if (!completer.isCompleted) {
      completer.completeError(const ManagedSkillRevisionAccessCancelled());
    }
  }
}
