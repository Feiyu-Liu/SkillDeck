@OnPlatform({'windows': Timeout(Duration(minutes: 2))})
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:skills_manager/features/cloud/data/cloud_device_identity.dart';
import 'package:skills_manager/features/cloud/data/workspace_sync_adapter.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/skills/agent_root_ownership_coordinator.dart';
import 'package:skills_manager/features/skills/data/repositories/diagnostic_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/ownership_gated_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/package_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/services/agent_root_ownership_repair_service.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/models/workspace_review.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';
import 'package:skills_workspace/skills_workspace.dart' as backend;

import '../../../support/fake_skills_workspace_repository.dart';
import '../../../support/recording_app_diagnostic_sink.dart';

void main() {
  late Directory temporary;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('cloud-adapter-');
    addTearDown(() async {
      if (!Platform.isWindows) {
        await Process.run('chmod', ['-R', 'u+w', temporary.path]);
      }
      await temporary.delete(recursive: true);
    });
  });

  test(
    'real Workspaces sync a publish, wait behind a Draft, then replace Source',
    () async {
      final a = await _open(temporary, 'a');
      final b = await _open(temporary, 'b');
      final service = FakeCloudService(acceptRealPacks: true);
      addTearDown(service.client.close);
      final origin = CloudServiceOrigin.parse('https://cloud.example.com');
      final ra = _reconciler(
        a,
        await _api(service.client, origin, service.session('account')),
      );
      final rb = _reconciler(
        b,
        await _api(service.client, origin, service.session('account')),
      );
      final sourcePath = await _source(temporary, 'first');
      final id = await _install(a, sourcePath);
      await _publish(a, id, 'version one');
      final first = (await a.adapter.inspectRevisionSelections(id))!;

      expect(await ra.startSyncing(id), isA<SkillSynced>());
      final bootstrap = await rb.bootstrap();
      expect(bootstrap.completed, isTrue);
      final bId = bootstrap.installedSkillIds.single;
      final received = (await b.adapter.inspectRevisionSelections(bId))!;
      final remoteId = (await ra.state.links()).single.lineageId!;
      final remote =
          await ra.api.readLineage(remoteId) as CloudApiSuccess<Lineage>;
      expect(received.source, PortableSource.fromJson(remote.value.source));
      expect(received.source, first.source);
      expect(received.source.isDeviceBound, isTrue);
      expect(received.source.toJson().toString(), isNot(contains(sourcePath)));
      expect(received.effective, first.effective);
      expect(b.adapter.slotKeyForName(received.declaredName), received.slotKey);

      await _editDraft(b, bId, 'local draft');
      await _publish(a, id, 'version two');
      final second = (await a.adapter.inspectRevisionSelections(id))!;
      expect(second.effective, isNot(first.effective));
      await ra.checkLocalChanges();
      await rb.feedCheck();
      expect(
        rb.outcomes[bId],
        isA<SyncNeedsAttention>().having(
          (outcome) => outcome.reason,
          'reason',
          AttentionReason.incomingDraft,
        ),
      );
      expect(
        (await b.adapter.inspectRevisionSelections(bId))!.effective,
        first.effective,
      );
      _backendValue(
        await b.repository
            .discardDraft(
              backend.DiscardDraftRequest(
                managedSkillId: backend.ManagedSkillId(bId),
              ),
            )
            .completed,
      );
      expect(await rb.reconcileSkill(bId), isA<SkillSynced>());
      expect(
        (await b.adapter.inspectRevisionSelections(bId))!.effective,
        second.effective,
      );

      final replacementParent = await Directory(
        p.join(temporary.path, 'other-parent'),
      ).create();
      final replacementPath = await _source(replacementParent, 'first');
      await File(p.join(replacementPath, 'different.md'))
          .writeAsString('new source bytes');
      final receipt = await a.app
          .replaceSource(
            skillId: WorkspaceSkillId(id),
            source: SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: replacementPath,
            ),
            expectedRevision: a.app.current!.revision,
          )
          .completed;
      expect(receipt, isA<WorkspaceCompleted<WorkspaceMutationReceipt>>());
      final replaced = (await a.adapter.inspectRevisionSelections(id))!;
      expect(
        replaced.source.toJson()['displayLabel'],
        first.source.toJson()['displayLabel'],
      );
      expect(replaced.source, isNot(first.source));
      await ra.checkLocalChanges();
      await rb.feedCheck();
      expect(replaced.effective, isNot(second.effective));
      expect(
        (await b.adapter.inspectRevisionSelections(bId))!.effective,
        replaced.effective,
      );
      expect(
        (await b.adapter.inspectRevisionSelections(bId))!.source,
        replaced.source,
      );
      expect(
        (await ra.api.readLineage(
          remoteId,
        ) as CloudApiSuccess<Lineage>).value.generation,
        2,
      );

      var previousA = replaced;
      var previousB = (await b.adapter.inspectRevisionSelections(bId))!;
      for (final generation in [3, 4]) {
        if (generation == 3) {
          await File(p.join(replacementPath, 'different.md'))
              .writeAsString('changed bytes at the same address');
        }
        final receipt = await a.app
            .replaceSource(
              skillId: WorkspaceSkillId(id),
              source: SkillSourceInput(
                kind: WorkspaceSourceKind.local,
                locator: replacementPath,
              ),
              expectedRevision: a.app.current!.revision,
            )
            .completed;
        expect(receipt, isA<WorkspaceCompleted<WorkspaceMutationReceipt>>());
        final reset = (await a.adapter.inspectRevisionSelections(id))!;
        expect(reset.source, previousA.source);
        expect(reset.sourceEpoch, isNot(previousA.sourceEpoch));
        if (generation == 3) {
          expect(reset.effective, isNot(previousA.effective));
        } else {
          expect(reset.effective, previousA.effective);
          final path = p.join(temporary.path, 'identical-source-reset.pack');
          expect(
            await a.adapter.exportRevisionPack(id, path),
            isA<WorkspaceExported>(),
          );
          final stale = isA<WorkspaceApplyFailed>().having(
            (result) => result.code,
            'code',
            WorkspaceFailureCode.staleSnapshot,
          );
          expect(
            await a.adapter.applyContent(
              managedSkillId: id,
              expectedEffective: previousA.effective,
              expectedSourceEpoch: previousA.sourceEpoch,
              effective: reset.effective,
              upstream: reset.upstream,
              packPath: path,
            ),
            stale,
          );
          expect(
            await a.adapter.remove(
              managedSkillId: id,
              expectedEffective: previousA.effective,
              expectedSourceEpoch: previousA.sourceEpoch,
            ),
            stale,
          );
          expect(
            (await a.adapter.inspectRevisionSelections(id))!.sourceEpoch,
            reset.sourceEpoch,
          );
        }
        await ra.checkLocalChanges();
        await rb.feedCheck();
        final applied = (await b.adapter.inspectRevisionSelections(bId))!;
        final observed =
            await ra.api.readLineage(remoteId) as CloudApiSuccess<Lineage>;
        expect(observed.value.generation, generation);
        expect(observed.value.source, reset.source.toJson());
        expect(applied.effective, reset.effective);
        expect(applied.sourceEpoch, isNot(previousB.sourceEpoch));
        expect((await ra.state.links()).single.sourceEpoch, reset.sourceEpoch);
        expect(
          (await rb.state.links()).single.sourceEpoch,
          applied.sourceEpoch,
        );
        previousA = reset;
        previousB = applied;
      }

      final traced = a.sink.events.where(
        (event) => event.event == 'operation.started',
      );
      final names = traced.map((event) => event.operationKey);
      expect(
        names,
        containsAll([
          'inspectRevisionSelections',
          'inspectCommittedChanges',
          'exportRevisionPack',
        ]),
      );
      expect(
        b.sink.events.where(
          (event) =>
              event.event == 'operation.started' &&
              event.operationKey == 'applyRemoteState',
        ),
        hasLength(6),
      );
    },
  );

  test(
    'real packs keep Git, Well-known and Adopted portable provenance',
    () async {
      final a = await _open(temporary, 'source');
      final id = await _install(a, await _source(temporary, 'fixture'));
      final packPath = p.join(temporary.path, 'fixture.pack');
      final pack =
          await a.adapter.exportRevisionPack(id, packPath) as WorkspaceExported;
      final sources = [
        PortableSource.git(
          locator: 'https://example.com/repository.git',
          ref: 'branch',
          repositorySubpath: 'catalog',
          skillPath: 'other/fixture',
        ),
        PortableSource.wellKnown(
          locator: 'https://example.com/.well-known/skills/index.json',
          skillPath: 'some/fixture',
        ),
        PortableSource.deviceBound(
          originSourceType: 'adoptedSnapshot',
          originDeviceLabel: 'Origin',
          displayLabel: 'Adopted example',
        ),
      ];
      for (final entry in sources.indexed) {
        final (index, source) = entry;
        final target = await _open(temporary, 'target-$index');
        if (index == 0) {
          final invalidPath = p.join(temporary.path, 'invalid.pack');
          await File(invalidPath).writeAsString('invalid pack');
          expect(
            await target.adapter.install(
              packPath: invalidPath,
              effective: pack.effective,
              upstream: pack.upstream,
              source: source,
            ),
            isA<WorkspaceApplyFailed>().having(
              (failure) => failure.code,
              'code',
              WorkspaceFailureCode.invalidPack,
            ),
          );
        }
        final installed = await target.adapter.install(
          packPath: packPath,
          effective: pack.effective,
          upstream: source.isAdoptedSnapshot ? null : pack.upstream,
          source: source,
        ) as WorkspaceInstalled;
        final observed = await target.adapter.inspectRevisionSelections(
          installed.managedSkillId,
        );
        expect(observed!.source, source);
        expect(observed.effective, pack.effective);
        expect(
          target.sink.events.where(
            (event) =>
                event.event == 'operation.started' &&
                event.operationKey == 'applyRemoteState',
          ),
          hasLength(index == 0 ? 2 : 1),
        );
      }
    },
  );

  test(
    'a local Git acquisition uploads a label without its repository path',
    () async {
      final a = await _open(temporary, 'local-git');
      final source = await _source(temporary, 'local-repository');
      for (final args in [
        ['init'],
        ['add', 'SKILL.md'],
        [
          '-c',
          'user.email=fixture@example.com',
          '-c',
          'user.name=Fixture',
          'commit',
          '-m',
          'Fixture',
        ],
      ]) {
        final result = await Process.run('git', args, workingDirectory: source);
        expect(result.exitCode, 0);
      }
      final id = await _install(a, source, kind: WorkspaceSourceKind.git);
      final skill = (await a.adapter.inspectRevisionSelections(id))!;
      expect(skill.source.toJson(), containsPair('originSourceType', 'local'));
      expect(skill.source.toJson()['originDeviceLabel'], 'local-git');
      expect(skill.source.toJson()['displayLabel'], 'source-local-repository');
      expect(
        skill.source.toJson()['originSourceId'],
        matches('^[0-9a-f]{64}\$'),
      );
      expect(skill.source.toJson().values, isNot(contains(source)));
    },
  );

  test('ownership refusal stays a typed adapter failure and retains Feed Check progress', () async {
    final a = await _open(temporary, 'gate-a');
    final ownership = FakeSkillsWorkspaceRepository();
    addTearDown(ownership.dispose);
    final agentRoot = await Directory(p.join(temporary.path, 'test-agent'))
        .create();
    final b = await _open(
      temporary,
      'gate-b',
      ownershipRepository: ownership,
      agents: [
        backend.AgentDefinition(
          id: 'test-agent',
          displayName: 'Test Agent',
          platforms: {
            for (final platform in backend.DesktopPlatform.values)
              platform: backend.AgentPlatformDefinition(
                globalSkillsPath: agentRoot.path,
                detectionPaths: [
                  backend.AgentDetectionPath.absolute(agentRoot.path),
                ],
              ),
          },
        ),
      ],
    );
    final service = FakeCloudService(acceptRealPacks: true);
    addTearDown(service.client.close);
    final origin = CloudServiceOrigin.parse('https://cloud.example.com');
    final ra = _reconciler(
      a,
      await _api(service.client, origin, service.session('account')),
    );
    final rb = _reconciler(
      b,
      await _api(service.client, origin, service.session('account')),
    );
    final id = await _install(a, await _source(temporary, 'gated'));
    expect(await ra.startSyncing(id), isA<SkillSynced>());
    final bId = (await rb.bootstrap()).installedSkillIds.single;
    // Activate while the audit is clean, then invalidate its cached approval.
    expect(
      await b.app
          .activate(
            skillIds: {WorkspaceSkillId(bId)},
            scope: WorkspaceScope.global,
            agentIds: {'test-agent'},
            activationMethod: WorkspaceActivationMethod.copy,
          )
          .completed,
      isA<WorkspaceCompleted<WorkspaceActivationAttempt>>(),
    );
    expect(
      b.app.current!.findSkillById(WorkspaceSkillId(bId))!.activations,
      hasLength(1),
    );
    b.coordinator.invalidate();
    ownership.ownershipAudit = WorkspaceAgentRootOwnershipAudit(
      supported: true,
      examinedRootCount: 1,
      issues: [
        WorkspaceAgentRootOwnershipIssue(
          rootPath: agentRoot.path,
          agentIds: {'test-agent'},
          roles: {WorkspaceAgentSkillRootRole.canonicalActivation},
          reason: WorkspaceAgentRootOwnershipIssueReason.ownerMismatch,
          repairable: false,
        ),
      ],
    );
    final original = (await b.adapter.inspectRevisionSelections(bId))!
        .effective;
    expect(
      await b.adapter.remove(managedSkillId: bId, expectedEffective: original),
      isA<WorkspaceApplyFailed>().having(
        (failure) => failure.code,
        'code',
        WorkspaceFailureCode.operationFailed,
      ),
    );
    final cursor = await rb.state.feedCursor();
    final lineage = (await ra.state.links()).single.lineageId!;
    expect(await ra.api.remove(lineage), isA<CloudApiSuccess<Lineage>>());
    await expectLater(
      rb.feedCheck(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'cloud_workspace_contract',
        ),
      ),
    );
    expect(await rb.state.feedCursor(), cursor);
    expect(
      (await b.adapter.inspectRevisionSelections(bId))!.effective,
      original,
    );
  });

  test('App runtimes debounce real publishes and synchronize across two Workspaces', () async {
    final a = await _open(temporary, 'runtime-a');
    final b = await _open(temporary, 'runtime-b');
    final service = FakeCloudService(acceptRealPacks: true);
    addTearDown(service.client.close);
    final origin = CloudServiceOrigin.parse('https://cloud.example.test');
    final apiA = await _api(service.client, origin, service.session('account'));
    final apiB = await _api(service.client, origin, service.session('account'));
    final aClock = _RuntimeClock(), bClock = _RuntimeClock();
    final aRuntime = CloudSyncRuntime(
      accountId: 'account',
      reconciler: _reconciler(a, apiA),
      diagnostics: AppDiagnostics(sink: a.sink),
      onSignInRequired: () => fail('Authorized device asked to sign in'),
      createTimer: aClock.create,
    );
    final bRuntime = CloudSyncRuntime(
      accountId: 'account',
      reconciler: _reconciler(b, apiB),
      diagnostics: AppDiagnostics(sink: b.sink),
      onSignInRequired: () => fail('Authorized device asked to sign in'),
      createTimer: bClock.create,
    );
    addTearDown(aRuntime.close);
    addTearDown(bRuntime.close);
    final id = await _install(a, await _source(temporary, 'runtime'));
    await _nextSyncState(aRuntime, aRuntime.start);
    expect(
      await aRuntime.runAction((sync) => sync.startSyncing(id)),
      isA<SkillSynced>(),
    );
    final bBoot = await _nextSyncState(bRuntime, bRuntime.start);
    final bId = bBoot.installedSkillIds.single;
    final before = (await b.adapter.inspectRevisionSelections(bId))!.effective;
    final writesBefore = service.requests
        .where((r) => r.path.endsWith('/head'))
        .length;
    final revisions = a.app.snapshots.listen(
      (_) => aRuntime.onWorkspaceCommitted(),
    );
    addTearDown(revisions.cancel);
    await _publish(a, id, 'runtime revision');
    expect(
      service.requests.where((r) => r.path.endsWith('/head')),
      hasLength(writesBefore),
    );
    final aAfter = await _nextSyncState(
      aRuntime,
      () => aClock.fire(const Duration(seconds: 2)),
    );
    expect(aAfter.skill(id).status, CloudSkillSyncStatus.synced);
    expect(
      service.requests.where((r) => r.path.endsWith('/head')),
      hasLength(writesBefore + 1),
    );
    final bAfter = await _nextSyncState(bRuntime, bRuntime.onForeground);
    expect(bAfter.skill(bId).status, CloudSkillSyncStatus.synced);
    final received = (await b.adapter.inspectRevisionSelections(bId))!
        .effective;
    expect(received, isNot(before));
    expect(
      received,
      (await a.adapter.inspectRevisionSelections(id))!.effective,
    );
    expect(b.app.current!.skills.single.activations, isEmpty);

    for (final trigger in [
      bRuntime.onReconnect,
      bRuntime.onWake,
      () => bClock.fire(const Duration(minutes: 2)),
    ]) {
      final reads = service.requests.where((r) => r.path == '/v0/feed').length;
      await _nextSyncState(bRuntime, trigger);
      expect(
        service.requests.where((r) => r.path == '/v0/feed'),
        hasLength(reads + 1),
      );
    }

    await _publish(a, id, 'device A conflict');
    await _publish(b, bId, 'device B conflict');
    await _nextSyncState(
      aRuntime,
      () => aClock.fire(const Duration(seconds: 2)),
    );
    final conflicted = await _nextSyncState(bRuntime, bRuntime.onForeground);
    expect(
      conflicted.skill(bId).attention?.reason,
      AttentionReason.syncMergeConflict,
    );
    final localId = WorkspaceSkillId(bId);
    final prepublish = (await b.adapter.inspectRevisionSelections(bId))!
        .effective;
    final inspected = await bRuntime.runAction(
      (_) => b.app.inspectUpdateCandidateResolution(localId).completed,
    );
    final review =
        (inspected as WorkspaceCompleted<WorkspaceUpdateCandidateReview?>)
            .value!;
    expect(review.hasUnresolvedConflicts, isTrue);
    final resolved = await bRuntime.runAction(
      (_) => b.app
          .resolveUpdateCandidateConflicts(
            review: review,
            side: WorkspaceUpdateCandidateSide.incoming,
          )
          .completed,
    );
    expect(resolved, isA<WorkspaceCompleted<SkillsWorkspaceSnapshot>>());
    expect(
      (await b.adapter.inspectRevisionSelections(bId))!.effective,
      prepublish,
    );
    expect(
      await bRuntime.runAction((sync) async {
        expect(
          await b.app.publishUpdateCandidate(localId).completed,
          isA<WorkspaceCompleted<WorkspaceMutationReceipt>>(),
        );
        return sync.reconcileSkill(bId);
      }),
      isA<SkillSynced>(),
    );
    final aAfterMerge = await _nextSyncState(aRuntime, aRuntime.onForeground);
    expect(aAfterMerge.skill(id).status, CloudSkillSyncStatus.synced);
    expect(
      (await a.adapter.inspectRevisionSelections(id))!.effective,
      (await b.adapter.inspectRevisionSelections(bId))!.effective,
    );
  });

  final serviceOrigin = Platform.environment['SKILLDECK_CLOUD_TEST_ORIGIN'];
  test(
    'M4-7 real service round-trips a Workspace pack',
    skip: serviceOrigin == null
        ? 'Set SKILLDECK_CLOUD_TEST_ORIGIN to opt in'
        : false,
    () async {
      final token = Platform.environment['SKILLDECK_CLOUD_TEST_TOKEN'];
      if (token == null || token.isEmpty) {
        fail('No test Cloud session supplied');
      }
      final client = http.Client();
      addTearDown(client.close);
      final origin = CloudServiceOrigin.parse(serviceOrigin!);
      final a = await _open(temporary, 'a-live');
      final b = await _open(temporary, 'b-live');
      final ra = _reconciler(a, await _api(client, origin, token));
      final rb = _reconciler(b, await _api(client, origin, token));
      final id = await _install(a, await _source(temporary, 'real-roundtrip'));
      addTearDown(() => ra.stopSyncing(id));
      await _publish(a, id, 'upload a real native Git pack');
      expect(await ra.startSyncing(id), isA<SkillSynced>());
      final lineage = (await ra.state.links()).single;
      final bResult = await rb.bootstrap();
      expect(bResult.completed, isTrue);
      expect(bResult.outcomes[lineage.lineageId], isA<SkillSynced>());
      final target = (await rb.state.links()).singleWhere(
        (link) => link.lineageId == lineage.lineageId,
      );
      expect(
        (await b.adapter.inspectRevisionSelections(target.managedSkillId))!
            .effective,
        (await a.adapter.inspectRevisionSelections(id))!.effective,
      );
    },
  );
}

