import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart' as cloud;
import 'package:skills_cloud/testing.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import '../../../support/fake_skill_browser_repository.dart';
import '../../../support/fake_skills_workspace_repository.dart';
import '../../../support/skills_manager_test_app.dart';

void main() {
  for (final activate in [true, false]) {
    testWidgets(
      'new Device offer ${activate ? 'activates exactly the selected pair' : 'dismisses without activating'}',
      (tester) async {
        final service = FakeCloudService();
        final runtime = CloudSyncRuntime(
          accountId: 'owner',
          reconciler: cloud.Reconciler(
            api: cloud.CloudApi(
              client: service.client,
              origin: cloud.CloudServiceOrigin.parse(
                'https://cloud.example.test',
              ),
              sessions: cloud.InMemoryCloudSessionStore(),
            ),
            workspace: FakeSyncWorkspace(),
            state: cloud.InMemorySyncStateStore(),
            scratchDirectory: '',
          ),
          diagnostics: AppDiagnostics.disabled(),
          onSignInRequired: () {},
        );
        addTearDown(service.client.close);
        addTearDown(() => unawaited(runtime.close()));
        final repository = FakeSkillsWorkspaceRepository(
          snapshot: SkillsWorkspaceSnapshot(
            revision: 1,
            projectRoots: [],
            skills: [_skill('First'), _skill('Second')],
          ),
          globalTargets: const [
            WorkspaceActivationTarget(
              agentId: 'alpha',
              displayName: 'Alpha',
              detected: true,
              location: '/alpha',
              scope: WorkspaceScope.global,
            ),
            WorkspaceActivationTarget(
              agentId: 'beta',
              displayName: 'Beta',
              detected: true,
              location: '/beta',
              scope: WorkspaceScope.global,
            ),
          ],
        );
        final offered = <String>{};
        Widget app(Key key) => KeyedSubtree(
          key: key,
          child: skillsManagerTestApp(
            browserRepository: FakeSkillBrowserRepository(),
            workspaceRepository: repository,
            overrides: [
              cloudSyncRuntimeProvider.overrideWithValue(runtime),
              cloudSyncStateProvider.overrideWith(
                (ref) => Stream.value(
                  const CloudSyncState(
                    accountId: 'owner',
                    bootstrapCompleted: true,
                    installedSkillIds: {'First', 'Second'},
                  ),
                ),
              ),
              claimCloudActivationOfferProvider.overrideWithValue(
                (accountId) async => offered.add(accountId),
              ),
              deviceAgentMembersProvider.overrideWithValue(
                const AsyncData({'alpha', 'beta'}),
              ),
            ],
          ),
        );
        await tester.pumpWidget(app(const Key('first-session')));
        await tester.pumpAndSettle();
        expect(find.text('Your synced Skills are ready'), findsOneWidget);
        expect(repository.activations, isEmpty);
        final activateButton = find.byKey(
          const Key('cloud-new-device-activate'),
        );
        if (activate) {
          final selection = find.bySemanticsLabel('First Beta');
          await tester.ensureVisible(selection);
          await tester.tap(selection);
          await tester.pumpAndSettle();
          await tester.tap(activateButton);
        } else {
          await tester.tap(find.byKey(const Key('cloud-new-device-later')));
        }
        await tester.pumpAndSettle();
        expect(find.text('Your synced Skills are ready'), findsNothing);
        if (activate) {
          expect(repository.activations.single.slotKeys, {'First'});
          expect(repository.activations.single.agentIds, {'beta'});
        } else {
          expect(repository.activations, isEmpty);
        }
        expect(offered, {'owner'});
      },
    );
  }
}

WorkspaceSkill _skill(String name) => WorkspaceSkill(
  id: WorkspaceSkillId(name),
  slotKey: name,
  displayName: name,
  declaredName: name,
  description: '',
  source: const SkillSourceProvenance(
    kind: WorkspaceSourceKind.local,
    locator: '/fixture',
  ),
  currentRevision: SkillRevision(
    contentHash: 'sha',
    fileCount: 1,
    byteSize: 100,
    acquiredAt: DateTime.utc(2026),
  ),
  activations: [],
);
