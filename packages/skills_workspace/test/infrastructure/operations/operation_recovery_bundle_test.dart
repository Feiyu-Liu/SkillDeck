import 'dart:convert';
import 'dart:io';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';
import 'package:test/test.dart';

const _operationId = '123e4567-e89b-42d3-a456-426614174300';
const _skillId = '123e4567-e89b-42d3-b456-426614174301';
const _hash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

void main() {
  const codec = OperationRecoveryBundleCodec();

  test('round-trips path-private manifest data behind opaque references', () {
    final operationId = OperationId(_operationId);
    final evidence = operationRecoveryReference(operationId, 'evidence');
    final apply = operationRecoveryReference(operationId, 'apply-main');
    final root = path.absolute('workspace');
    final target = path.join(root, 'repository-copies', 'reviewer');
    final parent = path.dirname(target);
    final manifest = OperationRecoveryBundleManifest(
      context: OperationRecoveryContext(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(4),
        committedRepositoryRevision: RepositoryRevision(5),
        destructive: true,
      ),
      destructiveIntent: _removalIntent(),
      entries: [
        OperationRecoveryEntryManifest(
          entryId: 'main',
          targetPath: target,
          displacedPath: path.join(parent, '.reviewer.applied'),
          rollbackResiduePath: path.join(parent, '.reviewer.rollback'),
          rollForwardResiduePath: path.join(parent, '.reviewer.roll-forward'),
          makeReadOnly: true,
          requirePlainDirectory: true,
          before: OperationRecoverySnapshot.absent(),
          intended: OperationRecoverySnapshot.directory(
            directories: const ['scripts'],
            files: [
              OperationRecoverySnapshotFile(
                relativePath: 'SKILL.md',
                sha256Digest: _hash,
                executable: false,
              ),
            ],
          ),
        ),
      ],
      bindings: [
        OperationRecoveryStepBinding(
          reference: evidence,
          action: OperationRecoveryAction.prepareEvidence,
        ),
        OperationRecoveryStepBinding(
          reference: apply,
          action: OperationRecoveryAction.applyEntry,
          entryId: 'main',
        ),
      ],
    );

    final bytes = codec.encodeManifest(manifest);
    final decoded = codec.verifyAndDecode(
      manifestBytes: bytes,
      completionFenceBytes: codec.createCompletionFence(bytes),
    );

    expect(decoded.context.operationId, operationId);
    expect(decoded.context.destructive, isTrue);
    final destructiveIntent =
        decoded.destructiveIntent as RemovalRecoveryIntent;
    expect(destructiveIntent.skills.single.managedSkillId.value, _skillId);
    expect(destructiveIntent.skills.single.slotKey, 'reviewer');
    expect(destructiveIntent.skills.single.activationIds, ['activation-1']);
    expect(decoded.entries.single.targetPath, contains('repository-copies'));
    expect(decoded.entries.single.before.present, isFalse);
    expect(
      decoded.entries.single.intended.files.single.relativePath,
      'SKILL.md',
    );
    expect(decoded.binding(apply).action, OperationRecoveryAction.applyEntry);
    expect(evidence.toString(), 'RecoveryReference(<opaque>)');
    expect(evidence.encoded, isNot(contains('/workspace')));
  });

  test('completion fence rejects a changed manifest', () {
    final registry = OperationRecoverySpecRegistry();
    final steps = OperationRecoveryPlanFactory(registry: registry)
        .createSqliteOnly(
          operationId: OperationId(_operationId),
          expectedRepositoryRevision: RepositoryRevision(0),
          committedRepositoryRevision: RepositoryRevision(1),
          destructive: false,
        );
    final spec = registry.lookup(OperationId(_operationId))!;
    final manifest = OperationRecoveryBundleManifest(
      context: spec.context,
      entries: const [],
      bindings: spec.bindings,
    );
    final bytes = codec.encodeManifest(manifest);
    final decoded = codec.verifyAndDecode(
      manifestBytes: bytes,
      completionFenceBytes: codec.createCompletionFence(bytes),
    );
    final changed = [...bytes, ...utf8.encode(' ')];

    expect(
      () => codec.verifyAndDecode(
        manifestBytes: changed,
        completionFenceBytes: codec.createCompletionFence(bytes),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.checksumMismatch)),
    );
    expect(decoded.context.expectedRepositoryRevision, RepositoryRevision(0));
    expect(steps.preparationSteps, hasLength(1));
  });

  test('round-trips exact Source Replacement roll-forward identity', () {
    final operationId = OperationId(_operationId);
    final manifest = OperationRecoveryBundleManifest(
      context: OperationRecoveryContext(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(4),
        committedRepositoryRevision: RepositoryRevision(5),
        destructive: true,
      ),
      entries: const [],
      bindings: const [],
      destructiveIntent: _replacementIntent(),
    );

    final bytes = codec.encodeManifest(manifest);
    final decoded = codec.verifyAndDecode(
      manifestBytes: bytes,
      completionFenceBytes: codec.createCompletionFence(bytes),
    );
    final intent = decoded.destructiveIntent as SourceReplacementRecoveryIntent;

    expect(intent.intendedSourceLineage.encoded, 'lineage-2');
    expect(intent.intendedSlotKey, 'replacement');
    expect(intent.intendedObjectId.value, '1' * 40);
    expect(intent.intendedContentHash, _hash);
    expect(intent.intendedObjectFormat, WorkspaceObjectFormat.sha1);
  });

  test(
    'SQLite-only factory owns references and required finalization steps',
    () {
      final registry = OperationRecoverySpecRegistry();
      final operationId = OperationId(_operationId);

      final steps = OperationRecoveryPlanFactory(registry: registry)
          .createSqliteOnly(
            operationId: operationId,
            expectedRepositoryRevision: RepositoryRevision(8),
            committedRepositoryRevision: RepositoryRevision(9),
            destructive: false,
          );

      expect(
        steps.preparationSteps.single.kind,
        PreparationStepKind.recoveryEvidence,
      );
      expect(steps.applyingSteps, isEmpty);
      expect(steps.finalizationSteps.map((step) => step.kind), [
        FinalizationStepKind.backupRotation,
        FinalizationStepKind.stagingCleanup,
        FinalizationStepKind.recoveryEvidenceCleanup,
      ]);
      final encodedReferences = <String>{
        ...steps.preparationSteps.map((step) => step.recoveryReference.encoded),
        ...steps.finalizationSteps.map(
          (step) => step.recoveryReference.encoded,
        ),
      };
      expect(encodedReferences, hasLength(4));
      expect(
        encodedReferences.every((value) => value.startsWith('or1:')),
        isTrue,
      );
      expect(encodedReferences.any((value) => value.contains('/')), isFalse);
      final spec = registry.lookup(operationId)!;
      expect(spec.context.destructive, isFalse);
      expect(spec.context.expectedRepositoryRevision, RepositoryRevision(8));
    },
  );

  test(
    'destructive factory releases access before residue and backup cleanup',
    () {
      final registry = OperationRecoverySpecRegistry();
      final operationId = OperationId(_operationId);
      registry
          .stageDestructiveEntries(operationId, <OperationRecoveryEntrySpec>[
            OperationRecoveryEntrySpec(
              entryId: 'managed-path',
              targetPath: path.join(
                Directory.systemTemp.absolute.path,
                'managed-path',
              ),
              intendedSourcePath: null,
              intendedKind: null,
            ),
          ]);

      final steps = OperationRecoveryPlanFactory(registry: registry)
          .createDestructive(
            operationId: operationId,
            expectedRepositoryRevision: RepositoryRevision(8),
            committedRepositoryRevision: RepositoryRevision(9),
            intent: _removalIntent(),
          );

      expect(steps.preparationSteps.map((step) => step.kind), [
        PreparationStepKind.recoveryEvidence,
        PreparationStepKind.destructiveBarrier,
        PreparationStepKind.destructiveResources,
      ]);
      expect(steps.applyingSteps.map((step) => step.kind), [
        ApplyingStepKind.destructiveReplacement,
      ]);
      expect(steps.finalizationSteps.map((step) => step.kind), [
        FinalizationStepKind.materializationVerification,
        FinalizationStepKind.materializationVerification,
        FinalizationStepKind.recoveryEvidenceCleanup,
        FinalizationStepKind.backupRotation,
        FinalizationStepKind.stagingCleanup,
        FinalizationStepKind.recoveryEvidenceCleanup,
      ]);
      final spec = registry.lookup(operationId)!;
      expect(spec.destructiveIntent, isA<RemovalRecoveryIntent>());
      expect(spec.entries, hasLength(1));
      expect(spec.bindings.map((binding) => binding.action), [
        OperationRecoveryAction.prepareEvidence,
        OperationRecoveryAction.armDestructiveBarrier,
        OperationRecoveryAction.prepareDestructiveResources,
        OperationRecoveryAction.applyEntry,
        OperationRecoveryAction.verifyEntry,
        OperationRecoveryAction.cleanupEntryResidue,
        OperationRecoveryAction.verifyDestructiveResources,
        OperationRecoveryAction.completeDestructiveBackup,
        OperationRecoveryAction.cleanupStaging,
        OperationRecoveryAction.retainRecoveryEvidence,
      ]);
      expect(
        spec.bindings.every(
          (binding) =>
              binding.reference.encoded.startsWith('or1:') &&
              !binding.reference.encoded.contains('/') &&
              !binding.reference.encoded.contains(r'\'),
        ),
        isTrue,
      );
    },
  );

  test('destructive intent mismatch and malformed content fail closed', () {
    final operationId = OperationId(_operationId);
    final manifest = OperationRecoveryBundleManifest(
      context: OperationRecoveryContext(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(4),
        committedRepositoryRevision: RepositoryRevision(5),
        destructive: true,
      ),
      entries: const [],
      bindings: const [],
      destructiveIntent: _removalIntent(),
    );
    final decoded =
        jsonDecode(utf8.decode(codec.encodeManifest(manifest)))
            as Map<String, Object?>;
    decoded['destructive'] = false;
    final mismatched = utf8.encode(jsonEncode(decoded));
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: mismatched,
        completionFenceBytes: codec.createCompletionFence(mismatched),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.bundleCorrupt)),
    );

    decoded['destructive'] = true;
    final destructiveIntent =
        decoded['destructiveIntent']! as Map<String, Object?>;
    destructiveIntent['skills'] = <Object?>[];
    final malformed = utf8.encode(jsonEncode(decoded));
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: malformed,
        completionFenceBytes: codec.createCompletionFence(malformed),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.bundleCorrupt)),
    );
  });

  test('schema 3 keeps NFD and non-ASCII names byte-exact in ASCII bytes', () {
    const nfdFile = 'café.md';
    const nfdDirectory = 'docś';
    const nfdTarget = 'AGENTŚ.md';
    final manifest = _manifest(
      targetName: 'café-skill',
      before: OperationRecoverySnapshot.directory(
        directories: const [nfdDirectory],
        files: [_file(nfdFile)],
        links: [
          OperationRecoverySnapshotLink(
            relativePath: 'CLAUDE.md',
            target: nfdTarget,
          ),
        ],
      ),
    );

    final bytes = codec.encodeManifest(manifest);
    final value = codec.manifestValue(manifest);
    final decoded = codec.verifyAndDecode(
      manifestBytes: bytes,
      completionFenceBytes: codec.createCompletionFence(bytes),
    );

    expect(bytes.every((byte) => byte < 0x80), isTrue);
    expect(utf8.decode(bytes), contains('cafe%CC%81.md'));
    expect(value['schema'], 3);
    expect(value.keys, contains('entries'));
    final before = decoded.entries.single.before;
    expect(before.files.single.relativePath, nfdFile);
    expect(before.directories.single, nfdDirectory);
    expect(before.links.single.relativePath, 'CLAUDE.md');
    expect(before.links.single.target, nfdTarget);
    expect(
      decoded.entries.single.targetPath,
      manifest.entries.single.targetPath,
    );
  });

  test('directory snapshot records links and rejects conflicting paths', () {
    final snapshot = OperationRecoverySnapshot.directory(
      directories: const ['docs'],
      files: [_file('docs/guide.md')],
      links: [_link('CLAUDE.md', 'AGENTS.md'), _link('docs-link', 'docs')],
    );
    expect(snapshot.links.map((link) => link.relativePath), [
      'CLAUDE.md',
      'docs-link',
    ]);

    expect(
      () => OperationRecoverySnapshot.directory(
        directories: const [],
        files: [_file('CLAUDE.md')],
        links: [_link('CLAUDE.md', 'AGENTS.md')],
      ),
      throwsArgumentError,
    );
    expect(
      () => OperationRecoverySnapshot.directory(
        directories: const ['docs-link'],
        files: const [],
        links: [_link('docs-link', 'docs')],
      ),
      throwsArgumentError,
    );
    expect(
      () => OperationRecoverySnapshot.directory(
        directories: const [],
        files: [_file('alias/guide.md')],
        links: [_link('alias', 'docs')],
      ),
      throwsArgumentError,
    );
    expect(() => _link('../escape', 'docs'), throwsArgumentError);
    expect(() => _link('alias', ''), throwsArgumentError);
  });

  test('rejects unpaired surrogates in snapshot names and link targets', () {
    expect(() => _file('\uD800.md'), throwsArgumentError);
    expect(() => _link('alias', 'docs\uDC00'), throwsArgumentError);
    expect(
      () => OperationRecoverySnapshot.directory(
        directories: const ['\uDBFF'],
        files: const [],
      ),
      throwsArgumentError,
    );
    expect(_file('\u{1F600}.md').relativePath, '\u{1F600}.md');
  });

  test('decodes a schema 2 manifest and rejects links in it', () {
    final manifest = _manifest(
      targetName: 'reviewer',
      before: OperationRecoverySnapshot.directory(
        directories: const ['scripts'],
        files: [_file('SKILL.md')],
      ),
    );
    final legacy = _legacyValue(codec.manifestValue(manifest));
    final legacyBytes = _canonical(legacy);

    final decoded = codec.verifyAndDecode(
      manifestBytes: legacyBytes,
      completionFenceBytes: _fence(legacyBytes, schema: 2),
    );
    expect(decoded.entries.single.before.links, isEmpty);
    expect(decoded.entries.single.before.files.single.relativePath, 'SKILL.md');
    expect(decoded.entries.single.targetPath, contains('reviewer'));

    final withLinks = _legacyValue(
      codec.manifestValue(manifest),
      keepLinks: true,
    );
    final withLinksBytes = _canonical(withLinks);
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: withLinksBytes,
        completionFenceBytes: _fence(withLinksBytes, schema: 2),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.bundleCorrupt)),
    );
  });

  test('fence and manifest schemas must agree and be readable', () {
    final manifest = _manifest(
      targetName: 'reviewer',
      before: OperationRecoverySnapshot.absent(),
    );
    final bytes = codec.encodeManifest(manifest);
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: bytes,
        completionFenceBytes: _fence(bytes, schema: 2),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.unsupportedSchema)),
    );

    final legacyBytes = _canonical(_legacyValue(codec.manifestValue(manifest)));
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: legacyBytes,
        completionFenceBytes: codec.createCompletionFence(legacyBytes),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.unsupportedSchema)),
    );

    final future = _legacyValue(codec.manifestValue(manifest))..['schema'] = 4;
    final futureBytes = _canonical(future);
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: futureBytes,
        completionFenceBytes: _fence(futureBytes, schema: 4),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.unsupportedSchema)),
    );
    expect(
      () => codec.decodeManifest(futureBytes),
      throwsA(_reason(OperationRecoveryFailureReason.unsupportedSchema)),
    );
  });

  test('non-canonical armor fails closed', () {
    final manifest = _manifest(
      targetName: 'reviewer',
      before: OperationRecoverySnapshot.directory(
        directories: const [],
        files: [_file('SKILL.md')],
      ),
    );
    final text = utf8.decode(codec.encodeManifest(manifest));
    final lowerCased = text.contains('%2F')
        ? text.replaceAll('%2F', '%2f')
        : text.replaceAll('%5C', '%5c');
    expect(lowerCased, isNot(text));
    final lowerCasedBytes = utf8.encode(lowerCased);
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: lowerCasedBytes,
        completionFenceBytes: codec.createCompletionFence(lowerCasedBytes),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.bundleCorrupt)),
    );

    final raw =
        jsonDecode(text.replaceAll('SKILL.md', 'SKILLé.md'))
            as Map<String, Object?>;
    final rawBytes = _canonical(raw);
    expect(
      () => codec.verifyAndDecode(
        manifestBytes: rawBytes,
        completionFenceBytes: codec.createCompletionFence(rawBytes),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.bundleCorrupt)),
    );
  });

  test('draft cleanup decisions read schema 2 and 3 only', () {
    final record = OperationRecoveryDraftCleanupDecisionRecord(
      operationId: OperationId(_operationId),
      cleanupId: 'draft-cleanup-0001',
      decision: OperationRecoveryDraftCleanupDecision.values.first,
    );
    final current = codec.encodeDraftCleanupDecision(record);
    expect(
      codec.decodeDraftCleanupDecision(current).cleanupId,
      record.cleanupId,
    );

    final legacy = jsonDecode(utf8.decode(current)) as Map<String, Object?>
      ..['schema'] = 2;
    expect(
      codec.decodeDraftCleanupDecision(_canonical(legacy)).decision,
      record.decision,
    );

    legacy['schema'] = 1;
    expect(
      () => codec.decodeDraftCleanupDecision(_canonical(legacy)),
      throwsA(_reason(OperationRecoveryFailureReason.unsupportedSchema)),
    );
  });

  test('rejects traversal-like reference tokens', () {
    expect(
      () => operationRecoveryReference(OperationId(_operationId), '../escape'),
      throwsArgumentError,
    );
    expect(
      () => decodeOperationRecoveryReference(
        RecoveryReference('or1:$_operationId:../escape'),
      ),
      throwsA(_reason(OperationRecoveryFailureReason.invalidReference)),
    );
  });
}

