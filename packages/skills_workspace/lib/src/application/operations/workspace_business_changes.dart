import '../../domain/identifiers.dart';

enum WorkspaceObjectFormat { sha1, sha256 }

enum WorkspaceSourceKind { local, git, wellKnown, adoptedSnapshot }

enum WorkspaceRevisionValidationState { valid, invalid }

enum WorkspaceDraftPurpose { customization, updateCandidateResolution }

enum WorkspaceUpdateCandidateStatus { conflicted, validationFailed }

enum WorkspaceUpdateCandidateItemKind {
  text,
  rename,
  deleteModify,
  binary,
  executableMode,
}

enum WorkspaceUpdateCandidateItemState { unresolved, resolved }

enum WorkspaceActivationScope { global, project }

enum WorkspaceActivationMode { copy, symbolicLink }

/// A versioned, exhaustive set of SQLite business mutations.
///
/// Values are operation-plan data, never closures, DAOs, companions, or SQL.
final class WorkspaceBusinessChangeSet {
  factory WorkspaceBusinessChangeSet({
    List<WorkspaceBusinessMutation> mutations =
        const <WorkspaceBusinessMutation>[],
    bool incrementsDestructionEpoch = false,
  }) => WorkspaceBusinessChangeSet._(
    List<WorkspaceBusinessMutation>.unmodifiable(mutations),
    incrementsDestructionEpoch,
  );

  const WorkspaceBusinessChangeSet._(
    this.mutations,
    this.incrementsDestructionEpoch,
  );

  static const int currentSchemaVersion = 2;
  static const WorkspaceBusinessChangeSet empty = WorkspaceBusinessChangeSet._(
    <WorkspaceBusinessMutation>[],
    false,
  );

  final List<WorkspaceBusinessMutation> mutations;
  final bool incrementsDestructionEpoch;

  bool get isEmpty => mutations.isEmpty && !incrementsDestructionEpoch;
}

sealed class WorkspaceBusinessMutation {
  const WorkspaceBusinessMutation();
}

final class PutManagedSkill extends WorkspaceBusinessMutation {
  PutManagedSkill({
    required this.managedSkillId,
    required this.slotKey,
    required this.declaredName,
    required this.displayName,
    required this.description,
    required this.activeSourceLineageId,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  }) {
    _requireText(slotKey, 'slotKey');
    _requireText(declaredName, 'declaredName');
    _requireText(displayName, 'displayName');
    _requireText(description, 'description');
    _requireText(activeSourceLineageId, 'activeSourceLineageId');
    _requireTimestampRange(createdAtMicros, updatedAtMicros);
  }

  final ManagedSkillId managedSkillId;
  final String slotKey;
  final String declaredName;
  final String displayName;
  final String description;
  final String activeSourceLineageId;
  final int createdAtMicros;
  final int updatedAtMicros;
}

final class DeleteManagedSkill extends WorkspaceBusinessMutation {
  const DeleteManagedSkill(this.managedSkillId);

  final ManagedSkillId managedSkillId;
}

final class PutSourceLineage extends WorkspaceBusinessMutation {
  PutSourceLineage({
    required this.sourceLineageId,
    required this.managedSkillId,
    required this.objectFormat,
    required this.createdAtMicros,
  }) {
    _requireText(sourceLineageId, 'sourceLineageId');
    _requireTimestamp(createdAtMicros, 'createdAtMicros');
  }

  final String sourceLineageId;
  final ManagedSkillId managedSkillId;
  final WorkspaceObjectFormat objectFormat;
  final int createdAtMicros;
}

final class DeleteSourceLineage extends WorkspaceBusinessMutation {
  DeleteSourceLineage(this.sourceLineageId) {
    _requireText(sourceLineageId, 'sourceLineageId');
  }

  final String sourceLineageId;
}

final class PutSkillSource extends WorkspaceBusinessMutation {
  PutSkillSource({
    required this.sourceLineageId,
    required this.kind,
    required this.payloadSchemaVersion,
    required this.payloadJson,
  }) {
    _requireText(sourceLineageId, 'sourceLineageId');
    if (payloadSchemaVersion < 1) {
      throw ArgumentError.value(
        payloadSchemaVersion,
        'payloadSchemaVersion',
        'must be positive',
      );
    }
    _requireText(payloadJson, 'payloadJson');
  }