Future<CloudSyncState> _nextSyncState(
  CloudSyncRuntime runtime,
  void Function() trigger,
) {
  final result = runtime.watch().skip(1).first;
  trigger();
  return result;
}

final class _RuntimeClock {
  final _timers = <Duration, _RuntimeTimer>{};

  Timer create(Duration duration, void Function() fire) =>
      _timers[duration] = _RuntimeTimer(fire);

  void fire(Duration duration) => _timers[duration]!.fire();
}

final class _RuntimeTimer implements Timer {
  _RuntimeTimer(this._callback);
  final void Function() _callback;

  @override
  bool isActive = true;
  @override
  int tick = 0;

  @override
  void cancel() => isActive = false;

  void fire() {
    expect(isActive, isTrue);
    cancel();
    tick++;
    _callback();
  }
}

Future<CloudApi> _api(
  http.Client client,
  CloudServiceOrigin origin,
  String token,
) async {
  final sessions = InMemoryCloudSessionStore();
  await sessions.write(StoredCloudSession(origin: origin, token: token));
  return CloudApi(client: client, origin: origin, sessions: sessions);
}

Reconciler _reconciler(_Fixture fixture, CloudApi api) => Reconciler(
  api: api,
  workspace: fixture.adapter,
  state: InMemorySyncStateStore(),
  scratchDirectory: fixture.scratch,
);

