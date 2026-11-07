import '../../application/operations/workspace_business_changes.dart';
import '../../domain/identifiers.dart';

final class WorkspaceBusinessChangeCodecException implements Exception {
  const WorkspaceBusinessChangeCodecException(this.reason);

  final String reason;
}

final class WorkspaceBusinessChangeSetCodec {
  const WorkspaceBusinessChangeSetCodec();

  Map<String, Object?> encode(WorkspaceBusinessChangeSet changes) => {
    'schemaVersion': WorkspaceBusinessChangeSet.currentSchemaVersion,
    'incrementsDestructionEpoch': changes.incrementsDestructionEpoch,
    'mutations': changes.mutations.map(_encodeMutation).toList(),
  };

  WorkspaceBusinessChangeSet decode(Object? value) {
    final map = _map(value);
    if (_integer(map, 'schemaVersion') !=
        WorkspaceBusinessChangeSet.currentSchemaVersion) {
      throw const WorkspaceBusinessChangeCodecException(
        'unsupportedSchemaVersion',
      );
    }
    try {
      return WorkspaceBusinessChangeSet(
        incrementsDestructionEpoch: _boolean(map, 'incrementsDestructionEpoch'),
        mutations: _list(map, 'mutations').map(_decodeMutation).toList(),
      );
    } on WorkspaceBusinessChangeCodecException {
      rethrow;
    } on ArgumentError {
      throw const WorkspaceBusinessChangeCodecException('invalidValue');
    }
  }
}

