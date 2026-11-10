import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';

/// The meaning a dialog's badge or note carries.
///
/// [danger] is for actions that permanently delete data, [info] for ordinary
/// tasks, [warning] for questions that need care, [success] for results.
enum AppDialogTone { danger, info, warning, success }

extension on AppDialogTone {
  Color softColor(AppPalette colors) => switch (this) {
    AppDialogTone.danger => colors.dangerSoft,
    AppDialogTone.info => colors.infoSoft,
    AppDialogTone.warning => colors.warningSoft,
    AppDialogTone.success => colors.successSoft,
  };

  Color strongColor(AppPalette colors) => switch (this) {
    AppDialogTone.danger => colors.danger,
    AppDialogTone.info => colors.infoStrong,
    AppDialogTone.warning => colors.warningStrong,
    AppDialogTone.success => colors.success,
  };

  // Info notes are quiet asides, so they read in grey rather than blue.
  Color noteColor(AppPalette colors) =>
      this == AppDialogTone.info ? colors.textSecondary : strongColor(colors);

  IconData get noteIcon => switch (this) {
    AppDialogTone.danger => LucideIcons.circleAlert,
    AppDialogTone.info => LucideIcons.info,
    AppDialogTone.warning => LucideIcons.triangleAlert,
    AppDialogTone.success => LucideIcons.circleCheck,
  };
}

abstract final class _DialogMetrics {
  static const horizontal = 28.0;
  static const sectionVertical = 20.0;
  static const badgeSize = 44.0;
  static const badgeRadius = 14.0;
  static const badgeIconSize = 20.0;
  static const actionGap = 10.0;

  static const sectionTitle = TextStyle(
    fontFamily: AppFonts.ui,
    fontFamilyFallback: AppFonts.fallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
}

/// A dialog laid out as one scrolling column of header and sections, under a
/// footer that floats over its bottom edge.
///
/// The header scrolls with the content, so a long dialog reads as a single
/// list and never nests a second scroll area. The content scrolls on beneath
/// the footer, which blurs whatever passes behind it; a bottom inset as tall
/// as the footer lets the last section still scroll clear of it. Sections
/// draw a full-width divider above themselves, so they stack into blocks
/// without nested borders. [onEscape] runs when Esc is pressed while this
/// dialog's route is on top; pass the same callback as the close or cancel
/// button, or null while the dialog must stay open.
class AppDialogScaffold extends StatefulWidget {
  const AppDialogScaffold({
    required this.width,
    required this.header,
    this.sections = const [],
    this.footer,
    this.onEscape,
    super.key,
  });

  final double width;
  final Widget header;
  final List<Widget> sections;
  final Widget? footer;
  final VoidCallback? onEscape;

  @override
  State<AppDialogScaffold> createState() => _AppDialogScaffoldState();
}

class _AppDialogScaffoldState extends State<AppDialogScaffold> {
  // The footer's measured height arrives a frame late, so the inset starts at
  // the height a one-line footer has; that is exact for nearly every dialog
  // and keeps the first frame from jumping.
  late double _footerHeight = switch (widget.footer) {
    AppDialogFooter(equalWidth: true) => AppDialogFooter.equalWidthHeight,
    AppDialogFooter() => AppDialogFooter.height,
    _ => 0,
  };

  void _setFooterHeight(double height) {
    if (!mounted || height == _footerHeight) return;
    setState(() => _footerHeight = height);
  }

