import 'dart:convert';

import '../../application/operations/operation_models.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/identifiers.dart';
import 'workspace_business_change_codec.dart';

final class OperationPlanCodecException implements Exception {
  const OperationPlanCodecException(this.reason);

  final String reason;

  @override
  String toString() => 'OperationPlanCodecException($reason)';
}

/// Current-only durable codec for immutable operation plans.
///
/// The schema version is stored beside the payload in SQLite. Migration code
/// owns any future historical decoder; recovery never guesses a plan shape.
final class OperationPlanCodec {
  const OperationPlanCodec();

  static const int currentSchemaVersion = 4;

  String encode(OperationPlan plan) => encodeDefinition(plan);

  String encodeDefinition(OperationJournalDefinition definition) => jsonEncode(
    switch (definition) {
      PreparedOperationEnvelope() => <String, Object?>{
        'definitionKind': 'preparedEnvelope',
        ..._encodeCommonDefinition(definition),
      },
      OperationPlan() => <String, Object?>{
        'definitionKind': 'sealedPlan',
        ..._encodeCommonDefinition(definition),
        'applyingSteps': definition.applyingSteps.map(_encodeApplying).toList(),
        'finalizationSteps': definition.finalizationSteps
            .map(_encodeFinalization)
            .toList(),
        'revisionSelectionChanges': definition.revisionSelectionChanges
            .map(_encodeSelectionChange)
            .toList(),
        'businessChanges': const WorkspaceBusinessChangeSetCodec().encode(
          definition.businessChanges,
        ),
      },
    },
  );

  OperationPlan decode({required int schemaVersion, required String payload}) {
    final definition = decodeDefinition(
      schemaVersion: schemaVersion,
      payload: payload,
    );
    if (definition is! OperationPlan) {
      throw const OperationPlanCodecException('expectedSealedPlan');
    }
    return definition;
  }

  OperationJournalDefinition decodeDefinition({
    required int schemaVersion,
    required String payload,
  }) {
    if (schemaVersion != currentSchemaVersion) {
      throw const OperationPlanCodecException('unsupportedSchemaVersion');
    }
    final Map<String, Object?> map;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, Object?>) {
        throw const OperationPlanCodecException('invalidPayloadShape');
      }
      map = decoded;
    } on FormatException {
      throw const OperationPlanCodecException('invalidJson');
    }
    try {
      final operationId = OperationId(_string(map, 'operationId'));
      final expected = RepositoryRevision(
        _integer(map, 'expectedRepositoryRevision'),
      );
      final committed = RepositoryRevision(
        _integer(map, 'committedRepositoryRevision'),
      );
      final generation = _integer(map, 'operationGeneration');
      final preparationSteps = _list(
        map,
        'preparationSteps',
      ).map(_decodePreparation).toList();
      final record = _decodeRecord(_map(map, 'record'), operationId);
      return switch (_string(map, 'definitionKind')) {
        'preparedEnvelope' => PreparedOperationEnvelope(
          operationId: operationId,
          expectedRepositoryRevision: expected,
          committedRepositoryRevision: committed,
          operationGeneration: generation,
          preparationSteps: preparationSteps,
          record: record,
        ),
        'sealedPlan' => OperationPlan(
          operationId: operationId,
          expectedRepositoryRevision: expected,
          committedRepositoryRevision: committed,
          operationGeneration: generation,
          preparationSteps: preparationSteps,
          applyingSteps: _list(
            map,
            'applyingSteps',
          ).map(_decodeApplying).toList(),
          finalizationSteps: _list(
            map,
            'finalizationSteps',
          ).map(_decodeFinalization).toList(),
          revisionSelectionChanges: _list(
            map,
            'revisionSelectionChanges',
          ).map(_decodeSelectionChange).toList(),
          businessChanges: const WorkspaceBusinessChangeSetCodec().decode(
            map['businessChanges'],
          ),
          record: record,
        ),
        _ => throw const OperationPlanCodecException('unknownDefinitionKind'),
      };
    } on OperationPlanCodecException {
      rethrow;
    } on ArgumentError {
      throw const OperationPlanCodecException('invalidPayloadValue');
    } on WorkspaceBusinessChangeCodecException {
      throw const OperationPlanCodecException('invalidBusinessChanges');
    }
  }
}

Map<String, Object?> _encodeCommonDefinition(
  OperationJournalDefinition definition,
) => <String, Object?>{
  'operationId': definition.operationId.value,
  'expectedRepositoryRevision': definition.expectedRepositoryRevision.value,
  'committedRepositoryRevision': definition.committedRepositoryRevision.value,
  'operationGeneration': definition.operationGeneration,
  'preparationSteps': definition.preparationSteps
      .map(_encodePreparation)
      .toList(),
  'record': _encodeRecord(definition.record),
};

Map<String, Object?> _encodePreparation(PreparationOperationStep step) => {
  'stepId': step.stepId,
  'kind': step.kind.name,
  'recoveryReference': step.recoveryReference.encoded,
};

Map<String, Object?> _encodeApplying(ApplyingOperationStep step) => {
  'stepId': step.stepId,
  'kind': step.kind.name,
  'recoveryReference': step.recoveryReference.encoded,
};

Map<String, Object?> _encodeFinalization(FinalizationOperationStep step) => {
  'stepId': step.stepId,
  'kind': step.kind.name,
  'recoveryReference': step.recoveryReference.encoded,
};

