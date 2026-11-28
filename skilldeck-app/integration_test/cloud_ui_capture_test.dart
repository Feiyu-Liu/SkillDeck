// Native, synthetic-data-only Cloud UI inventory. No production state is opened.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skills_cloud/skills_cloud.dart' as cloud;
import 'package:skills_cloud/testing.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/theme/app_button_theme.dart';
import 'package:skills_manager/features/skills/models/workspace_review.dart';
import 'package:window_manager/window_manager.dart';
import 'package:skills_manager/l10n/l10n.dart';

import '../test/support/fake_skill_browser_repository.dart';
import '../test/support/fake_skills_workspace_repository.dart';
import '../test/support/skills_manager_test_app.dart';

const _account = 'review-account';
final _origin = cloud.CloudServiceOrigin.parse('https://cloud.example.test');

final class _SessionStore implements cloud.CloudSessionStore {
  cloud.StoredCloudSession? session = cloud.StoredCloudSession(
    origin: _origin,
    token: 'synthetic-session',
    account: cloud.CloudAccount(
      id: _account,
      email: 'review@example.test',
      sessionExpiresAt: DateTime.utc(2027, 12),
    ),
  );
  bool failDelete = false;
  bool failRead = false;
  Completer<cloud.StoredCloudSession?>? reading;
  Completer<void>? deleting;
  @override
  Future<cloud.StoredCloudSession?> read(
    cloud.CloudServiceOrigin origin,
  ) async {
    if (failRead) throw StateError('synthetic_read_failure');
    return reading == null ? session : await reading!.future;
  }

  @override
  Future<void> write(cloud.StoredCloudSession value) async {
    session = value;
  }

  @override
  Future<void> delete(cloud.CloudServiceOrigin origin) async {
    if (failDelete) throw StateError('synthetic_failure');
    if (deleting != null) await deleting!.future;
    session = null;
  }
}