  @override
  Widget build(BuildContext context) {
    final footer = widget.footer;
    final content = SingleChildScrollView(
      padding: EdgeInsets.only(bottom: footer == null ? 0 : _footerHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [widget.header, ...widget.sections],
      ),
    );
    return AppCupertinoDialogSurface(
      width: widget.width,
      child: _EscapeHandler(
        onEscape: widget.onEscape,
        child: ColoredBox(
          color: AppPalette.of(context).surface,
          child: footer == null
              ? content
              : Stack(
                  children: [
                    content,
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _HeightReporter(
                        onHeight: _setFooterHeight,
                        child: footer,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Reports its child's laid-out height after the frame that produced it.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// The header of an [AppDialogScaffold]: a tone badge, a 20pt title, an
/// optional subtitle and [below] (such as a stepper), with [actions] such as
/// refresh and close pinned to the top-right.
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    required this.title,
    this.icon,
    this.tone = AppDialogTone.info,
    this.subtitle,
    this.below,
    this.actions = const [],
    this.titleKey,
    super.key,
  });

  final String title;
  final IconData? icon;
  final AppDialogTone tone;
  final String? subtitle;
  final Widget? below;
  final List<Widget> actions;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      key: titleKey,
      style: AppTypography.of(context).title.copyWith(height: 1.3),
    );
    // Nudged toward the corner past the header padding, so the buttons sit
    // 16 from the top and 12 from the trailing edge.
    final trailing = actions.isEmpty
        ? null
        : Transform.translate(
            offset: Offset(
              Directionality.of(context) == TextDirection.rtl ? -8 : 8,
              -12,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: AppSpacing.xs,
              children: actions,
            ),
          );
    // The actions only claim room in the top row, so the text below runs the
    // full width. The actions sit in the tighter trailing inset; the text
    // keeps the standard one.
    final textInset = EdgeInsetsDirectional.only(
      end: trailing == null ? 0 : _DialogMetrics.horizontal - 20,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        _DialogMetrics.horizontal,
        28,
        trailing == null ? _DialogMetrics.horizontal : 20,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppDialogBadge(icon: icon!, tone: tone),
                const Spacer(),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            Padding(padding: textInset, child: titleText),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: titleText),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing,
                ],
              ],
            ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: textInset,
              child: Text(
                subtitle!,
                style: AppTypography.of(context).bodyMuted
                    .copyWith(fontSize: 12, height: 1.5),
              ),
            ),
          ],
          if (below != null) ...[
            const SizedBox(height: 14),
            Padding(padding: textInset, child: below),
          ],
        ],
      ),
    );
  }
}

/// The ghost close button for an [AppDialogHeader].
///
/// [key] lands on the [AppIconButton] itself so tests can read its state.
AppIconButton appDialogCloseButton(
  BuildContext context, {
  required VoidCallback? onPressed,
  Key? key,
}) => AppIconButton(
  key: key,
  icon: LucideIcons.x,
  tooltip: context.l10n.commonClose,
  style: NeoButtonVariant.ghost,
  foregroundColor: AppPalette.of(context).textSecondary,
  onPressed: onPressed,
);

class AppDialogBadge extends StatelessWidget {
  const AppDialogBadge({
    required this.icon,
    this.tone = AppDialogTone.info,
    super.key,
  });

  final IconData icon;
  final AppDialogTone tone;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: AppCorners.smooth(
      color: tone.softColor(AppPalette.of(context)),
      radius: _DialogMetrics.badgeRadius,
    ),
    child: SizedBox.square(
      dimension: _DialogMetrics.badgeSize,
      child: Icon(
        icon,
        size: _DialogMetrics.badgeIconSize,
        color: tone.strongColor(AppPalette.of(context)),
      ),
    ),
  );
}

/// One block of an [AppDialogScaffold], separated from the block above it by
/// a full-width divider.
class AppDialogSection extends StatelessWidget {
  const AppDialogSection({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(
      horizontal: _DialogMetrics.horizontal,
      vertical: _DialogMetrics.sectionVertical,
    ),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;

  /// Shown at the end of the title row, such as a "view all" link.
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final hasLabel = title != null || subtitle != null || trailing != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppPalette.of(context).border)),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasLabel) ...[
              Row(
                children: [
                  if (title != null)
                    Expanded(
                      child: Text(
                        title!,
                        style: _DialogMetrics.sectionTitle.copyWith(
                          color: AppPalette.of(context).textPrimary,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  ?trailing,
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  style: AppTypography.of(context).caption.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// An inline icon-and-text note. It carries no fill, so it sits quietly
/// inside a section.
class AppDialogNote extends StatelessWidget {
  const AppDialogNote({
    required this.tone,
    required this.text,
    this.icon,
    super.key,
  });

  final AppDialogTone tone;
  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = tone.noteColor(AppPalette.of(context));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon ?? tone.noteIcon, size: 16, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: AppTypography.of(context).body
                .copyWith(fontSize: 13, height: 1.45, color: color),
          ),
        ),
      ],
    );
  }
}

/// The grey action bar of an [AppDialogScaffold].
///
/// Task dialogs keep [actions] right-aligned with [leading] (such as Back or a
/// status line) on the left. Confirmations set [equalWidth], which stretches
/// every action to the same width; give those buttons
/// `size: NeoButtonSize.large` and `fullWidth: true`.
class AppDialogFooter extends StatelessWidget {
  const AppDialogFooter({
    required this.actions,
    this.leading,
    this.equalWidth = false,
    super.key,
  });

  final List<Widget> actions;
  final Widget? leading;
  final bool equalWidth;

  /// The height of a one-line footer: the top border, the padding and a
  /// medium button (or, for [equalWidth], a large one).
  static const height = 1 + 16 + 34 + 16.0;
  static const equalWidthHeight = 1 + 16 + 40 + 20.0;

  static const _blurSigma = 20.0;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppPalette.of(context).dialogFooter,
            border: Border(
              top: BorderSide(color: AppPalette.of(context).border),
            ),
          ),
          child: Padding(
            padding: equalWidth
                ? const EdgeInsets.fromLTRB(
                    _DialogMetrics.horizontal,
                    16,
                    _DialogMetrics.horizontal,
                    20,
                  )
                : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              spacing: _DialogMetrics.actionGap,
              children: equalWidth
                  ? [for (final action in actions) Expanded(child: action)]
                  : [
                      // A Flexible leading would split the free space with a
                      // Spacer and leave a gap after the actions, so the leading
                      // slot takes all of it and aligns its child left.
                      Expanded(
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: leading,
                        ),
                      ),
                      ...actions,
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A confirmation: no close button, a tone badge, and two equal-width actions
/// at the bottom. Esc runs [onEscape], which should match the cancel action.
class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    required this.icon,
    required this.title,
    required this.actions,
    this.tone = AppDialogTone.info,
    this.message,
    this.sections = const [],
    this.width = AppDialogWidths.confirm,
    this.onEscape,
    this.titleKey,
    super.key,
  });

  final IconData icon;
  final String title;
  final List<Widget> actions;
  final AppDialogTone tone;
  final String? message;
  final List<Widget> sections;
  final double width;
  final VoidCallback? onEscape;
  final Key? titleKey;

  @override
  Widget build(BuildContext context) => AppDialogScaffold(
    width: width,
    onEscape: onEscape,
    header: AppDialogHeader(
      icon: icon,
      tone: tone,
      title: title,
      subtitle: message,
      titleKey: titleKey,
    ),
    sections: sections,
    footer: AppDialogFooter(equalWidth: true, actions: actions),
  );
}

