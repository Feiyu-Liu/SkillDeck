import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/data/file_sync_state_store.dart';
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

  test(
    'an automatic check stops safely when local sync state cannot be written',
    () async {
      final support = await Directory.systemTemp.createTemp(
        'unwritable-sync-state-',
      );
      addTearDown(() => support.delete(recursive: true));
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final state = FileSyncStateStore(
        supportDirectory: support.path,
        origin: _origin,
        accountId: 'account',
        deviceId: 'device',
        onDiagnostic: (code) =>
            fail('Unexpected state quarantine: ${code.name}'),
      );
      final logs = <String>[];
      final runtime = await _runtime(
        service,
        session: service.session('account'),
        state: state,
        diagnostics: AppDiagnostics.debug(writer: logs.add),
      );
      final boot = runtime.watch().firstWhere(
        (state) => state.bootstrapCompleted,
      );
      runtime.start();
      await boot;
      final checkpoint = support
          .listSync(recursive: true)
          .whereType<File>()
          .single;
      final prior = await checkpoint.readAsString();
      final preserved = await checkpoint.parent.rename(
        '${checkpoint.parent.path}-saved',
      );
      await File(checkpoint.parent.path)
          .writeAsString('Blocks the next directory create.');

      final stopped = runtime.watch().firstWhere(
        (state) => state.notice == CloudSyncNotice.stopped,
      );
      runtime.onForeground();
      await stopped;
      final requests = service.requests.length;
      runtime.onForeground();
      runtime.onReconnect();
      runtime.onWake();
      runtime.onWorkspaceCommitted();
      await expectLater(
        runtime.runAction(
          (_) async => fail('Stopped sync ran a queued action'),
        ),
        throwsStateError,
      );
      expect(service.requests, hasLength(requests));
      expect(logs.single, contains('local_state_io'));
      expect(logs.single, isNot(contains(support.path)));
      expect(
        await File(p.join(preserved.path, p.basename(checkpoint.path)))
            .readAsString(),
        prior,
      );
    },
  );

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

  test(
    'only explicit account sign-in rebaselines existing local tags',
    () async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final client = MockClient((request) async {
        if (request.url.path == '/v0/tags') return http.Response('{}', 404);
        return http.Response.fromStream(
          await service.client.send(
            http.Request(request.method, request.url)
              ..headers.addAll(request.headers),
          ),
        );
      });
      addTearDown(client.close);
      final workspace = FakeSyncWorkspace();
      final prior = workspace.createLocalTag('Prior account');
      final pending = workspace.createLocalTag('Pending for this account');
      final stored = SyncMetadataState(
        knownTagIds: {pending.id, 'deleted-tag'},
        eligibleTagIds: {pending.id, 'deleted-tag'},
      );
      for (final explicit in [false, true]) {
        final state = InMemorySyncStateStore();
        await state.setMetadataState(stored);
        final runtime = await _runtime(
          service,
          session: service.session('test-account'),
          client: client,
          state: state,
          workspace: workspace,
          rebaselineTagsOnStart: explicit,
        );
        final checked = runtime.watch().firstWhere(
          (state) => state.metadataUnavailable,
        );
        runtime.start();
        expect((await checked).bootstrapCompleted, isTrue);
        final tags = await state.metadataState();
        expect(
          tags.knownTagIds,
          explicit ? {prior.id, pending.id} : stored.knownTagIds,
        );
        expect(
          tags.eligibleTagIds,
          explicit ? {pending.id} : stored.eligibleTagIds,
        );
        await runtime.close();
      }
    },
  );

  for (final status in [429, 503]) {
    test(
      'automatic checks honor metadata Retry-After on HTTP $status',
      () async {
        final service = FakeCloudService(supportsMetadata: true);
        addTearDown(service.client.close);
        final workspace = FakeSyncWorkspace();
        final state = InMemorySyncStateStore();
        final sessions = InMemoryCloudSessionStore();
        await sessions.write(_session('account', service.session('account')));
        var elapsed = Duration.zero;
        final timers = <Duration, _TestTimer>{};
        final runtime = CloudSyncRuntime(
          accountId: 'account',
          reconciler: Reconciler(
            api: CloudApi(
              client: service.client,
              origin: _origin,
              sessions: sessions,
            ),
            workspace: workspace,
            state: state,
            scratchDirectory: '',
          ),
          diagnostics: AppDiagnostics.disabled(),
          onSignInRequired: () => fail('Unexpected authorization failure'),
          elapsed: () => elapsed,
          createTimer: (delay, run) => timers[delay] = _TestTimer(run),
        );
        addTearDown(runtime.close);
        Future<void> check(void Function() trigger) async {
          final next = runtime.watch().skip(1).first;
          trigger();
          await next;
          // The scheduler starts its next timer after the runtime publishes.
          await Future<void>.delayed(Duration.zero);
        }

        int attempts() => service.requests
            .where((r) => r.path == '/v0/tags' && r.method == 'POST')
            .length;
        int feeds() =>
            service.requests.where((r) => r.path == '/v0/feed').length;

        await check(runtime.start);
        final before = await state.workspaceCursor();
        expect(feeds(), 1);
        expect(before, isNotNull);
        workspace.createLocalTag('Retry this tag');
        service.failNext(
          path: '/v0/tags',
          method: 'POST',
          status: status,
          retryAfter: const Duration(minutes: 3),
        );
        await check(runtime.onForeground);
        expect(attempts(), 1);
        expect(feeds(), 1);
        expect(await state.workspaceCursor(), before);

        runtime.onWorkspaceCommitted();
        elapsed = const Duration(seconds: 2);
        await check(timers[elapsed]!.fire);
        expect(attempts(), 1);
        elapsed = const Duration(seconds: 179);
        await check(runtime.onWake);
        expect(attempts(), 1);
        expect(feeds(), 1);

        elapsed = const Duration(minutes: 3);
        await check(timers[const Duration(seconds: 1)]!.fire);
        expect(attempts(), 2);
        expect(await state.workspaceCursor(), isNot(before));
      },
    );
  }

  test(
    'manual Note resolution waits for the recovery read Retry-After',
    () async {
      final service = FakeCloudService(supportsMetadata: true);
      addTearDown(service.client.close);
      final workspace = FakeSyncWorkspace();
      final skill = workspace.seed(
        source: PortableSource.git(
          locator: 'https://github.com/test/skill.git',
        ),
      );
      var elapsed = Duration.zero;
      final runtime = await _runtime(
        service,
        session: service.session('account'),
        workspace: workspace,
        elapsed: () => elapsed,
      );
      final setup = await runtime.runAction((sync) async {
        await sync.bootstrap();
        await sync.startSyncing(skill.id);
        final id = (await sync.state.links()).single.lineageId!;
        await sync.api.writeNote(id, expectedVersion: 0, value: 'First');
        await sync.api.openNoteConflict(
          id,
          expectedVersion: 1,
          value: 'Second',
        );
        await sync.feedCheck();
        return (id: id, attention: sync.metadataAttention[skill.id]!);
      });
      final path = '/v0/lineages/${setup.id}/metadata/note';
      const retryAfter = Duration(seconds: 54);
      service.failNext(path: '$path/resolve', status: 503);
      service.failNext(path: path, status: 429, retryAfter: retryAfter);
      expect(
        await runtime.resolveNoteConflict(
          skill.id,
          expectedVersion: setup.attention.note!.version,
          expectedLocalNote: setup.attention.localNote,
          value: 'Local choice',
        ),
        isA<WaitingToUpload>().having(
          (result) => result.retryAfter,
          'retryAfter',
          retryAfter,
        ),
      );
      final requests = service.requests.length;
      Future<SyncOutcome> retry() => runtime.resolveNoteConflict(
        skill.id,
        expectedVersion: setup.attention.note!.version,
        expectedLocalNote: 'Local choice',
        value: 'Local choice',
      );
      elapsed = const Duration(seconds: 53);
      expect(await retry(), isA<WaitingToUpload>());
      expect(service.requests, hasLength(requests));
      elapsed = retryAfter;
      expect(await retry(), isA<SkillSynced>());
    },
  );
}

final class _TestTimer extends Fake implements Timer {
  _TestTimer(this._run);
  final void Function() _run;
  @override
  bool isActive = true;
  @override
  void cancel() => isActive = false;
  void fire() {
    expect(isActive, isTrue);
    cancel();
    _run();
  }
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
  FakeSyncWorkspace? workspace,
  SyncStateStore? state,
  Duration Function()? elapsed,
  bool rebaselineTagsOnStart = false,
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
      workspace: workspace ?? FakeSyncWorkspace(),
      state: state ?? InMemorySyncStateStore(),
      scratchDirectory: directory.path,
    ),
    diagnostics: diagnostics ?? AppDiagnostics.disabled(),
    elapsed: elapsed,
    rebaselineTagsOnStart: rebaselineTagsOnStart,
    onSignInRequired:
        onSignInRequired ?? () => fail('Sign-in required unexpectedly'),
  );
  addTearDown(runtime.close);
  return runtime;
}
