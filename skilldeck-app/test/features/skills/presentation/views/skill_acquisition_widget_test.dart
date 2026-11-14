import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/notifications/app_notification_presenter.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/skill_browser_repository.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';
import 'package:skills_manager/features/skills/presentation/widgets/source_form_controls.dart';
import 'package:skills_manager/features/skills/presentation/widgets/source_wizard_chrome.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../../../../support/fake_directory_picker.dart';
import '../../../../support/fake_skill_acquisition_repository.dart';
import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/skill_drift_test_support.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  testWidgets('reviews and confirms an occupied Install target', (
    tester,
  ) async {
    final draft = FakeWorkspaceInstallTakeoverDraft(
      targets: [
        WorkspaceOccupiedActivationTarget(
          slotKey: 'alpha',
          location: '/Users/test/.agents/skills',
          targetPath: '/Users/test/.agents/skills/alpha',
          agentIds: const ['codex'],
          kind: WorkspaceActivationTargetOccupancyKind.brokenSymbolicLink,
          contentRelation: WorkspaceActivationContentRelation.indeterminate,
          linkTarget: '/legacy/alpha',
        ),
      ],
    );
    final acquisition =
        FakeSkillAcquisitionRepository(
            agents: const [
              AgentOption(
                id: 'codex',
                displayName: 'Codex',
                location: '/Users/test/.agents/skills',
              ),
            ],
          )
          ..inspection = _inspection(
            const ResolvedSkillSource(
              kind: SkillSourceKind.local,
              value: '/source/alpha',
            ),
          )
          ..installAttempt = AcquisitionInstallTakeoverRequired(draft)
          ..receipt = InstallReceipt(
            catalog: InstalledSkillCatalog(revision: 1, skills: const []),
            affectedSlotKeys: {'alpha'},
          );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await _advanceToActivation(tester);

    await tester.tap(find.byKey(const Key('install-skills')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activation-takeover-dialog')), findsOneWidget);
    expect(find.text('/Users/test/.agents/skills/alpha'), findsOneWidget);
    expect(find.text('Broken symbolic link'), findsOneWidget);
    expect(find.text('Replace and install'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('activation-takeover-dialog')),
        matching: find.text('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('acquisition-dialog')), findsOneWidget);
    expect(acquisition.confirmedInstallTakeovers, isEmpty);

    await tester.tap(find.byKey(const Key('install-skills')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activation-takeover-confirm')));
    await tester.pumpAndSettle();

    expect(acquisition.confirmedInstallTakeovers, [same(draft)]);
    expect(find.byKey(const Key('acquisition-dialog')), findsNothing);
  });

  testWidgets(
    'selects shared locations once and adds undetected Agents through management',
    (tester) async {
      final acquisition =
          FakeSkillAcquisitionRepository(
              agents: const [
                AgentOption(
                  id: 'codex',
                  displayName: 'Codex',
                  location: '/shared',
                ),
                AgentOption(
                  id: 'opencode',
                  displayName: 'OpenCode',
                  location: '/shared',
                ),
                AgentOption(
                  id: 'universal',
                  displayName: 'Universal',
                  location: '/shared',
                  detected: false,
                ),
                AgentOption(
                  id: 'custom',
                  displayName: 'Custom',
                  location: '/custom',
                  detected: false,
                ),
              ],
            )
            ..inspection = _inspection(
              const ResolvedSkillSource(
                kind: SkillSourceKind.git,
                value: 'owner/repository',
              ),
            );
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          acquisitionRepository: acquisition,
          initialSourceInputMode: SkillSourceInputMode.typed,
        ),
      );
      await tester.pumpAndSettle();
      await _advanceToActivation(tester);
      expect(find.text('Universal Agents'), findsOneWidget);
      expect(find.byKey(const Key('location-/shared')), findsOneWidget);
      expect(find.byKey(const Key('agent-codex')), findsNothing);
      expect(find.text('Universal'), findsNothing);
      expect(find.text('/custom'), findsNothing);
      expect(find.byKey(const Key('other-activation-locations')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('add-agent')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('add-agent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('add-agent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-management-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-add-built-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('include-agent-custom')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('agent-management-close')));
      await tester.pumpAndSettle();
      expect(find.text('/custom'), findsOneWidget);
      expect(
        tester
            .widget<AgentActivationSwitch>(
              find.byKey(const Key('toggle-all-locations')),
            )
            .on,
        isFalse,
      );
      await tester.ensureVisible(find.byKey(const Key('toggle-all-locations')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('toggle-all-locations')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('toggle-all-locations')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AgentActivationSwitch>(
              find.byKey(const Key('toggle-all-locations')),
            )
            .on,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('install-skills')));
      await tester.pumpAndSettle();
      expect(acquisition.installSelection?.selectedAgentIds, {
        'codex',
        'opencode',
        'custom',
      });
    },
  );

  testWidgets('inspects, selects, installs, and refreshes the browser', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final installed = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha',
      activations: globalActivation(
        location: '/Users/test/.codex/skills',
        agentIds: const ['codex'],
      ),
    );
    final workspace = FakeSkillsWorkspaceRepository(
      documents: const {'alpha': '# Alpha'},
    );
    final browser = WorkspaceSkillBrowserRepository(workspace);
    final acquisition =
        FakeSkillAcquisitionRepository(
            agents: const [
              AgentOption(
                id: 'codex',
                displayName: 'Codex',
                location: '/Users/test/.codex/skills',
              ),
              AgentOption(id: 'aider', displayName: 'Aider', detected: false),
            ],
          )
          ..inspection = SkillSourceInspection(
            source: const ResolvedSkillSource(
              kind: SkillSourceKind.git,
              value: 'owner/repository',
            ),
            candidates: const [
              SkillCandidate(
                slotKey: 'alpha',
                declaredName: 'Alpha',
                description: 'Alpha description',
                skillPath: 'skills/alpha',
              ),
              SkillCandidate(
                slotKey: 'beta',
                declaredName: 'Beta',
                description: 'Beta description',
                skillPath: 'skills/beta',
              ),
            ],
          )
          ..receipt = InstallReceipt(
            catalog: InstalledSkillCatalog(revision: 1, skills: [installed]),
            affectedSlotKeys: {'alpha'},
          )
          ..onInstall = (_) => workspace.publish(
            SkillsWorkspaceSnapshot(
              revision: 1,
              projectRoots: const [],
              skills: [
                WorkspaceSkill(
                  id: installed.id,
                  slotKey: installed.slotKey,
                  declaredName: installed.displayName,
                  displayName: installed.displayName,
                  description: installed.description,
                  source: const SkillSourceProvenance(
                    kind: WorkspaceSourceKind.git,
                    locator: 'owner/repository',
                  ),
                  currentRevision: SkillRevision(
                    contentHash: installed.contentHash,
                    fileCount: 1,
                    byteSize: 10,
                    acquiredAt: DateTime.utc(2026),
                  ),
                  activations: globalActivation(
                    location: '/Users/test/.codex/skills',
                    agentIds: const ['codex'],
                  ),
                ),
              ],
            ),
          );

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: browser,
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
        workspaceRepository: workspace,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('acquisition-dialog')), findsOneWidget);
    expect(
      tester
          .widget<AppIconButton>(
            find.byKey(const Key('acquisition-close-button')),
          )
          .style,
      NeoButtonVariant.ghost,
    );
    expect(
      tester.widget<AppButton>(find.byKey(const Key('inspect-source'))).style,
      NeoButtonVariant.primary,
    );
    // The wizard opens with no Source kind selected.
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/repository',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('candidate-list')), findsOneWidget);
    expect(find.byKey(const Key('candidate-alpha')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('candidate-beta')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('candidate-beta')));
    await tester.tap(find.byKey(const Key('continue-acquisition')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('location-/Users/test/.codex/skills')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('agent-logo-codex')), findsWidgets);
    expect(find.text('/Users/test/.codex/skills'), findsOneWidget);
    expect(find.text('Activation target'), findsNothing);
    expect(find.byKey(const Key('agent-aider')), findsNothing);
    expect(find.text('Not detected on this device'), findsNothing);
    expect(find.byKey(const Key('add-agent')), findsOneWidget);
    expect(find.text('Scope'), findsNothing);
    expect(
      tester
          .widget<MorphingMenuButton>(
            find.byKey(const Key('acquisition-scope-selector')),
          )
          .alignment,
      MorphingMenuAlignment.start,
    );
    expect(
      tester.widget<AppButton>(find.byKey(const Key('add-agent'))).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<AppButton>(find.byKey(const Key('install-skills'))).style,
      NeoButtonVariant.primary,
    );
    await tester.tap(find.byKey(const Key('install-skills')));
    await tester.pumpAndSettle();

    expect(acquisition.installSelection!.selectedSkillNames, {'Alpha'});
    expect(acquisition.installSelection!.selectedAgentIds, {'codex'});
    expect(find.byKey(const Key('acquisition-dialog')), findsNothing);
    expect(find.byKey(const Key('skill-alpha')), findsOneWidget);
  });

  testWidgets('shows only the add Agent placeholder when none are detected', (
    tester,
  ) async {
    final acquisition =
        FakeSkillAcquisitionRepository(
            agents: const [
              AgentOption(id: 'aider', displayName: 'Aider', detected: false),
            ],
          )
          ..inspection = _inspection(
            const ResolvedSkillSource(
              kind: SkillSourceKind.git,
              value: 'owner/repository',
            ),
          );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();

    await _advanceToActivation(tester);

    expect(find.byKey(const Key('agent-aider')), findsNothing);
    expect(find.byKey(const Key('add-agent')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('detected-agent-count'))).data,
      '/ 0 detected',
    );
    await tester.tap(
      find.byKey(const Key('install-skills')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(acquisition.installSelection, isNull);
  });

  testWidgets('shows operation progress and exposes cancellation', (
    tester,
  ) async {
    final result = Completer<WorkspaceCompletion<SkillSourceInspection>>();
    var cancelCalls = 0;
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspectHandler = (_) => AcquisitionTask<SkillSourceInspection>(
        current: const AcquisitionProgress(phase: AcquisitionPhase.inspecting),
        states: const Stream.empty(),
        completed: result.future,
        cancel: () async {
          cancelCalls += 1;
          result.complete(
            WorkspaceFailed(
              failure: WorkspaceException(
                operation: WorkspaceOperationKind.inspectSource,
                code: WorkspaceErrorCode.operationCancelled,
              ),
            ),
          );
        },
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    // The wizard opens with no Source kind selected.
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/repository',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pump();

    expect(find.byKey(const Key('acquisition-progress')), findsOneWidget);
    expect(find.byKey(const Key('cancel-acquisition')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-acquisition')));
    await tester.pumpAndSettle();
    expect(cancelCalls, 1);
  });

  testWidgets('master skill toggle selects and clears all candidates', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = SkillSourceInspection(
        source: const ResolvedSkillSource(
          kind: SkillSourceKind.git,
          value: 'owner/repository',
        ),
        candidates: const [
          SkillCandidate(
            slotKey: 'alpha',
            declaredName: 'Alpha',
            description: 'Alpha description',
            skillPath: 'skills/alpha',
          ),
          SkillCandidate(
            slotKey: 'beta',
            declaredName: 'Beta',
            description: 'Beta description',
            skillPath: 'skills/beta',
          ),
        ],
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    // The wizard opens with no Source kind selected.
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/repository',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('toggle-all-skills')), findsOneWidget);
    expect(_masterCheckbox(tester).value, isTrue);
    expect(_masterCheckbox(tester).tristate, isTrue);
    expect(_candidateCheckbox(tester, 'alpha').value, isTrue);
    expect(_candidateCheckbox(tester, 'beta').value, isTrue);

    await tester.ensureVisible(find.byKey(const Key('candidate-beta')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('candidate-beta')));
    await tester.pumpAndSettle();

    expect(_candidateCheckbox(tester, 'alpha').value, isTrue);
    expect(_candidateCheckbox(tester, 'beta').value, isFalse);
    expect(_masterCheckbox(tester).value, isNull);

    await tester.ensureVisible(find.byKey(const Key('toggle-all-skills')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('toggle-all-skills')));
    await tester.pumpAndSettle();

    expect(_candidateCheckbox(tester, 'alpha').value, isTrue);
    expect(_candidateCheckbox(tester, 'beta').value, isTrue);
    expect(_masterCheckbox(tester).value, isTrue);

    await tester.ensureVisible(find.byKey(const Key('toggle-all-skills')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('toggle-all-skills')));
    await tester.pumpAndSettle();

    expect(_candidateCheckbox(tester, 'alpha').value, isFalse);
    expect(_candidateCheckbox(tester, 'beta').value, isFalse);
    expect(_masterCheckbox(tester).value, isFalse);
  });

  testWidgets('preserves optional Git ref and repository subpath', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = SkillSourceInspection(
        source: const ResolvedSkillSource(
          kind: SkillSourceKind.git,
          value: 'owner/repository',
        ),
        candidates: const [
          SkillCandidate(
            slotKey: 'alpha',
            declaredName: 'Alpha',
            description: 'Alpha description',
            skillPath: 'packages/skills/alpha',
          ),
        ],
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    // The wizard opens with no Source kind selected.
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/repository',
    );
    await tester.pump();
    await tester.enterText(find.byKey(const Key('source-ref')), 'release/v2');
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('source-subpath')),
      'packages/skills',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(acquisition.inspectedDraft?.kind, SkillSourceKind.git);
    expect(acquisition.inspectedDraft?.locator, 'owner/repository');
    expect(acquisition.inspectedDraft?.sourceRef, 'release/v2');
    expect(acquisition.inspectedDraft?.repositorySubpath, 'packages/skills');
  });

  testWidgets('opens with no Source kind chosen', (tester) async {
    final acquisition = FakeSkillAcquisitionRepository();

    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    // No card is preselected, so nothing below them is shown yet: the
    // locator's label, placeholder, and icon all depend on the kind.
    for (final kind in SkillSourceKind.values) {
      expect(
        tester
            .widget<SourceKindCard>(find.byKey(Key('source-kind-${kind.name}')))
            .selected,
        isFalse,
      );
    }
    expect(find.byKey(const Key('source-locator')), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('inspect-source')))
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-locator')), findsOneWidget);
    expect(
      tester
          .widget<SourceKindCard>(find.byKey(const Key('source-kind-git')))
          .selected,
      isTrue,
    );
  });

  testWidgets('local source card submits an explicit local draft', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = _inspection(
        const ResolvedSkillSource(
          kind: SkillSourceKind.local,
          value: '/tmp/skills',
        ),
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('source-kind-local')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-local')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      '/tmp/skills',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(acquisition.inspectedDraft?.kind, SkillSourceKind.local);
  });

  testWidgets('selected local directory is written back to the source field', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = _inspection(
        const ResolvedSkillSource(
          kind: SkillSourceKind.local,
          value: '/tmp/picked-skill',
        ),
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
        directoryPicker: FakeDirectoryPicker('/tmp/picked-skill'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('source-kind-local')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-local')));
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
            find.byKey(const Key('source-locator')),
          )
          .controller
          ?.text,
      '/tmp/picked-skill',
    );

    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();
    expect(acquisition.inspectedDraft?.locator, '/tmp/picked-skill');
  });

  testWidgets('a source failure stays inline until the form changes', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspectError = WorkspaceFailure(
        code: WorkspaceErrorCode.skillNotFound,
        operation: WorkspaceOperationKind.inspectSource,
        context: const {'reason': 'noValidSkills'},
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    // The wizard opens with no Source kind selected.
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/empty',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    final banner = find.byKey(const Key('acquisition-source-error'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(
        of: banner,
        matching: find.text(
          'No skills were found in this source. '
          'A skill is a folder that contains a SKILL.md file.',
        ),
      ),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/other',
    );
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
  });

  testWidgets('continue stays disabled until a locator is typed', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = _inspection(
        const ResolvedSkillSource(
          kind: SkillSourceKind.git,
          value: 'owner/repository',
        ),
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();

    VoidCallback? continueAction() => tester
        .widget<AppButton>(find.byKey(const Key('inspect-source')))
        .onPressed;
    expect(continueAction(), isNull);

    await tester.enterText(find.byKey(const Key('source-locator')), '   ');
    await tester.pumpAndSettle();
    expect(continueAction(), isNull);

    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/repository',
    );
    await tester.pumpAndSettle();
    expect(continueAction(), isNotNull);

    // Enter submits like the Continue button.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(acquisition.inspectedDraft?.locator, 'owner/repository');
    expect(find.byKey(const Key('candidate-list')), findsOneWidget);
  });

  testWidgets('an installed candidate is shown as installed, not selectable', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = SkillSourceInspection(
        source: const ResolvedSkillSource(
          kind: SkillSourceKind.git,
          value: 'owner/repository',
        ),
        candidates: const [
          SkillCandidate(
            slotKey: 'alpha',
            declaredName: 'Alpha',
            description: 'Alpha description',
            skillPath: 'skills/alpha',
          ),
          SkillCandidate(
            slotKey: 'beta',
            declaredName: 'Beta',
            description: 'Beta description',
            skillPath: 'skills/beta',
          ),
        ],
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
        workspaceRepository: FakeSkillsWorkspaceRepository(
          snapshot: driftWidgetSnapshot(
            integrity: WorkspaceSkillIntegrityStatus.healthy,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'owner/repository',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    final installed = tester.widget<SourceCandidateRow>(
      find.byKey(const Key('candidate-alpha')),
    );
    expect(installed.enabled, isFalse);
    expect(installed.disabledReason, contains('Already installed'));
    expect(
      find.byKey(const Key('candidate-installed-open-alpha')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<SourceCandidateRow>(find.byKey(const Key('candidate-beta')))
          .enabled,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('continue-acquisition')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('install-skills')));
    await tester.pumpAndSettle();
    expect(acquisition.installSelection?.selectedSkillNames, {'Beta'});
    expect(acquisition.installSelection?.installAllSkills, isFalse);
  });

  testWidgets('generic HTTPS selected as Git remains Git', (tester) async {
    const locator = 'https://git.example.com/group/repository';
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = _inspection(
        const ResolvedSkillSource(kind: SkillSourceKind.git, value: locator),
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-locator')), locator);
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(acquisition.inspectedDraft?.kind, SkillSourceKind.git);
    expect(acquisition.inspectedDraft?.locator, locator);
  });

  testWidgets('GitHub URL selected as Web remains well-known', (tester) async {
    const locator = 'https://github.com/owner/repository';
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = _inspection(
        const ResolvedSkillSource(
          kind: SkillSourceKind.wellKnown,
          value: locator,
        ),
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('source-kind-wellKnown')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-wellKnown')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('source-locator')), locator);
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(acquisition.inspectedDraft?.kind, SkillSourceKind.wellKnown);
    expect(acquisition.inspectedDraft?.locator, locator);
  });

  testWidgets(
    'manages a missing project root without losing the acquisition selection',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final workspace = FakeSkillsWorkspaceRepository();
      final acquisition = FakeSkillAcquisitionRepository()
        ..inspection = _inspection(
          const ResolvedSkillSource(
            kind: SkillSourceKind.git,
            value: 'owner/repository',
          ),
        )
        ..receipt = InstallReceipt(
          catalog: InstalledSkillCatalog(revision: 2, skills: const []),
          affectedSlotKeys: {'alpha'},
        );
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          acquisitionRepository: acquisition,
          initialSourceInputMode: SkillSourceInputMode.typed,
          workspaceRepository: workspace,
          directoryPicker: FakeDirectoryPicker('/projects/app'),
        ),
      );
      await tester.pumpAndSettle();

      await _advanceToActivation(tester);
      await tester.ensureVisible(
        find.byKey(const Key('acquisition-scope-selector')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('acquisition-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('acquisition-scope-option-manage-project-roots')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('project-roots-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('project-root-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-roots-close')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('acquisition-scope-selector')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('acquisition-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('acquisition-scope-option-project-project-1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('app'), findsOneWidget);
      expect(
        acquisition.targetInspections.last.scope,
        SkillActivationScope.project,
      );
      expect(acquisition.targetInspections.last.projectRootId, 'project-1');
      await tester.tap(find.byKey(const Key('install-skills')));
      await tester.pumpAndSettle();

      expect(acquisition.installSelection?.selectedSkillNames, {'Alpha'});
      expect(acquisition.installSelection?.scope, SkillActivationScope.project);
      expect(acquisition.installSelection?.projectRootId, 'project-1');
    },
  );

  testWidgets(
    'scope menu keeps global selected when Project Roots stays empty',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final acquisition = FakeSkillAcquisitionRepository()
        ..inspection = _inspection(
          const ResolvedSkillSource(
            kind: SkillSourceKind.git,
            value: 'owner/repository',
          ),
        );
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          acquisitionRepository: acquisition,
          initialSourceInputMode: SkillSourceInputMode.typed,
          workspaceRepository: FakeSkillsWorkspaceRepository(),
        ),
      );
      await tester.pumpAndSettle();

      await _advanceToActivation(tester);
      await tester.ensureVisible(
        find.byKey(const Key('acquisition-scope-selector')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('acquisition-scope-selector')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('acquisition-scope-option-manage-project-roots')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-roots-close')));
      await tester.pumpAndSettle();

      expect(
        acquisition.targetInspections.where(
          (inspection) => inspection.scope == SkillActivationScope.project,
        ),
        isEmpty,
      );
      expect(find.text('Global'), findsOneWidget);
    },
  );

  testWidgets('an unprepared host guides to Settings instead of a toast', (
    tester,
  ) async {
    // The wizard plus the hint is taller than the default test viewport, and
    // the Settings button has to be tappable.
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Source inspection is the first system Git call, so this is where an
    // unprepared host actually fails.
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspectError = WorkspaceFailure(
        code: WorkspaceErrorCode.developerToolsRequired,
        operation: WorkspaceOperationKind.inspectSource,
      );
    final presenter = _RecordingPresenter();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
        notificationPresenter: presenter,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-git')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      'github.com/owner/repository',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('acquisition-environment-hint')),
      findsOneWidget,
    );
    // A transient toast would disappear behind the operating system's own
    // install dialog and offer no next step.
    expect(presenter.presentations, isEmpty);

    final settingsAction = find.byKey(
      const Key('acquisition-environment-settings'),
    );
    await tester.ensureVisible(settingsAction);
    await tester.pumpAndSettle();
    await tester.tap(settingsAction);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('environment-settings')), findsOneWidget);
  });

  testWidgets('the host hint is keyed off the failure, not the source kind', (
    tester,
  ) async {
    // A local Source reaching the same typed failure must reach the same hint;
    // nothing in the install surface may branch on Git.
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspectError = WorkspaceFailure(
        code: WorkspaceErrorCode.developerToolsRequired,
        operation: WorkspaceOperationKind.inspectSource,
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        initialSourceInputMode: SkillSourceInputMode.typed,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('source-kind-local')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('source-kind-local')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('source-locator')),
      '/tmp/example',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('acquisition-environment-hint')),
      findsOneWidget,
    );
  });
  testWidgets('opens in smart mode with the check disabled until pasted', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('source-smart-input')), findsOneWidget);
    expect(find.byKey(const Key('source-kind-git')), findsNothing);
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('inspect-source')))
          .onPressed,
      isNull,
    );

    // Beside the mode switch, the Agent card opens. With neither the command
    // line tool nor the skilldeck Skill set up, it guides to Settings instead
    // of showing the prompt.
    await tester.ensureVisible(
      find.byKey(const Key('agent-install-prompt-toggle')),
    );
    await tester.tap(find.byKey(const Key('agent-install-prompt-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-install-setup')), findsOneWidget);
    expect(find.byKey(const Key('agent-install-prompt')), findsNothing);
    expect(
      find.byKey(const Key('agent-install-prompt-settings')),
      findsOneWidget,
    );
    // Tapping outside the card, in the dialog's side margin, closes it.
    final cardRect = tester.getRect(
      find.byKey(const Key('agent-install-setup')),
    );
    await tester.tapAt(Offset(cardRect.left - 16, cardRect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('agent-install-setup')), findsNothing);

    // Pasting a Source enables the check.
    await tester.enterText(
      find.byKey(const Key('source-smart-input')),
      'owner/repo',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('inspect-source')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a pasted install command checks, previews, then preselects', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = SkillSourceInspection(
        source: const ResolvedSkillSource(
          kind: SkillSourceKind.git,
          value: 'https://github.com/vercel-labs/skills',
        ),
        candidates: const [
          SkillCandidate(
            slotKey: 'find-skills',
            declaredName: 'find-skills',
            description: 'Find skills',
            skillPath: 'skills/find-skills',
          ),
          SkillCandidate(
            slotKey: 'beta',
            declaredName: 'Beta',
            description: 'Beta description',
            skillPath: 'skills/beta',
          ),
        ],
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('source-smart-input')),
      'npx skills add https://github.com/vercel-labs/skills --skill find-skills -y',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    // Smart mode stays on the Source step and shows what it found.
    expect(acquisition.inspectedDraft?.kind, SkillSourceKind.git);
    expect(
      acquisition.inspectedDraft?.locator,
      'https://github.com/vercel-labs/skills',
    );
    final card = find.byKey(const Key('smart-source-result'));
    expect(card, findsOneWidget);
    expect(
      find.descendant(of: card, matching: find.text('find-skills')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('-y')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('candidate-beta')), findsNothing);

    await tester.tap(find.byKey(const Key('continue-acquisition')));
    await tester.pumpAndSettle();

    expect(_candidateCheckbox(tester, 'find-skills').value, isTrue);
    expect(_candidateCheckbox(tester, 'beta').value, isFalse);
  });

  testWidgets('a plain web page explains that it holds no skills', (
    tester,
  ) async {
    var calls = 0;
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspectHandler = (draft) {
        calls += 1;
        return _failedInspection(
          draft.kind == SkillSourceKind.wellKnown
              ? WorkspaceFailure(
                  code: WorkspaceErrorCode.httpFailure,
                  operation: WorkspaceOperationKind.inspectSource,
                  context: const {
                    'reason': 'unexpectedStatus',
                    'statusCode': 404,
                  },
                )
              : WorkspaceFailure(
                  code: WorkspaceErrorCode.gitFailed,
                  operation: WorkspaceOperationKind.inspectSource,
                ),
        );
      };
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('source-smart-input')),
      'https://example.com/blog/my-skill',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();

    expect(calls, 2);
    final banner = find.byKey(const Key('acquisition-source-error'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(
        of: banner,
        matching: find.text('This address has no installable skills'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('inspect-source')))
          .onPressed,
      isNull,
    );

    // Editing the box clears the failure and re-enables the check.
    await tester.enterText(
      find.byKey(const Key('source-smart-input')),
      'owner/repo',
    );
    await tester.pumpAndSettle();
    expect(banner, findsNothing);
    expect(
      tester
          .widget<AppButton>(find.byKey(const Key('inspect-source')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('switching to the typed form carries the detected source', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository();
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('source-smart-input')),
      'https://github.com/owner/repository/tree/main/skills',
    );
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('input-mode-typed')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('input-mode-typed')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<SourceKindCard>(find.byKey(const Key('source-kind-git')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<CupertinoTextFormFieldRow>(
            find.byKey(const Key('source-locator')),
          )
          .controller
          ?.text,
      'https://github.com/owner/repository',
    );
    expect(
      tester
          .widget<CupertinoTextFormFieldRow>(
            find.byKey(const Key('source-ref')),
          )
          .initialValue,
      'main',
    );
    expect(
      tester
          .widget<CupertinoTextFormFieldRow>(
            find.byKey(const Key('source-subpath')),
          )
          .initialValue,
      'skills',
    );
  });

  testWidgets('the smart box offers the folder picker while empty', (
    tester,
  ) async {
    final acquisition = FakeSkillAcquisitionRepository()
      ..inspection = _inspection(
        const ResolvedSkillSource(
          kind: SkillSourceKind.local,
          value: '/tmp/picked-skill',
        ),
      );
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        acquisitionRepository: acquisition,
        directoryPicker: FakeDirectoryPicker('/tmp/picked-skill'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('empty-add-skills')));
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
            find.byKey(const Key('source-smart-input')),
          )
          .controller
          ?.text,
      '/tmp/picked-skill',
    );

    await tester.tap(find.byKey(const Key('inspect-source')));
    await tester.pumpAndSettle();
    expect(acquisition.inspectedDraft?.kind, SkillSourceKind.local);
    expect(acquisition.inspectedDraft?.locator, '/tmp/picked-skill');
  });
}