  final String sourceLineageId;
  final WorkspaceSourceKind kind;
  final int payloadSchemaVersion;
  final String payloadJson;
}

final class PutRevisionMetadata extends WorkspaceBusinessMutation {
  PutRevisionMetadata({
    required this.sourceLineageId,
    required this.objectId,
    required this.contentHash,
    required this.fileCount,
    required this.byteSize,
    required this.declaredName,
    required this.validationState,
    required this.validationCode,
    required this.createdAtMicros,
  }) {
    _requireText(sourceLineageId, 'sourceLineageId');
    _requireText(objectId, 'objectId');
    _requireHash(contentHash, 'contentHash');
    if (fileCount < 0 || byteSize < 0) {
      throw ArgumentError('Revision counts must not be negative.');
    }
    _requireText(declaredName, 'declaredName');
    if (validationState == WorkspaceRevisionValidationState.valid &&
        validationCode != null) {
      throw ArgumentError('A valid Revision cannot have a validation code.');
    }
    if (validationState == WorkspaceRevisionValidationState.invalid) {
      _requireText(validationCode, 'validationCode');
    }
    _requireTimestamp(createdAtMicros, 'createdAtMicros');
  }

  final String sourceLineageId;
  final String objectId;
  final String contentHash;
  final int fileCount;
  final int byteSize;
  final String declaredName;
  final WorkspaceRevisionValidationState validationState;
  final String? validationCode;
  final int createdAtMicros;
}

final class PutProjectRoot extends WorkspaceBusinessMutation {
  PutProjectRoot({
    required this.projectRootId,
    required this.canonicalPath,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  }) {
    _requireText(projectRootId, 'projectRootId');
    _requireText(canonicalPath, 'canonicalPath');
    _requireTimestampRange(createdAtMicros, updatedAtMicros);
  }

  final String projectRootId;
  final String canonicalPath;
  final int createdAtMicros;
  final int updatedAtMicros;
}

final class DeleteProjectRoot extends WorkspaceBusinessMutation {
  DeleteProjectRoot(this.projectRootId) {
    _requireText(projectRootId, 'projectRootId');
  }

  /// Unregisters only the live root.
  ///
  /// Existing project Activations retain this ID and their absolute path as
  /// provenance snapshots; they are neither deleted nor detached.
  final String projectRootId;
}

final class PutActivation extends WorkspaceBusinessMutation {
  PutActivation({
    required this.activationId,
    required this.managedSkillId,
    required this.canonicalPath,
    required this.scope,
    required this.mode,
    required this.projectRootId,
    required this.projectRootPath,
    required List<String> agentIds,
    required this.createdAtMicros,
  }) : agentIds = List<String>.unmodifiable(agentIds) {
    _requireText(activationId, 'activationId');
    _requireText(canonicalPath, 'canonicalPath');
    _requireTimestamp(createdAtMicros, 'createdAtMicros');
    if (scope == WorkspaceActivationScope.global &&
        (projectRootId != null || projectRootPath != null)) {
      throw ArgumentError('A global Activation cannot have a Project Root.');
    }
    if (scope == WorkspaceActivationScope.project) {
      _requireText(projectRootId, 'projectRootId');
      _requireText(projectRootPath, 'projectRootPath');
    }
    if (agentIds.isEmpty || agentIds.any((id) => id.trim().isEmpty)) {
      throw ArgumentError.value(agentIds, 'agentIds', 'must not be empty');
    }
    if (agentIds.toSet().length != agentIds.length) {
      throw ArgumentError.value(agentIds, 'agentIds', 'contains duplicates');
    }
  }

  final String activationId;
  final ManagedSkillId managedSkillId;
  final String canonicalPath;
  final WorkspaceActivationScope scope;
  final WorkspaceActivationMode mode;
  final String? projectRootId;
  final String? projectRootPath;
  final List<String> agentIds;
  final int createdAtMicros;
}

final class DeleteActivation extends WorkspaceBusinessMutation {
  DeleteActivation(this.activationId) {
    _requireText(activationId, 'activationId');
  }

