import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/features/skills/models/skill_source_link.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_tooltip.dart';

class SkillSourceLinkValue extends ConsumerStatefulWidget {
  const SkillSourceLinkValue({required this.source, super.key});

  final SkillSourceProvenance? source;

  @override
  ConsumerState<SkillSourceLinkValue> createState() =>
      _SkillSourceLinkValueState();
}

class _SkillSourceLinkValueState extends ConsumerState<SkillSourceLinkValue> {
  bool _copying = false;
  int _operation = 0;

  @override
  void didUpdateWidget(covariant SkillSourceLinkValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source?.locator != widget.source?.locator ||
        oldWidget.source?.kind != widget.source?.kind) {
      _operation++;
      _copying = false;
    }
  }

  Future<void> _copy(String address) async {
    if (_copying) return;
    _copying = true;
    final operation = ++_operation;
    var copied = false;
    try {
      await Clipboard.setData(ClipboardData(text: address));
      copied = true;
    } on Object {
      // Clipboard errors can contain the original address. Do not log them.
    }
    if (!mounted || operation != _operation) return;
    _copying = false;
    final notifications = ref.read(appNotificationControllerProvider.notifier);
    if (copied) {
      notifications.success(AppNotificationMessage.sourceCopied);
    } else {
      notifications.error(AppNotificationMessage.sourceCopyFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = SkillSourceLink.fromSource(widget.source);
    final style = AppTypography.of(context).mono.copyWith(
      fontWeight: FontWeight.w700,
      color: AppPalette.of(context).textPrimary,
    );
    if (link.copyText == null) {
      return Text(
        context.l10n.workspaceSourceUnavailable,
        style: style,
        overflow: TextOverflow.ellipsis,
      );
    }
    final label = link.label.isEmpty
        ? context.l10n.workspaceSourceAddress
        : link.label;
    final actionLabel = context.l10n.workspaceCopySource(label);
    final buttonTheme = NeoButtonTheme.of(context);
    return AppTooltip(
      message: actionLabel,
      maxWidth: 480,
      maxLines: null,
      child: NeoButtonTheme(
        data: buttonTheme.copyWith(
          medium: buttonTheme.medium.copyWith(horizontalPadding: 4),
        ),
        child: AppButton(
          key: const Key('skill-source-link'),
          label: label,
          semanticsLabel: actionLabel,
          textStyle: style.copyWith(decoration: TextDecoration.underline),
          style: NeoButtonVariant.ghost,
          contentAlignment: MainAxisAlignment.start,
          onPressed: () => _copy(link.copyText!),
        ),
      ),
    );
  }
}
