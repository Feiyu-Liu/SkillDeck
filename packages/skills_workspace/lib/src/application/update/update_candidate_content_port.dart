import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../operations/operation_models.dart';
import '../runtime/revision_engine_port.dart';

final class UpdateCandidateContent {
  const UpdateCandidateContent({
    required this.declaredName,
    required this.slotKey,
    required this.description,
  });

  final String declaredName;
  final String slotKey;
  final String description;
}

/// Projects user-visible candidate metadata from immutable Revision Store
/// content. SQLite intentionally stores revision addresses rather than a
/// second copy of Skill frontmatter.
abstract interface class UpdateCandidateContentPort {
  Future<UpdateCandidateContent?> readCandidateContent({
    required ManagedSkillId managedSkillId,
    required SourceLineageReference sourceLineage,
    required RevisionObjectId candidateObjectId,
    required CancellationToken cancellationToken,
  });
}
