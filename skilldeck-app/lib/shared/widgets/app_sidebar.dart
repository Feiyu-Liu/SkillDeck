import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

enum NavSection { installed, favorites, updates, settings }

extension NavSectionIcon on NavSection {
  IconData get icon => switch (this) {
    NavSection.installed => LucideIcons.squareLibrary,
    NavSection.favorites => LucideIcons.star,
    NavSection.updates => LucideIcons.arrowDownToLine,
    NavSection.settings => LucideIcons.settings2,
  };
}

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    required this.selected,
    required this.onSelected,
    this.updatePromptBuilder,
    this.width = AppSizes.sidebarWidth,
    this.progress = 1,
    super.key,
  });

  final NavSection selected;
  final ValueChanged<NavSection> onSelected;

  /// Builds the app-update prompt above Settings; `rail` is true once the
  /// sidebar has collapsed past the icon-rail threshold.
  final Widget Function(bool rail)? updatePromptBuilder;
  final double width;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // The content panel is inset from the sidebar box, so the canvas the user
    // sees around the rail already carries that gap on its right. Handing the
    // rail the same inset again would double it there, squeezing the button
    // and pushing it off the visible centre, so the right inset is released
    // as the rail closes and the button grows into it.
    final railGutter = AppInsets.shellContent.left * (1 - progress);
    return Container(
      key: const Key('app-sidebar'),
      width: width,
      color: AppPalette.of(context).canvas,
      // The left inset stays constant across the drag so the icons keep a
      // stable optical left edge instead of sliding as the rail narrows.
      padding: EdgeInsets.fromLTRB(
        AppSizes.sidebarHorizontalPadding,
        AppInsets.sidebar.top,
        AppSizes.sidebarHorizontalPadding - railGutter,
        AppInsets.sidebar.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Indent the brand by the nav buttons' own horizontal padding so
          // it hangs on the same optical edge as the nav labels below it.
          // The box collapses vertically as the rail drops the brand entirely:
          // keeping its row height would strand an empty band above the first
          // nav item. Its own bottom gap rides along inside the collapsing box
          // for the same reason. Horizontally the word only fades — no width
          // factor, which would wipe it right to left on top of the fade.
          ClipRect(
            child: Align(
              alignment: Alignment.topLeft,
              heightFactor: progress,
              child: Opacity(
                opacity: progress,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    bottom: AppSpacing.md,
                  ),
                  child: SizedBox(
                    height: 14,
                    child: Text(
                      l10n.appTitle,
                      style: AppTypography.of(context).sectionLabel
                          .copyWith(color: AppPalette.of(context).textFaint),
                      // The rail is narrower than the word; laying it out on
                      // one line keeps the fade from reflowing into two.
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                    ),
                  ),
                ),
              ),
            ),
          ),
          _NavItem(
            key: const Key('nav-item-installed'),
            label: l10n.navInstalled,
            icon: NavSection.installed.icon,
            selected: selected == NavSection.installed,
            onTap: () => onSelected(NavSection.installed),
            progress: progress,
          ),
          const SizedBox(height: AppSpacing.xs),
          _NavItem(
            key: const Key('nav-item-favorites'),
            label: l10n.navFavorites,
            icon: NavSection.favorites.icon,
            selected: selected == NavSection.favorites,
            onTap: () => onSelected(NavSection.favorites),
            progress: progress,
          ),
          const SizedBox(height: AppSpacing.xs),
          _NavItem(
            key: const Key('nav-item-updates'),
            label: l10n.navUpdates,
            icon: NavSection.updates.icon,
            selected: selected == NavSection.updates,
            onTap: () => onSelected(NavSection.updates),
            progress: progress,
          ),
          const Spacer(),
          ?updatePromptBuilder?.call(progress < AppSizes.sidebarRailThreshold),
          _NavItem(
            key: const Key('nav-item-settings'),
            label: l10n.navSettings,
            icon: NavSection.settings.icon,
            selected: selected == NavSection.settings,
            onTap: () => onSelected(NavSection.settings),
            progress: progress,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.progress,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final rail = progress < AppSizes.sidebarRailThreshold;
    Widget button = AppButton(
      label: rail ? '' : label,
      icon: icon,
      style: selected ? NeoButtonVariant.secondary : NeoButtonVariant.ghost,
      size: NeoButtonSize.medium,
      fullWidth: true,
      contentAlignment: rail
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      textStyle: selected
          ? AppTypography.of(context).navigationSelected
          : AppTypography.of(context).navigation,
      onPressed: onTap,
    );
    if (rail) {
      final base = NeoButtonTheme.of(context);
      // Two icon-only corrections, neither of which needs a next_ui patch.
      // `contentSpacing` is reserved between the icon and the label slot even
      // when the label is empty, so the centred row measures icon + gap and
      // the icon lands half a gap left of centre. The labelled horizontal
      // padding then leaves the narrow rail button too little room for the
      // icon itself.
      button = NeoButtonTheme(
        data: base.copyWith(
          contentSpacing: 0,
          medium: NeoButtonSizeSpec(
            height: base.medium.height,
            horizontalPadding: AppSpacing.sm,
            iconSize: base.medium.iconSize,
            fontSize: base.medium.fontSize,
          ),
        ),
        child: button,
      );
    }
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      enabled: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(child: button),
    );
  }
}
