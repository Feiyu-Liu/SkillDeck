import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/navigation/app_routes.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../command_line_activity.dart';

/// Shows what the command line is doing, floating over the content panel.
///
/// Running requests get a dark indicator with progress and Cancel; a finished
/// request becomes a summary that lists anything left undone.
class CommandLineActivityOverlay extends ConsumerWidget {
  const CommandLineActivityOverlay({super.key});

  static const maxWidth = 560.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(commandLineActivityProvider);
    final child = switch (activity) {
      null => const SizedBox.shrink(key: ValueKey('command-line-idle')),
      final value when !value.finished => _RunningIndicator(
        key: const Key('command-line-running'),
        activity: value,
      ),
      final value => _Summary(
        key: ValueKey('command-line-summary-${value.id}'),
        activity: value,
      ),
    };
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.xl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: math.min(
                maxWidth,
                math.max(0, constraints.maxWidth - 2 * AppSpacing.page),
              ),
            ),
            child: AnimatedSwitcher(
              duration: AppMotion.controlMorphDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Both floating panels are Neo surfaces: the running indicator matches the
/// App's black Neo button, the summary its white one. Rounder than a button
/// because each panel is much larger.
const double _panelRadius = 22;

NeoButtonVisualStyle _neoStyle(BuildContext context, NeoButtonVariant variant) {
  return SkillsButtonTheme.resolveStyle(context, variant);
}

/// The running indicator floats over changing content, so it keeps the Neo
/// surface but lifts higher than a button's own shadow.

NeoButtonVisualStyle _withShadow(
  NeoButtonVisualStyle style,
  BoxShadow shadow,
) => NeoButtonVisualStyle(
  foregroundColor: style.foregroundColor,
  fontWeight: style.fontWeight,
  fillColor: style.fillColor,
  fillGradient: style.fillGradient,
  innerHighlightColor: style.innerHighlightColor,
  borderColor: style.borderColor,
  borderGradient: style.borderGradient,
  borderWidth: style.borderWidth,
  dropShadow: shadow,
  hoverOverlayColor: style.hoverOverlayColor,
  hoverForegroundColor: style.hoverForegroundColor,
);

class _RunningIndicator extends ConsumerWidget {
  const _RunningIndicator({required this.activity, super.key});

  final CommandLineActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = activity.current;
    final detail = [
      if (activity.agentNames.isNotEmpty)
        l10n.commandLineAgents(activity.agentNames.join(', ')),
      l10n.commandLineProgress(activity.completed, activity.total),
      if (current != null) l10n.commandLineProcessing(current.slotKey),
    ].join(' · ');
    return NeoSurface(
      style: _withShadow(
        _neoStyle(context, NeoButtonVariant.primary),
        AppShadows.of(context).commandLine,
      ),
      borderRadius: _panelRadius,
      padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: AppCorners.smooth(
                  color: AppPalette.of(context).onPrimary
                      .withValues(alpha: 0.12),
                  radius: 7,
                ),
                child: Icon(
                  LucideIcons.terminal,
                  size: 13,
                  color: AppPalette.of(context).onPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.commandLineRunning(
                        commandLineProgressiveVerb(l10n, activity.kind),
                        activity.total,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.of(context).control.copyWith(
                        color: AppPalette.of(context).onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.of(context).caption.copyWith(
                        color: AppPalette.of(context).onPrimary
                            .withValues(alpha: 0.65),
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AppButton(
                key: const Key('command-line-cancel'),
                label: activity.cancelling
                    ? l10n.commandLineCancelling
                    : l10n.commandLineCancel,
                size: NeoButtonSize.small,
                loading: activity.cancelling,
                onPressed: activity.cancelling
                    ? null
                    : () => ref
                          .read(commandLineActivityProvider.notifier)
                          .cancel(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DarkProgressBar(
            progress: activity.total == 0
                ? 0
                : activity.completed / activity.total,
          ),
        ],
      ),
    );
  }
}

class _DarkProgressBar extends StatelessWidget {
  const _DarkProgressBar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.clamp(0, 1).toDouble();
    return Semantics(
      value: '${(fraction * 100).round()}%',
      child: SizedBox(
        height: 4,
        child: DecoratedBox(
          decoration: AppCorners.smooth(
            color: AppPalette.of(context).onPrimary.withValues(alpha: 0.15),
            radius: AppRadii.pill,
          ),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: fraction),
            duration: AppMotion.controlMorphDuration,
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: child,
            ),
            child: DecoratedBox(
              key: const Key('command-line-progress-fill'),
              decoration: AppCorners.smooth(
                color: AppPalette.of(context).onPrimary,
                radius: AppRadii.pill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Summary extends ConsumerWidget {
  const _Summary({required this.activity, super.key});

  final CommandLineActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final failures = activity.failures;
    final committed = [
      for (final item in activity.items)
        if (item.status.isCommitted) item.slotKey,
    ];
    final title = StringBuffer(
      activity.kind == CommandLineActivityKind.replaceSource
          ? l10n.commandLineSummaryReplaceSource(activity.committedCount)
          : l10n.commandLineSummaryTitle(
              commandLinePastVerb(l10n, activity.kind),
              activity.committedCount,
            ),
    );
    if (failures.isNotEmpty) {
      title.write(l10n.commandLineSummaryFailedSuffix(failures.length));
    } else if (activity.wasCancelled) {
      title.write(l10n.commandLineCancelledSuffix);
    }
    final allSucceeded = failures.isEmpty && !activity.wasCancelled;
    final detail = [
      l10n.commandLineSummaryOrigin,
      if (activity.agentNames.isNotEmpty)
        l10n.commandLineAgents(activity.agentNames.join(', ')),
      if (allSucceeded) l10n.commandLineSummaryAllSucceeded,
    ].join(' · ');
    final (icon, iconColor) = failures.isNotEmpty
        ? (LucideIcons.triangleAlert, AppPalette.of(context).warning)
        : activity.wasCancelled
        ? (LucideIcons.circleSlash, AppPalette.of(context).textSecondary)
        : (LucideIcons.circleCheck, AppPalette.of(context).success);
    final firstFailure = failures.firstOrNull;
    return NeoSurface(
      style: _neoStyle(context, NeoButtonVariant.secondary),
      borderRadius: _panelRadius,
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toString(),
                      key: const Key('command-line-summary-title'),
                      style: AppTypography.of(context).control.copyWith(
                        color: AppPalette.of(context).ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      key: const Key('command-line-summary-detail'),
                      style: AppTypography.of(context).caption
                          .copyWith(fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
              ),
              CupertinoButton(
                key: const Key('command-line-dismiss'),
                padding: const EdgeInsets.all(4),
                minimumSize: Size.zero,
                onPressed: () =>
                    ref.read(commandLineActivityProvider.notifier).dismiss(),
                child: Icon(
                  LucideIcons.x,
                  size: 16,
                  color: AppPalette.of(context).textSecondary,
                  semanticLabel: l10n.commandLineDismiss,
                ),
              ),
            ],
          ),
          if (failures.isNotEmpty) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              key: const Key('command-line-summary-failures'),
              decoration: AppCorners.smooth(
                radius: 10,
                side: BorderSide(color: AppPalette.of(context).border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, failure) in failures.indexed) ...[
                    if (index > 0)
                      SizedBox(
                        height: 1,
                        child: ColoredBox(color: AppPalette.of(context).border),
                      ),
                    _FailureRow(
                      slotKey: failure.slotKey,
                      reason: commandLineErrorMessage(l10n, failure.errorCode),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (committed.isNotEmpty) ...[
            const SizedBox(height: 12),
            // With failures the successes get a label; when everything
            // succeeded the title already says so.
            if (failures.isNotEmpty || activity.wasCancelled) ...[
              Row(
                children: [
                  Icon(
                    LucideIcons.circleCheck,
                    size: 13,
                    color: AppPalette.of(context).success,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.commandLineSummaryDone(committed.length),
                    style: AppTypography.of(context).caption
                        .copyWith(fontWeight: FontWeight.w400),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            _SkillChips(
              key: const Key('command-line-summary-chips'),
              names: committed,
            ),
          ],
          if (firstFailure != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                key: const Key('command-line-open-skill'),
                label: l10n.commandLineOpenSkill(firstFailure.slotKey),
                icon: LucideIcons.arrowUpRight,
                size: NeoButtonSize.small,
                onPressed: () => context.pushNamed(
                  AppRouteNames.skillDetail,
                  pathParameters: {'skillId': firstFailure.skillId},
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FailureRow extends StatelessWidget {
  const _FailureRow({required this.slotKey, required this.reason});

  final String slotKey;
  final String reason;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            LucideIcons.circleX,
            size: 14,
            color: AppPalette.of(context).danger,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                slotKey,
                style: AppTypography.of(context).caption.copyWith(
                  fontSize: 12.5,
                  color: AppPalette.of(context).ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                reason,
                style: AppTypography.of(context).caption
                    .copyWith(fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Committed Skill names as tags, at most two lines. Names that do not fit
/// fold into a trailing "+N" tag; a name is never split across lines.
class _SkillChips extends StatelessWidget {
  const _SkillChips({required this.names, super.key});

  final List<String> names;

  static const _maxLines = 2;
  static const _gap = 6.0;
  static const _padding = EdgeInsets.symmetric(horizontal: 8, vertical: 3);

  static final _nameStyle = AppTypography.caption.copyWith(
    fontWeight: FontWeight.w400,
  );
  static final _moreStyle = AppTypography.caption.copyWith(
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double widthOf(String text, TextStyle style, {bool bordered = true}) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final width = painter.width + _padding.horizontal + (bordered ? 2 : 0);
      painter.dispose();
      return width;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final widths = [for (final name in names) widthOf(name, _nameStyle)];
        // Mirror Wrap's line breaking to find how many names fit.
        var line = 1;
        var used = 0.0;
        final lineOf = <int>[];
        for (final width in widths) {
          final next = used == 0 ? width : used + _gap + width;
          if (next > maxWidth && used > 0) {
            line++;
            used = width;
          } else {
            used = next;
          }
          lineOf.add(line);
        }
        var shown = lineOf.where((l) => l <= _maxLines).length;
        if (shown < names.length) {
          // Make room on the last line for the "+N" tag.
          double lastLineWidth(int count) {
            var total = 0.0;
            for (var i = 0; i < count; i++) {
              if (lineOf[i] == _maxLines) {
                total += (total == 0 ? 0 : _gap) + widths[i];
              }
            }
            return total;
          }

          while (shown > 0) {
            final more = widthOf(
              l10n.commandLineSummaryMore(names.length - shown),
              _moreStyle,
              bordered: false,
            );
            final last = lastLineWidth(shown);
            if (last + (last == 0 ? 0 : _gap) + more <= maxWidth) break;
            shown--;
          }
        }
        final hidden = names.length - shown;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final name in names.take(shown))
              Container(
                padding: _padding,
                decoration: AppCorners.smooth(
                  color: AppPalette.of(context).surfaceSubtle,
                  radius: 6,
                  side: BorderSide(color: AppPalette.of(context).border),
                ),
                child: Text(
                  name,
                  maxLines: 1,
                  style: _nameStyle.copyWith(
                    color: AppPalette.of(context).bodyContent,
                  ),
                ),
              ),
            if (hidden > 0)
              Padding(
                key: const Key('command-line-summary-more'),
                padding: _padding,
                child: Text(
                  l10n.commandLineSummaryMore(hidden),
                  maxLines: 1,
                  style: _moreStyle.copyWith(
                    color: AppPalette.of(context).textSecondary,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String commandLineProgressiveVerb(
  AppLocalizations l10n,
  CommandLineActivityKind kind,
) => switch (kind) {
  CommandLineActivityKind.activate => l10n.commandLineVerbActivateProgressive,
  CommandLineActivityKind.deactivate =>
    l10n.commandLineVerbDeactivateProgressive,
  CommandLineActivityKind.favorite => l10n.commandLineVerbFavoriteProgressive,
  CommandLineActivityKind.unfavorite =>
    l10n.commandLineVerbUnfavoriteProgressive,
  CommandLineActivityKind.note => l10n.commandLineVerbNoteProgressive,
  CommandLineActivityKind.tagAdd => l10n.commandLineVerbTagAddProgressive,
  CommandLineActivityKind.tagRemove => l10n.commandLineVerbTagRemoveProgressive,
  CommandLineActivityKind.install => l10n.commandLineVerbInstallProgressive,
  CommandLineActivityKind.update => l10n.commandLineVerbUpdateProgressive,
  CommandLineActivityKind.remove => l10n.commandLineVerbRemoveProgressive,
  CommandLineActivityKind.replaceSource =>
    l10n.commandLineVerbReplaceSourceProgressive,
};

String commandLinePastVerb(
  AppLocalizations l10n,
  CommandLineActivityKind kind,
) => switch (kind) {
  CommandLineActivityKind.activate => l10n.commandLineVerbActivatePast,
  CommandLineActivityKind.deactivate => l10n.commandLineVerbDeactivatePast,
  CommandLineActivityKind.favorite => l10n.commandLineVerbFavoritePast,
  CommandLineActivityKind.unfavorite => l10n.commandLineVerbUnfavoritePast,
  CommandLineActivityKind.note => l10n.commandLineVerbNotePast,
  CommandLineActivityKind.tagAdd => l10n.commandLineVerbTagAddPast,
  CommandLineActivityKind.tagRemove => l10n.commandLineVerbTagRemovePast,
  CommandLineActivityKind.install => l10n.commandLineVerbInstallPast,
  CommandLineActivityKind.update => l10n.commandLineVerbUpdatePast,
  CommandLineActivityKind.remove => l10n.commandLineVerbRemovePast,
  CommandLineActivityKind.replaceSource =>
    l10n.commandLineVerbReplaceSourcePast,
};

/// Maps a stable Command Host error code to copy; unknown codes stay generic.
String commandLineErrorMessage(
  AppLocalizations l10n,
  String? code,
) => switch (code) {
  'activationTargetOccupied' => l10n.commandLineErrorActivationTargetOccupied,
  'agentRootOwnershipRepairRequired' => l10n.commandLineErrorOwnershipRepair,
  'unknownAgent' => l10n.commandLineErrorUnknownAgent,
  _ => l10n.commandLineErrorGeneric,
};
