import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/theme/app_button_theme.dart';

import '../../../../support/fake_directory_picker.dart';
import '../../../../support/fake_skill_acquisition_repository.dart';
import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  testWidgets(
    'a picked local directory is written back to the replacement source field',
    (tester) async {
      final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      final acquisition = FakeSkillAcquisitionRepository()
        ..inspection = SkillSourceInspection(
          source: const ResolvedSkillSource(
            kind: SkillSourceKind.local,
            value: '/tmp/picked-skill',
          ),
          candidates: const [
            SkillCandidate(
              slotKey: 'alpha',
              declaredName: 'Alpha Skill',
              description: '',
              skillPath: 'skills/alpha',
            ),
          ],
        );

      await tester.pumpWidget(
        skillsManagerTestApp(
          initialSourceInputMode: SkillSourceInputMode.typed,
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
            documents: {'alpha': '# Alpha'},
          ),
          acquisitionRepository: acquisition,
          directoryPicker: FakeDirectoryPicker('/tmp/picked-skill'),
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('replace-skill-source')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('source-replacement-kind-local')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('source-replacement-kind-local')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('choose-source-directory')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('choose-source-directory')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<CupertinoTextFormFieldRow>(
              find.byKey(const Key('source-replacement-locator')),
            )
            .controller
            ?.text,
        '/tmp/picked-skill',
      );

      await tester.tap(find.byKey(const Key('inspect-replacement-source')));
      await tester.pumpAndSettle();

      expect(acquisition.inspectedDraft?.locator, '/tmp/picked-skill');
    },
  );

  testWidgets('a candidate for a different Skill cannot be selected', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = SkillSourceInspection(
        source: const ResolvedSkillSource(
          kind: SkillSourceKind.git,
          value: 'https://example.com/skills.git',
        ),
        candidates: const [
          SkillCandidate(
            slotKey: 'alpha',
            declaredName: 'Alpha Skill',
            description: '',
            skillPath: 'skills/alpha',
          ),
          SkillCandidate(
            slotKey: 'beta',
            declaredName: 'Beta Skill',
            description: 'Not the target Skill',
            skillPath: 'skills/beta',
          ),
        ],
      );

    await tester.pumpWidget(
      skillsManagerTestApp(
        initialSourceInputMode: SkillSourceInputMode.typed,
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
          documents: {'alpha': '# Alpha'},
        ),
        acquisitionRepository: acquisition,
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-skill-source')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('source-replacement-kind-git')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-replacement-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-replacement-locator')),
      'https://example.com/skills.git',
    );
    await tester.tap(find.byKey(const Key('inspect-replacement-source')));
    await tester.pumpAndSettle();

    // Alpha auto-selects because it matches the Skill being replaced, so the
    // wizard can already continue.
    expect(find.text('A different Skill'), findsOneWidget);
    expect(
      tester
          .widget<AppButton>(
            find.byKey(const Key('continue-source-replacement')),
          )
          .onPressed,
      isNotNull,
    );

    // Tapping the disabled Beta row changes nothing: Alpha remains selected.
    await tester.ensureVisible(
      find.byKey(const Key('replacement-candidate-beta')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('replacement-candidate-beta')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<AppButton>(
            find.byKey(const Key('continue-source-replacement')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'a replacement failure keeps step three retryable without a banner',
    (tester) async {
      final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');
      final acquisition = FakeSkillAcquisitionRepository()
        ..inspection = SkillSourceInspection(
          source: const ResolvedSkillSource(
            kind: SkillSourceKind.local,
            value: '/tmp/alpha',
          ),
          candidates: const [
            SkillCandidate(
              slotKey: 'alpha',
              declaredName: 'Alpha Skill',
              description: '',
              skillPath: 'skills/alpha',
            ),
          ],
        );
      final workspace = FakeSkillsWorkspaceRepository()
        ..replaceSourceError = WorkspaceException(
          code: WorkspaceErrorCode.sourceUnavailable,
          operation: WorkspaceOperationKind.replaceSource,
        );

      await tester.pumpWidget(
        skillsManagerTestApp(
          initialSourceInputMode: SkillSourceInputMode.typed,
          browserRepository: FakeSkillBrowserRepository(
            catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
            documents: {'alpha': '# Alpha'},
          ),
          workspaceRepository: workspace,
          acquisitionRepository: acquisition,
          initialLocation: '/installed/alpha',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('replace-skill-source')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('source-replacement-kind-local')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('source-replacement-kind-local')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('source-replacement-locator')),
        '/tmp/alpha',
      );
      await tester.tap(find.byKey(const Key('inspect-replacement-source')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('continue-source-replacement')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-source-replacement')));
      await tester.pumpAndSettle();

      // The failure reaches the user as a toast; the wizard itself renders no
      // inline banner, and simply stays on step three so the user can retry.
      expect(find.byKey(const Key('source-replacement-error')), findsNothing);
      expect(
        find.byKey(const Key('source-replacement-dialog')),
        findsOneWidget,
      );

      workspace.replaceSourceError = null;
      await tester.tap(find.byKey(const Key('confirm-source-replacement')));
      await tester.pumpAndSettle();

      expect(workspace.replaceSourceRequests, hasLength(2));
      expect(find.byKey(const Key('source-replacement-dialog')), findsNothing);
    },
  );

  testWidgets('the wizard stepper reads 来源 / 选择 / 替换 in Chinese', (
    tester,
  ) async {
    final alpha = testSkill(slotKey: 'alpha', displayName: 'Alpha Skill');

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(
          catalog: InstalledSkillCatalog(revision: 1, skills: [alpha]),
          documents: {'alpha': '# Alpha'},
        ),
        locale: const Locale('zh'),
        initialLocation: '/installed/alpha',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('replace-skill-source')));
    await tester.pumpAndSettle();

    expect(find.text('来源'), findsOneWidget);
    expect(find.text('选择'), findsOneWidget);
    expect(find.text('替换'), findsOneWidget);
  });
}