Map<String, Object?> _encodeMutation(WorkspaceBusinessMutation mutation) =>
    switch (mutation) {
      PutManagedSkill() => {
        'kind': 'putManagedSkill',
        'managedSkillId': mutation.managedSkillId.value,
        'slotKey': mutation.slotKey,
        'declaredName': mutation.declaredName,
        'displayName': mutation.displayName,
        'description': mutation.description,
        'activeSourceLineageId': mutation.activeSourceLineageId,
        'createdAtMicros': mutation.createdAtMicros,
        'updatedAtMicros': mutation.updatedAtMicros,
      },
      DeleteManagedSkill() => {
        'kind': 'deleteManagedSkill',
        'managedSkillId': mutation.managedSkillId.value,
      },
      PutSourceLineage() => {
        'kind': 'putSourceLineage',
        'sourceLineageId': mutation.sourceLineageId,
        'managedSkillId': mutation.managedSkillId.value,
        'objectFormat': mutation.objectFormat.name,
        'createdAtMicros': mutation.createdAtMicros,
      },
      DeleteSourceLineage() => {
        'kind': 'deleteSourceLineage',
        'sourceLineageId': mutation.sourceLineageId,
      },
      PutSkillSource() => {
        'kind': 'putSkillSource',
        'sourceLineageId': mutation.sourceLineageId,
        'sourceKind': mutation.kind.name,
        'payloadSchemaVersion': mutation.payloadSchemaVersion,
        'payloadJson': mutation.payloadJson,
      },
      PutRevisionMetadata() => {
        'kind': 'putRevisionMetadata',
        'sourceLineageId': mutation.sourceLineageId,
        'objectId': mutation.objectId,
        'contentHash': mutation.contentHash,
        'fileCount': mutation.fileCount,
        'byteSize': mutation.byteSize,
        'declaredName': mutation.declaredName,
        'validationState': mutation.validationState.name,
        'validationCode': mutation.validationCode,
        'createdAtMicros': mutation.createdAtMicros,
      },
      PutProjectRoot() => {
        'kind': 'putProjectRoot',
        'projectRootId': mutation.projectRootId,
        'canonicalPath': mutation.canonicalPath,
        'createdAtMicros': mutation.createdAtMicros,
        'updatedAtMicros': mutation.updatedAtMicros,
      },
      DeleteProjectRoot() => {
        'kind': 'deleteProjectRoot',
        'projectRootId': mutation.projectRootId,
      },
      PutActivation() => {
        'kind': 'putActivation',
        'activationId': mutation.activationId,
        'managedSkillId': mutation.managedSkillId.value,
        'canonicalPath': mutation.canonicalPath,
        'scope': mutation.scope.name,
        'mode': mutation.mode.name,
        'projectRootId': mutation.projectRootId,
        'projectRootPath': mutation.projectRootPath,
        'agentIds': mutation.agentIds,
        'createdAtMicros': mutation.createdAtMicros,
      },
      DeleteActivation() => {
        'kind': 'deleteActivation',
        'activationId': mutation.activationId,
      },
      PutSkillUserData() => {
        'kind': 'putSkillUserData',
        'managedSkillId': mutation.managedSkillId.value,
        'favorite': mutation.favorite,
        'favoriteChangedAtMicros': mutation.favoriteChangedAtMicros,
        'note': mutation.note,
        'noteUpdatedAtMicros': mutation.noteUpdatedAtMicros,
      },
      DeleteSkillUserData() => {
        'kind': 'deleteSkillUserData',
        'managedSkillId': mutation.managedSkillId.value,
      },
      PutPersonalTag() => {
        'kind': 'putPersonalTag',
        'personalTagId': mutation.personalTagId,
        'normalizedKey': mutation.normalizedKey,
        'displayName': mutation.displayName,
        'color': mutation.color,
        'createdAtMicros': mutation.createdAtMicros,
        'updatedAtMicros': mutation.updatedAtMicros,
      },
      DeletePersonalTag() => {
        'kind': 'deletePersonalTag',
        'personalTagId': mutation.personalTagId,
      },
      PutSkillTagAssignment() => {
        'kind': 'putSkillTagAssignment',
        'managedSkillId': mutation.managedSkillId.value,
        'personalTagId': mutation.personalTagId,
        'createdAtMicros': mutation.createdAtMicros,
      },
      DeleteSkillTagAssignment() => {
        'kind': 'deleteSkillTagAssignment',
        'managedSkillId': mutation.managedSkillId.value,
        'personalTagId': mutation.personalTagId,
      },
      PutDraftWorkspace() => {
        'kind': 'putDraftWorkspace',
        'managedSkillId': mutation.managedSkillId.value,
        'sourceLineageId': mutation.sourceLineageId,
        'baseObjectId': mutation.baseObjectId,
        'purpose': mutation.purpose.name,
        'createdAtMicros': mutation.createdAtMicros,
        'updatedAtMicros': mutation.updatedAtMicros,
      },
      DeleteDraftWorkspace() => {
        'kind': 'deleteDraftWorkspace',
        'managedSkillId': mutation.managedSkillId.value,
      },
      PutUpdateCandidateSession() => {
        'kind': 'putUpdateCandidateSession',
        'managedSkillId': mutation.managedSkillId.value,
        'sourceLineageId': mutation.sourceLineageId,
        'previousUpstreamObjectId': mutation.previousUpstreamObjectId,
        'previousEffectiveObjectId': mutation.previousEffectiveObjectId,
        'incomingUpstreamObjectId': mutation.incomingUpstreamObjectId,
        'candidateObjectId': mutation.candidateObjectId,
        'status': mutation.status.name,
        'validationCode': mutation.validationCode,
        'items': mutation.items.map(_encodeCandidateItem).toList(),
        'createdAtMicros': mutation.createdAtMicros,
        'updatedAtMicros': mutation.updatedAtMicros,
      },
      DeleteUpdateCandidateSession() => {
        'kind': 'deleteUpdateCandidateSession',
        'managedSkillId': mutation.managedSkillId.value,
      },
      SetUpdateCandidateItemResolution() => {
        'kind': 'setUpdateCandidateItemResolution',
        'managedSkillId': mutation.managedSkillId.value,
        'path': mutation.path,
        'state': mutation.state.name,
        'updatedAtMicros': mutation.updatedAtMicros,
      },
    };

Map<String, Object?> _encodeCandidateItem(WorkspaceUpdateCandidateItem item) =>
    {
      'path': item.path,
      'kind': item.kind.name,
      'state': item.state.name,
      'baseObjectId': item.baseObjectId,
      'oursObjectId': item.oursObjectId,
      'theirsObjectId': item.theirsObjectId,
    };