typedef _Fixture = ({
  backend.SkillsRepository repository,
  OwnershipGatedSkillsWorkspaceRepository app,
  WorkspaceSyncAdapter adapter,
  RecordingAppDiagnosticSink sink,
  String scratch,
  AgentRootOwnershipCoordinator coordinator,
});

Future<_Fixture> _open(
  Directory temporary,
  String slug, {
  SkillsWorkspaceRepository? ownershipRepository,
  List<backend.AgentDefinition> agents = const [],
}) async {
  final location = p.join(temporary.path, slug);
  final home = await Directory(p.join(temporary.path, 'home-$slug')).create();
  final repository = backend.createSkillsRepository(
    backend.SkillsRepositoryConfiguration(
      rootPath: location,
      agentHomePath: home.path,
      additionalAgents: agents,
    ),
  );
  final raw = PackageSkillsWorkspaceRepository(backend: repository);
  final sink = RecordingAppDiagnosticSink();
  final diagnostics = AppDiagnostics(sink: sink);
  final diagnostic = DiagnosticSkillsWorkspaceRepository(
    delegate: raw,
    diagnostics: diagnostics,
    failureReporter: AppFailureReporter(diagnostics),
  );
  final coordinator = AgentRootOwnershipCoordinator(
    repository: ownershipRepository ?? diagnostic,
    repairService: _NoRepair(),
    reviewPresenter: _NoRepair(),
  );
  final app = OwnershipGatedSkillsWorkspaceRepository(
    delegate: diagnostic,
    coordinator: coordinator,
  );
  addTearDown(app.close);
  expect(await app.open(), isA<WorkspaceCompleted<SkillsWorkspaceSnapshot>>());
  final identity = await CloudDeviceIdentity.load(
    p.join(temporary.path, 'support-$slug'),
  );
  return (
    repository: repository,
    app: app,
    adapter: WorkspaceSyncAdapter(
      repository: app,
      deviceLabel: slug,
      deviceIdentity: identity,
    ),
    sink: sink,
    scratch: p.join(temporary.path, 'scratch-$slug'),
    coordinator: coordinator,
  );
}