WorkspaceSkill _skill(String name) => WorkspaceSkill(
  id: WorkspaceSkillId(name == 'Review' ? 'skill-0' : name),
  slotKey: name,
  declaredName: name,
  displayName: name,
  description:
      'Reusable guidance for reviewing changes and preparing a release.',
  source: const SkillSourceProvenance(
    kind: WorkspaceSourceKind.git,
    locator: 'https://example.test/team/skills',
  ),
  currentRevision: SkillRevision(
    contentHash: 'a' * 64,
    fileCount: 1,
    byteSize: 120,
    acquiredAt: DateTime.utc(2026, 11, 28),
  ),
  activations: [],
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  setUpAll(() async {
    // Capture-only: rapid root replacement can crash Flutter 3.50 native AX traversal.
    binding.platformDispatcher.semanticsEnabledTestValue = false;
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(800, 600));
    await windowManager.setOpacity(1);
    await windowManager.show();
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  testWidgets(
    'capture Cloud states in the real App shell',
    (tester) async {
      final output = Directory(
        const String.fromEnvironment('SKILLDECK_CAPTURE_DIRECTORY'),
      );
      await output.create(recursive: true);
      const captureItem = String.fromEnvironment('SKILLDECK_CAPTURE_ITEM');
      final manifest = File('${output.path}/capture-inventory.json');
      final inventory = <Map<String, Object?>>[
        if (captureItem.isNotEmpty && await manifest.exists())
          for (final row in jsonDecode(await manifest.readAsString()) as List)
            if ((row as Map)['item'] != captureItem)
              Map<String, Object?>.from(row),
      ];
      final scenarios = <(String, String)>[
        for (final state in [
          'signed-in',
          'checking-session',
          'session-read-failed',
          'offline',
          'signing-out',
          'sign-out-failed',
          'metadata-unavailable',
          'exclusions-empty',
          'exclusions-two',
        ])
          ('settings', state),
        for (final state in [
          'device-only',
          'synced',
          'waiting',
          'applying',
          'attention',
          'metadata-waiting',
          'note-too-large',
        ])
          ('skill-row', state),
        for (final state in [
          'device-only',
          'synced',
          'waiting',
          'applying',
          ...cloud.AttentionReason.values.map((r) => r.name),
          'note-too-large',
        ])
          ('skill-detail', state),
        ('notices', 'storage-limit'),
        ('notices', 'stopped'),
        ('new-device', 'three-skills'),
        ('new-device', 'loading-agents'),
        ('new-device', 'no-agents'),
        ('attention-actions', 'incomingDraft'),
        ('tag-limit', 'name'),
        ('tag-limit', 'vocabulary'),
        for (final name in [
          'removedWithDraft--remove',
          'sourceReplacedWithLocalChanges--acceptReplacement',
          'slotOccupied--replaceOccupied',
          'missingAfterReset--keepDeviceOnly',
          'tooLarge--stop',
        ])
          ('confirmation', name),
        ('conflict-review', 'syncMergeConflict'),
        ('incoming-review', 'incomingDraft'),
        ('incoming-review', 'incomingDraft--empty'),
        ('incoming-review', 'incomingDraft--binary'),
        ('note-review', 'two-texts'),
        ('note-review', 'empty-note'),
        ('note-review', 'three-texts'),
      ];
      for (final locale in ['en', 'zh']) {
        for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
          for (final (item, state) in scenarios.where(
            (entry) => captureItem.isEmpty || entry.$1 == captureItem,
          )) {
            debugPrint('CLOUD_CAPTURE: $item/$state $locale ${mode.name}');
            final service = FakeCloudService();
            final workspace = FakeSyncWorkspace();
            final local = workspace.seed(
              source: cloud.PortableSource.git(
                locator: 'https://example.test/team/skills',
              ),
              name: 'Review',
            );
            final scratch = await Directory.systemTemp.createTemp(
              'cloud-ui-capture-',
            );
            final syncStore = cloud.InMemorySyncStateStore();
            final cloudSessions = cloud.InMemoryCloudSessionStore();
            await cloudSessions.write(
              cloud.StoredCloudSession(
                origin: _origin,
                token: service.session(_account),
              ),
            );
            final runtime = CloudSyncRuntime(
              accountId: _account,
              reconciler: cloud.Reconciler(
                api: cloud.CloudApi(
                  client: service.client,
                  origin: _origin,
                  sessions: cloudSessions,
                ),
                workspace: workspace,
                state: syncStore,
                scratchDirectory: scratch.path,
              ),
              diagnostics: AppDiagnostics.disabled(),
              onSignInRequired: () {},
            );
            final store = _SessionStore()
              ..failDelete = state == 'sign-out-failed'
              ..failRead = state == 'session-read-failed';
            if (state == 'checking-session') {
              store.reading = Completer<cloud.StoredCloudSession?>();
            }
            final targetLoading =
                Completer<
                  WorkspaceCompletion<List<WorkspaceActivationTarget>>
                >();
            if (state == 'signing-out') store.deleting = Completer<void>();
            final client = MockClient((request) async {
              if (state == 'offline') throw http.ClientException('offline');
              return http.Response(
                jsonEncode(
                  request.url.path.endsWith('get-session')
                      ? {
                          'user': {
                            'id': _account,
                            'email': 'review@example.test',
                          },
                          'session': {'expiresAt': '2027-12-01T00:00:00Z'},
                        }
                      : {'success': true},
                ),
                200,
              );
            });
            final skills = ['Review', 'Release', 'Research']
                .map(_skill)
                .map(
                  (skill) =>
                      item == 'conflict-review' && skill.id.value == 'skill-0'
                      ? skill.copyWith(
                          draft: WorkspaceDraftSummary(
                            purpose:
                                WorkspaceDraftPurpose.updateCandidateResolution,
                            path: scratch.path,
                            isDirty: true,
                            updatedAt: DateTime.utc(2026, 11, 28),
                          ),
                          updateCandidate: WorkspaceUpdateCandidateSummary(
                            status: WorkspaceUpdateCandidateStatus.conflicted,
                            conflictPaths: ['SKILL.md'],
                            createdAt: DateTime.utc(2026, 11, 28),
                          ),
                        )
                      : skill,
                )
                .toList();
            final repository = FakeSkillsWorkspaceRepository(
              snapshot: SkillsWorkspaceSnapshot(
                revision: 1,
                projectRoots: [],
                skills: skills,
                personalTags: item == 'tag-limit'
                    ? [
                        WorkspacePersonalTag(
                          id: 'review-tag',
                          name: 'Review',
                          createdAt: DateTime.utc(2026),
                          updatedAt: DateTime.utc(2026),
                        ),
                      ]
                    : const [],
              ),
              globalTargets: state == 'no-agents'
                  ? const []
                  : const [
                      WorkspaceActivationTarget(
                        agentId: 'claude-code',
                        displayName: 'Claude Code',
                        detected: true,
                        location: '/synthetic/agent',
                        scope: WorkspaceScope.global,
                      ),
                    ],
            );
            final reason = cloud.AttentionReason.values
                .where((r) => r.name == state.split('--').first)
                .firstOrNull;
            final note = cloud.CloudNote(
              state == 'empty-note' ? null : 'Keep changes small.',
              3,
              conflict: cloud.CloudNoteConflict(
                cloud.CloudNoteCandidate(
                  state == 'empty-note' ? null : 'Keep changes small.',
                  null,
                ),
                const cloud.CloudNoteCandidate('Add a focused test.', null),
              ),
            );
            var lineage = 'lineage-review';
            if (item == 'incoming-review') {
              final remoteWorkspace = FakeSyncWorkspace();
              final seed = remoteWorkspace.seed(
                source: local.source,
                name: 'Review',
              );
              remoteWorkspace.publish(seed.id, {
                'SKILL.md': '---\nname: Review\n---\n# Improved guidance',
              });
              final remoteState = cloud.InMemorySyncStateStore();
              final sender = cloud.Reconciler(
                api: cloud.CloudApi(
                  client: service.client,
                  origin: _origin,
                  sessions: cloudSessions,
                ),
                workspace: remoteWorkspace,
                state: remoteState,
                scratchDirectory: scratch.path,
              );
              await sender.startSyncing(seed.id);
              lineage = (await remoteState.links()).single.lineageId!;
              await syncStore.put(
                cloud.SyncLink(managedSkillId: 'skill-0', lineageId: lineage),
              );
              repository.revisionPackDiffTask =
                  ({
                    required skillId,
                    required expectedEffective,
                    required incomingEffective,
                    required incomingUpstream,
                    required packPath,
                  }) => completedWorkspaceTask(
                    kind: WorkspaceOperationKind.inspectRevisionPackDiff,
                    value: WorkspaceRevisionPackDiff(
                      skillId: skillId,
                      from: expectedEffective,
                      to: incomingEffective,
                      files: state.endsWith('--empty')
                          ? const []
                          : [
                              (
                                path: state.endsWith('--binary')
                                    ? 'image.png'
                                    : 'SKILL.md',
                                previousPath: null,
                                status: WorkspaceDiffFileStatus.modified,
                                isBinary: state.endsWith('--binary'),
                                additions: 1,
                                deletions: 1,
                                hunks: [
                                  (
                                    header: '@@ -1 +1 @@',
                                    lines: [
                                      (
                                        kind: WorkspaceDiffLineKind.deletion,
                                        text: 'Review the change.',
                                        oldLineNumber: 1,
                                        newLineNumber: null,
                                      ),
                                      (
                                        kind: WorkspaceDiffLineKind.addition,
                                        text: 'Review the change and run the focused tests.',
                                        oldLineNumber: null,
                                        newLineNumber: 1,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                    ),
                  );
            }
            final actionRequest = Completer<void>();
            if (item == 'attention-actions') {
              await syncStore.put(
                const cloud.SyncLink(
                  managedSkillId: 'skill-0',
                  lineageId: 'lineage-review',
                ),
              );
              service.beforeRequest = (_) => actionRequest.future;
            }
            final snapshot = CloudSyncState(
              accountId: _account,
              bootstrapCompleted: true,
              links: state == 'device-only'
                  ? const {}
                  : {
                      'skill-0': cloud.SyncLink(
                        managedSkillId: 'skill-0',
                        lineageId: lineage,
                      ),
                    },
              applying: state == 'applying' ? const {'skill-0'} : const {},
              outcomes: {
                if (state == 'waiting')
                  'skill-0': const cloud.WaitingToUpload(),
                if (reason != null || state == 'attention')
                  'skill-0': cloud.SyncNeedsAttention(
                    reason ?? cloud.AttentionReason.incomingDraft,
                  ),
                if (reason == cloud.AttentionReason.slotOccupied)
                  'other-lineage': const cloud.SyncNeedsAttention(
                    cloud.AttentionReason.slotOccupied,
                    occupant: 'skill-0',
                  ),
              },
              metadataWaitingSkillIds: state == 'metadata-waiting'
                  ? const {'skill-0'}
                  : const {},
              metadataUnavailable: state == 'metadata-unavailable',
              vocabularyAttention: item == 'tag-limit'
                  ? {
                      'review-tag': state == 'name'
                          ? cloud.MetadataLimit.name
                          : cloud.MetadataLimit.vocabulary,
                    }
                  : const {},
              exclusions: state == 'exclusions-two'
                  ? const {'lineage-first', 'lineage-second'}
                  : const {},
              metadataAttention: {
                if (state == 'note-too-large')
                  'skill-0': const cloud.SyncMetadataAttention(
                    cloud.MetadataAttentionReason.noteTooLarge,
                  ),
                if (item == 'note-review')
                  'skill-0': cloud.SyncMetadataAttention(
                    cloud.MetadataAttentionReason.noteConflict,
                    note: note,
                    localNote: state == 'three-texts'
                        ? 'Also verify the release.'
                        : null,
                    hasUnsubmittedLocalNote: state == 'three-texts',
                  ),
              },
              installedSkillIds: item == 'new-device'
                  ? const {'skill-0', 'Release', 'Research'}
                  : const {},
              notice: item == 'notices'
                  ? (state == 'stopped'
                        ? CloudSyncNotice.stopped
                        : CloudSyncNotice.storageLimit)
                  : null,
            );
            final changes = StreamController<CloudSyncState>()..add(snapshot);
            final boundaryKey = GlobalKey();
            final browser = FakeSkillBrowserRepository(
              catalog: InstalledSkillCatalog(
                revision: 1,
                skills: [
                  for (final skill in skills)
                    InstalledSkill(
                      id: skill.id,
                      slotKey: skill.slotKey,
                      displayName: skill.displayName,
                      declaredName: skill.declaredName,
                      description: skill.description,
                      contentHash: skill.currentRevision.contentHash,
                      currentRevision: skill.currentRevision,
                      activationCount: item == 'skill-row' ? 1 : 0,
                      activations: item == 'skill-row'
                          ? globalActivation()
                          : const [],
                      source: skill.source,
                    ),
                ],
              ),
              documents: {
                for (final skill in skills)
                  skill.slotKey:
                      '# ${skill.displayName}\n\nReview changes carefully.',
              },
            );
            final route = item == 'settings'
                ? '/settings?section=cloud'
                : (item == 'skill-detail' ||
                      item == 'note-review' ||
                      item == 'confirmation' ||
                      item == 'conflict-review' ||
                      item == 'incoming-review' ||
                      item == 'attention-actions')
                ? '/installed/skill-0?tab=settings'
                : '/installed';
            await tester.pumpWidget(
              KeyedSubtree(
                key: UniqueKey(),
                child: RepaintBoundary(
                  key: boundaryKey,
                  child: skillsManagerTestApp(
                    browserRepository: browser,
                    workspaceRepository: repository,
                    catalogAuthority: item == 'new-device'
                        ? SkillBrowserCatalogAuthority.workspaceSnapshot
                        : SkillBrowserCatalogAuthority.repository,
                    initialLocation: route,
                    locale: Locale(locale),
                    overrides: [
                      if (state == 'loading-agents')
                        activationTargetsProvider.overrideWith(
                          (ref, scope) => targetLoading.future,
                        ),
                      initialAppearanceModeProvider.overrideWithValue(mode),
                      cloudIsMacOSProvider.overrideWithValue(true),
                      cloudOriginDefineProvider.overrideWithValue(
                        _origin.toString(),
                      ),
                      cloudSessionStoreProvider.overrideWithValue(store),
                      cloudHttpClientProvider.overrideWithValue(client),
                      cloudSyncRuntimeProvider.overrideWithValue(runtime),
                      cloudSyncStateProvider.overrideWith(
                        (ref) => changes.stream,
                      ),
                      claimCloudActivationOfferProvider.overrideWithValue(
                        (_) async => true,
                      ),
                      deviceAgentMembersProvider.overrideWithValue(
                        const AsyncData({'claude-code'}),
                      ),
                    ],
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            if (item == 'skill-row') expect(find.text('Review'), findsWidgets);
            if (state == 'signing-out' || state == 'sign-out-failed') {
              await tester.tap(find.text(locale == 'en' ? 'Sign out' : '退出登录'));
              await tester.pump(const Duration(milliseconds: 500));
            }
            if (item == 'note-review') {
              await tester.ensureVisible(
                find.byKey(const Key('cloud-note-review')),
              );
              await tester.tap(find.byKey(const Key('cloud-note-review')));
              await tester.pumpAndSettle();
            }
            if (item == 'confirmation' ||
                item == 'conflict-review' ||
                item == 'incoming-review') {
              final action = item == 'confirmation'
                  ? state.split('--').last
                  : item == 'incoming-review'
                  ? 'reviewIncoming'
                  : 'reviewConflict';
              final button = find.byKey(Key('cloud-attention-$action'));
              await tester.ensureVisible(button);
              await tester.tap(button);
              await tester.pumpAndSettle();
            }
            if (item == 'tag-limit') {
              await tester.tap(find.byKey(const Key('skill-sort-button')));
              await tester.pumpAndSettle();
              final tag = find.byKey(const ValueKey('tag-filter-review-tag'));
              await tester.ensureVisible(tag);
              final mouse = await tester.createGesture(
                kind: PointerDeviceKind.mouse,
                buttons: kSecondaryMouseButton,
              );
              await mouse.down(tester.getCenter(tag));
              await mouse.up();
              await tester.pumpAndSettle();
            }
            if (item == 'attention-actions') {
              final review = find.byKey(
                const Key('cloud-attention-reviewIncoming'),
              );
              await tester.ensureVisible(review);
              await tester.tap(review);
              await tester.pump();
            }
            Future<void> capture(String name) async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 1);
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              image.dispose();
              final file = File(
                '${output.path}/$item/$name-$locale-${mode.name}.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              final text = tester
                  .widgetList<Text>(find.byType(Text))
                  .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
                  .where((s) => s.isNotEmpty)
                  .toSet()
                  .toList();
              text.addAll(
                tester
                    .widgetList<Icon>(find.byType(Icon))
                    .map((icon) => icon.semanticLabel)
                    .whereType<String>(),
              );
              inventory.add({
                'item': item,
                'state': name,
                'locale': locale,
                'appearance': mode.name,
                'text': text,
                'visibleActions': [
                  for (final button in tester.widgetList<AppButton>(
                    find.byType(AppButton).hitTestable(),
                  ))
                    {
                      'label': button.label,
                      'enabled': button.onPressed != null && !button.loading,
                      'style': button.style.name,
                    },
                ],
                'screenshot': '$item/$name-$locale-${mode.name}.png',
              });
            }

            await capture(state);
            if (item == 'attention-actions') {
              actionRequest.complete();
              await tester.pumpAndSettle();
              await capture('failed');
            }

            if (item == 'note-review' && state != 'empty-note') {
              final combine = find.text(
                locale == 'en' ? 'Combine versions' : '合并版本',
              );
              await tester.ensureVisible(combine);
              await tester.pumpAndSettle();
              await tester.tap(combine);
              await tester.pumpAndSettle();
              await capture('$state-combining');
              final editor = find.byKey(
                const Key('cloud-note-resolution-text'),
              );
              await tester.ensureVisible(editor);
              await tester.enterText(editor, 'x' * 4097);
              await tester.pumpAndSettle();
              await capture('$state-too-large');
              await tester.enterText(editor, 'Reviewed note');
              await tester.pumpAndSettle();
              await tester.tap(find.byKey(const Key('cloud-note-resolve')));
              await tester.pumpAndSettle();
              await capture('$state-save-failed');
              changes.add(
                CloudSyncState(
                  accountId: _account,
                  metadataAttention: {
                    'skill-0': cloud.SyncMetadataAttention(
                      cloud.MetadataAttentionReason.noteConflict,
                      note: cloud.CloudNote('Updated on another Mac.', 4),
                    ),
                  },
                ),
              );
              await tester.pumpAndSettle();
              await capture('$state-versions-changed');
              changes.add(const CloudSyncState(accountId: _account));
              await tester.pumpAndSettle();
              await capture('$state-conflict-gone');
            }
            if (item == 'new-device' && state == 'three-skills') {
              final selection = find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.label == 'Review Claude Code',
              );
              await tester.ensureVisible(selection);
              await tester.tap(selection);
              await tester.pumpAndSettle();
              await capture('some-selected');
              await tester.tap(
                find.byKey(const Key('cloud-new-device-activate')),
              );
              await tester.pumpAndSettle();
              expect(repository.activations.single.slotKeys, {'Review'});
              // The existing fake records activation requests but does not project them.
              repository.publish(
                SkillsWorkspaceSnapshot(
                  revision: 2,
                  projectRoots: [],
                  skills: [
                    for (final skill in skills)
                      if (skill.id.value == 'skill-0')
                        WorkspaceSkill(
                          id: skill.id,
                          slotKey: skill.slotKey,
                          declaredName: skill.declaredName,
                          displayName: skill.displayName,
                          description: skill.description,
                          source: skill.source,
                          currentRevision: skill.currentRevision,
                          activations: globalActivation(
                            location: '/synthetic/agent',
                            agentIds: const ['claude-code'],
                          ),
                        )
                      else
                        skill,
                  ],
                ),
              );
              await tester.pumpAndSettle();
              expect(find.text('Review'), findsWidgets);
              await capture('after-activating');
            }
            if (item == 'conflict-review') {
              final l10n = AppLocalizations.of(
                tester.element(find.byType(Text).first),
              );
              await tester.tap(find.text(l10n.cloudConflictKeepThis));
              await tester.pumpAndSettle();
              final review = find.byKey(
                const Key('cloud-attention-reviewConflict'),
              );
              await tester.ensureVisible(review);
              await tester.tap(review);
              await tester.pumpAndSettle();
              await capture('after-choosing');
            }
            if (store.reading case final pending?) {
              pending.complete(null);
              await tester.pumpAndSettle();
            }
            if (state == 'loading-agents') {
              targetLoading.complete(WorkspaceCompleted(value: const []));
              await tester.pumpAndSettle();
            }
            if (store.deleting case final pending?) {
              pending.complete();
              await tester.pumpAndSettle();
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            // Some Settings states never subscribe; closing an unlistened
            // single-subscription stream must not block the next capture.
            unawaited(changes.close());
            await runtime.close();
            await scratch.delete(recursive: true);
            await repository.close();
            service.client.close();
            client.close();
          }
        }
      }
      await File('${output.path}/capture-inventory.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert(inventory));
    },
    semanticsEnabled: false,
    skip: !const bool.fromEnvironment('SKILLDECK_CLOUD_UI_CAPTURE'),
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
