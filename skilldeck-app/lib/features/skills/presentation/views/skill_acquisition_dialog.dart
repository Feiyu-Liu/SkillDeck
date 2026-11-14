import 'dart:async';

import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_location_label.dart';
import 'package:skills_manager/features/skills/presentation/widgets/activation_takeover_dialog.dart';
import 'package:skills_manager/features/skills/presentation/widgets/skill_scope_menu.dart';
import 'package:skills_manager/features/skills/presentation/widgets/smart_source_controls.dart';
import 'package:skills_manager/features/skills/presentation/widgets/source_form_controls.dart';
import 'package:skills_manager/features/skills/presentation/widgets/source_wizard_chrome.dart';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_operation_feedback.dart';
import 'package:skills_manager/features/skills/presentation/widgets/acquisition_environment_hint.dart';
import 'package:skills_manager/shared/failures/app_failure.dart';
import 'package:skills_manager/shared/widgets/app_failure_view.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_acquisition_view_model.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';
import 'package:skills_manager/features/settings/presentation/views/agent_management_dialog.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';

class SkillAcquisitionDialog extends ConsumerStatefulWidget {
  const SkillAcquisitionDialog({super.key});

  @override
  ConsumerState<SkillAcquisitionDialog> createState() =>
      _SkillAcquisitionDialogState();
}

class _SkillAcquisitionDialogState
    extends ConsumerState<SkillAcquisitionDialog> {
  SkillAcquisitionViewModel get vm =>
      ref.read(skillAcquisitionViewModelProvider.notifier);

  List<SkillProjectRoot> get _projectRoots => ref
      .read(workspaceProjectRootsProvider)
      .when(
        data: (value) => value,
        error: (_, _) => const <SkillProjectRoot>[],
        loading: () => const <SkillProjectRoot>[],
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      vm.reset();
    });
  }

  Future<void> _onContinue(SkillAcquisitionState state) async {
    switch (state.step) {
      case AcquisitionStep.source:
        if (state.smartInspected) {
          vm.continueFromSmartResult();
        } else {
          await vm.inspect();
        }
      case AcquisitionStep.skills:
        await vm.continueToActivation(_projectRoots);
      case AcquisitionStep.activation:
        await vm.install();
    }
  }

  Future<void> _reviewInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  ) async {
    final state = ref.read(skillAcquisitionViewModelProvider);
    final names = state.locationGroups
        .where((group) => state.selectedLocations.contains(group.key))
        .map((group) => activationAgentGroupTitle(context, group))
        .toSet()
        .join(', ');
    final confirmed = await showInstallTakeoverDialog(
      context: context,
      draft: draft,
      agentName: names.isEmpty ? context.l10n.acquisitionAgents : names,
    );
    if (!mounted) return;
    if (confirmed) {
      await vm.confirmInstallTakeover();
    } else {
      vm.dismissInstallTakeover();
    }
  }

  Future<void> _manageProjectRoots() async {
    await context.pushNamed(AppRouteNames.projectRoots);
    if (!mounted) return;
    await vm.reconcileProjectRoots(_projectRoots);
  }

  Future<void> _addAgent() async {
    await showAgentManagementDialog(context);
    if (!mounted) return;
    final state = ref.read(skillAcquisitionViewModelProvider);
    await vm.loadTargets(
      scope: state.scope,
      projectRootId: state.projectRootId,
    );
  }

  VoidCallback? get _addAgentCallback {
    return vm.isBusy ? null : _addAgent;
  }

  @override
  Widget build(BuildContext context) {
    final acquisition = ref.watch(skillAcquisitionViewModelProvider);
    final projectRoots = ref
        .watch(workspaceProjectRootsProvider)
        .when(
          data: (value) => value,
          error: (_, _) => const <SkillProjectRoot>[],
          loading: () => const <SkillProjectRoot>[],
        );
    ref.listen<SkillAcquisitionState>(skillAcquisitionViewModelProvider, (
      previous,
      next,
    ) {
      if (previous?.status != AcquisitionStatus.success &&
          next.status == AcquisitionStatus.success &&
          next.warnings.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && context.canPop()) context.pop();
        });
      }
      final draft = next.installTakeover;
      if (!identical(previous?.installTakeover, draft) && draft != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_reviewInstallTakeover(draft));
        });
      }
    });
    return PopScope(
      canPop: !acquisition.isBusy,
      child: AppDialogScaffold(
        key: const Key('acquisition-dialog'),
        width: AppDialogWidths.wide,
        onEscape: acquisition.isBusy ? null : context.pop,
        header: _WizardHeader(
          step: acquisition.step.index + 1,
          onClose: acquisition.isBusy ? null : context.pop,
        ),
        sections: [
          _WizardBody(
            state: acquisition,
            scope: acquisition.scope,
            projectRootId: acquisition.projectRootId,
            projectRoots: projectRoots,
            vm: vm,
            onLocatorChanged: vm.updateLocator,
            onSourceRefChanged: vm.updateSourceRef,
            onRepositorySubpathChanged: vm.updateRepositorySubpath,
            onSourceTypeChanged: vm.selectSourceKind,
            onScopeChanged: (scope) {
              unawaited(vm.selectScope(scope, projectRoots));
            },
            onProjectRootChanged: (rootId) {
              unawaited(vm.selectProjectRoot(rootId));
            },
            onManageProjectRoots: _manageProjectRoots,
            onAddAgent: _addAgentCallback,
          ),
        ],
        footer: _WizardFooter(
          step: acquisition.step.index + 1,
          smartInspected: acquisition.smartInspected,
          vm: vm,
          onBack: vm.back,
          onContinue: () => _onContinue(acquisition),
          onClose: context.pop,
        ),
      ),
    );
  }
}

