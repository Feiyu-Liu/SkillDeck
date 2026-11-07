import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/destructive/destructive_operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_coordinator.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/composition/source_replacement_preparation.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/source/application_source_payload_adapter.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

import '../support/source/source_acquisition_fakes.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceLayout layout;
  late SourceAcquisitionHandler sourceBehavior;
  late FakeSourceAcquisitionPorts sources;
  late _RevisionEngine revisions;
  late WorkspaceSourceReplacementPreparation preparation;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-source-replacement-',
    );
    layout = WorkspaceLayout(temporaryDirectory.path);
    sourceBehavior = (source, selection, options, cancellationToken) async =>
        SourceAcquisitionSuccess<AcquiredSource>(
          value: _acquired(source, [_skill(source)]),
        );
    sources = FakeSourceAcquisitionPorts(
      (source, selection, options, cancellationToken) =>
          sourceBehavior(source, selection, options, cancellationToken),
    );
    revisions = _RevisionEngine();
    preparation = WorkspaceSourceReplacementPreparation(
      sources: SourceAcquisitionCoordinator(
        local: sources,
        git: sources,
        wellKnown: sources,
      ),
      sourcePayloads: const ApplicationSourcePayloadAdapter(),
      revisions: revisions,
      layout: layout,
      filesystem: PlatformDurableWorkspaceFilesystem(),
    );
  });

  tearDown(() => temporaryDirectory.delete(recursive: true));

  test(
    'creates a verified operation-private Store and complete Bundle',
    () async {
      final result = await preparation.prepareSourceReplacement(
        _intent(),
        envelope: _envelope(),
        cancellationToken: CancellationToken.none(),
      );

      expect(result, isA<SourceReplacementPreparationSuccess>());
      final candidate =
          (result as SourceReplacementPreparationSuccess).candidate;
      expect(candidate.managedSkillId, _skillId);
      expect(candidate.sourceLineage, _lineage);
      expect(candidate.objectId, _commit);
      expect(candidate.slotKey, 'one');
      expect(candidate.contentHash, _hash);
      expect(revisions.calls, [
        'createStore',
        'writeTree',
        'createCommit',
        'verifyCommit',
        'createRecoveryPack',
        'restoreRecoveryPack',
        'verifyStore',
        'readTree',
      ]);
      final verificationPath = revisions.recoveryVerificationPath!;
      expect(
        path.isWithin(
          layout.operationStagingPath(_operationId),
          verificationPath,
        ),
        isTrue,
      );
      expect(path.basename(verificationPath), startsWith('.verify-'));
      expect(
        await Directory(
          layout.operationSourceReplacementStore(_operationId),
        ).exists(),
        isTrue,
      );
      final bundle = layout.operationSourceReplacementBundle(_operationId);
      final manifest = await File('$bundle/manifest.json').readAsBytes();
      const codec = RevisionRecoveryBundleCodec();
      final verified = codec.verify(
        manifestBytes: manifest,
        completionFenceBytes: await File('$bundle/COMPLETE').readAsBytes(),
        packBytes: await File('$bundle/objects.pack').readAsBytes(),
        indexBytes: await File('$bundle/objects.idx').readAsBytes(),
      );
      expect(verified.sourceLineageId, _lineage.encoded);
      expect(verified.currentUpstream, _commit);
      expect(verified.currentEffective, _commit);
      expect(verified.retainedPublishedRoots, [_commit]);
    },
  );

  test('rejects an ambiguous Source before Revision work', () async {
    sourceBehavior = (source, selection, options, cancellationToken) async =>
        SourceAcquisitionSuccess<AcquiredSource>(
          value: _acquired(source, [
            _skill(source),
            _skill(source, slot: 'two'),
          ]),
        );

    final result = await preparation.prepareSourceReplacement(
      _intent(),
      envelope: _envelope(),
      cancellationToken: CancellationToken.none(),
    );

    expect(
      (result as SourceReplacementPreparationFailure).code,
      SourceReplacementPreparationFailureCode.sourceAmbiguous,
    );
    expect(revisions.calls, isEmpty);
  });

  test(
    'cleans only operation staging when Revision preparation fails',
    () async {
      revisions.failCreateCommit = true;

      final result = await preparation.prepareSourceReplacement(
        _intent(),
        envelope: _envelope(),
        cancellationToken: CancellationToken.none(),
      );

      expect(
        (result as SourceReplacementPreparationFailure).code,
        SourceReplacementPreparationFailureCode.revisionPreparationFailed,
      );
      expect(
        await Directory(
          layout.operationSourceReplacementRoot(_operationId),
        ).exists(),
        isFalse,
      );
    },
  );
}

