import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';

import 'cloud_configuration.dart';
import 'data/cloud_gateway.dart';
import 'sync/cloud_sync_session.dart';
import '../settings/settings_providers.dart';
import '../skills/agent_root_ownership_coordinator.dart';
import '../skills/agent_root_ownership_providers.dart';
import '../skills/models/skills_workspace.dart';
import '../skills/workspace_snapshot_providers.dart';

final cloudConfigurationProvider = Provider<CloudConfiguration>(
  (ref) => CloudConfiguration.fromBuild(),
);
final cloudWorkspaceReadyProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await ref.read(workspaceSnapshotProvider.future);
  },
);
final cloudStartupProbeProvider =
    Provider<Future<bool> Function(CloudConfiguration)>(
      (ref) => hasPreviouslyEnabledCloudScope,
    );
final cloudGatewayFactoryProvider = Provider<CloudGatewayFactory>(
  (ref) => (configuration) async {
    final runtime = ref.read(skillsManagerRuntimeProvider);
    final gateway = await createCloudGateway(
      configuration,
      syncFactory: (auth, database) {
        final backend = runtime.cloudWorkspaceBackend;
        if (backend == null) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        return AppCloudSyncSession(
          auth: auth,
          database: database,
          repository: backend,
          canMutate: () async =>
              await AgentRootOwnershipCoordinator.withoutInteractiveRepair(
                () => ref
                    .read(agentRootOwnershipCoordinatorProvider)
                    .ensureReady(WorkspaceOperationKind.update),
              ) ==
              null,
        );
      },
    );
    runtime.addBeforeClose(gateway.close);
    return gateway;
  },
);
final cloudSettingsControllerProvider =
    NotifierProvider<CloudSettingsController, CloudSettingsState>(
      CloudSettingsController.new,
    );

enum CloudSettingsActivity {
  idle,
  signingIn,
  restoring,
  loadingDevices,
  revoking,
  signingOut,
  cancelling,
  loadingSync,
  syncing,
}

final class CloudSettingsState {
  const CloudSettingsState({
    this.session,
    this.devices = const [],
    this.deviceName = '',
    this.needsReconciliation = false,
    this.activity = CloudSettingsActivity.idle,
    this.sync,
    this.draftChoices = const {},
  });
  final CloudSession? session;
  final AppCloudSyncView? sync;
  final Set<String> draftChoices;
  final List<CloudDevice> devices;
  final String deviceName;
  final bool needsReconciliation;
  final CloudSettingsActivity activity;
  bool get busy => activity != CloudSettingsActivity.idle;
}

final class CloudSettingsController extends Notifier<CloudSettingsState> {
  Future<AppCloudGateway>? _gatewayFuture;
  AppCloudGateway? _gateway;
  CloudCancellation? _cancellation;
  var _disposed = false;
  var _actionEpoch = 0;
  static final _actionZoneKey = Object();
  StreamSubscription<AppCloudSyncView>? _backgroundUpdates;
  bool _startupChecked = false;
  @override
  CloudSettingsState build() {
    ref.onDispose(() {
      _disposed = true;
      _cancellation?.cancel();
      unawaited(_backgroundUpdates?.cancel());
      final future = _gatewayFuture;
      if (future != null) {
        unawaited(
          future.then<void>(
            (gateway) => gateway.close(),
            onError: (Object _) {},
          ),
        );
      }
    });
    return const CloudSettingsState();
  }

  Future<AppCloudGateway> _load() async {
    final configuration = ref.read(cloudConfigurationProvider);
    if (!configuration.configured) {
      throw const CloudException(CloudErrorCode.invalidConfiguration);
    }
    final future = _gatewayFuture ??= ref.read(cloudGatewayFactoryProvider)(
      configuration,
    );
    try {
      final gateway = _gateway = await future;
      if (_backgroundUpdates == null && gateway is AppCloudBackgroundGateway) {
        _backgroundUpdates = (gateway as AppCloudBackgroundGateway).syncUpdates
            .listen((view) => _publish(sync: view), onError: (Object _) {});
      }
      return gateway;
    } catch (_) {
      _gatewayFuture = null;
      rethrow;
    }
  }

  Future<void> restoreOptedInBackground() async {
    if (_startupChecked || _disposed || state.busy || state.session != null) {
      return;
    }
    final configuration = ref.read(cloudConfigurationProvider);
    if (!configuration.configured) return;
    _startupChecked = true;
    try {
      await ref.read(cloudWorkspaceReadyProvider)();
      if (_disposed || state.busy || state.session != null) return;
      if (!await ref.read(cloudStartupProbeProvider)(configuration) ||
          _disposed ||
          state.busy ||
          state.session != null) {
        return;
      }
      final gateway = await _load();
      if (gateway is AppCloudBackgroundGateway) {
        await (gateway as AppCloudBackgroundGateway).restoreOptedInBackground();
      }
    } catch (_) {
      /* Background failures never produce notification bursts. */
    } finally {
      _publish();
    }
  }

