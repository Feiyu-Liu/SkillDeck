import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/presentation/view_models/cloud_sign_in_view_model.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

final _origin = CloudServiceOrigin.parse('https://cloud.example.test');

void main() {
  for (final serviceReachable in [false, true]) {
    test(
      'a sync-session expiry is final when the session route is ${serviceReachable ? 'reachable' : 'offline'}',
      () async {
        final store = InMemoryCloudSessionStore();
        await store.write(_session('owner', 'expired'));
        var reads = 0;
        final client = MockClient((request) async {
          expect(request.url.path, '/api/auth/get-session');
          if (++reads > 1 && !serviceReachable) {
            throw http.ClientException('fixture endpoint offline');
          }
          return http.Response(
            jsonEncode({
              'user': {'id': 'owner', 'email': 'owner@example.test'},
              'session': {'expiresAt': '2036-01-01T00:00:00Z'},
            }),
            200,
          );
        });
        addTearDown(client.close);
        final container = ProviderContainer.test(
          overrides: [
            cloudOriginProvider.overrideWithValue(_origin),
            cloudSessionStoreProvider.overrideWithValue(store),
            cloudHttpClientProvider.overrideWithValue(client),
          ],
        );
        final initial = await container.read(
          cloudSignInViewModelProvider.future,
        );
        expect(initial.verifiedAccount?.id, 'owner');
        await container
            .read(cloudSignInViewModelProvider.notifier)
            .sessionExpired('owner');
        expect(
          container.read(cloudSignInViewModelProvider).value?.phase,
          CloudSignInPhase.signedOut,
        );
        expect(await store.read(_origin), isNull);
        expect(reads, 1);
      },
    );
  }

  test(
    'late 401 on the signed-out account cannot erase the new session',
    () async {
      final store = InMemoryCloudSessionStore();
      final container = ProviderContainer.test(
        overrides: [cloudSessionStoreProvider.overrideWithValue(store)],
      );
      await store.write(_session('old', 'old-token'));
      final requested = Completer<void>(), released = Completer<void>();
      final client = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer old-token');
        requested.complete();
        await released.future;
        return http.Response('{}', 401);
      });
      addTearDown(client.close);
      final reader = container.read(cloudAccountSessionStoreProvider('old'));
      final api = CloudApi(client: client, origin: _origin, sessions: reader);
      final pending = api.checkFeed();
      await requested.future;
      await store.write(_session('new', 'new-token'));
      released.complete();
      expect(await pending, isA<ApiSignInRequired>());
      expect(await reader.read(_origin), isNull);
      expect((await store.read(_origin))?.account?.id, 'new');
      expect(
        (await container
                .read(cloudAccountSessionStoreProvider('new'))
                .read(_origin))
            ?.token,
        'new-token',
      );
    },
  );

  test(
    'on an expired session a runtime stops and a fresh runtime can start',
    () async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final expired = Completer<void>();
      final old = await _runtime(
        service,
        session: 'expired',
        onSignInRequired: expired.complete,
      );
      old.start();
      await expired.future;
      await old.close();
      final requests = service.requests.length;
      old.onReconnect();
      await expectLater(old.runAction((_) async => true), throwsStateError);
      expect(service.requests, hasLength(requests));

      final next = await _runtime(service, session: service.session('new'));
      final boot = next.watch().firstWhere((state) => state.bootstrapCompleted);
      next.start();
      expect((await boot).notice, isNull);
      expect(service.requests.where((r) => r.path == '/v0/feed'), hasLength(1));
    },
  );

  test('coalesces lifecycle checks behind the running check and stops on a protocol defect', () async {
    final service = FakeCloudService();
    addTearDown(service.client.close);
    final firstFeed = Completer<void>(), release = Completer<void>();
    var feeds = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/v0/feed') {
        if (++feeds == 1) {
          firstFeed.complete();
          await release.future;
        } else {
          return http.Response('malformed', 200);
        }
      }
      return http.Response.fromStream(
        await service.client.send(
          http.Request(request.method, request.url)
            ..headers.addAll(request.headers),
        ),
      );
    });
    addTearDown(client.close);
    final logs = <String>[];
    final runtime = await _runtime(
      service,
      session: service.session('owner'),
      client: client,
      diagnostics: AppDiagnostics.debug(writer: logs.add),
    );
    final stopped = runtime.watch().firstWhere(
      (state) => state.notice == CloudSyncNotice.stopped,
    );
    runtime.start();
    await firstFeed.future;
    runtime.onForeground();
    runtime.onWake();
    runtime.onReconnect();
    expect(feeds, 1);
    release.complete();
    await stopped;
    expect(feeds, 2);
    runtime.onForeground();
    await expectLater(runtime.runAction((_) async => true), throwsStateError);
    expect(feeds, 2);
    expect(logs.single, contains('cloud_protocol'));
    expect(logs.single, isNot(contains('malformed')));
  });

  test('a persisted quota block is displayed as waiting', () {
    const state = CloudSyncState(
      links: {
        'skill': SyncLink(
          managedSkillId: 'skill',
          lineageId: 'lineage',
          uploadBlockedByQuota: true,
        ),
      },
    );
    expect(state.skill('skill').status, CloudSkillSyncStatus.waiting);
  });
}

StoredCloudSession _session(String accountId, String token) =>
    StoredCloudSession(
      origin: _origin,
      token: token,
      account: CloudAccount(
        id: accountId,
        email: '$accountId@example.test',
        sessionExpiresAt: DateTime.utc(2027),
      ),
    );

Future<CloudSyncRuntime> _runtime(
  FakeCloudService service, {
  required String session,
  http.Client? client,
  void Function()? onSignInRequired,
  AppDiagnostics? diagnostics,
}) async {
  final directory = await Directory.systemTemp.createTemp('sync-runtime-');
  addTearDown(() => directory.delete(recursive: true));
  final sessions = InMemoryCloudSessionStore();
  await sessions.write(_session('account', session));
  final runtime = CloudSyncRuntime(
    accountId: 'account',
    reconciler: Reconciler(
      api: CloudApi(
        client: client ?? service.client,
        origin: _origin,
        sessions: sessions,
      ),
      workspace: FakeSyncWorkspace(),
      state: InMemorySyncStateStore(),
      scratchDirectory: directory.path,
    ),
    diagnostics: diagnostics ?? AppDiagnostics.disabled(),
    onSignInRequired:
        onSignInRequired ?? () => fail('Sign-in required unexpectedly'),
  );
  addTearDown(runtime.close);
  return runtime;
}
