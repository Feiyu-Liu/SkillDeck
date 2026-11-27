import 'dart:async';

import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

enum CloudSyncNotice { storageLimit, stopped }

enum CloudSkillSyncStatus { deviceOnly, synced, waiting, applying, attention }

final class CloudSyncState {
  const CloudSyncState({
    this.accountId,
    this.links = const {},
    this.outcomes = const {},
    this.metadataAttention = const {},
    this.metadataWaitingSkillIds = const {},
    this.vocabularyAttention = const {},
    this.metadataUnavailable = false,
    this.exclusions = const {},
    this.applying = const {},
    this.installedSkillIds = const {},
    this.bootstrapCompleted = false,
    this.notice,
  });

  final String? accountId;
  final Map<String, SyncLink> links;
  final Map<String, SyncOutcome> outcomes;
  final Map<String, SyncMetadataAttention> metadataAttention;
  final Set<String> metadataWaitingSkillIds;
  final Map<String, MetadataLimit> vocabularyAttention;
  final bool metadataUnavailable;
  final Set<String> exclusions, applying, installedSkillIds;
  final bool bootstrapCompleted;
  final CloudSyncNotice? notice;

  ({CloudSkillSyncStatus status, SyncNeedsAttention? attention}) skill(
    String skillId,
  ) {
    if (applying.contains(skillId)) {
      return (status: CloudSkillSyncStatus.applying, attention: null);
    }
    final link = links[skillId];
    final outcome = outcomes[skillId] ?? link?.attentionAttempt?.outcome;
    return switch (outcome) {
      final SyncNeedsAttention reason => (
        status: CloudSkillSyncStatus.attention,
        attention: reason,
      ),
      WaitingToUpload() => (
        status: CloudSkillSyncStatus.waiting,
        attention: null,
      ),
      _ when link == null => (
        status: CloudSkillSyncStatus.deviceOnly,
        attention: null,
      ),
      _ when link.clientKey != null => (
        status: CloudSkillSyncStatus.waiting,
        attention: null,
      ),
      _ when link.uploadBlockedByQuota => (
        status: CloudSkillSyncStatus.waiting,
        attention: null,
      ),
      _ => (status: CloudSkillSyncStatus.synced, attention: null),
    };
  }
}

/// Runs all work for one verified Cloud Account in a single queue.
final class CloudSyncRuntime {
  CloudSyncRuntime({
    required this.accountId,
    required Reconciler reconciler,
    required AppDiagnostics diagnostics,
    required void Function() onSignInRequired,
    bool rebaselineTagsOnStart = false,
    Duration Function()? elapsed,
    Timer Function(Duration, void Function()) createTimer = Timer.new,
  }) : _reconciler = reconciler,
       _diagnostics = diagnostics,
       _onSignInRequired = onSignInRequired,
       _rebaselineTags = rebaselineTagsOnStart,
       _elapsed = elapsed ?? _monotonicClock(),
       _createTimer = createTimer {
    _snapshot = CloudSyncState(accountId: accountId);
    _scheduler = FeedCheckScheduler(
      check: _feedCheck,
      elapsed: _elapsed,
      createTimer: createTimer,
    );
  }

  final String accountId;
  final Reconciler _reconciler;
  final AppDiagnostics _diagnostics;
  final void Function() _onSignInRequired;
  final Duration Function() _elapsed;
  final Timer Function(Duration, void Function()) _createTimer;
  late final FeedCheckScheduler _scheduler;
  final _updates = StreamController<CloudSyncState>.broadcast();
  final _applying = <String>{};
  final _installed = <String>{};
  Future<void> _tail = Future.value();
  Future<void>? _closeFuture;
  late CloudSyncState _snapshot;
  CloudSyncNotice? _notice;
  Timer? _debounce;
  Duration _retryNotBefore = Duration.zero;
  bool _bootstrapped = false;
  bool _rebaselineTags;
  bool _stopped = false;

