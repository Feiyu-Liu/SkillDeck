import 'dart:async';
import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_dialog.dart';
import 'package:skills_manager/shared/widgets/app_dialog_motion.dart';
import 'package:skills_manager/shared/widgets/app_selection_area.dart';

String cloudNoteAttentionLabel(
  AppLocalizations l10n,
  MetadataAttentionReason reason,
) => switch (reason) {
  MetadataAttentionReason.noteConflict => l10n.cloudNoteConflict,
  MetadataAttentionReason.noteTooLarge => l10n.cloudNoteTooLarge,
};

class CloudNoteReviewAction extends StatelessWidget {
  const CloudNoteReviewAction({
    required this.skillId,
    required this.runtime,
    required this.attention,
    required this.enabled,
    this.onEditNote,
    super.key,
  });

  final String skillId;
  final CloudSyncRuntime runtime;
  final SyncMetadataAttention attention;
  final bool enabled;
  final VoidCallback? onEditNote;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (attention.reason == MetadataAttentionReason.noteTooLarge) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.cloudNoteTooLarge,
            style: AppTypography.of(context).bodyMuted,
          ),
          AppButton(
            key: const Key('cloud-note-edit'),
            label: l10n.cloudNoteEdit,
            size: NeoButtonSize.small,
            onPressed: enabled ? onEditNote : null,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.cloudNoteConflict,
          style: AppTypography.of(context).bodyMuted,
        ),
        AppButton(
          key: const Key('cloud-note-review'),
          style: NeoButtonVariant.primary,
          label: l10n.cloudNoteReview,
          size: NeoButtonSize.small,
          onPressed: enabled && attention.note != null
              ? () => unawaited(
                  AppDialogMotion.show<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => _NoteReviewDialog(
                      skillId: skillId,
                      runtime: runtime,
                      attention: attention,
                    ),
                  ),
                )
              : null,
        ),
      ],
    );
  }
}

class _NoteReviewDialog extends ConsumerStatefulWidget {
  const _NoteReviewDialog({
    required this.skillId,
    required this.runtime,
    required this.attention,
  });

  final String skillId;
  final CloudSyncRuntime runtime;
  final SyncMetadataAttention attention;

  @override
  ConsumerState<_NoteReviewDialog> createState() => _NoteReviewDialogState();
}

class _NoteReviewDialogState extends ConsumerState<_NoteReviewDialog> {
  late var _review = widget.attention;
  final _choice = TextEditingController();
  bool _versionsChanged = false;

  @override
  void initState() {
    super.initState();
    final note = _review.note!;
    _choice.text = {
      ?(note.conflict?.accepted.text ?? note.value),
      ?note.conflict?.incoming.text,
      if (_review.hasUnsubmittedLocalNote) ?_review.localNote,
    }.join('\n\n');
  }

  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _choice.dispose();
    super.dispose();
  }

  void _choose(String? value) {
    final text = value ?? '';
    _choice.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    setState(() {});
  }

  Future<void> _resolve() async {
    if (!identical(ref.read(cloudSyncRuntimeProvider), widget.runtime)) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final text = _choice.text.trim();
    try {
      final outcome = await widget.runtime.resolveNoteConflict(
        widget.skillId,
        expectedVersion: _review.note!.version,
        expectedLocalNote: _review.localNote,
        value: text.isEmpty ? null : text,
      );
      if (!mounted) return;
      if (outcome is SkillSynced) {
        Navigator.pop(context);
        return;
      }
    } on Object {
      if (!mounted) return;
    }
    setState(() {
      _busy = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final active = identical(
      ref.watch(cloudSyncRuntimeProvider),
      widget.runtime,
    );
    final state = ref.watch(cloudSyncStateProvider).value;
    final latest = active && state?.accountId == widget.runtime.accountId
        ? state!.metadataAttention[widget.skillId]
        : null;
    final noConflict =
        latest?.reason != MetadataAttentionReason.noteConflict ||
        latest?.note == null;
    if (!noConflict &&
        (latest!.note!.version != _review.note!.version ||
            latest.localNote != _review.localNote ||
            latest.hasUnsubmittedLocalNote !=
                _review.hasUnsubmittedLocalNote)) {
      _review = latest;
      _versionsChanged = true;
      _failed = false;
    }
    final note = _review.note!;
    String title(CloudNoteCandidate candidate) => candidate.device?.name != null
        ? l10n.cloudNoteFromDevice(candidate.device!.name!)
        : l10n.cloudNoteCloudVersion;
    final accepted =
        note.conflict?.accepted ?? CloudNoteCandidate(note.value, note.device);
    final shown = <(String, CloudNoteCandidate)>[
      (title(accepted), accepted),
      if (note.conflict case final conflict?)
        (title(conflict.incoming), conflict.incoming),
      if (_review.hasUnsubmittedLocalNote)
        (
          l10n.cloudNoteLocalVersion,
          CloudNoteCandidate(_review.localNote, null),
        ),
    ];
    final tooLong = utf8.encode(_choice.text.trim()).length > 4096;
    return AppDialogScaffold(
      width: 620,
      onEscape: _busy ? null : () => Navigator.pop(context),
      header: AppDialogHeader(
        title: l10n.cloudNoteReviewTitle,
        icon: LucideIcons.fileWarning,
      ),
      sections: [
        if (active)
          for (final (label, candidate) in shown)
            AppDialogSection(
              title: label,

              trailing: AppButton(
                label: l10n.cloudNoteUseVersion,
                size: NeoButtonSize.small,
                onPressed: _busy ? null : () => _choose(candidate.text),
              ),
              child: AppSelectionArea(
                child: Text(candidate.text ?? l10n.cloudNoteEmpty),
              ),
            ),
      ],
      footer: ColoredBox(
        color: AppPalette.of(context).surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (noConflict)
              AppDialogSection(child: Text(l10n.cloudNoteConflictGone))
            else
              AppDialogSection(
                title: l10n.cloudNoteResolution,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_failed || _versionsChanged || tooLong)
                      Text(
                        tooLong
                            ? l10n.cloudNoteEditorTooLarge
                            : _failed
                            ? l10n.cloudNoteResolutionFailed
                            : l10n.cloudNoteVersionsChanged,
                      ),
                    CupertinoTextField(
                      key: const Key('cloud-note-resolution-text'),
                      controller: _choice,
                      enabled: !_busy && active,
                      minLines: 4,
                      maxLines: 4,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
            AppDialogFooter(
              actions: [
                if (!noConflict)
                  AppButton(
                    label: l10n.commonCancel,
                    onPressed: _busy ? null : () => Navigator.pop(context),
                  ),
                AppButton(
                  key: const Key('cloud-note-resolve'),
                  label: noConflict
                      ? l10n.commonClose
                      : l10n.cloudNoteSaveResolution,
                  style: NeoButtonVariant.primary,
                  loading: _busy,
                  onPressed: noConflict
                      ? () => Navigator.pop(context)
                      : _busy || tooLong || !active
                      ? null
                      : () => unawaited(_resolve()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
