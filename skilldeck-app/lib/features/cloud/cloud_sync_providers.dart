import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_device_identity.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/data/file_sync_state_store.dart';
import 'package:skills_manager/features/cloud/data/workspace_sync_adapter.dart';
import 'package:skills_manager/features/cloud/presentation/view_models/cloud_sign_in_view_model.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

typedef CloudSyncLifecycleState = ({
  CloudSyncRuntime? runtime,
  bool startupFailed,
});
const _idle = (runtime: null, startupFailed: false);

final cloudSyncLifecycleProvider =
    NotifierProvider<CloudSyncRuntimeController, CloudSyncLifecycleState>(
      CloudSyncRuntimeController.new,
    );

final cloudSyncRuntimeProvider = Provider<CloudSyncRuntime?>((ref) {
  return ref.watch(cloudSyncLifecycleProvider.select((owner) => owner.runtime));
});

final cloudAccountSessionStoreProvider =
    Provider.family<CloudSessionStore, String>(
      (ref, accountId) =>
          _AccountSessionStore(ref.watch(cloudSessionStoreProvider), accountId),
    );

final cloudSyncStateProvider = StreamProvider<CloudSyncState>((ref) {
  final owner = ref.watch(cloudSyncLifecycleProvider);
  return owner.runtime?.watch() ??
      Stream.value(
        CloudSyncState(
          notice: owner.startupFailed ? CloudSyncNotice.stopped : null,
        ),
      );
});

const _wakeChannel = MethodChannel('skilldeck/cloud_lifecycle');

final claimCloudActivationOfferProvider =
    Provider<Future<bool> Function(String)>((ref) {
      final origin = ref.watch(cloudOriginProvider);
      return (accountId) async {
        final scope = sha256.convert(
          utf8.encode(jsonEncode([origin?.toString(), accountId])),
        );
        final key = 'agent_skills.cloud.activation_offered.$scope';
        final preferences = SharedPreferencesAsync();
        try {
          if (await preferences.getBool(key) == true) return false;
          await preferences.setBool(key, true);
        } on Object {
          // The view still offers once per account in this process.
        }
        return true;
      };
    });

