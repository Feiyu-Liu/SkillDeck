// Opt-in native presentation acceptance with synthetic Skills and isolated
// preference keys. Run once with phase=seed, then phase=restore to verify a
// separate native process restores the modes but opens all groups.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_grouping.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_sort.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/fake_skill_browser_repository.dart';
import '../test/support/skills_manager_test_app.dart';

const _phase = String.fromEnvironment('SKILLDECK_GROUPING_ACCEPTANCE');
const _screenshots = String.fromEnvironment('SKILLDECK_GROUPING_SCREENSHOTS');
const _prefix = 'skilldeck.repository_grouping.acceptance.20261112.';

final class _IsolatedPreferences extends SharedPreferencesAsync {
  @override
  Future<String?> getString(String key) => super.getString('$_prefix$key');
  @override
  Future<void> setString(String key, String value) =>
      super.setString('$_prefix$key', value);
  Future<void> cleanup() async {
    await super.remove('$_prefix${SkillListLayoutStore.preferenceKey}');
    for (final page in SkillListPage.values) {
      await super.remove('$_prefix${SkillListGroupingStore.keyFor(page)}');
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native grouping, search, folds and process preference restore',
    (tester) async {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1360, 900));
      await windowManager.show();
      final preferences = _IsolatedPreferences();
      if (_phase == 'seed') await preferences.cleanup();
      final store = SkillListGroupingStore(preferences: preferences);
      final initial = await store.read();
      final captureKey = GlobalKey();
      final repository = FakeSkillBrowserRepository(
        catalog: InstalledSkillCatalog(
          revision: 1,
          skills: [
            for (final (id, repo) in [
              ('Alpha', 'acme/tools'),
              ('Beta', 'acme/tools'),
              ('Gamma', 'other/tools'),
            ])
              InstalledSkill(
                id: WorkspaceSkillId(id),
                slotKey: id,
                displayName: id,
                description: '$id synthetic acceptance Skill',
                contentHash: 'a' * 64,
                activationCount: 1,
                activations: globalActivation(),
                isFavorite: true,
                source: SkillSourceProvenance(
                  kind: WorkspaceSourceKind.git,
                  locator: 'https://github.com/$repo',
                ),
              ),
          ],
        ),
      );
      Future<void> settle() async {
        // Native clocks keep running during screenshot encoding. Finish menu
        // morphs before locating and tapping their final target geometry.
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        if (_screenshots.isEmpty) return;
        final boundary =
            captureKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await Directory(_screenshots).create(recursive: true);
        await File('$_screenshots/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: captureKey,
          child: skillsManagerTestApp(
            browserRepository: repository,
            initialSkillListLayout: SkillListLayout.cards,
            overrides: [
              initialSkillListGroupingProvider.overrideWithValue(initial),
              initialAppearanceModeProvider.overrideWithValue(
                _phase == 'restore'
                    ? AppearanceMode.dark
                    : AppearanceMode.light,
              ),
              skillListGroupingStoreProvider.overrideWithValue(store),
              skillListLayoutStoreProvider.overrideWithValue(
                SkillListLayoutStore(preferences: preferences),
              ),
            ],
          ),
        ),
      );
      await settle();
      final card = find.byKey(const Key('skill-Alpha'));
      final group = find.byKey(
        const Key('repository-group-git:remote:github.com/acme/tools'),
      );
      final container = ProviderScope.containerOf(tester.element(card));
      if (_phase == 'seed') {
        expect(group, findsNothing);
        await tester.tap(find.byKey(const Key('skill-sort-button')));
        await settle();
        await capture('native-grouping-menu');
        await tester.tap(
          find.byKey(const Key('skill-grouping-option-repository')),
        );
        await settle();
        expect(group, findsOneWidget);
        await capture('native-installed-cards');
        await tester.tap(group);
        await settle();
        expect(card, findsNothing);
        await tester.tap(find.byKey(const Key('installed-search-control')));
        await settle();
        await tester.enterText(
          find.byKey(const Key('installed-search-field')),
          'Alpha',
        );
        await settle();
        expect(card, findsOneWidget);
        await capture('native-search-expanded');
        await tester.tap(group);
        await settle();
        expect(card, findsNothing);
        await tester.tap(find.byKey(const Key('installed-search-control')));
        await settle();
        await tester.enterText(
          find.byKey(const Key('installed-search-field')),
          '',
        );
        await settle();
        expect(card, findsNothing);
        await tester.tap(group);
        await settle();
        // Both pages use the existing shared layout preference; no user layout
        // preference is written by this fixture.
        container
            .read(skillListLayoutProvider.notifier)
            .select(SkillListLayout.list);
        await settle();
        await capture('native-installed-list');
        await tester.tap(find.byKey(const Key('nav-item-favorites')));
        await settle();
        expect(group, findsNothing);
        await tester.tap(find.byKey(const Key('skill-sort-button')));
        await settle();
        await tester.tap(
          find.byKey(const Key('skill-grouping-option-repository')),
        );
        await settle();
        expect(group, findsOneWidget);
        await capture('native-favorites-list');
        // Leave a folded group in session; the next process must open it.
        await tester.tap(group);
        await settle();
        expect(card, findsNothing);
        final saved = await store.read();
        expect(saved.values, everyElement(SkillListGroupingMode.repository));
      } else {
        expect(initial.values, everyElement(SkillListGroupingMode.repository));
        expect(group, findsOneWidget);
        expect(card, findsOneWidget);
        expect(container.read(skillListGroupFoldsProvider), isEmpty);
        await capture('native-restored-open-dark');
        await tester.tap(find.byKey(const Key('nav-item-favorites')));
        await settle();
        expect(group, findsOneWidget);
        expect(card, findsOneWidget);
        await windowManager.setSize(const Size(450, 500));
        await settle();
        await tester.tap(find.byKey(const Key('skill-sort-button')));
        await settle();
        expect(
          find.byKey(const Key('skill-filter-panel-scroll')),
          findsOneWidget,
        );
        await tester.ensureVisible(
          find.byKey(const Key('skill-grouping-option-repository')),
        );
        await settle();
        await capture('native-compact-menu-dark');
        await tester.tapAt(const Offset(4, 4));
        await settle();
        await capture('native-compact-groups-dark');
        await preferences.cleanup();
      }
      expect(tester.takeException(), isNull);
      binding.reportData = {
        'phase': _phase,
        'isolatedPreferences': true,
        'syntheticWorkspace': true,
      };
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isMacOS || !const {'seed', 'restore'}.contains(_phase),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
