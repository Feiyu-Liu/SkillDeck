import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/application/discovery/external_discovery_models.dart';
import 'package:skills_workspace/src/application/drafts/draft_models.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/revision_store/revision_store_access_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/lock_wait_policy.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

const _skillValue = '123e4567-e89b-42d3-a456-426614174000';
const _operationValue = '123e4567-e89b-42d3-b456-426614174001';
const _subjectValue = '123e4567-e89b-42d3-8456-426614174002';
const _objectValue = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _otherObjectValue = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final _skillId = ManagedSkillId(_skillValue);
final _operationId = OperationId(_operationValue);
final _lineage = SourceLineageReference('lineage-one');
final _otherLineage = SourceLineageReference('lineage-two');
final _objectId = RevisionObjectId(_objectValue);
final _otherObjectId = RevisionObjectId(_otherObjectValue);
final _identity = DraftPhysicalIdentity(volumeId: 'volume', fileId: 'file');

void main() {
  group('identity and lock value contracts', () {
    test('identity values support diagnostics, hashing, and ordering', () {
      final revision = RepositoryRevision(4);
      final equalRevision = RepositoryRevision(4);
      final reference = OperationSubjectReference(
        operationId: _operationId,
        subjectId: _subjectValue,
      );

      expect(revision.hashCode, equalRevision.hashCode);
      expect(revision.toString(), 'RepositoryRevision(4)');
      expect(_operationId.toString(), 'OperationId($_operationValue)');
      expect(reference.hashCode, reference.hashCode);
      expect(reference.toString(), contains(_subjectValue));
      expect(revision.compareTo(revision.next()), lessThan(0));
    });

    test('lock waiting rejects unusable timing and has value semantics', () {
      expect(
        () => LockWaitPolicy.wait(timeout: Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => LockWaitPolicy.wait(pollInterval: Duration.zero),
        throwsArgumentError,
      );
      final first = LockWaitPolicy.wait(
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
      );
      final equal = LockWaitPolicy.wait(
        timeout: const Duration(seconds: 2),
        pollInterval: const Duration(milliseconds: 10),
      );
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(const LockWaitPolicy.failFast()));
    });
  });

  group('activation model boundaries', () {
    test('resolved targets enforce scope provenance and value semantics', () {
      expect(
        () => ResolvedActivationTarget(
          location: ' ',
          scope: ActivationScope.global,
          mode: ActivationMode.copy,
          agentIds: const ['claude'],
        ),
        throwsArgumentError,
      );
      expect(
        () => ResolvedActivationTarget(
          location: '/agents',
          scope: ActivationScope.global,
          mode: ActivationMode.copy,
          agentIds: const [],
        ),
        throwsArgumentError,
      );
      expect(
        () => ResolvedActivationTarget(
          location: '/agents',
          scope: ActivationScope.project,
          mode: ActivationMode.copy,
          agentIds: const ['claude'],
        ),
        throwsArgumentError,
      );
      expect(
        () => ResolvedActivationTarget(
          location: '/agents',
          scope: ActivationScope.global,
          mode: ActivationMode.copy,
          agentIds: const ['claude'],
          projectRootId: 'root',
          projectRootPath: '/project',
        ),
        throwsArgumentError,
      );

      final first = _activationTarget();
      final equal = _activationTarget();
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first.toSkillActivation().location, '/agents');
      expect(() => first.agentIds.clear(), throwsUnsupportedError);
    });

    test('materialization plans reject ambiguous or empty paths', () {
      expect(
        () => PlannedActivationCopy(sourcePath: '/source', targetPath: ' '),
        throwsArgumentError,
      );
      expect(
        () => PlannedActivationCopy(sourcePath: ' ', targetPath: '/target'),
        throwsArgumentError,
      );
      expect(
        () => PlannedActivationSymbolicLink(
          linkTarget: ' ',
          targetPath: '/target',
        ),
        throwsArgumentError,
      );
      expect(
        () => ValidatedSymbolicLinkActivation(
          targetPath: '',
          expectedLinkTarget: '/repository',
        ),
        throwsArgumentError,
      );
    });

    test('activation warning and failure conversions preserve typed data', () {
      final warning = ActivationWarning(
        code: ActivationWarningCode.activationTargetSkipped,
        context: const {'agentId': 'claude'},
      );
      final equal = ActivationWarning(
        code: ActivationWarningCode.activationTargetSkipped,
        context: const {'agentId': 'claude'},
      );
      final failure = ActivationFailure<Object?>(
        code: ActivationFailureCode.externalConflict,
        context: const {'slotKey': 'reviewer'},
        warnings: [warning],
      );
      final copied = copyActivationFailure<String>(
        failure,
        additionalWarnings: [equal],
      );

      expect(warning, equal);
      expect(warning.hashCode, equal.hashCode);
      expect(failure.isFailure, isTrue);
      expect(copied.code, ActivationFailureCode.externalConflict);
      expect(copied.warnings, [equal, warning]);
    });
  });

  group('source and discovery result boundaries', () {
    test(
      'source warnings and failure copies retain immutable typed context',
      () {
        final warning = SourceAcquisitionWarning(
          code: SourceAcquisitionWarningCode.sourceEntrySkipped,
          context: const {'entry': 'internal'},
        );
        final equal = SourceAcquisitionWarning(
          code: SourceAcquisitionWarningCode.sourceEntrySkipped,
          context: const {'entry': 'internal'},
        );
        final failure = SourceAcquisitionFailure<int>(
          code: SourceAcquisitionFailureCode.invalidSkill,
          context: const {'reason': 'frontmatter'},
          warnings: [warning],
        );
        final copied = copySourceAcquisitionFailure<int, String>(failure);
        final success = SourceAcquisitionSuccess<String>(value: 'skill');

        expect(warning, equal);
        expect(warning.hashCode, equal.hashCode);
        expect(success.failureOrNull, isNull);
        expect(copied.code, failure.code);
        expect(copied.context, failure.context);
        expect(copied.warnings, failure.warnings);
      },
    );

    test(
      'acquired source content validates text and deeply freezes metadata',
      () {
        final frontmatter = <String, Object?>{
          'nested': <String, Object?>{
            'items': <Object?>['one'],
          },
        };
        final skill = AcquiredSourceSkill(
          provenance: LocalSourceDescriptor(locator: '/skills/reviewer'),
          declaredName: 'reviewer',
          description: 'Reviews code',
          slotKey: 'reviewer',
          skillPath: '/skills/reviewer',
          frontmatter: frontmatter,
          tree: _tree(),
        );
        (frontmatter['nested']! as Map<String, Object?>)['late'] = true;

        expect(skill.frontmatter['nested'], {
          'items': ['one'],
        });
        expect(
          () => (skill.frontmatter['nested']! as Map<String, Object?>).clear(),
          throwsUnsupportedError,
        );
        expect(
          () => AcquiredSourceSkill(
            provenance: LocalSourceDescriptor(locator: '/skills/reviewer'),
            declaredName: ' ',
            description: 'Reviews code',
            slotKey: 'reviewer',
            skillPath: '/skills/reviewer',
            frontmatter: const {},
            tree: _tree(),
          ),
          throwsArgumentError,
        );
      },
    );

    test('external discovery copies warnings and rejects empty locations', () {
      final warning = ExternalDiscoveryWarning(
        code: ExternalDiscoveryWarningCode.sourceEntrySkipped,
        context: const {'entry': 'broken'},
      );
      final equal = ExternalDiscoveryWarning(
        code: ExternalDiscoveryWarningCode.sourceEntrySkipped,
        context: const {'entry': 'broken'},
      );
      final failure = ExternalDiscoveryFailure<int>(
        code: ExternalDiscoveryFailureCode.invalidSkill,
        context: const {'slotKey': 'reviewer'},
        warnings: [warning],
      );
      final copied = copyExternalDiscoveryFailure<int, String>(
        failure,
        additionalWarnings: [equal],
      );
      final success = ExternalDiscoverySuccess<String>(value: 'scan');

      expect(warning, equal);
      expect(warning.hashCode, equal.hashCode);
      expect(success.failureOrNull, isNull);
      expect(copied.valueOrNull, isNull);
      expect(copied.warnings, [equal, warning]);
      expect(
        () => ScannedExternalSkill(
          declaredName: 'reviewer',
          description: 'Reviews code',
          slotKey: 'reviewer',
          contentHash: _hash,
          skillLocation: ' ',
          source: LocalSourceDescriptor(locator: '/skills/reviewer'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('revision access and content boundaries', () {
    test('selection provides stable lineage-scoped revision addressing', () {
      final selection = CurrentEffectiveRevisionSelection(
        sourceLineage: _lineage,
        objectId: _objectId,
      );
      final equalSelection = CurrentEffectiveRevisionSelection(
        sourceLineage: _lineage,
        objectId: _objectId,
      );

      expect(selection, equalSelection);
      expect(selection.hashCode, equalSelection.hashCode);
      expect(selection.address.sourceLineage, _lineage);
      expect(selection.address.objectId, _objectId);
      expect(
        const RevisionStoreAccessException(
          RevisionStoreAccessFailureCode.selectionUnavailable,
        ).toString(),
        'RevisionStoreAccessException(selectionUnavailable)',
      );
    });

    test('normalized revision bytes validate and compare by value', () {
      expect(
        () => NormalizedSkillFile(
          relativePath: '',
          bytes: const [],
          isExecutable: false,
        ),
        throwsArgumentError,
      );
      expect(
        () => NormalizedSkillTree(
          files: const [],
          contentHash: 'INVALID',
          byteSize: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => NormalizedSkillTree(
          files: const [],
          contentHash: _hash,
          byteSize: -1,
        ),
        throwsArgumentError,
      );
      final first = NormalizedSkillFile(
        relativePath: 'SKILL.md',
        bytes: const [1, 2, 3],
        isExecutable: false,
      );
      final equal = NormalizedSkillFile(
        relativePath: 'SKILL.md',
        bytes: const [1, 2, 3],
        isExecutable: false,
      );
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
    });
  });

  group('Draft evidence and planning boundaries', () {
    test('Draft evidence validates atomic file facts and hashes by value', () {
      expect(_identity.hashCode, _identity.hashCode);
      expect(
        () => _evidence(relativePath: '', kind: DraftFilesystemEntryKind.file),
        throwsArgumentError,
      );
      expect(
        () =>
            _evidence(relativePath: 'SKILL.md', byteSize: 1, contentHash: null),
        throwsArgumentError,
      );
      expect(
        () => _evidence(
          relativePath: 'SKILL.md',
          byteSize: 1,
          contentHash: 'INVALID',
        ),
        throwsArgumentError,
      );
      final first = _evidence(relativePath: 'SKILL.md');
      final equal = _evidence(relativePath: 'SKILL.md');
      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
    });

    test(
      'Draft fingerprints require deterministic ordering and immutable data',
      () {
        final a = _evidence(relativePath: 'a.md');
        final b = _evidence(relativePath: 'b.md');
        final first = DraftFingerprint([a, b]);
        final equal = DraftFingerprint([
          _evidence(relativePath: 'a.md'),
          _evidence(relativePath: 'b.md'),
        ]);

        expect(first, equal);
        expect(first.hashCode, equal.hashCode);
        expect(() => first.entries.clear(), throwsUnsupportedError);
        expect(() => DraftFingerprint([b, a]), throwsArgumentError);
        expect(() => DraftFingerprint([a, a]), throwsArgumentError);
        expect(
          () => CapturedDraftFile(
            relativePath: '',
            bytes: const [],
            isExecutable: false,
          ),
          throwsArgumentError,
        );
      },
    );

    test(
      'Draft planning state rejects impossible timestamps and revisions',
      () {
        expect(
          () => _draftState(managedSkillCreatedAtMicros: -1),
          throwsArgumentError,
        );
        expect(
          () => _draftState(draftCreatedAtMicros: -1),
          throwsArgumentError,
        );
        final failure = DraftPlanningFailure<String>(
          code: DraftPlanningFailureCode.invalidSkill,
        );
        expect(failure.valueOrNull, isNull);
        expect(failure.failureOrNull, same(failure));
      },
    );

    test('prepared Draft publication rejects invalid revision metadata', () {
      expect(() => _preparedDraft(contentHash: 'INVALID'), throwsArgumentError);
      expect(() => _preparedDraft(fileCount: -1), throwsArgumentError);
      expect(() => _preparedDraft(declaredName: ' '), throwsArgumentError);
    });
  });

  group('destructive and history recovery boundaries', () {
    test('destructive recovery intent rejects ambiguous identities', () {
      expect(() => _destructiveSkill(slotKey: ' '), throwsArgumentError);
      expect(
        () => _destructiveSkill(sourceLineages: const []),
        throwsArgumentError,
      );
      final repeatedLineage = RecoverySourceLineageIntent(
        sourceLineage: _lineage,
      );
      expect(
        () => _destructiveSkill(
          sourceLineages: [repeatedLineage, repeatedLineage],
        ),
        throwsArgumentError,
      );
      expect(
        () => _destructiveSkill(activationIds: const ['agent', 'agent']),
        throwsArgumentError,
      );
      expect(
        () => RemovalRecoveryIntent(skills: const []),
        throwsArgumentError,
      );
      final skill = _destructiveSkill();
      expect(
        () => SourceReplacementRecoveryIntent(
          skill: skill,
          intendedSourceLineage: _lineage,
          intendedSlotKey: 'reviewer',
          intendedObjectId: _objectId,
          intendedContentHash: _hash,
          intendedObjectFormat: WorkspaceObjectFormat.sha1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceReplacementRecoveryIntent(
          skill: skill,
          intendedSourceLineage: _otherLineage,
          intendedSlotKey: ' ',
          intendedObjectId: _objectId,
          intendedContentHash: _hash,
          intendedObjectFormat: WorkspaceObjectFormat.sha1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceReplacementRecoveryIntent(
          skill: skill,
          intendedSourceLineage: _otherLineage,
          intendedSlotKey: 'reviewer',
          intendedObjectId: _objectId,
          intendedContentHash: 'INVALID',
          intendedObjectFormat: WorkspaceObjectFormat.sha1,
        ),
        throwsArgumentError,
      );
      expect(
        () => SourceReplacementRecoveryIntent(
          skill: skill,
          intendedSourceLineage: _lineage,
          intendedSlotKey: 'reviewer',
          intendedObjectId: _objectId,
          intendedContentHash: _hash,
          intendedObjectFormat: WorkspaceObjectFormat.sha1,
        ),
        throwsArgumentError,
      );
    });

    test('historical selections compare by all persisted address facts', () {
      final reference = OperationSubjectReference(
        operationId: _operationId,
        subjectId: _subjectValue,
      );
      final first = HistoricalRevisionSelection(
        reference: reference,
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        objectId: _objectId,
        contentHash: _hash,
        declaredName: 'reviewer',
      );
      final equal = HistoricalRevisionSelection(
        reference: reference,
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        objectId: _objectId,
        contentHash: _hash,
        declaredName: 'reviewer',
      );
      final failure = HistoryFailure<String>(
        code: HistoryFailureCode.ioFailure,
      );

      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(failure.valueOrNull, isNull);
      expect(
        () => _preparedRestore(contentHash: 'INVALID'),
        throwsArgumentError,
      );
    });
  });
}

ResolvedActivationTarget _activationTarget() => ResolvedActivationTarget(
  location: '/agents',
  scope: ActivationScope.global,
  mode: ActivationMode.copy,
  agentIds: const ['claude'],
);

NormalizedSkillTree _tree() =>
    NormalizedSkillTree(files: const [], contentHash: _hash, byteSize: 0);

DraftEntryEvidence _evidence({
  required String relativePath,
  DraftFilesystemEntryKind kind = DraftFilesystemEntryKind.file,
  int? byteSize = 1,
  String? contentHash = _hash,
}) => DraftEntryEvidence(
  relativePath: relativePath,
  kind: kind,
  entryIdentity: _identity,
  resolvedIdentity: _identity,
  modifiedAtMicrosecondsUtc: 1,
  byteSize: byteSize,
  contentHash: contentHash,
  isExecutable: false,
);

DraftRevisionState _draftState({
  int managedSkillCreatedAtMicros = 0,
  int? draftCreatedAtMicros,
}) => DraftRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  currentUpstream: _objectId,
  currentEffective: _objectId,
  managedSkillCreatedAtMicros: managedSkillCreatedAtMicros,
  draftCreatedAtMicros: draftCreatedAtMicros,
);

PreparedDraftPublish _preparedDraft({
  String contentHash = _hash,
  int fileCount = 1,
  int byteSize = 1,
  String declaredName = 'reviewer',
  String description = 'Reviews code',
}) => PreparedDraftPublish(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  treeObjectId: _otherObjectId,
  effectiveObjectId: _objectId,
  effectiveRequest: RevisionCommitRequest(
    tree: _otherObjectId,
    parents: [_objectId],
    kind: RevisionCommitKind.localPublish,
  ),
  contentHash: contentHash,
  fileCount: fileCount,
  byteSize: byteSize,
  declaredName: declaredName,
  description: description,
  draftAction: PublishedDraftAction.deleteUnchanged,
  capturedDraftFingerprint: DraftFingerprint(const []),
  candidateRecoveryReference: RecoveryReference('candidate'),
  bundleRecoveryReference: RecoveryReference('bundle'),
  materializationRecoveryReference: RecoveryReference('materialization'),
  draftRecoveryReference: RecoveryReference('draft'),
);

DestructiveSkillRecoveryIntent _destructiveSkill({
  String slotKey = 'reviewer',
  List<RecoverySourceLineageIntent>? sourceLineages,
  List<String> activationIds = const ['agent'],
}) => DestructiveSkillRecoveryIntent(
  managedSkillId: _skillId,
  slotKey: slotKey,
  sourceLineages:
      sourceLineages ?? [RecoverySourceLineageIntent(sourceLineage: _lineage)],
  activationIds: activationIds,
  hasDraft: false,
  hasUpdateCandidateSession: false,
);

PreparedRestorePublish _preparedRestore({String contentHash = _hash}) =>
    PreparedRestorePublish(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      selectedObjectId: _objectId,
      treeObjectId: _otherObjectId,
      effectiveObjectId: _objectId,
      effectiveRequest: RevisionCommitRequest(
        tree: _otherObjectId,
        parents: [_objectId],
        kind: RevisionCommitKind.restorePublish,
      ),
      contentHash: contentHash,
      fileCount: 1,
      byteSize: 1,
      declaredName: 'reviewer',
      description: 'Reviews code',
      draftAction: RestoreDraftAction.noDraft,
      capturedDraftFingerprint: null,
      candidateRecoveryReference: RecoveryReference('candidate'),
      bundleRecoveryReference: RecoveryReference('bundle'),
      materializationRecoveryReference: RecoveryReference('materialization'),
      draftRecoveryReference: RecoveryReference('draft'),
    );