WorkspaceBusinessMutation _decodeMutation(Object? value) {
  final map = _map(value);
  return switch (_string(map, 'kind')) {
    'putManagedSkill' => PutManagedSkill(
      managedSkillId: _managedSkillId(map),
      slotKey: _string(map, 'slotKey'),
      declaredName: _string(map, 'declaredName'),
      displayName: _string(map, 'displayName'),
      description: _string(map, 'description'),
      activeSourceLineageId: _string(map, 'activeSourceLineageId'),
      createdAtMicros: _integer(map, 'createdAtMicros'),
      updatedAtMicros: _integer(map, 'updatedAtMicros'),
    ),
    'deleteManagedSkill' => DeleteManagedSkill(_managedSkillId(map)),
    'putSourceLineage' => PutSourceLineage(
      sourceLineageId: _string(map, 'sourceLineageId'),
      managedSkillId: _managedSkillId(map),
      objectFormat: _enumByName(
        WorkspaceObjectFormat.values,
        _string(map, 'objectFormat'),
      ),
      createdAtMicros: _integer(map, 'createdAtMicros'),
    ),
    'deleteSourceLineage' => DeleteSourceLineage(
      _string(map, 'sourceLineageId'),
    ),
    'putSkillSource' => PutSkillSource(
      sourceLineageId: _string(map, 'sourceLineageId'),
      kind: _enumByName(WorkspaceSourceKind.values, _string(map, 'sourceKind')),
      payloadSchemaVersion: _integer(map, 'payloadSchemaVersion'),
      payloadJson: _string(map, 'payloadJson'),
    ),
    'putRevisionMetadata' => PutRevisionMetadata(
      sourceLineageId: _string(map, 'sourceLineageId'),
      objectId: _string(map, 'objectId'),
      contentHash: _string(map, 'contentHash'),
      fileCount: _integer(map, 'fileCount'),
      byteSize: _integer(map, 'byteSize'),
      declaredName: _string(map, 'declaredName'),
      validationState: _enumByName(
        WorkspaceRevisionValidationState.values,
        _string(map, 'validationState'),
      ),
      validationCode: _optionalString(map, 'validationCode'),
      createdAtMicros: _integer(map, 'createdAtMicros'),
    ),
    'putProjectRoot' => PutProjectRoot(
      projectRootId: _string(map, 'projectRootId'),
      canonicalPath: _string(map, 'canonicalPath'),
      createdAtMicros: _integer(map, 'createdAtMicros'),
      updatedAtMicros: _integer(map, 'updatedAtMicros'),
    ),
    'deleteProjectRoot' => DeleteProjectRoot(_string(map, 'projectRootId')),
    'putActivation' => PutActivation(
      activationId: _string(map, 'activationId'),
      managedSkillId: _managedSkillId(map),
      canonicalPath: _string(map, 'canonicalPath'),
      scope: _enumByName(
        WorkspaceActivationScope.values,
        _string(map, 'scope'),
      ),
      mode: _enumByName(WorkspaceActivationMode.values, _string(map, 'mode')),
      projectRootId: _optionalString(map, 'projectRootId'),
      projectRootPath: _optionalString(map, 'projectRootPath'),
      agentIds: _stringList(map, 'agentIds'),
      createdAtMicros: _integer(map, 'createdAtMicros'),
    ),
    'deleteActivation' => DeleteActivation(_string(map, 'activationId')),
    'putSkillUserData' => PutSkillUserData(
      managedSkillId: _managedSkillId(map),
      favorite: _boolean(map, 'favorite'),
      favoriteChangedAtMicros: _optionalInteger(map, 'favoriteChangedAtMicros'),
      note: _optionalString(map, 'note'),
      noteUpdatedAtMicros: _optionalInteger(map, 'noteUpdatedAtMicros'),
    ),
    'deleteSkillUserData' => DeleteSkillUserData(_managedSkillId(map)),
    'putPersonalTag' => PutPersonalTag(
      personalTagId: _string(map, 'personalTagId'),
      normalizedKey: _string(map, 'normalizedKey'),
      displayName: _string(map, 'displayName'),
      color: _optionalString(map, 'color'),
      createdAtMicros: _integer(map, 'createdAtMicros'),
      updatedAtMicros: _integer(map, 'updatedAtMicros'),
    ),
    'deletePersonalTag' => DeletePersonalTag(_string(map, 'personalTagId')),
    'putSkillTagAssignment' => PutSkillTagAssignment(
      managedSkillId: _managedSkillId(map),
      personalTagId: _string(map, 'personalTagId'),
      createdAtMicros: _integer(map, 'createdAtMicros'),
    ),
    'deleteSkillTagAssignment' => DeleteSkillTagAssignment(
      managedSkillId: _managedSkillId(map),
      personalTagId: _string(map, 'personalTagId'),
    ),
    'putDraftWorkspace' => PutDraftWorkspace(
      managedSkillId: _managedSkillId(map),
      sourceLineageId: _string(map, 'sourceLineageId'),
      baseObjectId: _string(map, 'baseObjectId'),
      purpose: _enumByName(
        WorkspaceDraftPurpose.values,
        _string(map, 'purpose'),
      ),
      createdAtMicros: _integer(map, 'createdAtMicros'),
      updatedAtMicros: _integer(map, 'updatedAtMicros'),
    ),
    'deleteDraftWorkspace' => DeleteDraftWorkspace(_managedSkillId(map)),
    'putUpdateCandidateSession' => PutUpdateCandidateSession(
      managedSkillId: _managedSkillId(map),
      sourceLineageId: _string(map, 'sourceLineageId'),
      previousUpstreamObjectId: _string(map, 'previousUpstreamObjectId'),
      previousEffectiveObjectId: _string(map, 'previousEffectiveObjectId'),
      incomingUpstreamObjectId: _string(map, 'incomingUpstreamObjectId'),
      candidateObjectId: _string(map, 'candidateObjectId'),
      status: _enumByName(
        WorkspaceUpdateCandidateStatus.values,
        _string(map, 'status'),
      ),
      validationCode: _optionalString(map, 'validationCode'),
      items: _list(map, 'items').map(_decodeCandidateItem).toList(),
      createdAtMicros: _integer(map, 'createdAtMicros'),
      updatedAtMicros: _integer(map, 'updatedAtMicros'),
    ),
    'deleteUpdateCandidateSession' => DeleteUpdateCandidateSession(
      _managedSkillId(map),
    ),
    'setUpdateCandidateItemResolution' => SetUpdateCandidateItemResolution(
      managedSkillId: _managedSkillId(map),
      path: _string(map, 'path'),
      state: _enumByName(
        WorkspaceUpdateCandidateItemState.values,
        _string(map, 'state'),
      ),
      updatedAtMicros: _integer(map, 'updatedAtMicros'),
    ),
    _ => throw const WorkspaceBusinessChangeCodecException('unknownMutation'),
  };
}

