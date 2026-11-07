final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Stable business identity for one managed Skill.
///
/// The value is deliberately distinct from the Skill's mutable Slot Key and
/// from all revision-store object identifiers.
final class ManagedSkillId {
  /// Decodes a canonical UUIDv4 managed-Skill identity.
  ManagedSkillId(String value) : value = _requireUuidV4(value, 'value');

  /// The canonical persistence representation.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ManagedSkillId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'ManagedSkillId($value)';
}

/// Monotonic revision of the complete repository snapshot.
final class RepositoryRevision implements Comparable<RepositoryRevision> {
  /// Creates a non-negative repository revision.
  RepositoryRevision(this.value) {
    if (value < 0) {
      throw ArgumentError.value(value, 'value', 'must not be negative');
    }
  }

  /// The initial empty-workspace revision.
  factory RepositoryRevision.initial() => RepositoryRevision(0);

  /// The monotonic integer representation.
  final int value;

  /// Returns the immediately following revision.
  RepositoryRevision next() => RepositoryRevision(value + 1);

  @override
  int compareTo(RepositoryRevision other) => value.compareTo(other.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RepositoryRevision && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'RepositoryRevision($value)';
}

/// Stable identity shared by an operation's Journal and history Record.
final class OperationId {
  /// Decodes a canonical UUIDv4 operation identity.
  OperationId(String value) : value = _requireUuidV4(value, 'value');

  /// The canonical persistence representation.
  final String value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OperationId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'OperationId($value)';
}

/// Identifies one per-Skill subject within a user-visible operation.
///
/// The composite reference is used for historical selection so no independent
/// public Skill Revision identity is required.
final class OperationSubjectReference {
  /// Creates a reference to a persisted operation subject.
  OperationSubjectReference({
    required this.operationId,
    required String subjectId,
  }) : subjectId = _requireUuidV4(subjectId, 'subjectId');

  /// The operation that owns the subject.
  final OperationId operationId;

  /// The canonical identity of the subject row within that operation.
  final String subjectId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OperationSubjectReference &&
          operationId == other.operationId &&
          subjectId == other.subjectId;

  @override
  int get hashCode => Object.hash(operationId, subjectId);

  @override
  String toString() =>
      'OperationSubjectReference(operationId: $operationId, '
      'subjectId: $subjectId)';
}

String _requireUuidV4(String value, String name) {
  if (!_uuidV4Pattern.hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a canonical lowercase UUIDv4',
    );
  }
  return value;
}