  Stream<CloudSyncState> watch() => Stream.multi((controller) {
    controller.add(_snapshot);
    final subscription = _updates.stream.listen(
      controller.add,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });

  void start() => _scheduler.start();
  void onForeground() => _scheduler.onForeground();
  void onReconnect() => _scheduler.onReconnect();
  void onWake() => _scheduler.onWake();

  void onWorkspaceCommitted() {
    if (_stopped) return;
    _debounce?.cancel();
    _debounce = _createTimer(const Duration(seconds: 2), () {
      unawaited(_localCheck());
    });
  }

  void onApplying(String skillId, bool applying) {
    if (applying) {
      _applying.add(skillId);
    } else {
      _applying.remove(skillId);
    }
    _publish(_snapshot.links, _snapshot.exclusions);
  }

  Future<SyncOutcome> reconcileSkill(String skillId) =>
      runAction((reconciler) => reconciler.reconcileSkill(skillId));

  Future<SyncOutcome> resolveNoteConflict(
    String skillId, {
    required int expectedVersion,
    required String? expectedLocalNote,
    required String? value,
  }) => runAction((reconciler) async {
    final remaining = _retryNotBefore - _elapsed();
    if (remaining > Duration.zero) {
      return WaitingToUpload(retryAfter: remaining);
    }
    return reconciler.resolveNoteConflict(
      skillId,
      expectedVersion: expectedVersion,
      expectedLocalNote: expectedLocalNote,
      value: value,
    );
  });

  Future<T> runAction<T>(Future<T> Function(Reconciler) action) =>
      _enqueue(() async {
        final result = await action(_reconciler);
        if (result is SyncAccountCondition) _account(result);
        if (result is WaitingToUpload) _respectRetryAfter(result.retryAfter);
        return result;
      });

  Future<T> _enqueue<T>(Future<T> Function() work) {
    final result = _tail.then((_) async {
      if (_stopped) throw StateError('cloud_sync_inactive');
      try {
        final result = await AppDiagnostics.withoutDetails(work);
        await _refresh();
        return result;
      } on StateError catch (error) {
        final code = switch (error.message) {
          'cloud_protocol' => 'cloud_protocol',
          'cloud_workspace_contract' => 'cloud_workspace_contract',
          'sync_state_quarantine_failed' => 'sync_state_quarantine_failed',
          'local_state_io' => 'local_state_io',
          _ => 'unexpected_state',
        };
        _diagnostics.info('cloud.sync.stopped', context: {'code': code});
        _notice = CloudSyncNotice.stopped;
        _stop();
        _publish(_snapshot.links, _snapshot.exclusions);
        throw StateError(code);
      }
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> _localCheck() async {
    if (!_bootstrapped || _stopped) return;
    try {
      await _enqueue(() async {
        if (_retryNotBefore > _elapsed()) return;
        final result = await _reconciler.checkLocalChanges();
        _respectRetryAfter(result.retryAfter);
        _account(_reconciler.accountCondition);
      });
    } on Object {
      // The periodic check retries an uncommitted cursor while still active.
    }
  }

  Future<FeedCheckResult> _feedCheck() => _enqueue(() async {
    final remaining = _retryNotBefore - _elapsed();
    if (remaining > Duration.zero) {
      return FeedCheckResult.failure(retryAfter: remaining);
    }
    if (_rebaselineTags) {
      await _reconciler.rebaselineTagEligibility();
      _rebaselineTags = false;
    }
    if (!_bootstrapped) {
      if (await _reconciler.state.feedCursor() == null) {
        final result = await _reconciler.bootstrap();
        _installed.addAll(result.installedSkillIds);
        _respectRetryAfter(result.retryAfter);
        _account(_reconciler.accountCondition);
        if (!result.completed || _stopped) {
          return _stopped
              ? const FeedCheckResult.success()
              : FeedCheckResult.failure(retryAfter: result.retryAfter);
        }
        if (result.retryAfter case final delay?) {
          _bootstrapped = true;
          return FeedCheckResult.success(retryAfter: delay);
        }
      }
      _bootstrapped = true;
    }
    // Workspace cursors also retry on reconnect or the next scheduled check.
    final local = await _reconciler.checkLocalChanges();
    _respectRetryAfter(local.retryAfter);
    final account = _reconciler.accountCondition;
    if (_stopped ||
        account?.condition is ApiSignInRequired ||
        local.retryAfter != null) {
      _account(account);
      return local;
    }
    final result = await _reconciler.feedCheck();
    _respectRetryAfter(result.retryAfter);
    _account(_reconciler.accountCondition ?? account);
    return local.followedBy(result);
  });

  void _respectRetryAfter(Duration? delay) {
    if (delay == null) return;
    final deadline = _elapsed() + delay;
    if (deadline > _retryNotBefore) _retryNotBefore = deadline;
  }

  static Duration Function() _monotonicClock() {
    final clock = Stopwatch()..start();
    return () => clock.elapsed;
  }

  void _account(SyncAccountCondition? outcome) {
    switch (outcome?.condition) {
      case ApiSignInRequired():
        _stop();
        _onSignInRequired();
      case ApiStorageLimitReached():
        _notice = CloudSyncNotice.storageLimit;
      default:
        if (_notice == CloudSyncNotice.storageLimit) _notice = null;
    }
  }

  Future<void> _refresh() async {
    final links = await _reconciler.state.links();
    final exclusions = await _reconciler.state.exclusions();
    _publish({for (final link in links) link.managedSkillId: link}, exclusions);
  }

  void _publish(Map<String, SyncLink> links, Set<String> exclusions) {
    _snapshot = CloudSyncState(
      accountId: accountId,
      links: Map.unmodifiable(links),
      outcomes: _reconciler.outcomes,
      metadataAttention: Map.unmodifiable(_reconciler.metadataAttention),
      metadataWaitingSkillIds: Set.unmodifiable(
        _reconciler.metadataWaitingSkillIds,
      ),
      vocabularyAttention: Map.unmodifiable(_reconciler.vocabularyAttention),
      metadataUnavailable: _reconciler.metadataUnavailable,
      exclusions: Set.unmodifiable(exclusions),
      applying: Set.unmodifiable(_applying),
      bootstrapCompleted: _bootstrapped,
      installedSkillIds: Set.unmodifiable(_installed),
      notice: _notice,
    );
    if (!_updates.isClosed) _updates.add(_snapshot);
  }

  void _stop() {
    _stopped = true;
    _scheduler.stop();
    _debounce?.cancel();
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _stop();
    await _tail;
    unawaited(_updates.close());
  }
}