  void foreground() {
    final gateway = _gateway;
    if (gateway is AppCloudBackgroundGateway) {
      (gateway as AppCloudBackgroundGateway).foreground();
    }
  }

  void _publish({
    CloudSettingsActivity? activity,
    List<CloudDevice>? devices,
    AppCloudSyncView? sync,
  }) {
    if (_disposed ||
        (Zone.current[_actionZoneKey] is int &&
            Zone.current[_actionZoneKey] != _actionEpoch)) {
      return;
    }
    final gateway = _gateway;
    final sameAccount =
        gateway?.currentSession?.accountId == state.session?.accountId;
    final previousSync = sameAccount ? state.sync : null;
    final view = sync != null && sync.choices.isEmpty && previousSync != null
        ? sync.withChoices(previousSync.choices)
        : sync;
    state = CloudSettingsState(
      session: gateway?.currentSession,
      sync: gateway?.currentSession == null ? null : (view ?? previousSync),
      draftChoices: gateway?.currentSession == null || sync?.enabled == true
          ? const {}
          : state.draftChoices,
      devices: gateway?.currentSession == null
          ? const []
          : List.unmodifiable(devices ?? state.devices),
      deviceName: gateway?.deviceName ?? '',
      needsReconciliation:
          gateway?.currentSession != null &&
          (gateway?.needsReconciliation ?? false),
      activity: activity ?? state.activity,
    );
  }

  AppNotificationController get _notifications =>
      ref.read(appNotificationControllerProvider.notifier);
  Future<void> _run(
    CloudSettingsActivity activity,
    Future<void> Function(AppCloudGateway, CloudCancellation) action,
  ) async {
    if (state.busy) return;
    final epoch = ++_actionEpoch;
    final cancellation = CloudCancellation();
    _cancellation = cancellation;
    state = CloudSettingsState(
      session: state.session,
      sync: state.sync,
      draftChoices: state.draftChoices,
      devices: state.devices,
      deviceName: state.deviceName,
      needsReconciliation: state.needsReconciliation,
      activity: activity,
    );
    try {
      final gateway = await _load();
      cancellation.throwIfCancelled();
      await runZoned(
        () => action(gateway, cancellation),
        zoneValues: {_actionZoneKey: epoch},
      );
    } on CloudException catch (error) {
      if (!_disposed) {
        if (error.code == CloudErrorCode.cancelled) {
          _notifications.info(AppNotificationMessage.operationCancelled);
        } else {
          _notifications.error(switch (error.code) {
            CloudErrorCode.secureStorage =>
              AppNotificationMessage.cloudStorageFailed,
            CloudErrorCode.timeout => AppNotificationMessage.cloudTimedOut,
            CloudErrorCode.unauthorized =>
              AppNotificationMessage.cloudUnauthorized,
            CloudErrorCode.deviceLimit =>
              AppNotificationMessage.cloudDeviceLimit,
            CloudErrorCode.needsReconciliation =>
              AppNotificationMessage.cloudNeedsReconciliation,
            _ => AppNotificationMessage.cloudFailed,
          });
        }
      }
    } catch (_) {
      if (!_disposed) _notifications.error(AppNotificationMessage.cloudFailed);
    } finally {
      if (epoch == _actionEpoch) {
        _cancellation = null;
        _publish(activity: CloudSettingsActivity.idle);
      }
    }
  }

