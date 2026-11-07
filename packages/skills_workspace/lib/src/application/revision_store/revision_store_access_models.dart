import '../operations/operation_models.dart';
import '../runtime/revision_engine_port.dart';

/// One current Effective Revision resolved from a single SQLite snapshot.
final class CurrentEffectiveRevisionSelection {
  const CurrentEffectiveRevisionSelection({
    required this.sourceLineage,
    required this.objectId,
  });

  final SourceLineageReference sourceLineage;
  final RevisionObjectId objectId;

  RevisionAddress get address =>
      RevisionAddress(sourceLineage: sourceLineage, objectId: objectId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CurrentEffectiveRevisionSelection &&
          sourceLineage == other.sourceLineage &&
          objectId == other.objectId;

  @override
  int get hashCode => Object.hash(sourceLineage, objectId);
}

enum RevisionStoreAccessFailureCode {
  selectionUnavailable,
  selectionChangedRepeatedly,
  cancelled,
}

final class RevisionStoreAccessException implements Exception {
  const RevisionStoreAccessException(this.code);

  final RevisionStoreAccessFailureCode code;

  @override
  String toString() => 'RevisionStoreAccessException(${code.name})';
}