// ── Wizard Header (stepper + title) ──────────────────────────────────────────

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({required this.step, required this.onClose});

  final int step;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => AppDialogHeader(
    icon: LucideIcons.packagePlus,
    title: context.l10n.acquisitionTitle,
    subtitle: context.l10n.acquisitionSubtitleV2,
    below: SourceWizardStepper(
      currentStep: step,
      labels: [
        context.l10n.acquisitionSource,
        context.l10n.acquisitionSelect,
        context.l10n.acquisitionActivate,
      ],
    ),
    actions: [
      appDialogCloseButton(
        context,
        key: const Key('acquisition-close-button'),
        onPressed: onClose,
      ),
    ],
  );
}

class _WizardBody extends StatelessWidget {
  const _WizardBody({
    required this.state,
    required this.scope,
    required this.projectRootId,
    required this.projectRoots,
    required this.vm,
    required this.onLocatorChanged,
    required this.onSourceRefChanged,
    required this.onRepositorySubpathChanged,
    required this.onSourceTypeChanged,
    required this.onScopeChanged,
    required this.onProjectRootChanged,
    required this.onManageProjectRoots,
    required this.onAddAgent,
  });

  final SkillAcquisitionState state;
  final SkillActivationScope scope;
  final String? projectRootId;
  final List<SkillProjectRoot> projectRoots;
  final SkillAcquisitionViewModel vm;
  final ValueChanged<String> onLocatorChanged;
  final ValueChanged<String> onSourceRefChanged;
  final ValueChanged<String> onRepositorySubpathChanged;
  final ValueChanged<SkillSourceKind> onSourceTypeChanged;
  final ValueChanged<SkillActivationScope> onScopeChanged;
  final ValueChanged<String> onProjectRootChanged;
  final VoidCallback onManageProjectRoots;
  final VoidCallback? onAddAgent;

  @override
  Widget build(BuildContext context) {
    return switch (state.step) {
      AcquisitionStep.source => _Step1Body(
        state: state,
        vm: vm,
        onLocatorChanged: onLocatorChanged,
        onSourceRefChanged: onSourceRefChanged,
        onRepositorySubpathChanged: onRepositorySubpathChanged,
        onSourceTypeChanged: onSourceTypeChanged,
      ),
      AcquisitionStep.skills => _Step2Body(vm: vm),
      AcquisitionStep.activation => _Step3Body(
        vm: vm,
        scope: scope,
        projectRootId: projectRootId,
        projectRoots: projectRoots,
        onScopeChanged: onScopeChanged,
        onProjectRootChanged: onProjectRootChanged,
        onManageProjectRoots: onManageProjectRoots,
        onAddAgent: onAddAgent,
      ),
    };
  }
}

