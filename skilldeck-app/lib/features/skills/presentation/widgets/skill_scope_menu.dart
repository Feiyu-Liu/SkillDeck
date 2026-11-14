import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';

sealed class SkillScopeSelection {
  const SkillScopeSelection();
}

final class GlobalSkillScope extends SkillScopeSelection {
  const GlobalSkillScope();
}

final class ProjectSkillScope extends SkillScopeSelection {
  const ProjectSkillScope(this.rootId);
  final String rootId;
}

final class InactiveSkillScope extends SkillScopeSelection {
  const InactiveSkillScope();
}

/// Controlled presentation. Each page owns its selection and navigation.
class SkillScopeMenu extends StatelessWidget {
  const SkillScopeMenu({
    required this.selection,
    required this.projectRoots,
    required this.onSelected,
    required this.onManageProjects,
    this.includeInactive = false,
    this.iconOnly = false,
    this.compact = false,
    this.collapsedRadius,
    this.alignment = MorphingMenuAlignment.end,
    this.keyPrefix = 'scope',
    super.key,
  });

  final SkillScopeSelection selection;
  final List<SkillProjectRoot> projectRoots;
  final ValueChanged<SkillScopeSelection> onSelected;
  final VoidCallback onManageProjects;
  final bool includeInactive;
  final bool iconOnly;
  final bool compact;
  final double? collapsedRadius;
  final MorphingMenuAlignment alignment;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final menuStyle = SkillsButtonTheme.morphingMenuFor(context).style;
    final rootId = switch (selection) {
      ProjectSkillScope(:final rootId) => rootId,
      _ => null,
    };
    final root = projectRoots.where((r) => r.id == rootId).firstOrNull;
    final label = switch (selection) {
      InactiveSkillScope() => context.l10n.activationInactive,
      ProjectSkillScope() when root != null => p.basename(
        p.normalize(root.path),
      ),
      _ => context.l10n.commonGlobal,
    };
    final icon = switch (selection) {
      InactiveSkillScope() => LucideIcons.circleOff,
      ProjectSkillScope() => LucideIcons.folder,
      _ => LucideIcons.globe2,
    };
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: iconOnly ? AppSizes.controlHeight : 220,
      ),
      child: MorphingMenuButton(
        key: Key('$keyPrefix-selector'),
        icon: icon,
        label: iconOnly ? null : label,
        semanticsLabel: label,
        enableDragResize: false,
        alignment: alignment,
        direction: MorphingMenuDirection.down,
        expandedWidth: 320,
        expandedHeight:
            ((projectRoots.length + (includeInactive ? 3 : 2)) * 38 + 34)
                .clamp(110, 340)
                .toDouble(),
        style: menuStyle.copyWith(
          collapsedRadius: collapsedRadius,
          buttonHeight: AppSizes.controlHeight,
          minButtonWidth: AppSizes.controlHeight,
          triggerPadding: EdgeInsets.symmetric(
            // Icon-only centres the glyph in a controlHeight circle.
            horizontal: iconOnly
                ? (AppSizes.controlHeight - menuStyle.iconSize) / 2
                : (compact ? 11 : 10),
          ),
          textStyle: compact
              ? AppTypography.of(context).control.copyWith(fontSize: 12.5)
              : AppTypography.of(context).control,
        ),
        contentBuilder: (menuContext, close) => SingleChildScrollView(
          child: Column(
            children: [
              AppMorphingMenuOption(
                key: Key('$keyPrefix-option-global'),
                label: context.l10n.commonGlobal,
                selected: selection is GlobalSkillScope,
                leading: const Icon(LucideIcons.globe2, size: 16),
                onPressed: () {
                  onSelected(const GlobalSkillScope());
                  close();
                },
              ),
              const AppMorphingMenuDivider(),
              for (final project in projectRoots)
                AppTooltip(
                  message: project.path,
                  maxWidth: 420,
                  maxLines: null,
                  child: AppMorphingMenuOption(
                    key: Key('$keyPrefix-option-project-${project.id}'),
                    label: p.basename(p.normalize(project.path)),
                    selected: rootId == project.id,
                    leading: const Icon(LucideIcons.folder, size: 16),
                    onPressed: () {
                      onSelected(ProjectSkillScope(project.id));
                      close();
                    },
                  ),
                ),
              AppMorphingMenuOption(
                key: Key('$keyPrefix-option-manage-project-roots'),
                label: context.l10n.acquisitionManageProjectRoots,
                selected: false,
                leading: const Icon(LucideIcons.folderCog, size: 16),
                onPressed: () {
                  close();
                  onManageProjects();
                },
              ),
              if (includeInactive) ...[
                const AppMorphingMenuDivider(),
                AppMorphingMenuOption(
                  key: Key('$keyPrefix-option-inactive'),
                  label: context.l10n.activationInactive,
                  selected: selection is InactiveSkillScope,
                  leading: const Icon(LucideIcons.circleOff, size: 16),
                  onPressed: () {
                    onSelected(const InactiveSkillScope());
                    close();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
