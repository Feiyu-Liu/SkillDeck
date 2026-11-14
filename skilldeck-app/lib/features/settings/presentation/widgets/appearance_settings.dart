import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:skills_manager/features/settings/presentation/widgets/settings_layout.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_list_layout.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

/// How the App presents Skills, such as the Installed and Favorites layout.
class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({required this.showSectionHeader, super.key});

  final bool showSectionHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final layout = ref.watch(skillListLayoutProvider);
    final appearance = ref.watch(appearanceModeProvider);
    return Column(
      key: const Key('appearance-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showSectionHeader) ...[
          SettingsSectionHeader(
            title: l10n.settingsAppearanceTitle,
            description: l10n.settingsAppearanceDescription,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        SettingsGroup(
          children: [
            SettingsRow(
              title: l10n.settingsAppearanceMode,
              description: l10n.settingsAppearanceModeDescription,
              below: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Wrap(
                  key: const Key('appearance-mode-control'),
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final option in AppearanceMode.values)
                      _VisualOption(
                        key: ValueKey('appearance-mode-${option.name}'),
                        label: switch (option) {
                          AppearanceMode.system => l10n.settingsFollowSystem,
                          AppearanceMode.light =>
                            l10n.settingsAppearanceModeLight,
                          AppearanceMode.dark =>
                            l10n.settingsAppearanceModeDark,
                        },
                        selected: option == appearance,
                        onTap: () => ref
                            .read(appearanceModeProvider.notifier)
                            .select(option),
                        preview: _AppearancePreview(option),
                      ),
                  ],
                ),
              ),
            ),
            SettingsRow(
              title: l10n.settingsSkillListLayout,
              description: l10n.settingsSkillListLayoutDescription,
              below: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Wrap(
                  key: const Key('skill-list-layout-control'),
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.md,
                  children: [
                    for (final option in SkillListLayout.values)
                      _VisualOption(
                        key: ValueKey('skill-list-layout-${option.name}'),
                        preview: _LayoutPreview(option),
                        label: switch (option) {
                          SkillListLayout.list =>
                            l10n.settingsSkillListLayoutList,
                          SkillListLayout.cards =>
                            l10n.settingsSkillListLayoutCards,
                        },
                        selected: option == layout,
                        onTap: () => ref
                            .read(skillListLayoutProvider.notifier)
                            .select(option),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A miniature above its name, so the choice shows the difference instead of
/// only naming it.
class _VisualOption extends StatelessWidget {
  const _VisualOption({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.preview,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 132,
              height: 88,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadii.lg + 3),
                border: Border.all(
                  color: selected
                      ? AppPalette.of(context).ink
                      : AppPalette.of(context).transparent,
                  width: 2,
                ),
              ),
              child: preview,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: AppTypography.of(context).control.copyWith(
                color: selected
                    ? AppPalette.of(context).ink
                    : AppPalette.of(context).textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A miniature of the Skill list in [layout].
class _LayoutPreview extends StatelessWidget {
  const _LayoutPreview(this.layout);

  final SkillListLayout layout;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: AppCorners.smooth(
      color: AppPalette.of(context).onPrimary,
      radius: AppRadii.md,
      side: BorderSide(color: AppPalette.of(context).border),
    ),
    child: switch (layout) {
      SkillListLayout.list => const _ListPreview(),
      SkillListLayout.cards => const _CardsPreview(),
    },
  );
}

/// A miniature App window in [mode]: Follow System shows light on the left
/// and dark on the right.
class _AppearancePreview extends StatelessWidget {
  const _AppearancePreview(this.mode);

  final AppearanceMode mode;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    position: DecorationPosition.foreground,
    decoration: AppCorners.smooth(
      radius: AppRadii.md,
      side: BorderSide(color: AppPalette.of(context).border),
    ),
    child: AppSmoothClip(
      radius: AppRadii.md,
      child: switch (mode) {
        AppearanceMode.light => const _WindowPreview(AppPalette.light),
        AppearanceMode.dark => const _WindowPreview(AppPalette.dark),
        AppearanceMode.system => const Stack(
          fit: StackFit.expand,
          children: [
            _WindowPreview(AppPalette.light),
            ClipRect(
              clipper: _TrailingHalf(),
              child: _WindowPreview(AppPalette.dark),
            ),
          ],
        ),
      },
    ),
  );
}

class _TrailingHalf extends CustomClipper<Rect> {
  const _TrailingHalf();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(size.width / 2, 0, size.width, size.height);

  @override
  bool shouldReclip(_TrailingHalf oldClipper) => false;
}

/// A sidebar on the canvas beside a content surface, painted with [palette]
/// regardless of the current appearance.
class _WindowPreview extends StatelessWidget {
  const _WindowPreview(this.palette);

  final AppPalette palette;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: palette.canvas,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 6, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final width in const [20.0, 14.0, 17.0]) ...[
                  _Bar(width: width, height: 4, color: palette.borderStrong),
                  const SizedBox(height: 6),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: AppCorners.smooth(
                color: palette.surface,
                radius: AppRadii.xs,
                side: BorderSide(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bar(width: 34, height: 5, color: palette.ink),
                  const SizedBox(height: 8),
                  for (final width in const [60.0, 48.0, 54.0]) ...[
                    _Bar(width: width, height: 4, color: palette.borderStrong),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ListPreview extends StatelessWidget {
  const _ListPreview();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      for (final (index, width) in const [44.0, 36.0, 50.0, 40.0].indexed) ...[
        if (index > 0)
          SizedBox(
            height: 1,
            child: ColoredBox(color: AppPalette.of(context).border),
          ),
        Row(
          children: [
            _Bar(
              width: width,
              height: 5,
              color: AppPalette.of(context).borderStrong,
            ),
            const Spacer(),
            _Bar(width: 14, height: 5, color: AppPalette.of(context).border),
          ],
        ),
      ],
    ],
  );
}

class _CardsPreview extends StatelessWidget {
  const _CardsPreview();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final (index, row) in const [
        [30.0, 24.0],
        [22.0, 28.0],
      ].indexed) ...[
        if (index > 0) const SizedBox(height: 5),
        Expanded(
          child: Row(
            children: [
              for (final (column, width) in row.indexed) ...[
                if (column > 0) const SizedBox(width: 5),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: AppCorners.smooth(
                      color: AppPalette.of(context).surfaceSubtle,
                      radius: AppRadii.xs,
                      side: BorderSide(color: AppPalette.of(context).border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Bar(
                          width: width,
                          height: 4,
                          color: AppPalette.of(context).borderStrong,
                        ),
                        const SizedBox(height: 3),
                        _Bar(
                          width: 34,
                          height: 3,
                          color: AppPalette.of(context).border,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height, required this.color});

  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(height),
    ),
  );
}
