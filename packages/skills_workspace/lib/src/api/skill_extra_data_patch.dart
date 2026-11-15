import '../domain/identifiers.dart';
import 'revision_transfer.dart';

/// Omitted fields stay unchanged. `noteChanged: true, note: null` clears Note.
/// Tag identities are local Personal Tag IDs; remote tag mapping stays outside.
final class SkillExtraDataPatch {
  SkillExtraDataPatch({
    this.favorite,
    this.noteChanged = false,
    String? note,
    Set<String> addPersonalTagIds = const {},
    Set<String> removePersonalTagIds = const {},
  }) : note = note?.trim(),
       addPersonalTagIds = Set.unmodifiable(addPersonalTagIds),
       removePersonalTagIds = Set.unmodifiable(removePersonalTagIds) {
    if (!noteChanged && note != null ||
        noteChanged && note != null && note.trim().isEmpty ||
        addPersonalTagIds.intersection(removePersonalTagIds).isNotEmpty ||
        addPersonalTagIds.length + removePersonalTagIds.length > 1000 ||
        [
          ...addPersonalTagIds,
          ...removePersonalTagIds,
        ].any((id) => id.isEmpty || id.length > 256) ||
        favorite == null &&
            !noteChanged &&
            addPersonalTagIds.isEmpty &&
            removePersonalTagIds.isEmpty) {
      throw ArgumentError('Invalid Skill Extra Data patch.');
    }
    if (note != null && note.length > 1024 * 1024) {
      throw ArgumentError('Note exceeds the patch budget.');
    }
  }
  final bool? favorite;
  final bool noteChanged;
  final String? note;
  final Set<String> addPersonalTagIds, removePersonalTagIds;
}

final class ReserveSkillExtraDataPatchRequest {
  const ReserveSkillExtraDataPatchRequest({
    required this.managedSkillId,
    required this.expectedIdentity,
    required this.expectedRevision,
    required this.localOperationId,
    required this.patch,
  });
  final ManagedSkillId managedSkillId;
  final WorkspaceIdentity expectedIdentity;
  final RepositoryRevision expectedRevision;
  final OperationId localOperationId;
  final SkillExtraDataPatch patch;
}

final class ApplySkillExtraDataPatchRequest {
  const ApplySkillExtraDataPatchRequest({
    required this.binding,
    required this.expectedRevision,
    required this.patch,
  });
  final IncomingRevisionCommandBinding binding;
  final RepositoryRevision expectedRevision;
  final SkillExtraDataPatch patch;
}
