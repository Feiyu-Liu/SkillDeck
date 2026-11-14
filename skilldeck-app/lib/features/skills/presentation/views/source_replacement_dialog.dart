import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_activity.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_browser_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_operations_view_model.dart';
import 'package:skills_manager/features/skills/presentation/view_models/source_replacement_view_model.dart';
import 'package:skills_manager/features/skills/presentation/widgets/smart_source_controls.dart';
import 'package:skills_manager/features/skills/presentation/widgets/source_form_controls.dart';
import 'package:skills_manager/features/skills/presentation/widgets/source_wizard_chrome.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';
import 'package:skills_manager/shared/widgets/app_operation_feedback.dart';

/// Resolves the routed `:skillId` to its [InstalledSkill] before rendering
/// [SourceReplacementDialog], the same shape [RemoveSkillDialogRoute] in
/// `skill_workspace_panel.dart` uses — replacing a Source is reached by
/// pushing a named route, exactly like Add Skill, not by popping an
/// imperative overlay.
class SourceReplacementDialogRoute extends ConsumerWidget {
  const SourceReplacementDialogRoute({required this.skillId, super.key});

  final WorkspaceSkillId skillId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(skillBrowserCatalogProvider).skills;
    InstalledSkill? skill;
    for (final candidate in skills) {
      if (candidate.id == skillId) {
        skill = candidate;
        break;
      }
    }
    if (skill != null) return SourceReplacementDialog(skill: skill);
    return AppCupertinoDialogSurface(
      width: AppDialogWidths.confirm,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.workspaceSkillNotFound,
              style: AppTypography.of(context).title,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.errorSkillNotFound,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppPalette.of(context).textSecondary),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: context.l10n.commonClose,
              style: NeoButtonVariant.primary,
              onPressed: context.pop,
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a replacement Source for an already installed Skill, walking the
/// same three questions the Add Skill wizard does — Source, then which Skill
/// in it, then act — because replacing a Source is really installing from a
/// new place onto an existing Skill Slot, not a single form. Reuses
/// [SourceKindCard] / [SourceLocatorField] for step 1 and [SourceWizardStepper]
/// / [SourceCandidateRow] / [SourceWizardWarnings] for the chrome shared with
/// the Add Skill wizard.
class SourceReplacementDialog extends ConsumerStatefulWidget {
  const SourceReplacementDialog({required this.skill, super.key});

  final InstalledSkill skill;

  @override
  ConsumerState<SourceReplacementDialog> createState() =>
      _SourceReplacementDialogState();
}

class _SourceReplacementDialogState
    extends ConsumerState<SourceReplacementDialog> {
  SourceReplacementViewModel get _vm =>
      ref.read(sourceReplacementViewModelProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _vm.begin(widget.skill);
    });
  }

  Future<void> _onContinue(SourceReplacementState state) async {
    switch (state.step) {
      case ReplacementStep.source:
        await _vm.inspect();
      case ReplacementStep.select:
        _vm.continueToReplace();
      case ReplacementStep.replace:
        final outcome = await _vm.replace();
        if (!mounted) return;
        if (outcome == ReplaceSourceOutcome.replaced ||
            outcome == ReplaceSourceOutcome.pending) {
          context.pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final replacement = ref.watch(sourceReplacementViewModelProvider);
    final operations = ref.watch(skillOperationsViewModelProvider);
    final replacing = operations.operation.running;
    final isBusy = replacement.step == ReplacementStep.replace
        ? replacing
        : replacement.isBusy;

    return PopScope(
      canPop: !isBusy,
      child: AppDialogScaffold(
        key: const Key('source-replacement-dialog'),
        width: AppDialogWidths.wide,
        onEscape: isBusy ? null : context.pop,
        header: _Header(
          step: replacement.step.index + 1,
          onClose: isBusy ? null : context.pop,
        ),
        sections: [
          _WizardBody(
            skill: widget.skill,
            state: replacement,
            operations: operations,
            vm: _vm,
          ),
        ],
        footer: _Footer(
          state: replacement,
          isBusy: isBusy,
          onBack: _vm.back,
          onContinue: () => _onContinue(replacement),
          onCancel: () => unawaited(_vm.cancel()),
          onClose: () => context.pop(),
        ),
      ),
    );
  }
}

// ── Header (title + stepper) ─────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.step, required this.onClose});

  final int step;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => AppDialogHeader(
    icon: LucideIcons.arrowLeftRight,
    title: context.l10n.workspaceReplaceSourceTitle,
    subtitle: context.l10n.workspaceReplaceSourceDescription,
    below: SourceWizardStepper(
      currentStep: step,
      labels: [
        context.l10n.acquisitionSource,
        context.l10n.acquisitionSelect,
        context.l10n.workspaceReplaceSourceStepReplace,
      ],
    ),
    actions: [
      appDialogCloseButton(
        context,
        key: const Key('source-replacement-close-button'),
        onPressed: onClose,
      ),
    ],
  );
}

