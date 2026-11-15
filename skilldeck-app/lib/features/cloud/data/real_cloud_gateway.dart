import 'dart:async';

import 'package:skills_cloud/skills_cloud.dart';

import '../sync/cloud_sync_scheduler.dart';

import '../cloud_configuration.dart';
import '../sync/cloud_sync_session.dart';

abstract interface class AppCloudGateway {
  String get deviceName;
  CloudSession? get currentSession;
  bool get needsReconciliation;
  Future<CloudSession> signIn(CloudCancellation cancellation);
  Future<CloudSession?> restore(CloudCancellation cancellation);
  Future<List<CloudDevice>> devices();
  Future<bool> revoke(String deviceId);
  Future<void> logoutCredentials();
  Future<void> close();
}

typedef CloudGatewayFactory = Future<AppCloudGateway> Function(
  CloudConfiguration configuration,
);

abstract interface class AppCloudBackgroundGateway {
  Stream<AppCloudSyncView> get syncUpdates;
  Future<bool> restoreOptedInBackground();
  void foreground();
}

final class RealAppCloudGateway
    implements AppCloudGateway, AppCloudSyncGateway, AppCloudBackgroundGateway {
  RealAppCloudGateway({
    required CloudAuthClient auth,
    required CloudDeviceScopeStore? database,
    required this.deviceName,
    required this.platform,
    AppCloudSyncSession Function(
      CloudAuthClient,
      BackgroundSqliteCloudDatabase,
    )?
    syncFactory,
  }) : _auth = auth,
       _database = database,
       _syncFactory = syncFactory,
       _needsReconciliation = database == null;
  final CloudAuthClient _auth;
  final CloudDeviceScopeStore? _database;
  final AppCloudSyncSession Function(
    CloudAuthClient,
    BackgroundSqliteCloudDatabase,
  )?
  _syncFactory;
  AppCloudSyncSession? _sync;
  Future<void>? _closeFuture;
  AppCloudSyncScheduler? _scheduler;
  AppCloudSyncView? _latest;
  int _epoch = 0;
  final _updates = StreamController<AppCloudSyncView>.broadcast();
  @override
  Stream<AppCloudSyncView> get syncUpdates => _updates.stream;
  AppCloudSyncScheduler get _schedule => _scheduler ??= AppCloudSyncScheduler(
    synchronize: () async {
      _latest = await _syncSession.synchronize();
    },
    cancelAndDrain: () async {
      await _sync?.cancelAndDrain();
    },
    onState: (state) {
      if (_updates.isClosed) return;
      final view = (_latest ?? const AppCloudSyncView()).withBackground(
        running: state.phase == CloudSchedulePhase.running,
        error: state.error,
      );
      _latest = view;
      _updates.add(view);
    },
  );
  @override
  Future<bool> restoreOptedInBackground() async {
    final cancellation = CloudCancellation();
    final restored = await restore(cancellation);
    final database = _database;
    if (restored == null ||
        needsReconciliation ||
        database is! BackgroundSqliteCloudDatabase ||
        !await database.hasEnabledOptIn(session: restored)) {
      return false;
    }
    final view = await _syncSession.overview(loadChoices: false);
    _latest = view;
    if (!view.enabled || view.needsReconciliation) return false;
    _schedule.start();
    return true;
  }

  @override
  void foreground() => _scheduler?.foreground();

  AppCloudSyncSession get _syncSession {
    if (_closeFuture != null || currentSession == null) {
      throw const CloudException(CloudErrorCode.unauthorized);
    }
    final database = _database, factory = _syncFactory;
    if (needsReconciliation ||
        database is! BackgroundSqliteCloudDatabase ||
        factory == null) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return _sync ??= factory(_auth, database);
  }

  @override
  Future<AppCloudSyncView> syncOverview() async =>
      _latest = await _syncSession.overview();
  @override
  Future<AppCloudSyncView> enableSyncChoice(AppCloudSkillChoice choice) =>
      enableSyncChoices([choice]);
  @override
  Future<AppCloudSyncView> enableSyncChoices(
    List<AppCloudSkillChoice> choices,
  ) async {
    final epoch = _epoch;
    _latest = await _syncSession.enableChoices(choices);
    if (epoch != _epoch) throw const CloudException(CloudErrorCode.cancelled);
    return syncNow();
  }

  @override
  Future<AppCloudSyncView> syncNow() async {
    final view = await _syncSession.overview(loadChoices: false);
    if (!view.enabled || view.needsReconciliation) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    _latest = view;
    _schedule.start(immediate: false);
    await _schedule.runNow();
    return _latest!;
  }

  @override
  Future<AppCloudSyncView> stopSync() async {
    _epoch++;
    await _scheduler?.pause();
    return _latest = await _syncSession.stop();
  }

  @override
  final String deviceName;
  final String platform;
  bool _needsReconciliation;
  @override
  bool get needsReconciliation => _needsReconciliation;
  @override
  CloudSession? get currentSession => _auth.currentSession;
  @override
  Future<CloudSession> signIn(CloudCancellation cancellation) async {
    _epoch++;
    await _scheduler?.pause();
    await _sync?.stop();
    final session = await _auth.signIn(
      deviceName: deviceName,
      platform: platform,
      cancellation: cancellation,
    );
    // Only a new server device can establish device authority. No Workspace
    // scope is marked ready and no Sync request or upload starts here.
    try {
      final database = _database;
      if (database == null) {
        _needsReconciliation = true;
      } else {
        await database.initializeNewDeviceScope(session);
        _needsReconciliation = false;
      }
    } catch (_) {
      _needsReconciliation = true;
    }
    return session;
  }

  @override
  Future<CloudSession?> restore(CloudCancellation cancellation) async {
    _epoch++;
    await _scheduler?.pause();
    await _sync?.stop();
    final session = await _auth.restore(cancellation: cancellation);
    try {
      _needsReconciliation =
          session != null &&
          (_database == null || !await _database.hasDeviceScope(session));
    } catch (_) {
      _needsReconciliation = session != null;
    }
    return session;
  }

  @override
  Future<List<CloudDevice>> devices() => _auth.listDevices();
  @override
  Future<bool> revoke(String deviceId) async {
    if (deviceId == currentSession?.deviceId) {
      _epoch++;
      await _scheduler?.pause();
      await _sync?.stop();
    }
    return _auth.revokeDevice(deviceId);
  }

  @override
  Future<void> logoutCredentials() async {
    _epoch++;
    await _scheduler?.pause();
    try {
      await _sync?.stop();
    } finally {
      await _auth.logoutCredentials();
    }
  }

  @override
  Future<void> close() => _closeFuture ??= _close();
  Future<void> _close() async {
    _epoch++;
    await _scheduler?.close();
    try {
      await _sync?.close();
    } finally {
      try {
        await _auth.close();
      } finally {
        await _database?.close();
        await _updates.close();
      }
    }
  }
}
