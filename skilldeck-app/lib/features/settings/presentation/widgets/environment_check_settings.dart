import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/settings/models/environment_check.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// Lists the external tools SkillDeck depends on and lets the user verify them.
///
/// Nothing here probes on build. Checking is always an explicit action because
/// on macOS a missing developer toolchain makes the probe itself raise the
/// operating system's install dialog.
class EnvironmentCheckSettings extends ConsumerWidget {
  const EnvironmentCheckSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(environmentCheckViewModelProvider);
    return SettingsGroup(
      key: const Key('environment-settings'),
      label: context.l10n.settingsEnvironmentGroup,
      children: [
        for (final item in state.items)
          _EnvironmentCheckRow(
            key: Key('environment-check-item-${item.id.name}'),
            item: item,
            busy: state.isChecking,
            onCheck: () => unawaited(
              ref
                  .read(environmentCheckViewModelProvider.notifier)
                  .check(item.id),
            ),
          ),
      ],
    );
  }
}

class _EnvironmentCheckRow extends StatelessWidget {
  const _EnvironmentCheckRow({
    required this.item,
    required this.busy,
    required this.onCheck,
    super.key,
  });

  final EnvironmentCheckItem item;
  final bool busy;
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    final checking = item.status == EnvironmentCheckStatus.checking;
    return SettingsRow(
      leading: Icon(
        _statusIcon(item.status),
        size: AppSizes.iconMd - 1,
        color: _statusColor(item.status, AppPalette.of(context)),
      ),
      title: _itemLabel(context, item.id),
      descriptionWidget: Text(
        _statusText(context, item),
        key: Key('environment-check-status-${item.id.name}'),
        style: AppTypography.of(context).caption,
      ),
      trailing: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          // Re-running the probe is what re-raises the operating system's
          // install dialog, which is the only recourse for a user who
          // dismissed it. Off macOS, and before a check has found anything
          // missing, there is no dialog to reopen.
          if (_offersInstallPrompt(item))
            AppButton(
              key: const Key('environment-check-open-install-prompt'),
              label: context.l10n.settingsEnvironmentOpenInstallPrompt,
              icon: LucideIcons.download,
              onPressed: busy ? null : onCheck,
            ),
          AppButton(
            key: const Key('environment-check-recheck'),
            label: context.l10n.settingsEnvironmentRecheck,
            icon: LucideIcons.refreshCw,
            loading: checking,
            onPressed: busy ? null : onCheck,
          ),
        ],
      ),
    );
  }
}

bool _offersInstallPrompt(EnvironmentCheckItem item) =>
    Platform.isMacOS &&
    item.id == EnvironmentCheckId.git &&
    item.reasonKey == 'developerToolsRequired';

String _itemLabel(BuildContext context, EnvironmentCheckId id) => switch (id) {
  EnvironmentCheckId.git => context.l10n.settingsEnvironmentCheckGit,
};

String _statusText(BuildContext context, EnvironmentCheckItem item) {
  final l10n = context.l10n;
  return switch (item.status) {
    EnvironmentCheckStatus.notChecked =>
      l10n.settingsEnvironmentStatusNotChecked,
    EnvironmentCheckStatus.checking => l10n.settingsEnvironmentStatusChecking,
    EnvironmentCheckStatus.ok ||
    EnvironmentCheckStatus.attention ||
    EnvironmentCheckStatus.failed => _reasonText(context, item),
  };
}

String _reasonText(BuildContext context, EnvironmentCheckItem item) {
  final l10n = context.l10n;
  return switch (item.id) {
    EnvironmentCheckId.git => switch (item.reasonKey) {
      'available' => l10n.settingsEnvironmentGitAvailable,
      'notInstalled' => l10n.settingsEnvironmentGitNotInstalled,
      'developerToolsRequired' =>
        l10n.settingsEnvironmentGitDeveloperToolsRequired,
      'developerToolsInstalling' =>
        l10n.settingsEnvironmentGitDeveloperToolsInstalling,
      _ => l10n.settingsEnvironmentGitProbeFailed,
    },
  };
}

IconData _statusIcon(EnvironmentCheckStatus status) => switch (status) {
  EnvironmentCheckStatus.notChecked => LucideIcons.circleDashed,
  EnvironmentCheckStatus.checking => LucideIcons.loaderCircle,
  EnvironmentCheckStatus.ok => LucideIcons.circleCheck,
  EnvironmentCheckStatus.attention => LucideIcons.circleAlert,
  EnvironmentCheckStatus.failed => LucideIcons.circleX,
};

Color _statusColor(EnvironmentCheckStatus status, AppPalette colors) =>
    switch (status) {
      EnvironmentCheckStatus.notChecked ||
      EnvironmentCheckStatus.checking => colors.textSecondary,
      EnvironmentCheckStatus.ok => colors.success,
      EnvironmentCheckStatus.attention => colors.warning,
      EnvironmentCheckStatus.failed => colors.danger,
    };