class _WizardBody extends StatelessWidget {
  const _WizardBody({
    required this.skill,
    required this.state,
    required this.operations,
    required this.vm,
  });

  final InstalledSkill skill;
  final SourceReplacementState state;
  final SkillOperationsState operations;
  final SourceReplacementViewModel vm;

  @override
  Widget build(BuildContext context) {
    return switch (state.step) {
      ReplacementStep.source => _SourceStepBody(state: state, vm: vm),
      ReplacementStep.select => _SelectStepBody(
        skill: skill,
        state: state,
        vm: vm,
      ),
      ReplacementStep.replace => _ReplaceStepBody(
        skill: skill,
        state: state,
        operations: operations,
      ),
    };
  }
}

// ── Step 1: Source ────────────────────────────────────────────────────────────

class _SourceStepBody extends StatelessWidget {
  const _SourceStepBody({required this.state, required this.vm});

  final SourceReplacementState state;
  final SourceReplacementViewModel vm;

  // Mirrors the Add Skill Source step: the same mode switch, paste box,
  // kind cards and advanced options, so the two wizards read as one.
  @override
  Widget build(BuildContext context) {
    final isBusy = state.isBusy;
    final smart = state.inputMode == SkillSourceInputMode.smart;
    final kind = state.sourceKindChosen ? state.sourceDraft.kind : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppDialogSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              const SizedBox(height: 20),
              if (smart)
                ..._smartControls(isBusy)
              else
                ..._typedControls(kind, isBusy),
              if (isBusy) ...[
                const SizedBox(height: 20),
                AppOperationFeedback(
                  key: const Key('source-replacement-progress'),
                  label: _progressLabel(context, state.progress?.phase),
                  detail: state.progress?.currentItem,
                  progress: state.progress?.fraction,
                  warnings: [
                    for (final warning in state.warnings)
                      localizeWorkspaceWarning(context.l10n, warning),
                  ],
                  running: true,
                  cancelLabel: context.l10n.commonCancel,
                ),
              ],
            ],
          ),
        ),
        if (smart || kind == SkillSourceKind.git)
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

  List<Widget> _smartControls(bool isBusy) {
    final blank = state.rawInput.trim().isEmpty;
    final detection = state.detection;
    return [
      SmartSourceField(
        inputKey: const Key('source-replacement-smart-input'),
        value: state.rawInput,
        enabled: !isBusy,
        showPicker: blank || detection == SkillSourceDetection.local,
        onChanged: vm.updateRawInput,
        onSubmitted: _submit,
      ),
    ];
  }

  List<Widget> _typedControls(SkillSourceKind? kind, bool isBusy) => [
    // Equal-height cards, as in Add Skill.
    IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in SkillSourceKind.values) ...[
            if (option != SkillSourceKind.values.first)
              const SizedBox(width: 8),
            Expanded(
              child: SourceKindCard(
                key: Key('source-replacement-kind-${option.name}'),
                type: option,
                compact: true,
                selected: kind == option,
                onTap: isBusy ? null : () => vm.selectSourceKind(option),
              ),
            ),
          ],
        ],
      ),
    ),
    if (kind != null) ...[
      const SizedBox(height: 16),
      SourceLocatorField(
        inputKey: const Key('source-replacement-locator'),
        sourceType: kind,
        value: state.sourceDraft.locator,
        onChanged: vm.updateLocator,
        onSubmitted: _submit,
        enabled: !isBusy,
      ),
    ],
  ];

  Widget _gitOptions(BuildContext context, bool isBusy) => Row(
    children: [
      Expanded(
        child: SourceOptionField(
          inputKey: const Key('source-replacement-ref'),
          label: context.l10n.acquisitionGitRef,
          hint: context.l10n.acquisitionGitRefHint,
          value: state.sourceDraft.sourceRef,
          onChanged: vm.updateSourceRef,
          onSubmitted: _submit,
          enabled: !isBusy,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: SourceOptionField(
          inputKey: const Key('source-replacement-subpath'),
          label: context.l10n.acquisitionGitSubpath,
          hint: context.l10n.acquisitionGitSubpathHint,
          value: state.sourceDraft.repositorySubpath,
          onChanged: vm.updateRepositorySubpath,
          onSubmitted: _submit,
          enabled: !isBusy,
        ),
      ),
    ],
  );

  void _submit(String _) {
    if (state.canInspect) unawaited(vm.inspect());
  }

  String _progressLabel(BuildContext context, AcquisitionPhase? phase) =>
      switch (phase) {
        null || AcquisitionPhase.preparing => context.l10n.acquisitionPreparing,
        AcquisitionPhase.inspecting => context.l10n.acquisitionInspecting,
        AcquisitionPhase.waitingForLock =>
          context.l10n.acquisitionWaitingForRepository,
        AcquisitionPhase.planning => context.l10n.acquisitionPlanning,
        AcquisitionPhase.applying => context.l10n.acquisitionApplying,
        AcquisitionPhase.rollingBack => context.l10n.acquisitionRestoring,
        AcquisitionPhase.completed => context.l10n.acquisitionFinishing,
      };
}

