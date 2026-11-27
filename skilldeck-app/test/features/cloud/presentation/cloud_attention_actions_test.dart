import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_cloud/skills_cloud.dart' hide WorkspaceSkill;
import 'package:skills_cloud/skills_cloud.dart' as cloud show WorkspaceSkill;
import 'package:skills_cloud/testing.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/presentation/widgets/cloud_attention_actions.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/models/workspace_review.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../../../support/fake_skills_workspace_repository.dart';

final _origin = CloudServiceOrigin.parse('https://cloud.example.test');
const _account = 'account';

void main() {
  for (final (reason, expected) in [
    (
      AttentionReason.incomingDraft,
      ['publishDraft', 'reviewIncoming', 'discardDraft'],
    ),
    (AttentionReason.syncMergeConflict, ['reviewConflict']),
    (AttentionReason.removedWithDraft, ['remove', 'keepDeviceOnly']),
    (
      AttentionReason.sourceReplacedWithLocalChanges,
      ['acceptReplacement', 'keepDeviceOnly'],
    ),
    (AttentionReason.slotOccupied, ['replaceOccupied', 'exclude']),
    (AttentionReason.tooLarge, ['keepDeviceOnly', 'stop']),
    (
      AttentionReason.missingAfterReset,
      ['remove', 'keepDeviceOnly', 'uploadAsNew'],
    ),
  ]) {
    testWidgets('shows the actions for ${reason.name}', (tester) async {
      final fixture = await _Fixture.open(tester);
      await fixture.pump(tester, reason);
      for (final action in expected) {
        expect(_action(action), findsOneWidget);
      }
    });
  }

  for (final (reason, action) in [
    (AttentionReason.incomingDraft, 'discardDraft'),
    (AttentionReason.removedWithDraft, 'remove'),
    (AttentionReason.sourceReplacedWithLocalChanges, 'acceptReplacement'),
    (AttentionReason.slotOccupied, 'replaceOccupied'),
    (AttentionReason.missingAfterReset, 'remove'),
  ]) {
    testWidgets('cancelling $action on ${reason.name} changes nothing', (
      tester,
    ) async {
      final fixture = await _Fixture.open(tester);
      await fixture.pump(tester, reason);
      final before = await fixture.store.links();
      final snapshot = fixture.app.current;
      final requests = fixture.service.requests.length;
      await tester.tap(_action(action));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-attention-cancel')));
      await tester.pumpAndSettle();
      expect(await fixture.store.links(), before);
      expect(fixture.app.current, same(snapshot));
      expect(fixture.service.requests, hasLength(requests));
      expect(
        await fixture.workspace.inspectRevisionSelections(fixture.id.value),
        isNotNull,
      );
    });
  }

  for (final action in ['publishDraft', 'discardDraft']) {
    testWidgets('$action removes the Draft and reconciles its linked Skill', (
      tester,
    ) async {
      final fixture = await _Fixture.open(tester);
      await fixture.pump(tester, AttentionReason.incomingDraft);
      final prior = fixture.service.requests.length;
      await fixture.press(tester, action, confirm: action == 'discardDraft');
      expect(fixture.app.current.findSkillById(fixture.id)?.draft, isNull);
      expect(
        fixture.service.requests.skip(prior),
        contains((method: 'GET', path: '/v0/lineages/${fixture.lineage}')),
      );
    });
  }

  testWidgets('reviews the incoming pack without changing Workspace', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.pump(tester, AttentionReason.incomingDraft);
    final revision = fixture.app.current.revision;
    fixture.app.revisionPackDiffTask =
        ({
          required skillId,
          required expectedEffective,
          required incomingEffective,
          required incomingUpstream,
          required packPath,
        }) {
          expect(skillId, fixture.id);
          expect(expectedEffective, fixture.local.effective);
          expect(incomingEffective, fixture.remote.effective);
          expect(incomingUpstream, fixture.remote.upstream);
          expect(File(packPath).existsSync(), isTrue);
          return completedWorkspaceTask(
            kind: WorkspaceOperationKind.inspectRevisionPackDiff,
            value: WorkspaceRevisionPackDiff(
              skillId: skillId,
              from: expectedEffective,
              to: incomingEffective,
              files: const [
                (
                  path: 'incoming.bin',
                  previousPath: null,
                  status: WorkspaceDiffFileStatus.added,
                  isBinary: true,
                  additions: 0,
                  deletions: 0,
                  hunks: [],
                ),
              ],
            ),
          );
        };
    await fixture.press(tester, 'reviewIncoming');
    expect(find.text('incoming.bin'), findsOneWidget);
    expect(fixture.app.current.revision, revision);
    expect(fixture.app.current.findSkillById(fixture.id)?.draft, isNotNull);
  });

  for (final (side, label) in [
    (WorkspaceUpdateCandidateSide.current, 'Keep this Device’s version'),
    (WorkspaceUpdateCandidateSide.incoming, 'Keep the other Device’s version'),
  ]) {
    testWidgets(
      'choosing ${side.name} resolves, and publishing is a separate action',
      (tester) async {
        final fixture = await _Fixture.open(tester, conflict: true);
        await fixture.pump(tester, AttentionReason.syncMergeConflict);
        await fixture.press(tester, 'reviewConflict');
        await fixture.run(tester, () => tester.tap(find.text(label)));
        expect(fixture.app.resolvedConflictSides, [side]);
        expect(
          fixture.app.current.findSkillById(fixture.id)?.updateCandidate,
          isNotNull,
        );
        await fixture.press(tester, 'reviewConflict');
        await fixture.run(
          tester,
          () => tester.tap(find.text('Publish resolved Draft')),
        );
        expect(
          fixture.app.current.findSkillById(fixture.id)?.updateCandidate,
          isNull,
        );
      },
    );
  }

  for (final reason in [
    AttentionReason.removedWithDraft,
    AttentionReason.missingAfterReset,
  ]) {
    testWidgets(
      'confirmed ${reason.name} removal unlinks and removes local Skill',
      (tester) async {
        final fixture = await _Fixture.open(tester);
        await fixture.pump(tester, reason);
        await fixture.press(tester, 'remove', confirm: true);
        expect(
          await fixture.workspace.inspectRevisionSelections(fixture.id.value),
          isNull,
        );
        expect(await fixture.store.links(), isEmpty);
        if (reason == AttentionReason.removedWithDraft) {
          expect(fixture.app.current.findSkillById(fixture.id)?.draft, isNull);
        }
      },
    );
  }

  for (final reason in [
    AttentionReason.removedWithDraft,
    AttentionReason.sourceReplacedWithLocalChanges,
    AttentionReason.tooLarge,
    AttentionReason.missingAfterReset,
  ]) {
    testWidgets(
      'keep Device Only excludes the linked Lineage for ${reason.name}',
      (tester) async {
        final fixture = await _Fixture.open(tester);
        await fixture.pump(tester, reason);
        await fixture.press(tester, 'keepDeviceOnly');
        expect(await fixture.store.exclusions(), {fixture.lineage});
        expect(await fixture.store.links(), isEmpty);
        expect(
          await fixture.workspace.inspectRevisionSelections(fixture.id.value),
          isNotNull,
        );
      },
    );
  }

  testWidgets('accepting replacement reads and applies the linked Cloud Head', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.pump(tester, AttentionReason.sourceReplacedWithLocalChanges);
    await fixture.press(tester, 'acceptReplacement', confirm: true);
    expect(
      (await fixture.workspace.inspectRevisionSelections(fixture.id.value))
          ?.effective,
      fixture.remote.effective,
    );
  });

  testWidgets('replaces the occupant of an unlinked Cloud Slot', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.pump(tester, AttentionReason.slotOccupied);
    await fixture.press(tester, 'replaceOccupied', confirm: true);
    expect(
      (await fixture.workspace.inspectRevisionSelections(fixture.id.value))
          ?.effective,
      fixture.remote.effective,
    );
    expect((await fixture.store.links()).single.lineageId, fixture.lineage);
  });

  testWidgets('keeping an occupied Slot excludes the incoming Lineage', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.pump(tester, AttentionReason.slotOccupied);
    await fixture.press(tester, 'exclude');
    expect(await fixture.store.exclusions(), {fixture.lineage});
    expect(
      (await fixture.workspace.inspectRevisionSelections(fixture.id.value))
          ?.effective,
      fixture.local.effective,
    );
  });

  testWidgets('an occupied replacement excludes the linked remote ID', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.pump(
      tester,
      AttentionReason.slotOccupied,
      linkedOccupant: true,
    );
    await fixture.press(tester, 'exclude');
    expect(await fixture.store.exclusions(), {fixture.lineage});
    expect(await fixture.store.links(), isEmpty);
    expect(
      await fixture.workspace.inspectRevisionSelections(fixture.id.value),
      isNotNull,
    );
  });

  testWidgets('a destructive confirmation expires after a Workspace change', (
    tester,
  ) async {
    final fixture = await _Fixture.open(tester);
    await fixture.pump(tester, AttentionReason.sourceReplacedWithLocalChanges);
    final before = fixture.service.requests.length;
    await tester.tap(_action('acceptReplacement'));
    await tester.pumpAndSettle();
    final snapshot = fixture.app.current;
    fixture.app.publish(
      SkillsWorkspaceSnapshot(
        revision: snapshot.revision + 1,
        projectRoots: snapshot.projectRoots,
        skills: snapshot.skills,
      ),
    );
    await tester.tap(find.byKey(const Key('cloud-attention-confirm')));
    await tester.pumpAndSettle();
    expect(fixture.service.requests, hasLength(before));
    expect(
      (await fixture.workspace.inspectRevisionSelections(fixture.id.value))
          ?.effective,
      fixture.local.effective,
    );
  });

  testWidgets('Stop Syncing stops the matched Cloud Lineage', (tester) async {
    final fixture = await _Fixture.open(tester);
    await fixture.pump(tester, AttentionReason.tooLarge);
    await fixture.press(tester, 'stop');
    expect(fixture.service.requests.last, (
      method: 'POST',
      path: '/v0/lineages/${fixture.lineage}/stop',
    ));
    expect(await fixture.store.links(), isEmpty);
  });

  testWidgets(
    'upload as new creates a different Lineage for the same local Skill',
    (tester) async {
      final fixture = await _Fixture.open(tester);
      await fixture.pump(tester, AttentionReason.missingAfterReset);
      await fixture.press(tester, 'uploadAsNew');
      final link = (await fixture.store.links()).single;
      expect(link.lineageId, isNot(fixture.lineage));
      expect(link.managedSkillId, fixture.id.value);
    },
  );
}