  final String activationId;
}

final class PutSkillUserData extends WorkspaceBusinessMutation {
  PutSkillUserData({
    required this.managedSkillId,
    required this.favorite,
    required this.favoriteChangedAtMicros,
    required this.note,
    required this.noteUpdatedAtMicros,
  }) {
    if (favorite && favoriteChangedAtMicros == null) {
      throw ArgumentError('A favorite requires its changed timestamp.');
    }
    if (!favorite && favoriteChangedAtMicros != null) {
      throw ArgumentError('A cleared favorite cannot retain its timestamp.');
    }
    if (note == null && noteUpdatedAtMicros != null) {
      throw ArgumentError('A cleared note cannot retain its timestamp.');
    }
    if (note != null) {
      _requireText(note, 'note');
      if (noteUpdatedAtMicros == null) {
        throw ArgumentError('A note requires its updated timestamp.');
      }
    }
    if (favoriteChangedAtMicros case final value?) {
      _requireTimestamp(value, 'favoriteChangedAtMicros');
    }
    if (noteUpdatedAtMicros case final value?) {
      _requireTimestamp(value, 'noteUpdatedAtMicros');
    }
  }

  final ManagedSkillId managedSkillId;
  final bool favorite;
  final int? favoriteChangedAtMicros;
  final String? note;
  final int? noteUpdatedAtMicros;
}

final class DeleteSkillUserData extends WorkspaceBusinessMutation {
  const DeleteSkillUserData(this.managedSkillId);

  final ManagedSkillId managedSkillId;
}

final class PutPersonalTag extends WorkspaceBusinessMutation {
  PutPersonalTag({
    required this.personalTagId,
    required this.normalizedKey,
    required this.displayName,
    required this.color,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  }) {
    _requireText(personalTagId, 'personalTagId');
    _requireText(normalizedKey, 'normalizedKey');
    _requireText(displayName, 'displayName');
    if (color != null && !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color!)) {
      throw ArgumentError.value(color, 'color', 'must be #RRGGBB');
    }
    _requireTimestampRange(createdAtMicros, updatedAtMicros);
  }

  final String personalTagId;
  final String normalizedKey;
  final String displayName;
  final String? color;
  final int createdAtMicros;
  final int updatedAtMicros;
}

final class DeletePersonalTag extends WorkspaceBusinessMutation {
  DeletePersonalTag(this.personalTagId) {
    _requireText(personalTagId, 'personalTagId');
  }

  final String personalTagId;
}

final class PutSkillTagAssignment extends WorkspaceBusinessMutation {
  PutSkillTagAssignment({
    required this.managedSkillId,
    required this.personalTagId,
    required this.createdAtMicros,
  }) {
    _requireText(personalTagId, 'personalTagId');
    _requireTimestamp(createdAtMicros, 'createdAtMicros');
  }

  final ManagedSkillId managedSkillId;
  final String personalTagId;
  final int createdAtMicros;
}

final class DeleteSkillTagAssignment extends WorkspaceBusinessMutation {
  DeleteSkillTagAssignment({
    required this.managedSkillId,
    required this.personalTagId,
  }) {
    _requireText(personalTagId, 'personalTagId');
  }

  final ManagedSkillId managedSkillId;
  final String personalTagId;
}

final class PutDraftWorkspace extends WorkspaceBusinessMutation {
  PutDraftWorkspace({
    required this.managedSkillId,
    required this.sourceLineageId,
    required this.baseObjectId,
    required this.purpose,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  }) {
    _requireText(sourceLineageId, 'sourceLineageId');
    _requireText(baseObjectId, 'baseObjectId');
    _requireTimestampRange(createdAtMicros, updatedAtMicros);
  }

  final ManagedSkillId managedSkillId;
  final String sourceLineageId;
  final String baseObjectId;
  final WorkspaceDraftPurpose purpose;
  final int createdAtMicros;
  final int updatedAtMicros;
}

final class DeleteDraftWorkspace extends WorkspaceBusinessMutation {
  const DeleteDraftWorkspace(this.managedSkillId);

  final ManagedSkillId managedSkillId;
}