// ── Step 2: Select the matching Skill ────────────────────────────────────────

class _SelectStepBody extends StatelessWidget {
  const _SelectStepBody({
    required this.skill,
    required this.state,
    required this.vm,
  });

  final InstalledSkill skill;
  final SourceReplacementState state;
  final SourceReplacementViewModel vm;

  @override
  Widget build(BuildContext context) {
    final inspection = state.inspection;
    if (inspection == null) return const SizedBox.shrink();
    final candidates = inspection.candidates;

    return AppDialogSection(
      title: context.l10n.acquisitionSkillsFound,
      trailing: Container(
        width: 22,
        height: 18,
        decoration: AppCorners.smooth(
          color: AppPalette.of(context).surfaceMuted,
          radius: 5,
        ),
        alignment: Alignment.center,
        child: Text(
          '${candidates.length}',
          style: AppTypography.of(context).body
              .copyWith(fontSize: 13, fontWeight: FontWeight.w600)
              .copyWith(
                letterSpacing: 0,
                color: AppPalette.of(context).textSecondary,
              ),
        ),
      ),
      child: Column(
        key: const Key('replacement-candidate-list'),
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
          else if (!candidates.any((c) => c.slotKey == skill.slotKey))
            Row(
              children: [
                Icon(
                  LucideIcons.searchX,
                  size: 20,
                  color: AppPalette.of(context).textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.workspaceReplaceSourceNoMatch(
                      skill.displayName,
                    ),
                    style: AppTypography.of(context).bodyMuted,
                  ),
                ),
              ],
            )
          else
            ...candidates.asMap().entries.map((entry) {
              final idx = entry.key;
              final candidate = entry.value;
              final colors = AppPalette.of(context).candidateAccents;
              final color = colors[idx % colors.length];
              final enabled = candidate.slotKey == skill.slotKey;
              final isSelected = state.selectedSlotKey == candidate.slotKey;
              return SourceCandidateRow(
                key: Key('replacement-candidate-${candidate.slotKey}'),
                declaredName: candidate.declaredName,
                description: candidate.description,
                color: color,
                enabled: enabled,
                disabledReason: enabled
                    ? null
                    : context.l10n.workspaceReplaceSourceMismatch,
                onTap: () => vm.selectCandidate(candidate.slotKey),
                trailing: Icon(
                  isSelected ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 18,
                  color: isSelected
                      ? AppPalette.of(context).ink
                      : AppPalette.of(context).textSecondary,
                ),
              );
            }),
          SourceWizardWarnings(warnings: state.warnings),
        ],
      ),
    );
  }
}

// ── Step 3: Replace ──────────────────────────────────────────────────────────

class _ReplaceStepBody extends ConsumerWidget {
  const _ReplaceStepBody({
    required this.skill,
    required this.state,
    required this.operations,
  });

