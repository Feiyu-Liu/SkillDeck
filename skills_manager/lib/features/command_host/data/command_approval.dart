import 'package:flutter/foundation.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

/// A destructive command-line request waiting for the user in the App.
///
/// ADR-0111 decision 6: the CLI can only ask. The user confirms in the App
/// against the Repository Revision they reviewed, exactly like the GUI's own
/// destructive confirmations (ADR-0055).
sealed class CommandApprovalSubject {
  const CommandApprovalSubject();
}

/// Removal of Managed Skills. The sheet derives each Skill's one-line
/// disclosure from the current Snapshot, so it stays current while open.
final class CommandApprovalRemoveSkills extends CommandApprovalSubject {
  CommandApprovalRemoveSkills(List<String> skillIds)
    : skillIds = List.unmodifiable(skillIds);

  /// `WorkspaceSkillId.value`s, in the order the command resolved them.
  final List<String> skillIds;
}

/// Source Replacement for Managed Skills, one new Source per Skill. The
/// Workspace validates each replacement again when it runs; the sheet only
/// shows which Source each Skill would follow afterwards.
final class CommandApprovalReplaceSource extends CommandApprovalSubject {
  CommandApprovalReplaceSource(List<CommandApprovalReplaceSourceItem> items)
    : items = List.unmodifiable(items);

  /// In the order the command resolved them; executed in this order too.
  final List<CommandApprovalReplaceSourceItem> items;
}

final class CommandApprovalReplaceSourceItem {
  const CommandApprovalReplaceSourceItem({
    required this.skillId,
    required this.source,
    required this.candidateDeclaredName,
  });

  /// `WorkspaceSkillId.value`.
  final String skillId;

  /// Already narrowed to one candidate through `skillPath`.
  final SkillSourceInput source;

  final String candidateDeclaredName;
}

/// Deletion of one Personal Tag, which unassigns it from every Skill.
final class CommandApprovalDeleteTag extends CommandApprovalSubject {
  const CommandApprovalDeleteTag({required this.tagId});

  final String tagId;
}

@immutable
final class CommandApprovalRequest {
  const CommandApprovalRequest({
    required this.id,
    required this.subject,
    required this.expiresAt,
    this.staleReview = false,
  });

  /// Opaque, printed by the CLI for `skilldeck approvals wait <id>`.
  final String id;
  final CommandApprovalSubject subject;
  final DateTime expiresAt;

  /// True when an earlier confirmation was rejected because the Repository
  /// changed after the user reviewed it; the sheet asks for a fresh review.
  final bool staleReview;

  CommandApprovalRequest asStale() => CommandApprovalRequest(
    id: id,
    subject: subject,
    expiresAt: expiresAt,
    staleReview: true,
  );
}

sealed class CommandApprovalDecision {
  const CommandApprovalDecision();
}

/// The user confirmed what they saw at [reviewedRevision].
final class CommandApprovalApproved extends CommandApprovalDecision {
  const CommandApprovalApproved({required this.reviewedRevision});

  final int reviewedRevision;
}

final class CommandApprovalDenied extends CommandApprovalDecision {
  const CommandApprovalDenied();
}

/// The request left the App without a decision: expired, cancelled from the
/// CLI, or replaced. The presenter only closes its sheet.
final class CommandApprovalWithdrawn extends CommandApprovalDecision {
  const CommandApprovalWithdrawn();
}

/// The App side of an approval. The Command Host calls [present] once per
/// review, again with [CommandApprovalRequest.asStale] after a stale
/// confirmation, and [withdraw] when a request ends without the user.
///
/// [present] brings the window forward without taking keyboard focus and
/// completes when the user decides or the request is withdrawn.
abstract interface class CommandApprovalPresenter {
  Future<CommandApprovalDecision> present(CommandApprovalRequest request);

  void withdraw(String requestId);
}
