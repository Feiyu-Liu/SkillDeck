import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';

import '../support/fake_skill_browser_repository.dart';
import '../support/skills_manager_test_app.dart';

void main() {
  testWidgets('keeps the Installed detail open across sidebar navigation', (
    tester,
  ) async {
    final skill = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha Skill',
      activations: globalActivation(),
      isFavorite: true,
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
          documents: const {'alpha': '# Alpha'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('skill-alpha')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-detail')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nav-item-favorites')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-detail')), findsNothing);

    await tester.tap(find.byKey(const Key('nav-item-installed')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-detail')), findsOneWidget);
  });

  testWidgets('keeps the Installed list offset after closing a detail', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final skills = [
      for (var index = 0; index < 24; index++)
        testSkill(
          slotKey: 'skill-$index',
          displayName: 'Skill $index',
          activations: globalActivation(),
        ),
    ];
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: skills),
          documents: {for (final skill in skills) skill.slotKey: '# Skill'},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('skill-list'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('skill-skill-12')),
      180,
      scrollable: scrollable,
    );
    final stateBefore = tester.state<ScrollableState>(scrollable);
    final offsetBefore = stateBefore.position.pixels;
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.byKey(const Key('skill-skill-12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-detail-back')));
    await tester.pumpAndSettle();

    final restoredScrollable = find.descendant(
      of: find.byKey(const Key('skill-list')),
      matching: find.byType(Scrollable),
    );
    final stateAfter = tester.state<ScrollableState>(restoredScrollable);
    expect(stateAfter, same(stateBefore));
    expect(stateAfter.position.pixels, offsetBefore);
  });
}
