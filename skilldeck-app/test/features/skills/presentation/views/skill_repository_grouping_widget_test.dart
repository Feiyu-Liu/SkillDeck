import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:skills_manager/features/library/personal_tag_providers.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_grouping.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_sort.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

InstalledSkill _skill(String id, String repo, {bool favorite = true}) =>
    InstalledSkill(
      id: WorkspaceSkillId(id),
      slotKey: id,
      displayName: id,
      description: '$id description',
      contentHash: 'a' * 64,
      activationCount: 1,
      source: SkillSourceProvenance(
        kind: WorkspaceSourceKind.git,
        locator: 'https://github.com/$repo',
      ),
      activations: globalActivation(),
      isFavorite: favorite,
      personalTagIds: id == 'Alpha' ? ['docs'] : [],
    );
Finder _group(String repo) =>
    find.byKey(ValueKey('repository-group-git:remote:github.com/$repo'));
Finder _member(String name) => find.byKey(Key('skill-$name'));

void main() {
  for (final page in SkillListPage.values) {
    for (final layout in SkillListLayout.values) {
      testWidgets(
        '${page.name} ${layout.name}: groups filtered members and folds with keyboard',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(1360, 900));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final repository = FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(
              revision: 1,
              skills: [
                _skill('Alpha', 'a/repo'),
                _skill('Beta', 'a/repo'),
                _skill('Gamma', 'b/repo', favorite: false),
              ],
            ),
          );
          await tester.pumpWidget(
            skillsManagerTestApp(
              browserRepository: repository,
              initialSkillListLayout: layout,
              initialLocation: '/${page.name}',
              overrides: [
                initialSkillListGroupingProvider.overrideWithValue({
                  page: SkillListGroupingMode.repository,
                }),
              ],
            ),
          );
          await tester.pumpAndSettle();
          expect(_group('a/repo'), findsOneWidget);
          expect(
            _group('b/repo'),
            page == SkillListPage.installed ? findsOneWidget : findsNothing,
          );
          expect(
            find.descendant(
              of: _group('a/repo'),
              matching: find.text('2 Skills'),
            ),
            findsOneWidget,
          );
          await tester.tap(_group('a/repo'));
          await tester.pumpAndSettle();
          expect(_member('Alpha'), findsNothing);
          Focus.of(
            tester.element(
              find.descendant(
                of: _group('a/repo'),
                matching: find.text('a/repo'),
              ),
            ),
          ).requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(_member('Alpha'), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(_member('Alpha'), findsNothing);
          // A tag filter retains the browse fold and updates the visible count.
          final container = ProviderScope.containerOf(
            tester.element(_group('a/repo')),
          );
          container.read(personalTagFilterProvider.notifier).toggle('docs');
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: _group('a/repo'),
              matching: find.text('1 Skill'),
            ),
            findsOneWidget,
          );
          expect(_group('b/repo'), findsNothing);
          container.read(personalTagFilterProvider.notifier).clear();
          await tester.pumpAndSettle();
          expect(_member('Alpha'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets(
    'search temporarily expands, permits manual folding and restores browse folds',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(
              revision: 1,
              skills: [_skill('Alpha', 'a/repo'), _skill('Beta', 'a/repo')],
            ),
          ),
          overrides: [
            initialSkillListGroupingProvider.overrideWithValue({
              SkillListPage.installed: SkillListGroupingMode.repository,
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(_group('a/repo'));
      await tester.pumpAndSettle();
      expect(_member('Alpha'), findsNothing);
      await tester.tap(find.byKey(const Key('installed-search-control')));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('installed-search-field'));
      await tester.enterText(field, 'Alpha');
      await tester.pumpAndSettle();
      expect(_member('Alpha'), findsOneWidget);
      expect(
        find.descendant(of: _group('a/repo'), matching: find.text('1 Skill')),
        findsOneWidget,
      );
      await tester.tap(_group('a/repo'));
      await tester.pumpAndSettle();
      expect(_member('Alpha'), findsNothing);
      await tester.tap(find.byKey(const Key('installed-search-control')));
      await tester.pumpAndSettle();
      await tester.enterText(field, 'Beta');
      await tester.pumpAndSettle();
      expect(_member('Beta'), findsOneWidget);
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(_member('Beta'), findsNothing);
      expect(_member('Alpha'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'source-only catalog replacement with identical content regroups immediately',
    (tester) async {
      final repository = FakeSkillBrowserRepository(
        catalog: InstalledSkillCatalog(
          revision: 1,
          skills: [_skill('Alpha', 'a/repo')],
        ),
      );
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: repository,
          overrides: [
            initialSkillListGroupingProvider.overrideWithValue({
              SkillListPage.installed: SkillListGroupingMode.repository,
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(_group('a/repo'), findsOneWidget);
      repository.publish(
        InstalledSkillCatalog(revision: 2, skills: [_skill('Alpha', 'b/repo')]),
      );
      await tester.pumpAndSettle();
      expect(_group('a/repo'), findsNothing);
      expect(_group('b/repo'), findsOneWidget);
    },
  );
  testWidgets(
    'mode selection closes existing menu, resets scroll and keeps page choices independent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(
              revision: 1,
              skills: [
                for (var i = 0; i < 30; i++) _skill('Skill$i', 'a/repo'),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(_member('Skill0')),
      );
      final scrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byKey(const Key('skill-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.byKey(const Key('skill-sort-button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('skill-grouping-option-repository')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('skill-grouping-option-repository')),
        findsNothing,
      );
      expect(scrollable.position.pixels, 0);
      scrollable.position.jumpTo(200);
      await tester.pumpAndSettle();
      container
          .read(skillListGroupingProvider.notifier)
          .select(SkillListPage.installed, SkillListGroupingMode.none);
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
      container
          .read(skillListGroupingProvider.notifier)
          .select(SkillListPage.installed, SkillListGroupingMode.repository);
      await tester.pumpAndSettle();
      expect(
        container.read(skillListGroupingProvider)[SkillListPage.installed],
        SkillListGroupingMode.repository,
      );
      expect(
        container.read(skillListGroupingProvider)[SkillListPage.favorites],
        isNull,
      );
    },
  );
  testWidgets('detail back preserves grouped scroll and session fold state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(
        revision: 1,
        skills: [
          _skill('Alpha', 'a/repo'),
          for (var i = 0; i < 30; i++) _skill('Skill$i', 'b/repo'),
        ],
      ),
      documents: {for (var i = 0; i < 30; i++) 'Skill$i': '# Skill'},
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        overrides: [
          initialSkillListGroupingProvider.overrideWithValue({
            SkillListPage.installed: SkillListGroupingMode.repository,
          }),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(_group('a/repo'));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const Key('skill-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(300);
    await tester.pumpAndSettle();
    final offset = scrollable.position.pixels;
    final card = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith('skill-Skill'),
        )
        .hitTestable()
        .first;
    final router = GoRouter.of(tester.element(card));
    await tester.tap(card);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-list')), findsNothing);
    router.pop();
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, offset);
    expect(_member('Alpha'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
