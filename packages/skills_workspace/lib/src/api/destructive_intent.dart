import '../domain/identifiers.dart';

/// Proof that a destructive operation was confirmed against a reviewed state.
///
/// Removal and Source Replacement compare [reviewedRevision] with the current
/// authoritative revision after acquiring the writer lease and before they
/// plan, journal, or mutate anything.
final class DestructiveIntent {
  /// Creates an intent bound to the repository state reviewed by the caller.
  const DestructiveIntent({required this.reviewedRevision});

  /// The repository revision shown when the destructive action was confirmed.
  final RepositoryRevision reviewedRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DestructiveIntent && reviewedRevision == other.reviewedRevision;

  @override
  int get hashCode => reviewedRevision.hashCode;

  @override
  String toString() => 'DestructiveIntent(reviewedRevision: $reviewedRevision)';
}