final class WorkspaceUpdateCandidateItem {
  WorkspaceUpdateCandidateItem({
    required this.path,
    required this.kind,
    required this.state,
    required this.baseObjectId,
    required this.oursObjectId,
    required this.theirsObjectId,
  }) {
    _requireSafeRelativePath(path, 'path');
  }

  final String path;
  final WorkspaceUpdateCandidateItemKind kind;
  final WorkspaceUpdateCandidateItemState state;
  final String? baseObjectId;
  final String? oursObjectId;
  final String? theirsObjectId;
}

final class PutUpdateCandidateSession extends WorkspaceBusinessMutation {
  PutUpdateCandidateSession({
    required this.managedSkillId,
    required this.sourceLineageId,
    required this.previousUpstreamObjectId,
    required this.previousEffectiveObjectId,
    required this.incomingUpstreamObjectId,
    required this.candidateObjectId,
    required this.status,
    required this.validationCode,
    required List<WorkspaceUpdateCandidateItem> items,
    required this.createdAtMicros,
    required this.updatedAtMicros,
  }) : items = List<WorkspaceUpdateCandidateItem>.unmodifiable(items) {
    _requireText(sourceLineageId, 'sourceLineageId');
    _requireText(previousUpstreamObjectId, 'previousUpstreamObjectId');
    _requireText(previousEffectiveObjectId, 'previousEffectiveObjectId');
    _requireText(incomingUpstreamObjectId, 'incomingUpstreamObjectId');
    _requireText(candidateObjectId, 'candidateObjectId');
    if (status == WorkspaceUpdateCandidateStatus.conflicted &&
        validationCode != null) {
      throw ArgumentError('A conflicted Session cannot have validation code.');
    }
    if (status == WorkspaceUpdateCandidateStatus.validationFailed) {
      _requireText(validationCode, 'validationCode');
    }
    if (items.map((item) => item.path).toSet().length != items.length) {
      throw ArgumentError.value(items, 'items', 'contains duplicate paths');
    }
    _requireTimestampRange(createdAtMicros, updatedAtMicros);
  }

  final ManagedSkillId managedSkillId;
  final String sourceLineageId;
  final String previousUpstreamObjectId;
  final String previousEffectiveObjectId;
  final String incomingUpstreamObjectId;
  final String candidateObjectId;
  final WorkspaceUpdateCandidateStatus status;
  final String? validationCode;
  final List<WorkspaceUpdateCandidateItem> items;
  final int createdAtMicros;
  final int updatedAtMicros;
}

final class DeleteUpdateCandidateSession extends WorkspaceBusinessMutation {
  const DeleteUpdateCandidateSession(this.managedSkillId);

  final ManagedSkillId managedSkillId;
}

final class SetUpdateCandidateItemResolution extends WorkspaceBusinessMutation {
  SetUpdateCandidateItemResolution({
    required this.managedSkillId,
    required this.path,
    required this.state,
    required this.updatedAtMicros,
  }) {
    _requireSafeRelativePath(path, 'path');
    _requireTimestamp(updatedAtMicros, 'updatedAtMicros');
  }

  final ManagedSkillId managedSkillId;
  final String path;
  final WorkspaceUpdateCandidateItemState state;
  final int updatedAtMicros;
}

void _requireText(String? value, String name) {
  if (value == null || value.trim().isEmpty || value.contains('\u0000')) {
    throw ArgumentError.value(value, name, 'must be non-empty text');
  }
}

void _requireHash(String value, String name) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be a lowercase SHA-256 hash');
  }
}

void _requireSafeRelativePath(String value, String name) {
  _requireText(value, name);
  if (value.startsWith('/') ||
      value.startsWith(r'\') ||
      RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value) ||
      value.split(RegExp(r'[/\\]+')).any((segment) => segment == '..')) {
    throw ArgumentError.value(value, name, 'must be a safe relative path');
  }
}

void _requireTimestamp(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}

void _requireTimestampRange(int created, int updated) {
  _requireTimestamp(created, 'createdAtMicros');
  if (updated < created) {
    throw ArgumentError.value(
      updated,
      'updatedAtMicros',
      'must not precede creation',
    );
  }
}