Future<String> _source(Directory temporary, String slug) async {
  final source = await Directory(p.join(temporary.path, 'source-$slug'))
      .create();
  await File(p.join(source.path, 'SKILL.md')).writeAsString(
    '---\nname: cloud-fixture\ndescription: Native pack sync fixture\n---\n# Fixture $slug\n',
  );
  return source.path;
}

Future<String> _install(
  _Fixture fixture,
  String source, {
  WorkspaceSourceKind kind = WorkspaceSourceKind.local,
}) async {
  final result = await fixture.app
      .install(
        WorkspaceInstallRequest(
          source: SkillSourceInput(kind: kind, locator: source),
          scope: WorkspaceScope.global,
          storeOnly: true,
        ),
      )
      .completed;
  return ((result as WorkspaceCompleted<WorkspaceInstallAttempt>).value
          as WorkspaceInstallCompleted)
      .receipt
      .affectedSkillIds
      .single
      .value;
}

Future<void> _editDraft(_Fixture fixture, String id, String text) async {
  final draft = _backendValue(
    await fixture.repository
        .ensureDraft(
          backend.EnsureDraftRequest(
            managedSkillId: backend.ManagedSkillId(id),
          ),
        )
        .completed,
  );
  await File(p.join(draft.path, 'body.md')).writeAsString(text);
}

Future<void> _publish(_Fixture fixture, String id, String text) async {
  await _editDraft(fixture, id, text);
  _backendValue(
    await fixture.repository
        .publishDraft(
          backend.PublishDraftRequest(
            managedSkillId: backend.ManagedSkillId(id),
          ),
        )
        .completed,
  );
}

T _backendValue<T>(backend.SkillsResult<T> result) => result.fold(
  onSuccess: (success) => success.value,
  onFailure: (failure) => throw StateError(failure.code.name),
  onCommittedFinalizationPending: (_) =>
      throw StateError('finalization pending'),
);

final class _NoRepair
    implements
        AgentRootOwnershipRepairService,
        AgentRootOwnershipReviewPresenter {
  @override
  Future<AgentRootOwnershipRepairOutcome> repair({
    required WorkspaceAgentRootOwnershipAudit audit,
    required Set<String> reviewedRootPaths,
  }) async => throw StateError('Ownership repair not part of this fixture');

  @override
  Future<Set<String>?> review(WorkspaceAgentRootOwnershipAudit audit) async =>
      throw StateError('Ownership review not part of this fixture');
}
