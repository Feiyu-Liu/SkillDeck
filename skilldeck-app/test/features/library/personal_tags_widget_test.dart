import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:skills_manager/features/library/personal_tag_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/library/presentation/widgets/personal_tag_controls.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';

import '../../support/fake_skill_browser_repository.dart';
import '../../support/fake_skills_workspace_repository.dart';
import '../../support/skills_manager_test_app.dart';

void main() {
  testWidgets(
    '450 by 500 scrolls the whole panel with many tags and keeps editing accessible',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1360, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final base = _workspace().current;
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: base.revision,
          skills: base.skills,
          projectRoots: base.projectRoots,
          personalTags: [
            ...base.personalTags,
            for (var index = 0; index < 20; index++)
              _tag('extra$index', 'Extra $index'),
          ],
        ),
      );
      await tester.pumpWidget(_app(workspace));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(_skill('alpha')),
      );
      // Exercise the breakpoint transition as well as the compact endpoint.
      await tester.binding.setSurfaceSize(const Size(450, 500));
      await tester.pumpAndSettle();
      await _openSortCard(tester, roomy: false);
      final wholeScroll = find.byKey(const Key('skill-filter-panel-scroll'));
      expect(wholeScroll, findsOneWidget);
      final grouping = find.byKey(
        const Key('skill-grouping-option-repository'),
      );
      await tester.ensureVisible(grouping);
      await tester.pumpAndSettle();
      expect(grouping.hitTestable(), findsOneWidget);
      await tester.ensureVisible(_filterTag('writing'));
      await tester.pumpAndSettle();
      await tester.tap(_filterTag('writing'));
      await tester.pumpAndSettle();
      expect(container.read(personalTagFilterProvider), {'writing'});
      await tester.ensureVisible(find.byKey(const Key('tag-filter-clear')));
      await tester.tap(find.byKey(const Key('tag-filter-clear')));
      await tester.pumpAndSettle();
      expect(container.read(personalTagFilterProvider), isEmpty);
      await tester.ensureVisible(find.byKey(const Key('tag-filter-create')));
      await tester.tap(find.byKey(const Key('tag-filter-create')));
      await tester.pumpAndSettle();
      final nameField = find.byKey(const Key('personal-tag-name-field'));
      await tester.ensureVisible(nameField);
      await tester.enterText(nameField, 'Ops');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(workspace.createdPersonalTags.single.name, 'Ops');
      await tester.ensureVisible(_filterTag('docs'));
      await tester.tap(_filterTag('docs'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('personal-tag-editor')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'roomy panel keeps fixed options and scrolls many tags independently',
    (tester) async {
      final base = _workspace().current;
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: base.revision,
          skills: base.skills,
          projectRoots: base.projectRoots,
          personalTags: [
            ...base.personalTags,
            for (var index = 0; index < 20; index++)
              _tag('extra$index', 'Extra $index'),
          ],
        ),
      );
      await tester.pumpWidget(_app(workspace));
      await tester.pumpAndSettle();
      await _openSortCard(tester);
      expect(find.byKey(const Key('skill-filter-panel-scroll')), findsNothing);
      final grouping = find.byKey(
        const Key('skill-grouping-option-repository'),
      );
      final top = tester.getTopLeft(grouping);
      await tester.drag(
        find.byKey(const Key('tag-filter-list')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(grouping), top);
      expect(_filterTag('writing').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('sort card tags filter Skills that carry every selected tag', (
    tester,
  ) async {
    final workspace = _workspace();
    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();
    expect(_triggerChips, findsNothing);

    await _openSortCard(tester);
    expect(_filterTag('writing'), findsOneWidget);
    await tester.tap(_filterTag('writing'));
    await tester.pumpAndSettle();
    expect(_skill('alpha'), findsOneWidget);
    expect(_skill('beta'), findsOneWidget);
    expect(_skill('gamma'), findsNothing);

    // Toggling keeps the card open for the next tag.
    await tester.tap(_filterTag('docs'));
    await tester.pumpAndSettle();
    expect(_skill('alpha'), findsOneWidget);
    expect(_skill('beta'), findsNothing);
    // No Skill carries both tags, so the empty state offers a way out.
    await tester.tap(_filterTag('docs'));
    await tester.tap(_filterTag('frontend'));
    await tester.pumpAndSettle();
    await _closeSortCard(tester);
    expect(find.byKey(const Key('browser-tag-filter-empty')), findsOneWidget);
    await tester.tap(find.byKey(const Key('browser-clear-tag-filter')));
    await tester.pumpAndSettle();
    expect(_skill('gamma'), findsOneWidget);
    expect(_triggerChips, findsNothing);
  });

  testWidgets('the sort button shows two selected tags and counts the rest', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_workspace()));
    await tester.pumpAndSettle();
    await _openSortCard(tester);
    await tester.tap(_filterTag('writing'));
    await tester.tap(_filterTag('docs'));
    await tester.pumpAndSettle();
    await _closeSortCard(tester);
    expect(_triggerChips, findsNWidgets(2));
    expect(find.text('+1'), findsNothing);

    await _openSortCard(tester);
    await tester.tap(_filterTag('frontend'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tag-filter-clear')));
    await tester.pumpAndSettle();
    await _closeSortCard(tester);
    expect(_triggerChips, findsNothing);

    await _openSortCard(tester);
    for (final id in ['writing', 'docs', 'frontend']) {
      await tester.tap(_filterTag(id));
    }
    await tester.pumpAndSettle();
    await _closeSortCard(tester);
    expect(_triggerChips, findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('skill-sort-button')),
        matching: find.text('+1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the sort card creates a tag inline', (tester) async {
    final workspace = _workspace();
    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();
    await _openSortCard(tester);

    await tester.tap(find.byKey(const Key('tag-filter-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('personal-tag-name-field')),
      'Ops',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(workspace.createdPersonalTags.single.name, 'Ops');
    expect(find.byKey(const Key('personal-tag-name-field')), findsNothing);
    expect(find.text('Ops'), findsOneWidget);
  });

  testWidgets('deleting a tag confirms the affected count and clears filter', (
    tester,
  ) async {
    final workspace = _workspace();
    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();
    await _openSortCard(tester);
    await tester.tap(_filterTag('writing'));
    await tester.pumpAndSettle();
    expect(_skill('gamma'), findsNothing);

    await tester.tap(_filterTag('writing'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('personal-tag-delete')));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 Skills will lose this tag.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('personal-tag-delete-confirm')));
    await tester.pumpAndSettle();

    expect(workspace.deletedPersonalTags, ['writing']);
    expect(find.byKey(const Key('personal-tag-editor')), findsNothing);
    expect(_filterTag('writing'), findsNothing);
    expect(_skill('gamma'), findsOneWidget);
  });

  testWidgets('renaming to an existing name shows the error inline', (
    tester,
  ) async {
    final workspace = _workspace();
    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();
    await _openSortCard(tester);

    await tester.tap(_filterTag('docs'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('personal-tag-name-field')),
      'WRITING',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('personal-tag-name-error')), findsOneWidget);
    expect(workspace.current.findPersonalTag('docs')!.name, 'Docs');

    await tester.enterText(
      find.byKey(const Key('personal-tag-name-field')),
      'Guides',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(workspace.updatedPersonalTags.last, (
      tagId: 'docs',
      name: 'Guides',
      color: '#3E63DD',
    ));
    expect(find.byKey(const Key('personal-tag-editor')), findsNothing);
    expect(_filterTag('docs'), findsOneWidget);
  });

  testWidgets('recoloring keeps the editor open', (tester) async {
    final workspace = _workspace();
    await tester.pumpWidget(_app(workspace));
    await tester.pumpAndSettle();
    await _openSortCard(tester);

    await tester.tap(_filterTag('frontend'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('personal-tag-color-#30A46C')));
    await tester.pumpAndSettle();

    expect(workspace.updatedPersonalTags.last, (
      tagId: 'frontend',
      name: 'Frontend',
      color: '#30A46C',
    ));
    expect(find.byKey(const Key('personal-tag-editor')), findsOneWidget);
    await tester.tap(find.byKey(const Key('personal-tag-editor-back')));
    await tester.pumpAndSettle();
    expect(_filterTag('frontend'), findsOneWidget);
  });

  testWidgets('cards show tags beside the activation footer', (tester) async {
    await tester.pumpWidget(_app(_workspace(), layout: SkillListLayout.cards));
    await tester.pumpAndSettle();

    final alphaCard = _skill('alpha');
    expect(
      find.descendant(of: alphaCard, matching: find.byType(PersonalTagChip)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: _skill('gamma'),
        matching: find.byType(PersonalTagChip),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the detail preview row adds, creates, and removes Skill tags', (
    tester,
  ) async {
    final workspace = _workspace();
    await tester.pumpWidget(_app(workspace, location: '/installed/gamma'));
    await tester.pumpAndSettle();

    final editor = find.byKey(const Key('skill-tag-editor'));
    await tester.ensureVisible(editor);
    expect(
      find.descendant(of: editor, matching: find.byType(PersonalTagChip)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('skill-tag-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('skill-tag-option-docs')));
    await tester.pumpAndSettle();
    expect(workspace.assignedPersonalTags.last.tagId, 'docs');

    await tester.enterText(
      find.byKey(const Key('skill-tag-search')),
      'writing',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-tag-create')), findsNothing);

    await tester.enterText(find.byKey(const Key('skill-tag-search')), 'Ops');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-tag-create')));
    await tester.pumpAndSettle();
    final created = workspace.current.personalTags.firstWhere(
      (tag) => tag.name == 'Ops',
    );
    expect(
      workspace.current
          .findSkillById(WorkspaceSkillId('gamma'))!
          .personalTagIds,
      containsAll(['frontend', 'docs', created.id]),
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('skill-tag-frontend')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(workspace.unassignedPersonalTags.single.tagId, 'frontend');
  });
}

Finder get _triggerChips => find.descendant(
  of: find.byKey(const Key('skill-sort-button')),
  matching: find.byType(PersonalTagChip),
);

Finder _filterTag(String id) => find.byKey(ValueKey('tag-filter-$id'));

Future<void> _openSortCard(WidgetTester tester, {bool roomy = true}) async {
  // This suite's existing tag actions use a roomy menu; compact scrolling is
  // exercised separately at the minimum window size.
  if (roomy) {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const Key('skill-sort-button')));
  await tester.pumpAndSettle();
}

Future<void> _closeSortCard(WidgetTester tester) async {
  await tester.tapAt(const Offset(4, 4));
  await tester.pumpAndSettle();
}

Finder _skill(String slotKey) => find.byKey(Key('skill-$slotKey'));

Widget _app(
  FakeSkillsWorkspaceRepository workspace, {
  SkillListLayout layout = SkillListLayout.list,
  String location = '/installed',
}) => skillsManagerTestApp(
  browserRepository: FakeSkillBrowserRepository(
    documents: const {'alpha': '# A', 'beta': '# B', 'gamma': '# G'},
  ),
  workspaceRepository: workspace,
  catalogAuthority: SkillBrowserCatalogAuthority.workspaceSnapshot,
  initialSkillListLayout: layout,
  initialLocation: location,
);

FakeSkillsWorkspaceRepository _workspace() => FakeSkillsWorkspaceRepository(
  documents: const {'alpha': '# A', 'beta': '# B', 'gamma': '# G'},
  snapshot: SkillsWorkspaceSnapshot(
    revision: 1,
    projectRoots: const [],
    personalTags: [
      _tag('writing', 'Writing'),
      _tag('docs', 'Docs'),
      _tag('frontend', 'Frontend'),
    ],
    skills: [
      _skillRecord('alpha', 'Alpha Skill', const ['writing', 'docs']),
      _skillRecord('beta', 'Beta Skill', const ['writing']),
      _skillRecord('gamma', 'Gamma Skill', const ['frontend']),
    ],
  ),
);

WorkspacePersonalTag _tag(String id, String name) => WorkspacePersonalTag(
  id: id,
  name: name,
  color: '#3E63DD',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

WorkspaceSkill _skillRecord(
  String slotKey,
  String displayName,
  List<String> tagIds,
) => WorkspaceSkill(
  id: WorkspaceSkillId(slotKey),
  slotKey: slotKey,
  declaredName: slotKey,
  displayName: displayName,
  description: '$displayName description',
  source: SkillSourceProvenance(
    kind: WorkspaceSourceKind.local,
    locator: '/skills/$slotKey',
  ),
  currentRevision: SkillRevision(
    contentHash: 'a' * 64,
    fileCount: 1,
    byteSize: 3,
    acquiredAt: DateTime.utc(2026),
  ),
  activations: globalActivation(),
  personalTagIds: tagIds,
);
