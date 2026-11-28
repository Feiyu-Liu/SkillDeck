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
import 'package:skills_manager/shared/theme/app_theme.dart';

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
      CloudSyncState state({required bool waiting}) => CloudSyncState(
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
        metadataAttention: const {
          'incomingDraft': SyncMetadataAttention(
            MetadataAttentionReason.noteConflict,
            note: CloudNote('Cloud text', 3),
          ),
          'synced': SyncMetadataAttention(MetadataAttentionReason.noteTooLarge),
        },
        metadataWaitingSkillIds: waiting
            ? const {'synced', 'incomingDraft'}
            : const {},
        bootstrapCompleted: true,
      );
      var edits = 0;
      for (final (locale, labels) in [
        (
          'en',
          [
            'Device Only',
            'Synced',
            'Waiting to Upload',
            'Applying Cloud changes…',
            "Another device updated this Skill. You have a Draft here, so the update is waiting.",
            "This Skill was changed on two devices.",
            "Another device removed this Skill. You have an unpublished Draft here.",
            "This Skill is too large to sync. Make it smaller, or stop syncing it.",
            "A synced Skill has the same name as this Skill.",
            "This Skill is no longer in your SkillDeck Cloud library.",
            "Another device switched this Skill to a new source. Changes on this device haven't synced.",
            'Review note conflict',
            'Shorten the note to 4 KiB or less to sync it.',
            'Edit note',
          ],
        ),
        (
          'zh',
          [
            '仅此设备',
            '已同步',
            '等待上传',
            '正在应用云端更改…',
            "另一台设备更新了此 Skill。这里有草稿，所以更新还在等待。",
            "此 Skill 在两台设备上都有修改。",
            "另一台设备已删除此 Skill，这里还有未发布的草稿。",
            "此 Skill 太大，无法同步。请减小它的体积，或停止同步。",
            "有一个已同步的 Skill 与此 Skill 同名。",
            "此 Skill 已不在你的 SkillDeck Cloud 资料库中。",
            "另一台设备把此 Skill 换成了新的来源，这台设备上的更改还没有同步。",
            '审阅备注冲突',
            '将备注缩短至 4 KiB 以内即可同步。',
            '编辑备注',
          ],
        ),
      ]) {
        final updates = StreamController<CloudSyncState>()
          ..add(state(waiting: true));
        addTearDown(() => unawaited(updates.close()));
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(locale),
            overrides: [
              cloudSyncRuntimeProvider.overrideWithValue(runtime),
              cloudSyncStateProvider.overrideWith((ref) => updates.stream),
            ],
            child: CupertinoApp(
              locale: Locale(locale),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: appLocalizationsDelegates,
              home: CupertinoPageScaffold(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      CloudSkillSyncMark(
                        skillId: WorkspaceSkillId('incomingDraft'),
                      ),
                      CloudSkillSyncMark(skillId: WorkspaceSkillId('synced')),
                      for (final id in [
                        ...ids,
                        ...AttentionReason.values.map((r) => r.name),
                      ])
                        CloudSkillSyncTile(
                          skillId: WorkspaceSkillId(id),
                          enabled: true,
                          onEditNote: () => edits++,
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
        expect(
          find.bySemanticsLabel(locale == 'en' ? 'Note conflict' : '备注冲突'),
          findsOneWidget,
        );
        final pending = locale == 'en'
            ? 'Favorites, notes, or tags are waiting to sync.'
            : '收藏、备注或标签正在等待同步。';
        expect(find.text(pending), findsNWidgets(2));
        final pendingMarks = find.descendant(
          of: find.byType(CloudSkillSyncMark),
          matching: find.bySemanticsLabel(pending),
        );
        expect(pendingMarks, findsNWidgets(2));
        updates.add(state(waiting: false));
        await tester.pumpAndSettle();
        expect(find.text(pending), findsNothing);
        expect(pendingMarks, findsNothing);
        for (final label in labels) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.tap(find.byKey(const Key('cloud-note-edit')));
        await tester.pump();
      }
      expect(edits, 2);
    },
  );

  testWidgets(
    'note review shows the third candidate and retains the chosen text on failure',
    (tester) async {
      final service = FakeCloudService();
      addTearDown(service.client.close);
      final runtime = CloudSyncRuntime(
        accountId: 'account',
        reconciler: Reconciler(
          api: CloudApi(
            client: service.client,
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
      const state = CloudSyncState(
        accountId: 'account',
        metadataAttention: {
          'skill': SyncMetadataAttention(
            MetadataAttentionReason.noteConflict,
            note: CloudNote(
              'Cloud candidate',
              3,
              conflict: CloudNoteConflict(
                CloudNoteCandidate(
                  'Cloud candidate',
                  CloudNoteDevice('Studio', 'macos'),
                ),
                CloudNoteCandidate(
                  'Other candidate',
                  CloudNoteDevice('Laptop', 'macos'),
                ),
              ),
            ),
            localNote: 'First local draft',
            hasUnsubmittedLocalNote: true,
          ),
        },
      );
      final updates = StreamController<CloudSyncState>()..add(state);
      addTearDown(() => unawaited(updates.close()));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cloudSyncRuntimeProvider.overrideWithValue(runtime),
            cloudSyncStateProvider.overrideWith((ref) => updates.stream),
          ],
          child: CupertinoApp(
            locale: const Locale('en'),
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: CupertinoPageScaffold(
              child: CloudSkillSyncTile(
                skillId: WorkspaceSkillId('skill'),
                enabled: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-note-review')));
      await tester.pumpAndSettle();
      expect(find.text('Cloud candidate'), findsOneWidget);
      expect(find.text('Other candidate'), findsOneWidget);
      expect(find.text('First local draft'), findsOneWidget);
      expect(find.text('Unsynced note on this device'), findsOneWidget);

      final field = find.byKey(const Key('cloud-note-resolution-text'));
      await tester.ensureVisible(find.text('Combine versions'));
      await tester.tap(find.text('Combine versions'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoTextField>(field).controller!.text,
        'Cloud candidate\n\nOther candidate\n\nFirst local draft',
      );
      await tester.enterText(field, 'My chosen wording');
      await tester.tap(find.byKey(const Key('cloud-note-resolve')));
      await tester.pumpAndSettle();
      expect(
        find.text('The resolution couldn’t sync. Your chosen text stays here.'),
        findsOneWidget,
      );
      expect(
        tester.widget<CupertinoTextField>(field).controller!.text,
        'My chosen wording',
      );
      updates.add(const CloudSyncState(accountId: 'account'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'There is no conflict to resolve now. Your edited text stays here.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppButton>(find.byKey(const Key('cloud-note-resolve')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<CupertinoTextField>(field).controller!.text,
        'My chosen wording',
      );
    },
  );
}