SourceReplacementPreparationIntent _intent() =>
    SourceReplacementPreparationIntent(
      operationId: _operationId,
      managedSkillId: _skillId,
      source: LocalSourceDescriptor(locator: '/source'),
      intendedSourceLineage: _lineage,
      includeInternal: false,
      fullDepth: false,
    );

PreparedOperationEnvelope _envelope() => PreparedOperationEnvelope(
  operationId: _operationId,
  expectedRepositoryRevision: RepositoryRevision(0),
  committedRepositoryRevision: RepositoryRevision(1),
  operationGeneration: 1,
  preparationSteps: [
    PreparationOperationStep(
      stepId: 'prepare',
      recoveryReference: RecoveryReference('prepare'),
      kind: PreparationStepKind.recoveryEvidence,
    ),
  ],
  record: OperationRecordPlan(
    operationId: _operationId,
    kind: 'replaceSource',
    subjects: const [],
    retainWithoutSubjects: true,
  ),
);

AcquiredSource _acquired(
  SourceDescriptor source,
  List<AcquiredSourceSkill> skills,
) => AcquiredSource(canonicalSource: source, skills: skills);

AcquiredSourceSkill _skill(SourceDescriptor source, {String slot = 'one'}) =>
    AcquiredSourceSkill(
      provenance: source,
      declaredName: slot,
      description: '$slot description',
      slotKey: slot,
      skillPath: slot,
      frontmatter: const {},
      tree: NormalizedSkillTree(
        files: [
          NormalizedSkillFile(
            relativePath: 'SKILL.md',
            bytes: const [1],
            isExecutable: false,
          ),
        ],
        contentHash: _hash,
        byteSize: 1,
      ),
    );

final class _RevisionEngine implements RevisionEnginePort {
  final List<String> calls = [];
  bool failCreateCommit = false;
  String? recoveryVerificationPath;

  @override
  Future<void> createStore(String repositoryPath) async {
    calls.add('createStore');
    await Directory(repositoryPath).create(recursive: true);
  }

  @override
  Future<RevisionObjectId> writeTree(
    String repositoryPath,
    NormalizedSkillTree tree,
  ) async {
    calls.add('writeTree');
    return _tree;
  }

  @override
  Future<RevisionObjectId> createCommit(
    String repositoryPath,
    RevisionCommitRequest request,
  ) async {
    calls.add('createCommit');
    if (failCreateCommit) {
      throw const RevisionEngineException(
        RevisionEngineFailureCode.unexpectedFailure,
      );
    }
    return _commit;
  }

  @override
  Future<void> verifyCommit(
    String repositoryPath,
    RevisionObjectId commit,
    RevisionCommitRequest expected,
  ) async {
    calls.add('verifyCommit');
  }

  @override
  Future<void> createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
  }) async {
    calls.add('createRecoveryPack');
    await File(
      '$bundleStagingPath/objects.pack',
    ).writeAsBytes([1], flush: true);
    await File('$bundleStagingPath/objects.idx').writeAsBytes([2], flush: true);
  }

  @override
  Future<void> close() async {}

  @override
  Future<List<RevisionChange>> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  }) => throw UnimplementedError();

  @override
  Future<bool> isAncestor({
    required String repositoryPath,
    required RevisionObjectId ancestor,
    required RevisionObjectId descendant,
  }) => throw UnimplementedError();

  @override
  Future<RevisionMergeResult> merge({
    required String repositoryPath,
    required RevisionObjectId previousUpstream,
    required RevisionObjectId currentEffective,
    required RevisionObjectId incomingUpstream,
  }) => throw UnimplementedError();

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) async {
    calls.add('readTree');
    return _skill(LocalSourceDescriptor(locator: '/source')).tree;
  }

  @override
  Future<void> restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) async {
    calls.add('restoreRecoveryPack');
    recoveryVerificationPath = stagedRepositoryPath;
    await Directory(stagedRepositoryPath).create(recursive: true);
  }

  @override
  Future<void> replaceRetentionRefs(
    String repositoryPath,
    List<RevisionRetentionRef> references,
  ) => throw UnimplementedError();

  @override
  Future<RevisionEngineStatus> status() => throw UnimplementedError();

  @override
  Future<void> verifyStore(String repositoryPath) async {
    calls.add('verifyStore');
  }
}

final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174020');
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('123e4567-e89b-42d3-8456-426614174001');
final _tree = RevisionObjectId('a' * 40);
final _commit = RevisionObjectId('b' * 40);
const _hash =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