// ── Step 1: Source ────────────────────────────────────────────────────────────

class _Step1Body extends ConsumerWidget {
  const _Step1Body({
    required this.state,
    required this.vm,
    required this.onLocatorChanged,
    required this.onSourceRefChanged,
    required this.onRepositorySubpathChanged,
    required this.onSourceTypeChanged,
  });

  final SkillAcquisitionState state;
  final SkillAcquisitionViewModel vm;
  final ValueChanged<String> onLocatorChanged;
  final ValueChanged<String> onSourceRefChanged;
  final ValueChanged<String> onRepositorySubpathChanged;
  final ValueChanged<SkillSourceKind> onSourceTypeChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isBusy = vm.isBusy;
    final smart = state.inputMode == SkillSourceInputMode.smart;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The mode switch and the input it governs share one section.
        AppDialogSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AcquisitionInputModeSwitch(
                    mode: smart
                        ? AcquisitionInputModeOption.smart
                        : AcquisitionInputModeOption.typed,
                    enabled: !isBusy,
                    onChanged: (option) => vm.selectInputMode(switch (option) {
                      AcquisitionInputModeOption.smart =>
                        SkillSourceInputMode.smart,
                      AcquisitionInputModeOption.typed =>
                        SkillSourceInputMode.typed,
                    }),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Shrinks before the switch does when the row runs short.
                  const Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: SmartSourceAgentPrompt(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (smart) ..._smartControls(context, isBusy),
              if (!smart) ..._typedControls(context, isBusy),
              // Progress or error
              if (isBusy) ...[
                const SizedBox(height: 20),
                AppOperationFeedback(
                  key: const Key('acquisition-progress'),
                  label: _progressLabel(
                    context,
                    vm.progress?.phase,
                    commandLineBusy: ref.watch(commandLineBusyProvider),
                  ),
                  detail: vm.progress?.currentItem,
                  progress: vm.progress?.fraction,
                  warnings: [
                    for (final warning in vm.warnings)
                      localizeWorkspaceWarning(context.l10n, warning),
                  ],
                  running: true,
                  cancelLabel: context.l10n.commonCancel,
                ),
              ],
              // Source inspection is the first system Git call, so an unprepared host
              // fails here rather than at install. Without this the suppressed toast
              // would leave the step silently stuck.
              if (vm.failure?.message ==
                  AppFailureMessage.developerToolsRequired) ...[
                const SizedBox(height: 16),
                AcquisitionEnvironmentHint(
                  key: const Key('acquisition-environment-hint'),
                  failure: vm.failure!,
                ),
              ] else if (vm.status == AcquisitionStatus.failure &&
                  vm.failure != null) ...[
                // Stays until the form changes: a toast alone is gone before the
                // user has read which part of the Source to fix.
                const SizedBox(height: 16),
                AppFailureView(
                  key: const Key('acquisition-source-error'),
                  failure: vm.failure!,
                  variant: AppFailureViewVariant.banner,
                  title:
                      vm.failure!.codeKey ==
                          SkillAcquisitionErrorCode.webSourceHasNoSkills.name
                      ? context.l10n.acquisitionErrorWebSourceHasNoSkillsTitle
                      : null,
                  onAction: vm.canInspect
                      ? () => unawaited(vm.inspect())
                      : null,
                ),
              ],
              if (vm.status == AcquisitionStatus.failure)
                SourceWizardWarnings(warnings: vm.warnings),
            ],
          ),
        ),
        if (smart ||
            (state.sourceKindChosen &&
                state.sourceDraft.kind == SkillSourceKind.git))
          AppDialogSection(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            title: smart ? null : context.l10n.acquisitionAdvancedOptions,
            child: smart
                ? SmartSourceAdvancedDisclosure(
                    expanded: state.advancedExpanded,
                    onToggle: vm.toggleAdvanced,
                    child: _gitOptions(context, isBusy),
                  )
                : _gitOptions(context, isBusy),
          ),
      ],
    );
  }

  List<Widget> _smartControls(BuildContext context, bool isBusy) {
    final blank = state.rawInput.trim().isEmpty;
    final detection = state.detection;
    final inspection = state.inspection;
    final showResult = state.smartInspected && inspection != null;
    final candidatesByName = {
      if (inspection != null)
        for (final candidate in inspection.candidates)
          candidate.slotKey: candidate.declaredName,
    };
    return [
      SmartSourceField(
        inputKey: const Key('source-smart-input'),
        value: state.rawInput,
        enabled: !isBusy,
        showPicker: blank || detection == SkillSourceDetection.local,
        onChanged: vm.updateRawInput,
        onSubmitted: _submit,
      ),
      if (showResult) ...[
        const SizedBox(height: 16),
        SmartSourceResultCard(
          kind: inspection.source.kind,
          locator: inspection.source.value,
          candidateCount: inspection.candidates.length,
          preselectedNames: [
            for (final slot in state.preselectedSlots)
              candidatesByName[slot] ?? slot,
          ],
          scopeGlobalPreselected: state.requestGlobalScope,
          preselectedAgentNames: state.requestedAgentIds.contains('*')
              ? const []
              : state.requestedAgentIds,
          unmatchedSkillNames: state.unmatchedSkillNames,
          ignoredFlags: state.ignoredFlags,
        ),
      ],
    ];
  }

  List<Widget> _typedControls(BuildContext context, bool isBusy) {
    final kind = state.sourceKindChosen ? state.sourceDraft.kind : null;
    return [
      // Equal-height cards: the row measures its tallest card and stretches
      // the others to it, which a plain Row cannot do inside a scroll view.
      IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final type in SkillSourceKind.values) ...[
              if (type != SkillSourceKind.values.first)
                const SizedBox(width: 8),
              Expanded(
                child: SourceKindCard(
                  key: Key('source-kind-${type.name}'),
                  type: type,
                  compact: true,
                  selected: kind == type,
                  onTap: isBusy ? null : () => onSourceTypeChanged(type),
                ),
              ),
            ],
          ],
        ),
      ),
      // Nothing below the cards makes sense before a kind is chosen: the
      // locator's label, placeholder, icon, and extra fields all follow it.
      if (kind != null) ...[
        const SizedBox(height: 16),
        SourceLocatorField(
          inputKey: const Key('source-locator'),
          sourceType: kind,
          value: state.sourceDraft.locator,
          onChanged: onLocatorChanged,
          onSubmitted: _submit,
          enabled: !isBusy,
          footnote: context.l10n.acquisitionMultipleSkillsHintV2,
        ),
      ],
    ];
  }

  Widget _gitOptions(BuildContext context, bool isBusy) => Row(
    children: [
      Expanded(
        child: SourceOptionField(
          inputKey: const Key('source-ref'),
          label: context.l10n.acquisitionGitRef,
          hint: context.l10n.acquisitionGitRefHint,
          value: state.sourceDraft.sourceRef,
          onChanged: onSourceRefChanged,
          onSubmitted: _submit,
          enabled: !isBusy,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: SourceOptionField(
          inputKey: const Key('source-subpath'),
          label: context.l10n.acquisitionGitSubpath,
          hint: context.l10n.acquisitionGitSubpathHint,
          value: state.sourceDraft.repositorySubpath,
          onChanged: onRepositorySubpathChanged,
          onSubmitted: _submit,
          enabled: !isBusy,
        ),
      ),
    ],
  );

  void _submit(String _) {
    if (vm.canInspect) unawaited(vm.inspect());
  }

  String _progressLabel(
    BuildContext context,
    AcquisitionPhase? phase, {
    required bool commandLineBusy,
  }) => switch (phase) {
    null || AcquisitionPhase.preparing => context.l10n.acquisitionPreparing,
    AcquisitionPhase.inspecting => context.l10n.acquisitionInspecting,
    AcquisitionPhase.waitingForLock =>
      commandLineBusy
          ? context.l10n.operationWaitingForCommandLine
          : context.l10n.acquisitionWaitingForRepository,
    AcquisitionPhase.planning => context.l10n.acquisitionPlanning,
    AcquisitionPhase.applying => context.l10n.acquisitionApplying,
    AcquisitionPhase.rollingBack => context.l10n.acquisitionRestoring,
    AcquisitionPhase.completed => context.l10n.acquisitionFinishing,
  };
}