/// Shows a simple [AppConfirmDialog] and resolves to whether the user
/// confirmed. Esc and Cancel resolve to false; tapping outside does nothing.
///
/// Set [showCancel] to false for a notice with a single acknowledgement.
Future<bool> showAppConfirmDialog({
  required BuildContext context,
  required IconData icon,
  required String title,
  required String confirmLabel,
  AppDialogTone tone = AppDialogTone.info,
  String? message,
  List<Widget> sections = const [],
  String? cancelLabel,
  bool showCancel = true,
  IconData? confirmIcon,
  NeoButtonVariant confirmStyle = NeoButtonVariant.primary,
  Key? cancelKey,
  Key? confirmKey,
}) async {
  final confirmed = await AppDialogMotion.show<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      void cancel() => Navigator.of(context).pop(false);
      return AppConfirmDialog(
        icon: icon,
        tone: tone,
        title: title,
        message: message,
        sections: sections,
        onEscape: cancel,
        actions: [
          if (showCancel)
            AppButton(
              key: cancelKey,
              label: cancelLabel ?? context.l10n.commonCancel,
              size: NeoButtonSize.large,
              fullWidth: true,
              onPressed: cancel,
            ),
          AppButton(
            key: confirmKey,
            label: confirmLabel,
            icon: confirmIcon,
            style: confirmStyle,
            size: NeoButtonSize.large,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
    },
  );
  return confirmed ?? false;
}

/// Runs [onEscape] for an Esc press while this dialog's route is on top and
/// focus sits inside it.
///
/// A hardware-keyboard handler is used rather than shortcuts because a dialog
/// route opened with `barrierDismissible: false` disables Flutter's own
/// dismiss action, and focus often rests on the route's scope above any
/// shortcut widget placed in the dialog. The focus check keeps Esc for an open
/// menu overlay, which closes the menu instead.
class _EscapeHandler extends StatefulWidget {
  const _EscapeHandler({required this.onEscape, required this.child});

  final VoidCallback? onEscape;
  final Widget child;

  @override
  State<_EscapeHandler> createState() => _EscapeHandlerState();
}

class _EscapeHandlerState extends State<_EscapeHandler> {
  ModalRoute<Object?>? _route;
  FocusScopeNode? _scope;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _scope = FocusScope.of(context);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    final onEscape = widget.onEscape;
    if (onEscape == null ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (_route case final route? when !route.isCurrent) return false;
    final scope = _scope;
    final focused = FocusManager.instance.primaryFocus;
    if (scope != null &&
        focused != null &&
        focused != scope &&
        !focused.ancestors.contains(scope)) {
      return false;
    }
    onEscape();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
