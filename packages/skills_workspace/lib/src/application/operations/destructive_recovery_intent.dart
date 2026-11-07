import '../../domain/identifiers.dart';
import '../runtime/revision_engine_port.dart';
import 'operation_models.dart';
import 'workspace_business_changes.dart';

/// One private Source Lineage that destructive recovery may need to restore
/// before the BCP or permanently remove after it.
final class RecoverySourceLineageIntent {
  const RecoverySourceLineageIntent({required this.sourceLineage});

  final SourceLineageReference sourceLineage;
}

/// Path-free identity of one managed aggregate involved in destruction.
///
/// Concrete recovery resolves these IDs to private Store, Bundle, Draft,
/// Repository Copy and Activation paths only while building its durable bundle.
final class DestructiveSkillRecoveryIntent {
  DestructiveSkillRecoveryIntent({
    required this.managedSkillId,
    required this.slotKey,
    required List<RecoverySourceLineageIntent> sourceLineages,
    required List<String> activationIds,
    required this.hasDraft,
    required this.hasUpdateCandidateSession,
  }) : sourceLineages = List.unmodifiable(sourceLineages),
       activationIds = List.unmodifiable(activationIds) {
    _requireText(slotKey, 'slotKey');
    if (sourceLineages.isEmpty) {
      throw ArgumentError.value(
        sourceLineages,
        'sourceLineages',
        'must not be empty',
      );
    }
    if (sourceLineages.map((lineage) => lineage.sourceLineage).toSet().length !=
        sourceLineages.length) {
      throw ArgumentError.value(
        sourceLineages,
        'sourceLineages',
        'contains duplicates',
      );
    }
    if (activationIds.any((id) => id.trim().isEmpty) ||
        activationIds.toSet().length != activationIds.length) {
      throw ArgumentError.value(
        activationIds,
        'activationIds',
        'must contain unique non-empty IDs',
      );
    }
  }

  final ManagedSkillId managedSkillId;
  final String slotKey;
  final List<RecoverySourceLineageIntent> sourceLineages;
  final List<String> activationIds;
  final bool hasDraft;
  final bool hasUpdateCandidateSession;
}

sealed class DestructiveOperationRecoveryIntent {
  DestructiveOperationRecoveryIntent({
    required List<DestructiveSkillRecoveryIntent> skills,
  }) : skills = List.unmodifiable(skills) {
    if (skills.isEmpty ||
        skills.map((skill) => skill.managedSkillId).toSet().length !=
            skills.length) {
      throw ArgumentError.value(
        skills,
        'skills',
        'must contain unique managed Skills',
      );
    }
  }

  final List<DestructiveSkillRecoveryIntent> skills;
}

final class SourceReplacementRecoveryIntent
    extends DestructiveOperationRecoveryIntent {
  SourceReplacementRecoveryIntent({
    required DestructiveSkillRecoveryIntent skill,
    required this.intendedSourceLineage,
    required this.intendedSlotKey,
    required this.intendedObjectId,
    required this.intendedContentHash,
    required this.intendedObjectFormat,
  }) : super(skills: [skill]) {
    _requireText(intendedSlotKey, 'intendedSlotKey');
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(intendedContentHash)) {
      throw ArgumentError.value(
        intendedContentHash,
        'intendedContentHash',
        'must be a lowercase SHA-256 digest',
      );
    }
    if (skill.sourceLineages.any(
      (lineage) => lineage.sourceLineage == intendedSourceLineage,
    )) {
      throw ArgumentError(
        'Source Replacement must use a fresh Source Lineage.',
      );
    }
  }

  DestructiveSkillRecoveryIntent get skill => skills.single;
  final SourceLineageReference intendedSourceLineage;
  final String intendedSlotKey;
  final RevisionObjectId intendedObjectId;
  final String intendedContentHash;
  final WorkspaceObjectFormat intendedObjectFormat;
}

final class RemovalRecoveryIntent extends DestructiveOperationRecoveryIntent {
  RemovalRecoveryIntent({required super.skills});
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'must be non-empty text');
  }
}
