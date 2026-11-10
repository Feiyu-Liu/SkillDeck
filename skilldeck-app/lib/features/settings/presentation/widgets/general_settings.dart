import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/project_roots_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';

/// Interface language, the global activation method, and project roots.
class GeneralSettings extends ConsumerWidget {
  const GeneralSettings({required this.showSectionHeader, super.key});

  final bool showSectionHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final appSettings = ref.watch(appSettingsViewModelProvider);
    final settingsVm = ref.read(appSettingsViewModelProvider.notifier);
    final method = appSettings.settings.globalActivationMethod;
    return Column(
      key: const Key('general-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSectionHeader) ...[
          SettingsSectionHeader(
            title: l10n.settingsGeneralTitle,
            description: l10n.settingsGeneralDescription,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        SettingsGroup(
          label: l10n.settingsLanguageGroup,
          children: [
            SettingsRow(
              title: l10n.settingsInterfaceLanguage,
              description: l10n.settingsLanguageDescription,
              trailing: AppSegmentedControl<AppLocalePreference>(
                key: const Key('interface-language-control'),
                value: appSettings.settings.localePreference,
                segments: {
                  AppLocalePreference.system: l10n.settingsFollowSystem,
                  AppLocalePreference.zh: l10n.settingsChinese,
                  AppLocalePreference.en: l10n.settingsEnglish,
                },
                onChanged: settingsVm.setLocalePreference,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          label: l10n.settingsActivationGroup,
          children: [
            SettingsRow(
              title: l10n.settingsGlobalActivationMethod,
              descriptionWidget: Text(
                switch (method) {
                  WorkspaceActivationMethod.automatic =>
                    l10n.settingsActivationMethodAutomaticDescription,
                  WorkspaceActivationMethod.copy =>
                    l10n.settingsActivationMethodCopyDescription,
                  WorkspaceActivationMethod.symbolicLink =>
                    l10n.settingsActivationMethodSymbolicLinkDescription,
                },
                key: const Key('global-activation-method-description'),
                style: AppTypography.of(context).caption,
              ),
              trailing: AppSegmentedControl<WorkspaceActivationMethod>(
                key: const Key('global-activation-method-control'),
                value: method,
                enabled: !appSettings.isBusy,
                segments: {
                  WorkspaceActivationMethod.automatic:
                      l10n.settingsActivationMethodAutomatic,
                  WorkspaceActivationMethod.copy:
                      l10n.settingsActivationMethodCopy,
                  WorkspaceActivationMethod.symbolicLink:
                      l10n.settingsActivationMethodSymbolicLink,
                },
                onChanged: settingsVm.setGlobalActivationMethod,
              ),
            ),
            SettingsFootnote(
              l10n.settingsActivationMethodScopeNote,
              icon: LucideIcons.info,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const _ProjectRootsGroup(),
      ],
    );
  }
}

class _ProjectRootsGroup extends ConsumerWidget {
  const _ProjectRootsGroup();

  Future<void> _add(WidgetRef ref) async {
    if (ref.read(projectRootsViewModelProvider).busy) return;
    final path = await ref.read(directoryPickerProvider).pickDirectory();
    if (path == null) return;
    await ref.read(projectRootsViewModelProvider.notifier).register(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final roots =
        ref.watch(workspaceProjectRootsProvider).value ??
        const <SkillProjectRoot>[];
    final busy = ref.watch(projectRootsViewModelProvider).busy;
    return SettingsGroup(
      key: const Key('project-roots-settings'),
      label: l10n.settingsProjectRootsGroup,
      children: [
        SettingsRow(
          title: l10n.settingsProjectRootsRegistered,
          description: l10n.projectRootsDescription,
          trailing: AppButton(
            key: const Key('settings-project-root-add'),
            label: l10n.projectRootsAdd,
            icon: LucideIcons.plus,
            loading: busy,
            onPressed: busy ? null : () => unawaited(_add(ref)),
          ),
        ),
        if (roots.isEmpty)
          SettingsFootnote(
            l10n.projectRootsEmpty,
            key: const Key('settings-project-roots-empty'),
          )
        else
          for (final root in roots)
            Padding(
              key: Key('settings-project-root-${root.id}'),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.folder,
                    size: AppSizes.iconSm,
                    color: AppPalette.of(context).textMuted,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      root.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.of(context).mono,
                    ),
                  ),
                  AppIconButton(
                    key: Key('settings-project-root-remove-${root.id}'),
                    icon: LucideIcons.circleMinus,
                    tooltip: l10n.projectRootsRemove,
                    style: NeoButtonVariant.ghost,
                    foregroundColor: AppPalette.of(context).textMuted,
                    onPressed: busy
                        ? null
                        : () => unawaited(
                            ref
                                .read(projectRootsViewModelProvider.notifier)
                                .unregister(root.id),
                          ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
