import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/presentation/widgets/cloud_skill_sync.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

void main() {
  testWidgets(
    'each Skill status and attention reason renders in both languages',
    (tester) async {
      const ids = ['device', 'synced', 'waiting', 'applying'];
      final fake = FakeCloudService();
      addTearDown(fake.client.close);
      final runtime = CloudSyncRuntime(
        accountId: 'account',
        reconciler: Reconciler(
          api: CloudApi(
            client: fake.client,
            origin: CloudServiceOrigin.parse('https://cloud.example.test'),
            sessions: InMemoryCloudSessionStore(),
          ),
          workspace: FakeSyncWorkspace(),
          state: InMemorySyncStateStore(),
          scratchDirectory: '',
        ),
        diagnostics: AppDiagnostics.disabled(),
        onSignInRequired: () {},
      );
      addTearDown(() => unawaited(runtime.close()));
      final state = CloudSyncState(
        accountId: runtime.accountId,
        links: const {
          'synced': SyncLink(managedSkillId: 'synced', lineageId: 'id'),
          'waiting': SyncLink(managedSkillId: 'waiting', clientKey: 'key'),
        },
        applying: const {'applying'},
        outcomes: {
          for (final reason in AttentionReason.values)
            reason.name: SyncNeedsAttention(reason),
        },
        bootstrapCompleted: true,
      );
      for (final (locale, labels) in [
        (
          'en',
          [
            'Device Only',
            'Synced',
            'Waiting to Upload',
            'Applying Cloud changes…',
            'An incoming change is waiting for this Draft.',
            'Changes from two Devices need to be merged.',
            'This Skill was removed on another Device while a Draft exists here.',
            'This Skill is too large to sync.',
            'A different local Skill occupies this slot.',
            'Missing from the Cloud Library after a reset.',
            'The Source was replaced on another Device while this Device has unsynced changes.',
          ],
        ),
        (
          'zh',
          [
            '仅此设备',
            '已同步',
            '等待上传',
            '正在应用云端更改…',
            '请先处理草稿，再应用云端更改。',
            '两台设备上的更改需要合并。',
            '另一台设备已删除此 Skill，这台设备仍有草稿。',
            '此 Skill 太大，无法同步。',
            '另一个本地 Skill 已占用此位置。',
            '重置后，此 Skill 已不在云端资料库中。',
            '另一台设备已替换来源，这台设备仍有未同步的更改。',
          ],
        ),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              cloudSyncRuntimeProvider.overrideWithValue(runtime),
              cloudSyncStateProvider.overrideWith((ref) => Stream.value(state)),
            ],
            child: CupertinoApp(
              locale: Locale(locale),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              home: CupertinoPageScaffold(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final id in [
                        ...ids,
                        ...AttentionReason.values.map((r) => r.name),
                      ])
                        CloudSkillSyncTile(
                          skillId: WorkspaceSkillId(id),
                          enabled: true,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
      }
    },
  );
}