// ── Step 2: Select candidates ─────────────────────────────────────────────────

class _Step2Body extends StatelessWidget {
  const _Step2Body({required this.vm});

  final SkillAcquisitionViewModel vm;

  @override
  Widget build(BuildContext context) {
    final inspection = vm.inspection;
    if (inspection == null) return const SizedBox.shrink();
    final candidates = inspection.candidates;
    final skillSelectionState = vm.skillSelectionState;
    final selectAllValue = switch (skillSelectionState) {
      SkillSelectionState.none => false,
      SkillSelectionState.partial => null,
      SkillSelectionState.all => true,
    };

    return AppDialogSection(
      title: context.l10n.acquisitionSkillsFound,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 8),
          Container(
            width: 22,
            height: 18,
            decoration: AppCorners.smooth(
              color: AppPalette.of(context).surfaceMuted,
              radius: 5,
            ),
            alignment: Alignment.center,
            child: Text(
              '${candidates.length}',
              style: AppTypography.of(context).body.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppPalette.of(context).textSecondary,
              ),
            ),
          ),
          if (candidates.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text(
              context.l10n.acquisitionSelectAllSkills,
              style: AppTypography.of(context).caption
                  .copyWith(fontWeight: FontWeight.w400),
            ),
            const SizedBox(width: 8),
            CupertinoCheckbox(
              key: const Key('toggle-all-skills'),
              value: selectAllValue,
              tristate: true,
              semanticLabel: context.l10n.acquisitionSelectAllSkills,
              activeColor: AppPalette.of(context).ink,
              checkColor: AppPalette.of(context).onPrimary,
              onChanged: (_) => vm.toggleAllSkills(
                skillSelectionState != SkillSelectionState.all,
              ),
            ),
          ],
        ],
      ),
      child: Column(
        key: const Key('candidate-list'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (candidates.isEmpty)
            Row(
              children: [
                Icon(
                  LucideIcons.searchX,
                  size: 20,
                  color: AppPalette.of(context).textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  context.l10n.acquisitionNoValidSkills,
                  style: AppTypography.of(context).bodyMuted,
                ),
              ],
            )
          else
            ...candidates.asMap().entries.map((entry) {
              final idx = entry.key;
              final candidate = entry.value;
              final colors = AppPalette.of(context).candidateAccents;
              final color = colors[idx % colors.length];
              final isSelected = vm.selectedSlots.contains(candidate.slotKey);
              if (vm.installedSlotKeys.contains(candidate.slotKey)) {
                return _InstalledCandidateRow(
                  candidate: candidate,
                  color: color,
                  skill: vm.installedSkill(candidate.slotKey),
                );
              }
              return SourceCandidateRow(
                key: Key('candidate-${candidate.slotKey}'),
                declaredName: candidate.declaredName,
                description: candidate.description,
                color: color,
                enabled: true,
                onTap: () => vm.toggleSkill(candidate.slotKey, !isSelected),
                trailing: CupertinoCheckbox(
                  value: isSelected,
                  activeColor: AppPalette.of(context).ink,
                  checkColor: AppPalette.of(context).onPrimary,
                  onChanged: (val) =>
                      vm.toggleSkill(candidate.slotKey, val ?? false),
                ),
              );
            }),
          SourceWizardWarnings(warnings: vm.warnings),
        ],
      ),
    );
  }
}