  final InstalledSkill skill;
  final SourceReplacementState state;
  final SkillOperationsState operations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final source = state.inspection?.source;
    final progress = operations.operation.progress;
    final running = operations.operation.running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppDialogSection(
          title: l10n.acquisitionSource,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SourceSummaryRow(
                label: l10n.workspaceReplaceSourceCurrent,
                value: skill.source?.locator ?? '',
              ),
              Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  LucideIcons.arrowDown,
                  size: 16,
                  color: AppPalette.of(context).textSecondary,
                ),
              ),
              _SourceSummaryRow(
                label: l10n.workspaceReplaceSourceNew,
                value: source?.value ?? '',
              ),
            ],
          ),
        ),
        AppDialogSection(
          child: Column(
            children: [
              AppDialogNote(
                tone: AppDialogTone.success,
                text: l10n.workspaceReplaceSourceFound(skill.displayName),
              ),
              const SizedBox(height: 12),
              AppDialogNote(
                tone: AppDialogTone.warning,
                text: l10n.commandLineApprovalReplaceSourceWarning,
              ),
            ],
          ),
        ),
        if (running) ...[
          const SizedBox(height: 20),
          AppDialogSection(
            child: AppOperationFeedback(
              key: const Key('source-replacement-operation'),
              label: progress != null
                  ? localizeWorkspacePhase(
                      l10n,
                      progress.phase,
                      commandLineBusy: ref.watch(commandLineBusyProvider),
                    )
                  : l10n.workspaceReplacing,
              detail: progress?.currentItem,
              progress: progress?.fraction,
              warnings: [
                for (final warning in operations.operation.warnings)
                  localizeWorkspaceWarning(l10n, warning),
              ],
              running: true,
              cancelLabel: l10n.commonCancel,
            ),
          ),
        ],
      ],
    );
  }
}

class _SourceSummaryRow extends StatelessWidget {
  const _SourceSummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.of(context).body
              .copyWith(fontSize: 13, fontWeight: FontWeight.w600)
              .copyWith(color: AppPalette.of(context).textSecondary),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: AppTypography.of(context).mono
              .copyWith(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.state,
    required this.isBusy,
    required this.onBack,
    required this.onContinue,
    required this.onCancel,
    required this.onClose,
  });

  final SourceReplacementState state;
  final bool isBusy;
  final VoidCallback onBack;
  final Future<void> Function() onContinue;
  final VoidCallback onCancel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final primaryEnabled = switch (state.step) {
      ReplacementStep.source => !isBusy && state.canInspect,
      ReplacementStep.select => !isBusy && state.canContinueToReplace,
      ReplacementStep.replace => !isBusy,
    };

    return LayoutBuilder(
      builder: (context, constraints) => AppDialogFooter(
        leading: state.step == ReplacementStep.source
            ? Text(
                context.l10n.acquisitionStep(1),
                style: AppTypography.of(context).caption,
              )
            : AppButton(
                label: l10n.commonBack,
                icon: LucideIcons.chevronLeft,
                style: NeoButtonVariant.ghost,
                onPressed: isBusy ? null : onBack,
              ),
        actions: [
          ConstrainedBox(
            // Keep Back/the step status readable while long actions wrap.
            // This includes the footer padding, gaps and its leading spacer.
            constraints: BoxConstraints(maxWidth: constraints.maxWidth - 210),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                if (isBusy)
                  AppButton(
                    key: const Key('cancel-source-replacement'),
                    label: l10n.commonCancel,
                    onPressed: onCancel,
                  )
                else
                  AppButton(
                    key: const Key('cancel-source-replacement'),
                    label: l10n.commonCancel,
                    onPressed: onClose,
                  ),
                AppButton(
                  key: switch (state.step) {
                    ReplacementStep.source => const Key(
                      'inspect-replacement-source',
                    ),
                    ReplacementStep.select => const Key(
                      'continue-source-replacement',
                    ),
                    ReplacementStep.replace => const Key(
                      'confirm-source-replacement',
                    ),
                  },
                  label: state.step == ReplacementStep.replace
                      ? l10n.workspaceReplaceSourceConfirm
                      : l10n.commonContinue,
                  icon: state.step == ReplacementStep.replace
                      ? LucideIcons.link2
                      : LucideIcons.arrowRight,
                  style: NeoButtonVariant.primary,
                  onPressed: primaryEnabled
                      ? () => unawaited(onContinue())
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
