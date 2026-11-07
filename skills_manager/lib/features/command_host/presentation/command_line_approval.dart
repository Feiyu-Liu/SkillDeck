import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:skills_manager/shared/platform/window_attention.dart';

import '../data/command_approval.dart';

/// The one approval the App is showing, if any.
final commandLineApprovalProvider =
    NotifierProvider<CommandLineApprovalController, CommandApprovalRequest?>(
      CommandLineApprovalController.new,
    );

/// What the Command Host presents approvals through.
final commandApprovalPresenterProvider = Provider<CommandApprovalPresenter>(
  (ref) => ref.watch(commandLineApprovalProvider.notifier),
);

/// Holds the approval sheet's request and hands the user's decision back to
/// the Command Host. The sheet itself only reads [state] and calls
/// [approve] or [deny].
final class CommandLineApprovalController
    extends Notifier<CommandApprovalRequest?>
    implements CommandApprovalPresenter {
  Completer<CommandApprovalDecision>? _decision;

  @override
  CommandApprovalRequest? build() {
    ref.onDispose(() => _complete(const CommandApprovalWithdrawn()));
    return null;
  }

  @override
  Future<CommandApprovalDecision> present(CommandApprovalRequest request) {
    // The Command Host admits one pending request. A fresh review of the same
    // request (after a stale confirmation) updates the open sheet in place
    // rather than closing and reopening it.
    final reviewAgain = state?.id == request.id;
    _complete(const CommandApprovalWithdrawn(), close: !reviewAgain);
    final decision = Completer<CommandApprovalDecision>();
    _decision = decision;
    state = request;
    return decision.future;
  }

  @override
  void withdraw(String requestId) {
    if (state?.id != requestId) return;
    _complete(const CommandApprovalWithdrawn());
  }

  /// The user confirmed what the sheet showed at [reviewedRevision].
  void approve({required int reviewedRevision}) =>
      _complete(CommandApprovalApproved(reviewedRevision: reviewedRevision));

  void deny() => _complete(const CommandApprovalDenied());

  void _complete(CommandApprovalDecision decision, {bool close = true}) {
    final pending = _decision;
    _decision = null;
    if (pending != null && !pending.isCompleted) pending.complete(decision);
    if (close && ref.mounted) state = null;
  }
}

/// Brings the window forward for a new approval. Tests replace it.
final commandLineApprovalAttentionProvider = Provider<Future<void> Function()>(
  (ref) => requestWindowAttention,
);