  Future<void> signIn() =>
      _run(CloudSettingsActivity.signingIn, (gateway, cancellation) async {
        await gateway.signIn(cancellation);
        cancellation.throwIfCancelled();
        final devices = await gateway.devices();
        cancellation.throwIfCancelled();
        _publish(devices: devices);
        if (!_disposed) {
          _notifications.success(AppNotificationMessage.cloudDeviceConnected);
        }
      });
  Future<void> restore() => _run(CloudSettingsActivity.restoring, (
    gateway,
    cancellation,
  ) async {
    final session = await gateway.restore(cancellation);
    cancellation.throwIfCancelled();
    if (session == null) {
      if (!_disposed) {
        _notifications.info(AppNotificationMessage.cloudNoSavedSession);
      }
      return;
    }
    final devices = await gateway.devices();
    cancellation.throwIfCancelled();
    _publish(devices: devices);
    if (!_disposed) {
      if (gateway.needsReconciliation) {
        _notifications.warning(AppNotificationMessage.cloudNeedsReconciliation);
      } else {
        _notifications.success(AppNotificationMessage.cloudConnectionRestored);
      }
    }
  });
  Future<void> refreshDevices() =>
      _run(CloudSettingsActivity.loadingDevices, (gateway, cancellation) async {
        final devices = await gateway.devices();
        cancellation.throwIfCancelled();
        _publish(devices: devices);
      });
  Future<void> revokeDevice(String deviceId) => _run(
    CloudSettingsActivity.revoking,
    (gateway, cancellation) async {
      final pending = await gateway.revoke(deviceId);
      cancellation.throwIfCancelled();
      final devices = gateway.currentSession == null
          ? <CloudDevice>[]
          : await gateway.devices();
      _publish(devices: devices);
      if (!_disposed) {
        if (pending) {
          _notifications.warning(AppNotificationMessage.cloudRevocationPending);
        } else {
          _notifications.success(AppNotificationMessage.cloudDeviceRevoked);
        }
      }
    },
  );
  Future<void> signOut() => _run(CloudSettingsActivity.signingOut, (
    gateway,
    cancellation,
  ) async {
    await gateway.logoutCredentials();
    _publish(devices: const []);
    if (!_disposed) _notifications.info(AppNotificationMessage.cloudSignedOut);
  });
  Future<void> loadSync() =>
      _run(CloudSettingsActivity.loadingSync, (gateway, cancellation) async {
        if (gateway is! AppCloudSyncGateway) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        final view = await (gateway as AppCloudSyncGateway).syncOverview();
        cancellation.throwIfCancelled();
        _publish(sync: view);
      });
  void toggleSyncChoice(AppCloudSkillChoice choice) {
    final next = {...state.draftChoices},
        key = '${choice.kind.name}:${choice.id}';
    if (!next.remove(key)) next.add(key);
    state = CloudSettingsState(
      session: state.session,
      devices: state.devices,
      deviceName: state.deviceName,
      needsReconciliation: state.needsReconciliation,
      activity: state.activity,
      sync: state.sync,
      draftChoices: Set.unmodifiable(next),
    );
  }

  Future<void> enableSelectedSync() => _run(CloudSettingsActivity.syncing, (
    gateway,
    cancellation,
  ) async {
    if (gateway is! AppCloudSyncGateway) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final choices =
        state.sync?.choices
            .where(
              (choice) => state.draftChoices.contains(
                '${choice.kind.name}:${choice.id}',
              ),
            )
            .toList() ??
        [];
    _publish(
      sync: await (gateway as AppCloudSyncGateway).enableSyncChoices(choices),
    );
  });
  Future<void> enableSync(AppCloudSkillChoice choice) =>
      _run(CloudSettingsActivity.syncing, (gateway, cancellation) async {
        if (gateway is! AppCloudSyncGateway) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        _publish(
          sync: await (gateway as AppCloudSyncGateway).enableSyncChoice(choice),
        );
      });
  Future<void> resumeSync() => _run(CloudSettingsActivity.syncing, (
    gateway,
    cancellation,
  ) async {
    if (gateway is! AppCloudSyncGateway) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final choices =
        state.sync?.choices
            .where((choice) => state.sync!.selectedIds.contains(choice.id))
            .toList() ??
        [];
    _publish(
      sync: await (gateway as AppCloudSyncGateway).enableSyncChoices(choices),
    );
  });
  Future<void> syncNow() =>
      _run(CloudSettingsActivity.syncing, (gateway, cancellation) async {
        if (gateway is! AppCloudSyncGateway) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        _publish(sync: await (gateway as AppCloudSyncGateway).syncNow());
      });
  Future<void> stopSync() async {
    if (state.activity == CloudSettingsActivity.syncing) {
      final epoch = ++_actionEpoch;
      _cancellation?.cancel();
      _publish(activity: CloudSettingsActivity.cancelling);
      try {
        final gateway = _gateway ?? await _gatewayFuture;
        if (gateway is AppCloudSyncGateway) {
          final view = await (gateway as AppCloudSyncGateway).stopSync();
          if (epoch == _actionEpoch) {
            _publish(sync: view, activity: CloudSettingsActivity.idle);
          }
        }
      } catch (_) {
        if (epoch == _actionEpoch) {
          _publish(activity: CloudSettingsActivity.idle);
        }
      } finally {
        if (epoch == _actionEpoch) _cancellation = null;
      }
      return;
    }
    await _run(CloudSettingsActivity.syncing, (gateway, cancellation) async {
      if (gateway is! AppCloudSyncGateway) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      _publish(sync: await (gateway as AppCloudSyncGateway).stopSync());
    });
  }

  void cancel() {
    _cancellation?.cancel();
    if (state.busy) _publish(activity: CloudSettingsActivity.cancelling);
  }
}
