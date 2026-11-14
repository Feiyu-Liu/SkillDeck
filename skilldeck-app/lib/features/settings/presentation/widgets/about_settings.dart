import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:skills_manager/features/self_update/presentation/widgets/self_update_settings.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/settings/presentation/widgets/open_source_licenses_dialog.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

final _skillDeckWebsiteUri = Uri.parse('https://skilldeck.cc/');
final _skillDeckChangelogUri = Uri.parse('https://skilldeck.cc/changelog');
final _skillDeckPrivacyUri = Uri.parse('https://skilldeck.cc/privacy');
final _skillDeckTermsUri = Uri.parse('https://skilldeck.cc/terms');

/// SkillDeck's identity, its update status, and links to its documents.
class AboutSettings extends ConsumerWidget {
  const AboutSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final version = ref.watch(appVersionProvider);
    final installBlocked =
        ref.watch(appSettingsViewModelProvider).isBusy ||
        ref.watch(workspaceFinalizationCoordinatorProvider).isRecovering;
    return Column(
      key: const Key('about-skilldeck-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // The icon artwork sits on an opaque white square, so it fills the
            // tile and the border is drawn over its clipped edge.
            Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: AppCorners.smooth(
                color: AppPalette.of(context).surface,
                radius: AppRadii.panel,
              ),
              foregroundDecoration: AppCorners.smooth(
                radius: AppRadii.panel,
                side: BorderSide(color: AppPalette.of(context).border),
              ),
              child: Image.asset(
                'assets/app_icon.png',
                fit: BoxFit.cover,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.settingsAboutTitle,
                    style: AppTypography.of(context).title
                        .copyWith(fontSize: 19),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    l10n.settingsAppVersion(
                      version.value ?? l10n.settingsAppUpdateVersionUnknown,
                    ),
                    key: const Key('self-update-current-version'),
                    style: AppTypography.of(context).mono
                        .copyWith(color: AppPalette.of(context).textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        SelfUpdateSettings(installBlocked: installBlocked),
        const SizedBox(height: AppSpacing.xl),
        SettingsGroup(
          label: l10n.settingsLinksGroup,
          children: [
            _LinkRow(
              key: const Key('settings-official-website'),
              icon: LucideIcons.globe2,
              label: l10n.settingsOfficialWebsite,
              detail: _skillDeckWebsiteUri.host,
              uri: _skillDeckWebsiteUri,
            ),
            _LinkRow(
              key: const Key('settings-changelog'),
              icon: LucideIcons.history,
              label: l10n.settingsChangelog,
              uri: _skillDeckChangelogUri,
            ),
            _LinkRow(
              key: const Key('settings-privacy-policy'),
              icon: LucideIcons.shieldCheck,
              label: l10n.settingsPrivacyPolicy,
              uri: _skillDeckPrivacyUri,
            ),
            _LinkRow(
              key: const Key('settings-terms-of-service'),
              icon: LucideIcons.fileText,
              label: l10n.settingsTermsOfService,
              uri: _skillDeckTermsUri,
            ),
            _ActionRow(
              key: const Key('settings-licenses'),
              icon: LucideIcons.scale,
              label: l10n.settingsOpenSourceLicenses,
              trailingIcon: LucideIcons.chevronRight,
              onTap: () => unawaited(showOpenSourceLicensesDialog(context)),
            ),
          ],
        ),
      ],
    );
  }
}

/// A row that opens a SkillDeck web page in the browser.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.uri,
    this.detail,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final Uri uri;

  @override
  Widget build(BuildContext context) => _ActionRow(
    icon: icon,
    label: label,
    detail: detail,
    trailingIcon: LucideIcons.arrowUpRight,
    link: true,
    onTap: () => unawaited(_openExternalUrl(uri)),
  );
}

/// A hoverable row with an icon, a label, an optional detail and a trailing
/// glyph that says where it leads: out to the browser or into the App.
class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.trailingIcon,
    required this.onTap,
    this.detail,
    this.link = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? detail;
  final IconData trailingIcon;
  final VoidCallback onTap;
  final bool link;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => Semantics(
    link: widget.link,
    button: !widget.link,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: ColoredBox(
          color: _hovered
              ? AppPalette.of(context).surfaceMuted
              : AppPalette.of(context).transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: AppSizes.iconSm,
                  color: AppPalette.of(context).bodyContent,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.label,
                    style: AppTypography.of(context).body.copyWith(
                      color: AppPalette.of(context).textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.detail case final detail?) ...[
                  Text(detail, style: AppTypography.of(context).caption),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Icon(
                  widget.trailingIcon,
                  size: AppSizes.iconSm,
                  color: AppPalette.of(context).textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openExternalUrl(Uri uri) async {
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // The operating system owns external URL handling. A missing browser or
    // platform launcher should leave the Settings page usable.
  }
}