/// The App owns lifecycle listeners even while an account is offline.
final class CloudSyncRuntimeController
    extends Notifier<CloudSyncLifecycleState> {
  Future<void> _transition = Future.value();
  CloudSyncRuntime? _current;
  bool _closing = false;
  int _epoch = 0;

  @override
  CloudSyncLifecycleState build() {
    final origin = ref.watch(cloudOriginProvider);
    if (origin == null) return _idle;
    final client = ref.watch(cloudHttpClientProvider);
    if (client == null) return _idle;
    final local = ref.watch(skillsManagerRuntimeProvider);
    final diagnostics = ref.watch(appDiagnosticsProvider);
    final repository = ref.watch(skillsWorkspaceRepositoryProvider);
    final device = ref.watch(cloudDeviceProvider);

    void changeAccount(String? accountId, {required bool explicitSignIn}) {
      final epoch = ++_epoch;
      final old = _current;
      _current = null;
      if (old != null) state = _idle;
      final drained = old?.close();
      _transition = _transition.then((_) async {
        await drained;
        if (!_active(epoch)) return;
        state = _idle;
        if (accountId == null) return;
        try {
          final support = await getApplicationSupportDirectory();
          final label = (await device()).name;
          if (!_active(epoch)) return;
          await ref.read(workspaceSnapshotProvider.future);
          if (!_active(epoch)) return;
          final identity = await CloudDeviceIdentity.load(support.path);
          if (!_active(epoch)) return;

          final store = FileSyncStateStore(
            supportDirectory: support.path,
            origin: origin,
            accountId: accountId,
            // Application Support is already unique to this local Device.
            deviceId: 'local-macos',
            onDiagnostic: (code) => diagnostics.info(
              'cloud.state.recovered',
              context: {'code': code.name},
            ),
          );
          final api = CloudApi(
            client: client,
            origin: origin,
            sessions: ref.read(cloudAccountSessionStoreProvider(accountId)),
          );
          late final CloudSyncRuntime runtime;
          runtime = CloudSyncRuntime(
            accountId: accountId,
            rebaselineTagsOnStart: explicitSignIn,
            reconciler: Reconciler(
              api: api,
              state: store,
              workspace: WorkspaceSyncAdapter(
                repository: repository,
                deviceLabel: label,
                deviceIdentity: identity,
                onApplying: (id, applying) => runtime.onApplying(id, applying),
              ),
              scratchDirectory: p.join(support.path, 'cloud', 'scratch'),
            ),
            diagnostics: diagnostics,
            onSignInRequired: () {
              if (_active(epoch) && identical(_current, runtime)) {
                unawaited(
                  ref
                      .read(cloudSignInViewModelProvider.notifier)
                      .sessionExpired(accountId),
                );
              }
            },
          );
          _current = runtime;
          state = (runtime: runtime, startupFailed: false);
          runtime.start();
        } on Object {
          // Native or local storage errors may contain paths or account data.
          diagnostics.info('cloud.sync.stopped', context: {'code': 'startup'});
          if (_active(epoch)) state = (runtime: null, startupFailed: true);
        }
      });
    }

    // Listen for account identity changes without rebuilding when Settings
    // updates the same verified account or when a Workspace snapshot arrives.
    ref.listen(cloudSignInViewModelProvider, (previous, current) {
      final accountId = current.value?.verifiedAccount?.id;
      if (previous?.value?.verifiedAccount?.id != accountId) {
        changeAccount(
          accountId,
          explicitSignIn: current.value?.explicitSignIn ?? false,
        );
      }
    });
    final initial = ref.read(cloudSignInViewModelProvider).value;
    if (initial?.verifiedAccount case final account?) {
      changeAccount(account.id, explicitSignIn: initial!.explicitSignIn);
    }
    ref.listen(workspaceSnapshotProvider.select((s) => s.value?.revision), (
      previous,
      revision,
    ) {
      if (previous != null && revision != null && previous != revision) {
        _current?.onWorkspaceCommitted();
      }
    });

    List<ConnectivityResult>? lastConnection;
    final connection = Connectivity().onConnectivityChanged.listen((results) {
      final connected = !results.contains(ConnectivityResult.none);
      final previous = lastConnection;
      lastConnection = results;
      if (connected &&
          (previous?.contains(ConnectivityResult.none) == true ||
              ref.read(cloudSignInViewModelProvider).value?.phase ==
                  CloudSignInPhase.offline)) {
        _trigger((sync) => sync.onReconnect());
      }
    }, onError: (Object _) {});
    _wakeChannel.setMethodCallHandler((call) async {
      if (call.method == 'wake') _trigger((sync) => sync.onWake());
    });

    Future<void>? closeFuture;
    Future<void> drain() async {
      _closing = true;
      _epoch++;
      _wakeChannel.setMethodCallHandler(null);
      final old = _current;
      _current = null;
      await connection.cancel();
      await old?.close();
      await _transition;
    }

    Future<void> close() => closeFuture ??= drain();

    local.addBeforeClose(close);
    ref.onDispose(() {
      unawaited(close().whenComplete(() => local.removeBeforeClose(close)));
    });
    return _idle;
  }

  bool _active(int epoch) => ref.mounted && !_closing && _epoch == epoch;

  void onForeground() => _trigger((sync) => sync.onForeground());

  void _trigger(void Function(CloudSyncRuntime) trigger) {
    if (!ref.mounted || _closing || ref.read(cloudOriginProvider) == null) {
      return;
    }
    final sync = _current;
    if (sync != null) {
      trigger(sync);
    } else if (ref.read(cloudSignInViewModelProvider).value?.phase ==
        CloudSignInPhase.offline) {
      unawaited(_refreshSession());
    }
  }

  Future<void> _refreshSession() {
    if (!ref.mounted || _closing) return Future.value();
    return ref.read(cloudSignInViewModelProvider.notifier).refreshSession();
  }
}

/// The live account owner is the sole writer of credentials.
final class _AccountSessionStore implements CloudSessionStore {
  const _AccountSessionStore(this._store, this._accountId);

  final CloudSessionStore _store;
  final String _accountId;

  @override
  Future<StoredCloudSession?> read(CloudServiceOrigin origin) async {
    final session = await _store.read(origin);
    return session?.account?.id == _accountId ? session : null;
  }

  @override
  Future<void> delete(CloudServiceOrigin origin) async {}

  @override
  Future<void> write(StoredCloudSession session) async {
    throw StateError('cloud_session_read_only');
  }
}
