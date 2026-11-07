import 'dart:async';

import 'package:skills_manager/features/command_host/data/command_approval.dart';

final class ApprovalPresenter implements CommandApprovalPresenter {
  final requests = <CommandApprovalRequest>[];
  final withdrawn = <String>[];
  final decisions = <Completer<CommandApprovalDecision>>[];
  final presented = Completer<void>();

  @override
  Future<CommandApprovalDecision> present(CommandApprovalRequest request) {
    requests.add(request);
    final decision = Completer<CommandApprovalDecision>();
    decisions.add(decision);
    if (!presented.isCompleted) presented.complete();
    return decision.future;
  }

  void decide(CommandApprovalDecision decision) =>
      decisions.last.complete(decision);

  @override
  void withdraw(String requestId) {
    withdrawn.add(requestId);
    if (requests.last.id == requestId && !decisions.last.isCompleted) {
      decide(const CommandApprovalWithdrawn());
    }
  }
}