Finder _action(String action) => find.byKey(Key('cloud-attention-$action'));

final class _Fixture {
  _Fixture(
    this.service,
    this.runtime,
    this.store,
    this.workspace,
    this.app,
    this.local,
    this.remote,
    this.lineage,
  );

  final FakeCloudService service;
  final CloudSyncRuntime runtime;
  final InMemorySyncStateStore store;
  final FakeSyncWorkspace workspace;
  final FakeSkillsWorkspaceRepository app;
  final cloud.WorkspaceSkill local;
  final cloud.WorkspaceSkill remote;
  final String lineage;

  WorkspaceSkillId get id => WorkspaceSkillId(local.id);

  static Future<_Fixture> open(
    WidgetTester tester, {
    bool conflict = false,
  }) async {
    return (await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync(
        'cloud-attention-widget-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final workspace = FakeSyncWorkspace();
      final local = workspace.seed(
        source: PortableSource.git(locator: 'https://example.test/local.git'),
      );
      final remoteWorkspace = FakeSyncWorkspace();
      final seed = remoteWorkspace.seed(
        source: PortableSource.git(locator: 'https://example.test/remote.git'),
      );
      final remote = remoteWorkspace.publish(seed.id, {
        'body.txt': 'Another Device',
      });
      final sessions = InMemoryCloudSessionStore();
      await sessions.write(
        StoredCloudSession(origin: _origin, token: service.session(_account)),
      );
      final api = CloudApi(
        client: service.client,
        origin: _origin,
        sessions: sessions,
      );
      final remoteStore = InMemorySyncStateStore();
      final sender = Reconciler(
        api: api,
        workspace: remoteWorkspace,
        state: remoteStore,
        scratchDirectory: temp.path,
      );
      expect(await sender.startSyncing(remote.id), isA<SkillSynced>());
      final lineage = (await remoteStore.links()).single.lineageId!;
      final id = WorkspaceSkillId(local.id);
      final now = DateTime.utc(2027);
      final app = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 1,
          projectRoots: [],
          skills: [
            WorkspaceSkill(
              id: id,
              slotKey: 'fixture',
              declaredName: 'fixture',
              displayName: 'Fixture',
              description: 'A fixture',
              source: const SkillSourceProvenance(
                kind: WorkspaceSourceKind.git,
                locator: 'https://example.test/local.git',
              ),
              currentRevision: SkillRevision(
                contentHash: 'fixture',
                fileCount: 1,
                byteSize: 1,
                acquiredAt: now,
              ),
              activations: [],
              draft: WorkspaceDraftSummary(
                purpose: WorkspaceDraftPurpose.customization,
                path: temp.path,
                isDirty: true,
                updatedAt: now,
              ),
              updateCandidate: conflict
                  ? WorkspaceUpdateCandidateSummary(
                      status: WorkspaceUpdateCandidateStatus.conflicted,
                      conflictPaths: ['body.txt'],
                      createdAt: now,
                    )
                  : null,
            ),
          ],
        ),
      );
      addTearDown(app.close);
      final store = InMemorySyncStateStore();
      final runtime = CloudSyncRuntime(
        accountId: _account,
        reconciler: Reconciler(
          api: api,
          workspace: workspace,
          state: store,
          scratchDirectory: temp.path,
        ),
        diagnostics: AppDiagnostics.disabled(),
        onSignInRequired: () => fail('Fixture session expired'),
      );
      return _Fixture(
        service,
        runtime,
        store,
        workspace,
        app,
        local,
        remote,
        lineage,
      );
    }))!;
  }

  Future<void> pump(
    WidgetTester tester,
    AttentionReason reason, {
    bool linkedOccupant = false,
  }) async {
    const linkedSkillId = 'previous-linked-skill';
    if (reason != AttentionReason.slotOccupied) {
      await store.put(SyncLink(managedSkillId: id.value, lineageId: lineage));
    } else if (linkedOccupant) {
      await store.put(
        SyncLink(managedSkillId: linkedSkillId, lineageId: lineage),
      );
    }
    final snapshot = CloudSyncState(
      accountId: _account,
      links: {
        for (final link in await store.links()) link.managedSkillId: link,
      },
      outcomes: {
        if (reason == AttentionReason.slotOccupied)
          (linkedOccupant ? linkedSkillId : lineage): SyncNeedsAttention(
            reason,
            occupant: id.value,
          )
        else
          id.value: SyncNeedsAttention(reason),
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cloudSyncRuntimeProvider.overrideWithValue(runtime),
          cloudSyncStateProvider.overrideWith((ref) => Stream.value(snapshot)),
          skillsWorkspaceRepositoryProvider.overrideWithValue(app),
        ],
        child: CupertinoApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: appLocalizationsDelegates,
          home: NeoButtonTheme(
            data: SkillsButtonTheme.neo,
            child: CupertinoPageScaffold(
              child: CloudAttentionActions(skillId: id),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    String action, {
    bool confirm = false,
  }) async {
    if (confirm) {
      await tester.tap(_action(action));
      await tester.pumpAndSettle();
    }
    await run(
      tester,
      () => tester.tap(
        confirm
            ? find.byKey(const Key('cloud-attention-confirm'))
            : _action(action),
      ),
    );
  }

  Future<void> run(WidgetTester tester, Future<void> Function() action) async {
    await tester.runAsync(() async {
      var finished = false;
      final subscription = runtime
          .watch()
          .skip(1)
          .listen((_) => finished = true);
      await action();
      for (var attempt = 0; !finished && attempt < 100; attempt++) {
        await tester.pump(const Duration(milliseconds: 10));
        if (!finished) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      expect(finished, isTrue, reason: 'The queued Cloud action should finish');
      unawaited(subscription.cancel());
    });
    await tester.pumpAndSettle();
  }
}