OperationRecoverySnapshotFile _file(String relativePath) =>
    OperationRecoverySnapshotFile(
      relativePath: relativePath,
      sha256Digest: _hash,
      executable: false,
    );

OperationRecoverySnapshotLink _link(String relativePath, String target) =>
    OperationRecoverySnapshotLink(relativePath: relativePath, target: target);

OperationRecoveryBundleManifest _manifest({
  required String targetName,
  required OperationRecoverySnapshot before,
}) {
  final operationId = OperationId(_operationId);
  final root = path.absolute('workspace');
  final target = path.join(root, 'repository-copies', targetName);
  final parent = path.dirname(target);
  return OperationRecoveryBundleManifest(
    context: OperationRecoveryContext(
      operationId: operationId,
      expectedRepositoryRevision: RepositoryRevision(4),
      committedRepositoryRevision: RepositoryRevision(5),
      destructive: false,
    ),
    entries: [
      OperationRecoveryEntryManifest(
        entryId: 'main',
        targetPath: target,
        displacedPath: path.join(parent, '.$targetName.applied'),
        rollbackResiduePath: path.join(parent, '.$targetName.rollback'),
        rollForwardResiduePath: path.join(parent, '.$targetName.roll-forward'),
        makeReadOnly: true,
        requirePlainDirectory: true,
        before: before,
        intended: OperationRecoverySnapshot.directory(
          directories: const [],
          files: [_file('SKILL.md')],
        ),
      ),
    ],
    bindings: [
      OperationRecoveryStepBinding(
        reference: operationRecoveryReference(operationId, 'evidence'),
        action: OperationRecoveryAction.prepareEvidence,
      ),
    ],
  );
}