WorkspaceUpdateCandidateItem _decodeCandidateItem(Object? value) {
  final map = _map(value);
  return WorkspaceUpdateCandidateItem(
    path: _string(map, 'path'),
    kind: _enumByName(
      WorkspaceUpdateCandidateItemKind.values,
      _string(map, 'kind'),
    ),
    state: _enumByName(
      WorkspaceUpdateCandidateItemState.values,
      _string(map, 'state'),
    ),
    baseObjectId: _optionalString(map, 'baseObjectId'),
    oursObjectId: _optionalString(map, 'oursObjectId'),
    theirsObjectId: _optionalString(map, 'theirsObjectId'),
  );
}

ManagedSkillId _managedSkillId(Map<String, Object?> map) =>
    ManagedSkillId(_string(map, 'managedSkillId'));

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const WorkspaceBusinessChangeCodecException('invalidMap');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! List<Object?>) {
    throw const WorkspaceBusinessChangeCodecException('invalidList');
  }
  return value;
}

List<String> _stringList(Map<String, Object?> map, String key) =>
    _list(map, key).map(_requiredString).toList();

String _string(Map<String, Object?> map, String key) =>
    _requiredString(map[key]);

String _requiredString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const WorkspaceBusinessChangeCodecException('invalidString');
  }
  return value;
}

String? _optionalString(Map<String, Object?> map, String key) {
  final value = map[key];
  return value == null ? null : _requiredString(value);
}

int _integer(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw const WorkspaceBusinessChangeCodecException('invalidInteger');
  }
  return value;
}

int? _optionalInteger(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! int) {
    throw const WorkspaceBusinessChangeCodecException('invalidInteger');
  }
  return value;
}

bool _boolean(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! bool) {
    throw const WorkspaceBusinessChangeCodecException('invalidBoolean');
  }
  return value;
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw const WorkspaceBusinessChangeCodecException('unknownEnumValue');
}
