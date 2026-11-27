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
    return AppButton(
      key: const Key('cloud-note-review'),
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
  bool _chosen = false;
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
    setState(() => _chosen = true);
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
    final note = _review.note!;
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
    final shown = <(String, CloudNoteCandidate)>[
      (
        l10n.cloudNoteCloudVersion,
        note.conflict?.accepted ?? CloudNoteCandidate(note.value, note.device),
      ),
      if (note.conflict case final conflict?)
        (l10n.cloudNoteOtherVersion, conflict.incoming),
      if (_review.hasUnsubmittedLocalNote)
        (
          l10n.cloudNoteLocalVersion,
          CloudNoteCandidate(_review.localNote, null),
        ),
    ];
    final changed =
        !noConflict &&
        (latest!.note!.version != note.version ||
            latest.localNote != _review.localNote ||
            latest.hasUnsubmittedLocalNote != _review.hasUnsubmittedLocalNote);
    final tooLong = utf8.encode(_choice.text.trim()).length > 4096;
    return AppDialogScaffold(
      width: 620,
      onEscape: _busy ? null : () => Navigator.pop(context),
      header: AppDialogHeader(
        title: l10n.cloudNoteReview,
        icon: LucideIcons.fileWarning,
      ),
      sections: [
        if (active)
          for (final (label, candidate) in shown)
            AppDialogSection(
              title: label,
              subtitle: candidate.device?.name ?? candidate.device?.platform,
              trailing: AppButton(
                label: l10n.cloudNoteUseVersion,
                size: NeoButtonSize.small,
                onPressed: _busy ? null : () => _choose(candidate.text),
              ),
              child: AppSelectionArea(
                child: Text(candidate.text ?? l10n.cloudNoteEmpty),
              ),
            ),
        AppDialogSection(
          title: l10n.cloudNoteResolution,
          trailing: !active
              ? null
              : AppButton(
                  label: l10n.cloudNoteCombine,
                  size: NeoButtonSize.small,
                  onPressed: _busy
                      ? null
                      : () => _choose(
                          {for (final (_, candidate) in shown) ?candidate.text}
                              .join('\n\n'),
                        ),
                ),
          child: CupertinoTextField(
            key: const Key('cloud-note-resolution-text'),
            controller: _choice,
            enabled: !_busy,
            minLines: 2,
            maxLines: 6,
            onChanged: (_) => setState(() => _chosen = true),
          ),
        ),
        if (_failed || changed || tooLong || noConflict)
          AppDialogSection(
            trailing: changed
                ? AppButton(
                    label: l10n.cloudNoteReviewLatest,
                    size: NeoButtonSize.small,
                    onPressed: _busy
                        ? null
                        : () => setState(() => _review = latest),
                  )
                : null,
            child: Text(switch ((active, noConflict, changed, tooLong)) {
              (true, true, _, _) => l10n.cloudNoteConflictGone,
              (true, _, true, _) => l10n.cloudNoteVersionsChanged,
              (true, _, _, true) => l10n.cloudNoteTooLarge,
              _ => l10n.cloudNoteResolutionFailed,
            }),
          ),
      ],
      footer: AppDialogFooter(
        actions: [
          AppButton(
            label: l10n.commonClose,
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
          AppButton(
            key: const Key('cloud-note-resolve'),
            label: l10n.cloudNoteSaveResolution,
            style: NeoButtonVariant.primary,
            onPressed: _busy || !_chosen || tooLong || changed || noConflict
                ? null
                : () => unawaited(_resolve()),
          ),
        ],
      ),
    );
  }
}
