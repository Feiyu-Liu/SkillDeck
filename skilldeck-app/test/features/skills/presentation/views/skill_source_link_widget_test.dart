import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/data/services/skill_source_link_opener.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_source_link.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  Future<FakeSkillBrowserRepository> pumpSource(
    WidgetTester tester,
    _RecordingOpener opener,
    String locator,
  ) async {
    final skill = InstalledSkill(
      id: WorkspaceSkillId('alpha'),
      description: 'Alpha',
      contentHash: 'hash-alpha',
      activationCount: 0,
      slotKey: 'alpha',
      displayName: 'Alpha',
      source: SkillSourceProvenance(
        kind: WorkspaceSourceKind.git,
        locator: locator,
      ),
    );
    final repository = FakeSkillBrowserRepository(
      catalog: InstalledSkillCatalog(revision: 1, skills: [skill]),
      documents: const {'alpha': '# Alpha'},
    );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: repository,
        initialLocation: '/installed/alpha/activate',
        overrides: [skillSourceLinkOpenerProvider.overrideWithValue(opener)],
      ),
    );
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets(
    'opens the real source from settings and reports an open failure',
    (tester) async {
      final opener = _RecordingOpener()..succeeds = false;
      await pumpSource(
        tester,
        opener,
        'https://github.com/owner/repo?tab=readme-ov-file#readme',
      );
      await tester.tap(find.byKey(const Key('skill-source-link')));
      await tester.pumpAndSettle();
      expect(
        opener.opened.single.uri.toString(),
        'https://github.com/owner/repo?tab=readme-ov-file#readme',
      );
      expect(find.byKey(const Key('skill-source-link-failed')), findsOneWidget);
    },
  );

  testWidgets('source link supports keyboard activation', (tester) async {
    final opener = _RecordingOpener();
    await pumpSource(tester, opener, 'https://example.com/repo');
    final link = find.byKey(const Key('skill-source-link'));
    final label = find.descendant(of: link, matching: find.byType(Text)).first;
    Focus.of(tester.element(label)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opener.opened.single.uri.toString(), 'https://example.com/repo');
  });

  testWidgets(
    'replacement provenance updates the link and clears old failures',
    (tester) async {
      final opener = _RecordingOpener()..succeeds = false;
      final repository = await pumpSource(
        tester,
        opener,
        'https://example.com/old',
      );
      await tester.tap(find.byKey(const Key('skill-source-link')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-source-link-failed')), findsOneWidget);

      repository.publish(
        InstalledSkillCatalog(
          revision: 2,
          skills: [
            InstalledSkill(
              id: WorkspaceSkillId('alpha'),
              slotKey: 'alpha',
              displayName: 'Alpha',
              description: 'Alpha',
              contentHash: 'hash-alpha',
              activationCount: 0,
              source: const SkillSourceProvenance(
                kind: WorkspaceSourceKind.git,
                locator: 'https://example.com/new',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('skill-source-link-failed')), findsNothing);
      opener.succeeds = true;
      await tester.tap(find.byKey(const Key('skill-source-link')));
      await tester.pumpAndSettle();
      expect(opener.opened.last.uri.toString(), 'https://example.com/new');
    },
  );

  testWidgets('credential-bearing sources stay non-clickable and redacted', (
    tester,
  ) async {
    final opener = _RecordingOpener();
    await pumpSource(
      tester,
      opener,
      'https://user:password@example.com/repo?token=secret',
    );
    expect(find.byKey(const Key('skill-source-link')), findsNothing);
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .join('\n');
    expect(texts, isNot(contains('password')));
    expect(texts, isNot(contains('secret')));
    expect(opener.opened, isEmpty);
  });
}

class _RecordingOpener extends SkillSourceLinkOpener {
  final List<SkillSourceLink> opened = [];
  bool succeeds = true;

  @override
  Future<bool> open(SkillSourceLink link) async {
    opened.add(link);
    return succeeds;
  }
}