/// A candidate that a managed Skill already occupies.
///
/// Installing it again fails, because a Slot holds one managed Skill. The row
/// says so up front and opens the installed Skill, where updating it or
/// replacing its Source is one step away.
class _InstalledCandidateRow extends StatelessWidget {
  const _InstalledCandidateRow({
    required this.candidate,
    required this.color,
    required this.skill,
  });

  final SkillCandidate candidate;
  final Color color;
  final WorkspaceSkill? skill;

  @override
  Widget build(BuildContext context) {
    final skill = this.skill;
    return SourceCandidateRow(
      key: Key('candidate-${candidate.slotKey}'),
      declaredName: candidate.declaredName,
      description: candidate.description,
      color: color,
      enabled: false,
      onTap: null,
      disabledReason: context.l10n.acquisitionCandidateInstalled,
      trailing: skill == null
          ? const SizedBox.shrink()
          : AppButton(
              key: Key('candidate-installed-open-${candidate.slotKey}'),
              label: context.l10n.acquisitionOpenInstalledSkill,
              size: NeoButtonSize.small,
              style: NeoButtonVariant.ghost,
              onPressed: () => context.goNamed(
                AppRouteNames.skillDetail,
                pathParameters: {'skillId': skill.id.value},
              ),
            ),
    );
  }
}