AcquisitionTask<SkillSourceInspection> _failedInspection(
  WorkspaceFailure failure,
) => AcquisitionTask<SkillSourceInspection>(
  current: const AcquisitionProgress(phase: AcquisitionPhase.inspecting),
  states: const Stream.empty(),
  completed: Future.value(WorkspaceFailed(failure: failure)),
  cancel: () async {},
);

SkillSourceInspection _inspection(ResolvedSkillSource source) =>
    SkillSourceInspection(
      source: source,
      candidates: const [
        SkillCandidate(
          slotKey: 'alpha',
          declaredName: 'Alpha',
          description: 'Alpha description',
          skillPath: 'skills/alpha',
        ),
      ],
    );

Future<void> _advanceToActivation(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('empty-add-skills')));
  await tester.pumpAndSettle();
  // The wizard opens with no Source kind selected.
  await tester.ensureVisible(find.byKey(const Key('source-kind-git')));
  await tester.pump();
  await tester.tap(find.byKey(const Key('source-kind-git')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('source-locator')),
    'owner/repository',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('inspect-source')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('continue-acquisition')));
  await tester.pumpAndSettle();
}

CupertinoCheckbox _candidateCheckbox(WidgetTester tester, String slotKey) =>
    tester.widget<CupertinoCheckbox>(
      find.descendant(
        of: find.byKey(Key('candidate-$slotKey')),
        matching: find.byType(CupertinoCheckbox),
      ),
    );

CupertinoCheckbox _masterCheckbox(WidgetTester tester) => tester
    .widget<CupertinoCheckbox>(find.byKey(const Key('toggle-all-skills')));

final class _RecordingPresenter implements AppNotificationPresenter {
  final presentations = <AppNotificationPresentation>[];

  @override
  void present(AppNotificationPresentation presentation) {
    presentations.add(presentation);
  }

  @override
  void dismissAll() {}

  @override
  void dispose() {}
}