Map<String, Object?> _encodeSelectionChange(
  RevisionSelectionChangePlan change,
) => {
  'managedSkillId': change.managedSkillId.value,
  'previousUpstream': _encodeAddress(change.previousUpstream),
  'previousEffective': _encodeAddress(change.previousEffective),
  'intendedUpstream': _encodeAddress(change.intendedUpstream),
  'intendedEffective': _encodeAddress(change.intendedEffective),
};

Map<String, Object?>? _encodeAddress(RevisionAddress? address) =>
    address == null
    ? null
    : {
        'sourceLineage': address.sourceLineage.encoded,
        'objectId': address.objectId.value,
      };

Map<String, Object?> _encodeRecord(OperationRecordPlan record) => {
  'kind': record.kind,
  'retainWithoutSubjects': record.retainWithoutSubjects,
  'subjects': record.subjects
      .map(
        (subject) => {
          'subjectId': subject.reference.subjectId,
          'managedSkillId': subject.managedSkillId.value,
          'displayName': subject.displayName,
          'sourceLineage': subject.sourceLineage?.encoded,
          'beforeObjectId': subject.beforeObjectId?.value,
          'afterObjectId': subject.afterObjectId?.value,
          'beforeContentHash': subject.beforeContentHash,
          'afterContentHash': subject.afterContentHash,
        },
      )
      .toList(),
};

PreparationOperationStep _decodePreparation(Object? value) {
  final map = _asMap(value);
  return PreparationOperationStep(
    stepId: _string(map, 'stepId'),
    recoveryReference: RecoveryReference(_string(map, 'recoveryReference')),
    kind: _enumByName(PreparationStepKind.values, _string(map, 'kind')),
  );
}

ApplyingOperationStep _decodeApplying(Object? value) {
  final map = _asMap(value);
  return ApplyingOperationStep(
    stepId: _string(map, 'stepId'),
    recoveryReference: RecoveryReference(_string(map, 'recoveryReference')),
    kind: _enumByName(ApplyingStepKind.values, _string(map, 'kind')),
  );
}

FinalizationOperationStep _decodeFinalization(Object? value) {
  final map = _asMap(value);
  return FinalizationOperationStep(
    stepId: _string(map, 'stepId'),
    recoveryReference: RecoveryReference(_string(map, 'recoveryReference')),
    kind: _enumByName(FinalizationStepKind.values, _string(map, 'kind')),
  );
}

RevisionSelectionChangePlan _decodeSelectionChange(Object? value) {
  final map = _asMap(value);
  return RevisionSelectionChangePlan(
    managedSkillId: ManagedSkillId(_string(map, 'managedSkillId')),
    previousUpstream: _decodeAddress(map['previousUpstream']),
    previousEffective: _decodeAddress(map['previousEffective']),
    intendedUpstream: _decodeAddress(map['intendedUpstream']),
    intendedEffective: _decodeAddress(map['intendedEffective']),
  );
}

RevisionAddress? _decodeAddress(Object? value) {
  if (value == null) return null;
  final map = _asMap(value);
  return RevisionAddress(
    sourceLineage: SourceLineageReference(_string(map, 'sourceLineage')),
    objectId: RevisionObjectId(_string(map, 'objectId')),
  );
}

OperationRecordPlan _decodeRecord(
  Map<String, Object?> map,
  OperationId operationId,
) => OperationRecordPlan(
  operationId: operationId,
  kind: _string(map, 'kind'),
  retainWithoutSubjects: _boolean(map, 'retainWithoutSubjects'),
  subjects: _list(map, 'subjects').map((value) {
    final subject = _asMap(value);
    final lineage = subject['sourceLineage'];
    return OperationSubjectPlan(
      reference: OperationSubjectReference(
        operationId: operationId,
        subjectId: _string(subject, 'subjectId'),
      ),
      managedSkillId: ManagedSkillId(_string(subject, 'managedSkillId')),
      displayName: _string(subject, 'displayName'),
      sourceLineage: lineage == null
          ? null
          : SourceLineageReference(_requiredStringValue(lineage)),
      beforeObjectId: _optionalObjectId(subject, 'beforeObjectId'),
      afterObjectId: _optionalObjectId(subject, 'afterObjectId'),
      beforeContentHash: _optionalRawString(subject, 'beforeContentHash'),
      afterContentHash: _optionalRawString(subject, 'afterContentHash'),
    );
  }).toList(),
);

RevisionObjectId? _optionalObjectId(Map<String, Object?> source, String key) {
  final value = _optionalRawString(source, key);
  return value == null ? null : RevisionObjectId(value);
}

String? _optionalRawString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value == null) return null;
  return _requiredStringValue(value);
}

Map<String, Object?> _map(Map<String, Object?> source, String key) =>
    _asMap(source[key]);

Map<String, Object?> _asMap(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const OperationPlanCodecException('invalidMap');
  }
  return value;
}

List<Object?> _list(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! List<Object?>) {
    throw const OperationPlanCodecException('invalidList');
  }
  return value;
}

String _string(Map<String, Object?> source, String key) =>
    _requiredStringValue(source[key]);

String _requiredStringValue(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const OperationPlanCodecException('invalidString');
  }
  return value;
}

int _integer(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! int) {
    throw const OperationPlanCodecException('invalidInteger');
  }
  return value;
}

bool _boolean(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is! bool) {
    throw const OperationPlanCodecException('invalidBoolean');
  }
  return value;
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw const OperationPlanCodecException('unknownEnumValue');
}
