/// Advisory notification that some Draft filesystem activity occurred.
///
/// The token intentionally carries no path, event kind, or dirty-state claim.
/// Consumers must perform an authoritative full Draft comparison before making
/// any business decision.
final class DraftChangeHint {
  const DraftChangeHint();
}

/// Observes best-effort Draft filesystem activity.
///
/// Implementations may coalesce, duplicate, reorder, or miss events. This port
/// is suitable only for scheduling a refresh; it is never correctness evidence.
abstract interface class DraftChangeHintPort {
  Stream<DraftChangeHint> watchDraft(String draftPath);
}
