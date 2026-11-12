// Opt-in native desktop acceptance; all Workspace and Agent paths are generated.
// Seed with packages/skills_workspace/tool/benchmark_startup_fixture.dart, then:
// flutter test --no-pub -d macos --dart-define=SKILLDECK_STARTUP_FIXTURE=<root> \
//   integration_test/startup_fixture_performance_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skills_manager/features/skills/data/repositories/package_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:window_manager/window_manager.dart';

import '../../packages/skills_workspace/tool/benchmark_startup_fixture.dart'
    as fixture;
import '../test/support/skills_manager_test_app.dart';

const _fixturePath = String.fromEnvironment('SKILLDECK_STARTUP_FIXTURE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'generated Workspace reaches visible Installed catalog on a real desktop',
    skip: _fixturePath.isEmpty,
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.show();
      final root = Directory(_fixturePath);
      await fixture.verifyStartupFixtureRoot(root);
      final before = await fixture.captureStartupProjectionManifest(root);
      final runs = <int>[];
      for (var run = 0; run < 6; run++) {
        final backend = fixture.createStartupFixtureRepository(root);
        final workspace = PackageSkillsWorkspaceRepository(backend: backend);
        try {
          final clock = Stopwatch()..start();
          await tester.pumpWidget(
            skillsManagerTestApp(
              browserRepository: WorkspaceSkillBrowserRepository(workspace),
              workspaceRepository: workspace,
              catalogAuthority: SkillBrowserCatalogAuthority.workspaceSnapshot,
            ),
          );
          // The list is virtualized and its default ordering need not put 000
          // in the viewport. Measure the first actual generated row rendered.
          final row = find.byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('skill-startup-skill-');
          });
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (row.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(row, findsWidgets);
          clock.stop();
          runs.add(clock.elapsedMicroseconds);
          final container = ProviderScope.containerOf(
            tester.element(row.first),
          );
          final snapshot = container
              .read(workspaceSnapshotProvider)
              .requireValue;
          expect(snapshot.skills, hasLength(85));
          expect(
            backend.snapshot.managedSkills.expand((skill) => skill.activations),
            hasLength(340),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await workspace.close();
        }
      }
      final after = await fixture.captureStartupProjectionManifest(root);
      expect(
        after,
        before,
        reason:
            'Healthy UI startup must preserve projection bytes and metadata.',
      );
      final warm = runs.skip(1).toList()..sort();
      final report = <String, Object>{
        'boundary': 'pumpWidget to first rendered Installed Skill row; excludes native process bootstrap',
        'skills': 85,
        'copyActivations': 340,
        'firstMountMicros': runs.first,
        'warmMountRunsMicros': runs.skip(1).toList(),
        'warmMountMedianMicros': warm[2],
        'projectionManifest': after,
        'projectionsUnchanged': true,
      };
      binding.reportData = {'startupFixture': report};
      debugPrint('[startup-fixture] ${jsonEncode(report)}');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