// ── Step 3: Activate ──────────────────────────────────────────────────────────

class _Step3Body extends ConsumerWidget {
  const _Step3Body({
    required this.vm,
    required this.scope,
    required this.projectRootId,
    required this.projectRoots,
    required this.onScopeChanged,
    required this.onProjectRootChanged,
    required this.onManageProjectRoots,
    required this.onAddAgent,
  });

  final SkillAcquisitionViewModel vm;
  final SkillActivationScope scope;
  final String? projectRootId;
  final List<SkillProjectRoot> projectRoots;
  final ValueChanged<SkillActivationScope> onScopeChanged;
  final ValueChanged<String> onProjectRootChanged;
  final VoidCallback onManageProjectRoots;
  final VoidCallback? onAddAgent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(deviceAgentMembersProvider);
    final currentMembers = membership.value;
    if (currentMembers != null &&
        !_sameIds(currentMembers, vm.memberIds ?? const {})) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          final latest = ref.read(deviceAgentMembersProvider).value;
          if (latest != null && !_sameIds(latest, vm.memberIds ?? const {})) {
            vm.reconcileAgentMembership(latest);
          }
        }
      });
    }
    final groups = vm.visibleLocations;
    final selectedCount = groups
        .where((g) => vm.selectedLocations.contains(g.key))
        .length;
    final scopeSelection = switch ((scope, projectRootId)) {
      (SkillActivationScope.project, final String rootId) => ProjectSkillScope(
        rootId,
      ),
      _ => const GlobalSkillScope(),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppDialogSection(
          title: context.l10n.acquisitionActivationScopeTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkillScopeMenu(
                keyPrefix: 'acquisition-scope',
                alignment: MorphingMenuAlignment.start,
                selection: scopeSelection,
                projectRoots: projectRoots,
                onManageProjects: onManageProjectRoots,
                onSelected: (selection) {
                  switch (selection) {
                    case GlobalSkillScope():
                      onScopeChanged(SkillActivationScope.global);
                    case ProjectSkillScope(:final rootId):
                      onProjectRootChanged(rootId);
                    case InactiveSkillScope():
                      break;
                  }
                },
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => vm.setStoreOnly(!vm.storeOnly),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    CupertinoCheckbox(
                      value: vm.storeOnly,
                      activeColor: AppPalette.of(context).ink,
                      onChanged: (value) => vm.setStoreOnly(value ?? false),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.acquisitionStoreOnly,
                      style: AppTypography.of(context).control.copyWith(
                        fontWeight: FontWeight.w400,
                        color: AppPalette.of(context).bodyContent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // AGENTS section
        if (!vm.storeOnly)
          AppDialogSection(
            title: context.l10n.acquisitionAgents,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 6),
                Text(
                  context.l10n.acquisitionDetectedCount(
                    vm.agents
                        .where(
                          (agent) => agent.detected && agent.id != 'universal',
                        )
                        .length,
                  ),
                  key: const Key('detected-agent-count'),
                  style: AppTypography.of(context).body
                      .copyWith(fontSize: 13, fontWeight: FontWeight.w600)
                      .copyWith(
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                        color: AppPalette.of(context).textSecondary,
                      ),
                ),
                const SizedBox(width: 12),
                AgentActivationSwitch(
                  key: const Key('toggle-all-locations'),
                  on: groups.isNotEmpty && selectedCount == groups.length,
                  label: context.l10n.activationAllAgentsToggle,
                  onChanged: vm.loadingTargets || vm.isBusy || groups.isEmpty
                      ? null
                      : (value) => vm.selectAllLocations(
                          value,
                          visibleKeys: groups.map((g) => g.key),
                        ),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                if (vm.loadingTargets || membership.isLoading)
                  const Center(child: CupertinoActivityIndicator())
                else if (membership.hasError)
                  AppButton(
                    label: context.l10n.commonRetry,
                    onPressed: () {
                      ref
                          .read(activationCatalogRevisionProvider.notifier)
                          .refresh();
                      if (ref.read(appSettingsViewModelProvider).errorCode ==
                          'settings_load_failed') {
                        ref.read(appSettingsViewModelProvider.notifier).load();
                      }
                    },
                  )
                else if (vm.failure?.operationKey ==
                    WorkspaceOperationKind.inspectActivationTargets.name)
                  AppButton(
                    label: context.l10n.commonRetry,
                    onPressed: vm.retryTargets,
                  )
                else
                  Column(
                    children: [
                      for (final group in groups)
                        _AgentActivateRow(
                          key: ValueKey(group.key),
                          group: group,
                          isOn: vm.selectedLocations.contains(group.key),
                          onToggle: vm.isBusy
                              ? null
                              : (value) => vm.toggleLocation(group.key, value),
                        ),
                      _AddAgentPlaceholderRow(onPressed: onAddAgent),
                    ],
                  ),
              ],
            ),
          ),
        if (vm.status == AcquisitionStatus.installing ||
            vm.failure != null ||
            (vm.status == AcquisitionStatus.success && vm.warnings.isNotEmpty))
          AppDialogSection(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (vm.status == AcquisitionStatus.installing) ...[
                  const SizedBox(height: 20),
                  AppOperationFeedback(
                    label: context.l10n.acquisitionInstalling,
                    detail: vm.progress?.currentItem,
                    progress: vm.progress?.fraction,
                    warnings: [
                      for (final warning in vm.warnings)
                        localizeWorkspaceWarning(context.l10n, warning),
                    ],
                    running: true,
                    cancelLabel: context.l10n.commonCancel,
                  ),
                ],
                if (vm.failure != null) ...[
                  const SizedBox(height: 16),
                  if (vm.failure!.message ==
                      AppFailureMessage.developerToolsRequired)
                    AcquisitionEnvironmentHint(
                      key: const Key('acquisition-environment-hint'),
                      failure: vm.failure!,
                    )
                  else
                    _InstallFailureBanner(vm: vm, failure: vm.failure!),
                  SourceWizardWarnings(warnings: vm.warnings),
                ],
                if (vm.status == AcquisitionStatus.success &&
                    vm.warnings.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  AppOperationFeedback(
                    label: context.l10n.operationSucceeded,
                    warnings: [
                      for (final warning in vm.warnings)
                        localizeWorkspaceWarning(context.l10n, warning),
                    ],
                    cancelLabel: context.l10n.commonCancel,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// The install step's failure, with an action that matches what it says.
///
/// The recovery label comes from the failure's policy, so the action must
/// follow it too: "Refresh" re-inspects the Source rather than replaying the
/// same install, and an occupied Slot leads to Replace Source.
class _InstallFailureBanner extends StatelessWidget {
  const _InstallFailureBanner({required this.vm, required this.failure});

  final SkillAcquisitionViewModel vm;
  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    if (failure.codeKey == WorkspaceErrorCode.sourceReplacementRequired.name) {
      final slotKey = failure.context['slotKey'];
      final skill = slotKey is String ? vm.installedSkill(slotKey) : null;
      return AppFailureView(
        key: const Key('acquisition-install-error'),
        failure: failure,
        variant: AppFailureViewVariant.banner,
        actionKey: const Key('acquisition-replace-source'),
        actionLabel: skill == null ? null : context.l10n.workspaceReplaceSource,
        actionIcon: LucideIcons.link2,
        onAction: skill == null
            ? null
            : () => context.goNamed(
                AppRouteNames.replaceSource,
                pathParameters: {'skillId': skill.id.value},
              ),
      );
    }
    return AppFailureView(
      key: const Key('acquisition-install-error'),
      failure: failure,
      variant: AppFailureViewVariant.banner,
      onAction: switch (failure.recoveryPolicy) {
        AppRecoveryPolicy.none => null,
        AppRecoveryPolicy.retryExplicitly => () => unawaited(vm.install()),
        AppRecoveryPolicy.refresh ||
        AppRecoveryPolicy.refreshThenReview => () => unawaited(vm.reinspect()),
      },
    );
  }
}

bool _sameIds(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);

class _AgentActivateRow extends StatelessWidget {
  const _AgentActivateRow({
    super.key,
    required this.group,
    required this.isOn,
    required this.onToggle,
  });

  final ActivationLocationGroup group;
  final bool isOn;
  final ValueChanged<bool>? onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppPalette.of(context).border),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: AgentActivationGroupLabel(group: group)),
          const SizedBox(width: 12),
          AgentActivationSwitch(
            key: Key('location-${group.location}'),
            label:
                '${activationAgentGroupTitle(context, group)} ${group.location}',
            on: isOn,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

class _AddAgentPlaceholderRow extends StatelessWidget {
  const _AddAgentPlaceholderRow({required this.onPressed});
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppButton(
          key: const Key('add-agent'),
          label: context.l10n.agentsManage,
          size: NeoButtonSize.small,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

// ── Wizard Footer ─────────────────────────────────────────────────────────────

class _WizardFooter extends StatelessWidget {
  const _WizardFooter({
    required this.step,
    required this.smartInspected,
    required this.vm,
    required this.onBack,
    required this.onContinue,
    required this.onClose,
  });

  final int step;
  final bool smartInspected;
  final SkillAcquisitionViewModel vm;
  final VoidCallback onBack;
  final Future<void> Function() onContinue;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isBusy = vm.isBusy;
    final selectedCount = vm.selectedSlots.length;

    // A failure that offers no recovery (the address simply holds no Skills)
    // keeps the check disabled until the input changes; retrying the same
    // address would only repeat it.
    final failureBlocksInspect =
        vm.status == AcquisitionStatus.failure &&
        vm.failure?.recoveryPolicy == AppRecoveryPolicy.none;
    final primaryEnabled = switch (step) {
      1 when smartInspected => !isBusy,
      1 => vm.canInspect && !failureBlocksInspect,
      2 => !isBusy && vm.selectedSlots.isNotEmpty,
      _ => !isBusy && vm.canInstall,
    };

    return AppDialogFooter(
      leading: step == 1
          ? Text(
              context.l10n.acquisitionStep(1),
              style: AppTypography.of(context).control.copyWith(
                fontWeight: FontWeight.w500,
                color: AppPalette.of(context).textSecondary,
              ),
            )
          : AppButton(
              label: context.l10n.commonBack,
              icon: LucideIcons.chevronLeft,
              style: NeoButtonVariant.ghost,
              onPressed: isBusy ? null : onBack,
            ),
      actions: [
        if (isBusy)
          AppButton(
            key: const Key('cancel-acquisition'),
            label: context.l10n.commonCancel,
            onPressed: () => unawaited(vm.cancel()),
          )
        else
          AppButton(
            key: const Key('close-acquisition'),
            label: vm.status == AcquisitionStatus.success
                ? context.l10n.commonDone
                : context.l10n.commonCancel,
            onPressed: onClose,
          ),
        if (vm.status != AcquisitionStatus.success)
          AppButton(
            key: switch (step) {
              1 when !smartInspected => const Key('inspect-source'),
              1 || 2 => const Key('continue-acquisition'),
              _ => const Key('install-skills'),
            },
            label: switch (step) {
              1 when !smartInspected => context.l10n.acquisitionInspect,
              1 || 2 => context.l10n.commonContinue,
              _ => context.l10n.acquisitionInstall(
                selectedCount,
                selectedCount == 1 ? '' : 's',
              ),
            },
            icon: switch (step) {
              1 when !smartInspected => LucideIcons.search,
              1 || 2 => LucideIcons.arrowRight,
              _ => LucideIcons.arrowDownToLine,
            },
            style: NeoButtonVariant.primary,
            // The install step owns the spinner so the button reads as
            // working rather than merely disabled while the install runs.
            loading: step == 3 && isBusy,
            onPressed: primaryEnabled ? () => unawaited(onContinue()) : null,
          ),
      ],
    );
  }
}
