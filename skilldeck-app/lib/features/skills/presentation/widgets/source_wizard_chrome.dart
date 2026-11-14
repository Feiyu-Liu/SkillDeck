import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/l10n/workspace_operation_l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// Shared chrome for the source-driven wizards — Add Skill and Replace
/// Source. Both walk a Source through inspection and candidate selection
/// before acting on it, so the step indicator, candidate row, and warning
/// list are the single definition of that shared shape; each dialog supplies
/// its own step labels, trailing selector, and callbacks.

class SourceWizardStepper extends StatelessWidget {
  const SourceWizardStepper({
    required this.currentStep,
    required this.labels,
    super.key,
  });

  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final index = i + 1;
      if (i > 0) children.add(const _StepConnector());
      children.add(
        _StepItem(index: index, label: labels[i], currentStep: currentStep),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.index,
    required this.label,
    required this.currentStep,
  });

  final int index;
  final String label;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final isDone = currentStep > index;
    final isActive = currentStep == index;
    final bgColor = (isDone || isActive)
        ? AppPalette.of(context).ink
        : AppPalette.of(context).surfaceMuted;
    final labelColor = (isDone || isActive)
        ? AppPalette.of(context).ink
        : AppPalette.of(context).textSecondary;
    final labelWeight = isActive ? FontWeight.w600 : FontWeight.w500;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: isDone
              ? Icon(
                  LucideIcons.check,
                  size: 13,
                  color: AppPalette.of(context).onPrimary,
                )
              : Text(
                  '0$index',
                  style: AppTypography.of(context).sectionLabel.copyWith(
                    color: isActive
                        ? AppPalette.of(context).onPrimary
                        : AppPalette.of(context).textSecondary,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTypography.of(context).control
              .copyWith(fontWeight: labelWeight, color: labelColor),
        ),
      ],
    );
  }
}

class _StepConnector extends StatelessWidget {
  const _StepConnector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: AppPalette.of(context).borderStrong,
    );
  }
}

/// One row in a Source's candidate list. [enabled] false renders the row
/// dimmed and unresponsive to taps, with [disabledReason] explaining why —
/// used by Replace Source to gray out candidates that are not the Skill
/// being replaced.
class SourceCandidateRow extends StatelessWidget {
  const SourceCandidateRow({
    required this.declaredName,
    required this.description,
    required this.color,
    required this.enabled,
    required this.onTap,
    required this.trailing,
    this.disabledReason,
    super.key,
  });

  final String declaredName;
  final String description;
  final Color color;
  final bool enabled;
  final VoidCallback? onTap;
  final Widget trailing;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppPalette.of(context).border),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: AppCorners.smooth(
                  color: color.withValues(alpha: 0.12),
                  radius: 8,
                ),
                alignment: Alignment.center,
                child: Text(
                  declaredName.isNotEmpty ? declaredName[0].toUpperCase() : '?',
                  style: AppTypography.of(context).body
                      .copyWith(fontWeight: FontWeight.w700, color: color),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      declaredName,
                      style: AppTypography.of(context).body
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.of(context).control.copyWith(
                          fontWeight: FontWeight.w400,
                          color: AppPalette.of(context).textSecondary,
                        ),
                      ),
                    ],
                    if (disabledReason != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        disabledReason!,
                        style: AppTypography.of(context).caption.copyWith(
                          fontWeight: FontWeight.w400,
                          color: AppPalette.of(context).textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class SourceWizardWarnings extends StatelessWidget {
  const SourceWizardWarnings({required this.warnings, super.key});

  final List<WorkspaceWarning> warnings;

  @override
  Widget build(BuildContext context) {
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    LucideIcons.triangleAlert,
                    size: 14,
                    color: AppPalette.of(context).warning,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      localizeWorkspaceWarning(context.l10n, warning),
                      style: AppTypography.of(context).caption
                          .copyWith(fontWeight: FontWeight.w400),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