/// Rewrites a schema-3 value into the schema-2 shape: raw strings and, unless
/// [keepLinks], no `links` key on snapshots.
Map<String, Object?> _legacyValue(
  Map<String, Object?> armored, {
  bool keepLinks = false,
}) {
  Object? disarm(Object? value) => switch (value) {
    final String string => Uri.decodeComponent(string),
    final Map<String, Object?> map => <String, Object?>{
      for (final entry in map.entries)
        if (keepLinks || entry.key != 'links' || !map.containsKey('present'))
          entry.key: disarm(entry.value),
    },
    final List<Object?> list => list.map(disarm).toList(),
    _ => value,
  };
  final legacy = disarm(armored)! as Map<String, Object?>;
  legacy['schema'] = 2;
  return legacy;
}

List<int> _canonical(Map<String, Object?> value) => canonicalJson.encode(value);

List<int> _fence(List<int> manifestBytes, {required int schema}) =>
    canonicalJson.encode({
      'schema': schema,
      'manifestSha256': sha256.convert(manifestBytes).toString(),
    });

Matcher _reason(OperationRecoveryFailureReason reason) =>
    isA<OperationRecoveryException>().having(
      (error) => error.reason,
      'reason',
      reason,
    );

RemovalRecoveryIntent _removalIntent() => RemovalRecoveryIntent(
  skills: [
    DestructiveSkillRecoveryIntent(
      managedSkillId: ManagedSkillId(_skillId),
      slotKey: 'reviewer',
      sourceLineages: [
        RecoverySourceLineageIntent(
          sourceLineage: SourceLineageReference('lineage-1'),
        ),
      ],
      activationIds: const ['activation-1'],
      hasDraft: true,
      hasUpdateCandidateSession: false,
    ),
  ],
);

SourceReplacementRecoveryIntent _replacementIntent() =>
    SourceReplacementRecoveryIntent(
      skill: _removalIntent().skills.single,
      intendedSourceLineage: SourceLineageReference('lineage-2'),
      intendedSlotKey: 'replacement',
      intendedObjectId: RevisionObjectId('1' * 40),
      intendedContentHash: _hash,
      intendedObjectFormat: WorkspaceObjectFormat.sha1,
    );
