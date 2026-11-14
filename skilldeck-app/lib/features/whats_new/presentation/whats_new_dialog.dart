import 'dart:ui' show ImageFilter;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/settings/presentation/settings_section.dart';
import 'package:skills_manager/features/whats_new/whats_new_catalog.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';

/// Introduces what an App update brings, once, on the first launch after it.
class WhatsNewDialog extends StatelessWidget {
  const WhatsNewDialog({required this.entry, super.key});

  static const width = 480.0;
  static const heroHeight = 216.0;
  static const bodyMaxWidth = 320.0;

  final WhatsNewEntry entry;

  void _openSettings(BuildContext context, SettingsSection section) {
    // Resolve the router before popping: afterwards this context is
    // deactivated and cannot look one up.
    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.go(settingsLocation(section));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    void close() => Navigator.of(context).pop();
    final dark = CupertinoTheme.brightnessOf(context) == Brightness.dark;
    final settingsSection = entry.settingsSection;
    return AppDialogScaffold(
      key: const Key('whats-new-dialog'),
      width: width,
      onEscape: close,
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: heroHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  dark
                      ? entry.darkHeroAsset ?? entry.heroAsset
                      : entry.heroAsset,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  excludeFromSemantics: true,
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: _HeroCloseButton(
                    tooltip: l10n.commonClose,
                    onPressed: close,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 32, 40, 28),
            child: Column(
              children: [
                _VersionBadge(label: l10n.whatsNewVersionBadge(entry.version)),
                const SizedBox(height: 10),
                Text(
                  entry.title(l10n),
                  textAlign: TextAlign.center,
                  style: AppTypography.of(context).title.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                    color: AppPalette.of(context).ink,
                  ),
                ),
                const SizedBox(height: 10),
                // Narrower than the title, as in the design, so a wrapped
                // line breaks into two balanced halves.
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: bodyMaxWidth),
                  child: Text(
                    entry.body(l10n),
                    textAlign: TextAlign.center,
                    style: AppTypography.of(context).body.copyWith(
                      fontSize: 13,
                      height: 1.6,
                      color: AppPalette.of(context).bodyContent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
            child: Row(
              spacing: 12,
              children: [
                if (settingsSection != null)
                  Expanded(
                    child: AppButton(
                      key: const Key('whats-new-open-settings'),
                      label: entry.settingsAction!(l10n),
                      size: NeoButtonSize.large,
                      fullWidth: true,
                      onPressed: () => _openSettings(context, settingsSection),
                    ),
                  ),
                Expanded(
                  child: AppButton(
                    key: const Key('whats-new-dismiss'),
                    label: l10n.whatsNewDismiss,
                    style: NeoButtonVariant.primary,
                    size: NeoButtonSize.large,
                    fullWidth: true,
                    onPressed: close,
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

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('whats-new-version-badge'),
    height: 22,
    padding: const EdgeInsets.symmetric(horizontal: 9),
    decoration: AppCorners.smooth(
      color: AppPalette.of(context).infoSoft,
      radius: 11,
    ),
    // Centers the label vertically while the pill keeps the label's width;
    // an aligned Container would stretch across the dialog.
    child: Center(
      widthFactor: 1,
      child: Text(
        label,
        style: AppTypography.of(context).caption.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: AppPalette.of(context).info,
        ),
      ),
    ),
  );
}

/// A frosted round button that stays legible over any hero image.
class _HeroCloseButton extends StatelessWidget {
  const _HeroCloseButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: tooltip,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const Key('whats-new-close'),
        onTap: onPressed,
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppPalette.of(context).ink.withValues(alpha: 0.15),
                border: Border.all(
                  color: AppPalette.of(context).ink.withValues(alpha: 0.1),
                ),
              ),
              child: Icon(
                LucideIcons.x,
                size: 15,
                color: AppPalette.of(context).white,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
