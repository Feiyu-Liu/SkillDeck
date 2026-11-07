import '../support/content/drift_export_inspector.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/application/drift/drift_plan_assembler.dart';
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/drift/drift_artifacts.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_mutation_models.dart';
import 'package:skills_workspace/src/application/drafts/draft_models.dart';
import 'package:skills_workspace/src/application/history/history_models.dart';
import 'package:skills_workspace/src/application/install/initial_import_models.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/activation_mutation_ports.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/application/update/update_models.dart';
import 'package:skills_workspace/src/composition/revision_operation_plans.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late WorkspaceLayout layout;
  late OperationRecoverySpecRegistry registry;
  late WorkspaceRevisionOperationPlans plans;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-revision-plans-',
    );
    layout = WorkspaceLayout(temporaryDirectory.path);
    registry = OperationRecoverySpecRegistry();
    final recoveryFactory = OperationRecoveryPlanFactory(registry: registry);
    plans = WorkspaceRevisionOperationPlans(
      assembler: OperationPlanAssembler(
        subjectIdentities: _SubjectIdentities(),
        recoveryPlans: recoveryFactory,
      ),
      recoverySpecs: registry,
      layout: layout,
      targetExpectations: const _TargetExpectations(),
      artifactInspector: const FileSystemPublishedArtifactInspector(
        contentWorker: DirectRevisionContentWorker(),
        metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
      ),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  Future<DriftResolutionPreflight> reviewedDrift({
    bool keep = false,
    bool metadataOnly = false,
    bool cleanDraft = false,
  }) async {
    const inspector = FileSystemPublishedArtifactInspector(
      contentWorker: DirectRevisionContentWorker(),
      metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
    );
    final repo = layout.repositoryCopyPath('sample');
    await Directory(repo).create(recursive: true);
    final copy = SkillActivation(
      location: path.join(temporaryDirectory.path, 'copy'),
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const ['copy-agent'],
    );
    final link = SkillActivation(
      location: path.join(temporaryDirectory.path, 'link'),
      scope: ActivationScope.global,
      mode: ActivationMode.symbolicLink,
      agentIds: const ['link-agent'],
    );
    final copyPath = path.join(copy.location, 'sample');
    await Directory(copyPath).create(recursive: true);
    await Directory(link.location).create(recursive: true);
    await File(path.join(copyPath, 'notes')).writeAsString('managed');
    final base = await inspector.observe(
      path: copyPath,
      cancellationToken: CancellationToken.none(),
    );
    PublishedArtifactInspection external;
    if (metadataOnly) {
      await Directory(repo).delete();
      await File(repo).writeAsString('external');
      final metadata = await inspector.observeMetadata(
        path: repo,
        cancellationToken: CancellationToken.none(),
      );
      external = PublishedArtifactInspection(
        state: PublishedArtifactState.mismatching,
        mismatchKind: PublishedArtifactMismatchKind.wrongEntryType,
        observedEntryKind: ObservedEntryKind.file,
        metadataFingerprint: metadata.metadataFingerprint,
      );
    } else {
      await File(path.join(repo, 'notes')).writeAsString('external');
      external = await inspector.inspectDirectory(
        path: repo,
        expectedContentHash: base.fingerprint!,
        cancellationToken: CancellationToken.none(),
      );
    }
    final inspected = SkillMaterializationInspection(
      effectiveObjectId: _current,
      effectiveContentHash: base.fingerprint!,
      artifacts: [
        SkillMaterializationArtifact(
          locationKind: SkillDriftLocationKind.repositoryCopy,
          targetPath: repo,
          inspection: external,
        ),
        SkillMaterializationArtifact(
          locationKind: SkillDriftLocationKind.copyActivation,
          targetPath: copyPath,
          activation: copy,
          inspection: base,
        ),
        SkillMaterializationArtifact(
          locationKind: SkillDriftLocationKind.symbolicLinkActivation,
          targetPath: path.join(link.location, 'sample'),
          activation: link,
          inspection: const PublishedArtifactInspection(
            state: PublishedArtifactState.missing,
          ),
        ),
      ],
    );
    final skill = ManagedSkill(
      id: _skillId,
      slotKey: 'sample',
      declaredName: 'sample',
      displayName: 'Sample',
      description: 'Description',
      source: LocalSourceDescriptor(locator: temporaryDirectory.path),
      currentRevision: ManagedSkillRevisionSummary(
        contentHash: base.fingerprint!,
        fileCount: 1,
        byteSize: 7,
        publishedAt: DateTime.utc(2026),
      ),
      activations: [copy, link],
    );
    final review =
        createDriftReview(
              owner: Object(),
              managedSkillId: _skillId,
              inspected: inspected,
              artifacts: driftArtifactsFor(inspected),
              missingArtifactCount: 1,
            )
            as DriftReviewEvidence;
    return DriftResolutionPreflight(
      snapshotRevision: RepositoryRevision(3),
      plannedAtMicros: 4,
      skill: skill,
      state: RestoreRevisionState(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        currentUpstream: _initial,
        currentEffective: _current,
        managedSkillCreatedAtMicros: 1,
        draftCreatedAtMicros: cleanDraft ? 2 : null,
      ),
      review: review,
      current: inspected,
      resolution: keep
          ? const KeepExternalSkillDrift('repositoryCopy')
          : const RestoreManagedSkillDrift(),
      selectedPath: keep ? repo : null,
      selectedFingerprint: keep ? external.fingerprint : null,
      hadCleanDraft: cleanDraft,
    );
  }

  PreparedRestorePublishPlan driftPublishPlan(
    DriftResolutionPreflight preflight,
  ) => const DriftPlanAssembler()
      .assemble(
        preflight: preflight,
        prepared: PreparedRestorePublish(
          managedSkillId: _skillId,
          sourceLineage: _lineage,
          selectedObjectId: _current,
          treeObjectId: _incoming,
          effectiveObjectId: _published,
          effectiveRequest: RevisionCommitRequest(
            tree: _incoming,
            parents: [_current],
            kind: RevisionCommitKind.localPublish,
          ),
          contentHash: preflight.selectedFingerprint!,
          fileCount: 1,
          byteSize: 8,
          declaredName: 'sample',
          description: 'External',
          draftAction: preflight.hadCleanDraft
              ? RestoreDraftAction.preserveAndReanchor
              : RestoreDraftAction.noDraft,
          capturedDraftFingerprint: preflight.hadCleanDraft
              ? DraftFingerprint(const [])
              : null,
          candidateRecoveryReference: RecoveryReference('candidate'),
          bundleRecoveryReference: RecoveryReference('bundle'),
          materializationRecoveryReference: RecoveryReference(
            'materialization',
          ),
          draftRecoveryReference: RecoveryReference('draft'),
        ),
      )
      .valueOrNull!;

  OperationPlan sealDrift(
    DriftResolutionPreflight preflight, {
    CancellationToken? token,
    PreparedRestorePublishPlan? publication,
  }) {
    final envelope = plans.createDriftEnvelope(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(3),
      preflight: preflight,
    );
    final plan = plans.sealDriftPlan(
      envelope: envelope,
      preflight: preflight,
      publishedPlan:
          publication ??
          (preflight.keepsExternal ? driftPublishPlan(preflight) : null),
      cancellationToken: token ?? CancellationToken.none(),
    );
    expect(envelope.isSealedBy(plan), isTrue);
    return plan;
  }

  test(
    'sealDriftPlan keep consumes every materialization intent and clean Draft cleanup',
    () async {
      final preflight = await reviewedDrift(keep: true, cleanDraft: true);
      final operation = sealDrift(preflight);
      final spec = registry.lookup(_operationId)!;
      expect(spec.entries, hasLength(4));
      expect(
        spec.entries.first.targetPath,
        layout.revisionBundlePath(_skillId),
      );
      expect(
        spec.entries.skip(1).every((e) => e.verifyBeforeCapture != null),
        isTrue,
      );
      expect(
        spec.entries.last.intendedKind,
        OperationRecoveryEntryKind.symbolicLink,
      );
      expect(spec.draftCleanups.single.expectedBaseObjectId, _published);
      expect(operation.record.kind, 'resolveSkillDrift');
      expect(operation.record.subjects.single.beforeObjectId, _current);
      expect(operation.record.subjects.single.afterObjectId, _published);
      expect(
        operation.revisionSelectionChanges.single.intendedEffective!.objectId,
        _published,
      );
    },
  );

  test(
    'sealDriftPlan restore touches reviewed drift and missing, leaves matching copy unchanged',
    () async {
      final preflight = await reviewedDrift();
      final operation = sealDrift(preflight);
      final entries = registry.lookup(_operationId)!.entries;
      expect(entries.map((e) => e.targetPath), [
        preflight.current.artifacts.first.targetPath,
        preflight.current.artifacts.last.targetPath,
      ]);
      expect(entries.first.intendedKind, OperationRecoveryEntryKind.directory);
      expect(
        entries.last.intendedKind,
        OperationRecoveryEntryKind.symbolicLink,
      );
      expect(operation.businessChanges.isEmpty, isTrue);
      expect(operation.revisionSelectionChanges, isEmpty);
      expect(operation.record.subjects.single.beforeObjectId, isNull);
      expect(operation.record.subjects.single.afterObjectId, isNull);
    },
  );

  test(
    'sealDriftPlan rejects a publication omitting a managed materialization',
    () async {
      final preflight = await reviewedDrift(keep: true);
      final published = driftPublishPlan(preflight);
      final incomplete = PreparedRestorePublishPlan(
        businessChanges: published.businessChanges,
        revisionSelectionChanges: published.revisionSelectionChanges,
        recoveryIntent: published.recoveryIntent,
        materializationIntents: published.materializationIntents
            .take(1)
            .toList(),
      );
      expect(
        () => sealDrift(preflight, publication: incomplete),
        throwsStateError,
      );
    },
  );

  test(
    'sealDriftPlan metadata verifier rejects changed wrong-type bytes',
    () async {
      final preflight = await reviewedDrift(metadataOnly: true);
      sealDrift(preflight);
      final entry = registry.lookup(_operationId)!.entries.first;
      expect(await entry.verifyBeforeCapture!(entry.targetPath), isTrue);
      await File(entry.targetPath).writeAsString('changed external metadata');
      await expectLater(
        entry.verifyBeforeCapture!(entry.targetPath),
        throwsA(isA<ExternalOperationPreconditionChanged>()),
      );
    },
  );

  test(
    'sealDriftPlan rechecks untouched matching copy before capturing restore',
    () async {
      final preflight = await reviewedDrift();
      sealDrift(preflight);
      final repoEntry = registry.lookup(_operationId)!.entries.first;
      final other = preflight.current.artifacts[1].targetPath;
      await File(
        path.join(other, 'notes'),
      ).writeAsString('later external drift');
      await expectLater(
        repoEntry.verifyBeforeCapture!(repoEntry.targetPath),
        throwsA(isA<ExternalOperationPreconditionChanged>()),
      );
      expect(
        await File(path.join(other, 'notes')).readAsString(),
        'later external drift',
      );
      expect(
        await File(path.join(repoEntry.targetPath, 'notes')).readAsString(),
        'external',
      );
    },
  );

  test(
    'sealDriftPlan propagates context cancellation token to artifact verifiers',
    () async {
      final preflight = await reviewedDrift();
      final inspector = DriftExportInspector(
        delegate: const FileSystemPublishedArtifactInspector(
          contentWorker: DirectRevisionContentWorker(),
          metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
        ),
      );
      plans = WorkspaceRevisionOperationPlans(
        assembler: OperationPlanAssembler(
          subjectIdentities: _SubjectIdentities(),
          recoveryPlans: OperationRecoveryPlanFactory(registry: registry),
        ),
        recoverySpecs: registry,
        layout: layout,
        targetExpectations: const _TargetExpectations(),
        artifactInspector: inspector,
      );
      final source = CancellationSource();
      sealDrift(preflight, token: source.token);
      final entry = registry.lookup(_operationId)!.entries.first;
      expect(await entry.verifyBeforeCapture!(entry.targetPath), isTrue);
      expect(inspector.observedTokens, isNotEmpty);
      expect(
        inspector.observedTokens.every(
          (token) => identical(token, source.token),
        ),
        isTrue,
      );
    },
  );

  test('initial import seals Store, Bundle and materializations', () {
    final activationRoot = path.join(temporaryDirectory.path, 'agent');
    final target = ResolvedActivationTarget(
      location: activationRoot,
      scope: ActivationScope.global,
      mode: ActivationMode.copy,
      agentIds: const <String>['agent'],
    );
    final acquired = _acquiredSkill();
    final subject = InitialImportSubjectPreflight(
      skill: acquired,
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      sourcePayload: const PersistedSourcePayload(
        kind: WorkspaceSourceKind.local,
        payloadSchemaVersion: 1,
        payloadJson: '{}',
      ),
      targets: <InitialImportTargetPreflight>[
        InitialImportTargetPreflight(
          target: target,
          targetPath: path.join(activationRoot, acquired.slotKey),
          mustExist: false,
        ),
      ],
    );
    final preflight = InitialImportPreflight(
      kind: InitialImportKind.install,
      snapshotRevision: RepositoryRevision(4),
      plannedAtMicros: 10,
      subjects: <InitialImportSubjectPreflight>[subject],
      revisionIntents: <InitialRevisionPreparationIntent>[
        InitialRevisionPreparationIntent(
          managedSkillId: _skillId,
          sourceLineage: _lineage,
          tree: acquired.tree,
          resolvedSourceRevision: null,
        ),
      ],
    );
    final envelope = plans.createEnvelope(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(4),
      preflight: preflight,
    );
    final prepared = PreparedInitialRevision(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      objectId: _initial,
      objectFormat: WorkspaceObjectFormat.sha1,
      candidateRecoveryReference: operationRecoveryReference(
        _operationId,
        'candidate-${_skillId.value}',
      ),
      bundleRecoveryReference: operationRecoveryReference(
        _operationId,
        'bundle-${_skillId.value}',
      ),
    );
    final address = RevisionAddress(
      sourceLineage: _lineage,
      objectId: _initial,
    );
    final operation = plans.sealPlan(
      envelope: envelope,
      preflight: preflight,
      initialImportPlan: InitialImportPlan(
        kind: InitialImportKind.install,
        businessChanges: _managedSkillChanges(),
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: _skillId,
            previousUpstream: null,
            previousEffective: null,
            intendedUpstream: address,
            intendedEffective: address,
          ),
        ],
        revisionIntents: preflight.revisionIntents,
        preparedRevisions: <PreparedInitialRevision>[prepared],
        recoveryIntents: <RevisionRecoveryIntent>[
          RevisionRecoveryIntent(
            managedSkillId: _skillId,
            sourceLineage: _lineage,
            retainedRoot: _initial,
            recoveryReference: prepared.bundleRecoveryReference,
          ),
        ],
        materializationIntents: <InitialImportMaterializationIntent>[
          RepositoryCopyMaterializationIntent(
            managedSkillId: _skillId,
            slotKey: 'sample',
            revision: address,
          ),
        ],
        affectedSkillIds: <ManagedSkillId>{_skillId},
      ),
    );

    expect(envelope.isSealedBy(operation), isTrue);
    expect(operation.record.subjects.single.afterObjectId, _initial);
    final spec = registry.lookup(_operationId)!;
    expect(spec.entries, hasLength(4));
    expect(
      spec.entries.map((entry) => entry.targetPath),
      containsAll(<String>[
        layout.revisionStorePath(_skillId),
        layout.revisionBundlePath(_skillId),
        layout.repositoryCopyPath('sample'),
        path.join(activationRoot, 'sample'),
      ]),
    );
  });

  test('initial import refuses two materializations on one target path', () {
    // The resolver merges roots that are one directory; if a plan still
    // carries two targets on one path, sealing must fail loudly rather than
    // mutate it twice.
    final activationRoot = path.join(temporaryDirectory.path, 'agent');
    final acquired = _acquiredSkill();
    final targetPath = path.join(activationRoot, acquired.slotKey);
    final targets = <InitialImportTargetPreflight>[
      for (final agentId in <String>['agent', 'other'])
        InitialImportTargetPreflight(
          target: ResolvedActivationTarget(
            location: activationRoot,
            scope: ActivationScope.global,
            mode: ActivationMode.copy,
            agentIds: <String>[agentId],
          ),
          targetPath: targetPath,
          mustExist: false,
        ),
    ];
    final subject = InitialImportSubjectPreflight(
      skill: acquired,
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      sourcePayload: const PersistedSourcePayload(
        kind: WorkspaceSourceKind.local,
        payloadSchemaVersion: 1,
        payloadJson: '{}',
      ),
      targets: targets,
    );
    final preflight = InitialImportPreflight(
      kind: InitialImportKind.install,
      snapshotRevision: RepositoryRevision(4),
      plannedAtMicros: 10,
      subjects: <InitialImportSubjectPreflight>[subject],
      revisionIntents: <InitialRevisionPreparationIntent>[
        InitialRevisionPreparationIntent(
          managedSkillId: _skillId,
          sourceLineage: _lineage,
          tree: acquired.tree,
          resolvedSourceRevision: null,
        ),
      ],
    );
    final envelope = plans.createEnvelope(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(4),
      preflight: preflight,
    );
    final prepared = PreparedInitialRevision(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      objectId: _initial,
      objectFormat: WorkspaceObjectFormat.sha1,
      candidateRecoveryReference: operationRecoveryReference(
        _operationId,
        'candidate-${_skillId.value}',
      ),
      bundleRecoveryReference: operationRecoveryReference(
        _operationId,
        'bundle-${_skillId.value}',
      ),
    );
    final address = RevisionAddress(
      sourceLineage: _lineage,
      objectId: _initial,
    );

    expect(
      () => plans.sealPlan(
        envelope: envelope,
        preflight: preflight,
        initialImportPlan: InitialImportPlan(
          kind: InitialImportKind.install,
          businessChanges: _managedSkillChanges(),
          revisionSelectionChanges: <RevisionSelectionChangePlan>[
            RevisionSelectionChangePlan(
              managedSkillId: _skillId,
              previousUpstream: null,
              previousEffective: null,
              intendedUpstream: address,
              intendedEffective: address,
            ),
          ],
          revisionIntents: preflight.revisionIntents,
          preparedRevisions: <PreparedInitialRevision>[prepared],
          recoveryIntents: <RevisionRecoveryIntent>[
            RevisionRecoveryIntent(
              managedSkillId: _skillId,
              sourceLineage: _lineage,
              retainedRoot: _initial,
              recoveryReference: prepared.bundleRecoveryReference,
            ),
          ],
          materializationIntents: <InitialImportMaterializationIntent>[
            RepositoryCopyMaterializationIntent(
              managedSkillId: _skillId,
              slotKey: 'sample',
              revision: address,
            ),
          ],
          affectedSkillIds: <ManagedSkillId>{_skillId},
        ),
      ),
      throwsStateError,
    );
  });

  test('Draft Publish reanchors at BCP and finalizes captured Draft', () {
    final skill = _managedSkill(
      draft: DraftSummary(
        purpose: DraftPurpose.customization,
        path: layout.draftPath(_skillId),
        isDirty: true,
        updatedAt: DateTime.fromMicrosecondsSinceEpoch(2, isUtc: true),
      ),
    );
    final state = _draftState();
    final preflight = PublishDraftPreparationRequired(
      snapshotRevision: RepositoryRevision(2),
      plannedAtMicros: 4,
      skill: skill,
      state: state,
    );
    final envelope = plans.createPublishEnvelope(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(2),
      preflight: preflight,
    );
    final effective = RevisionAddress(
      sourceLineage: _lineage,
      objectId: _published,
    );
    final operation = plans.sealPublishPlan(
      envelope: envelope,
      preflight: preflight,
      preparedPlan: PreparedDraftPublishPlan(
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            _revisionMetadata(_published, _newHash),
            PutDraftWorkspace(
              managedSkillId: _skillId,
              sourceLineageId: _lineage.encoded,
              baseObjectId: _published.value,
              purpose: WorkspaceDraftPurpose.customization,
              createdAtMicros: 2,
              updatedAtMicros: 4,
            ),
          ],
        ),
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: _skillId,
            previousUpstream: RevisionAddress(
              sourceLineage: _lineage,
              objectId: _initial,
            ),
            previousEffective: RevisionAddress(
              sourceLineage: _lineage,
              objectId: _current,
            ),
            intendedUpstream: RevisionAddress(
              sourceLineage: _lineage,
              objectId: _initial,
            ),
            intendedEffective: effective,
          ),
        ],
        recoveryIntent: DraftRevisionRecoveryIntent(
          managedSkillId: _skillId,
          sourceLineage: _lineage,
          retainedRoots: <RevisionObjectId>[_published],
          candidateRecoveryReference: operationRecoveryReference(
            _operationId,
            'candidate-${_skillId.value}',
          ),
          bundleRecoveryReference: operationRecoveryReference(
            _operationId,
            'bundle-${_skillId.value}',
          ),
          draftCleanup: PublishedDraftCleanupIntent(
            managedSkillId: _skillId,
            expectedBaseObjectId: _published,
            capturedFingerprint: DraftFingerprint(const []),
          ),
        ),
        materializationIntents: <DraftMaterializationIntent>[
          DraftRepositoryMaterializationIntent(
            managedSkillId: _skillId,
            revision: effective,
            recoveryReference: operationRecoveryReference(
              _operationId,
              'materialization-${_skillId.value}',
            ),
            slotKey: 'sample',
          ),
        ],
      ),
    );

    expect(envelope.isSealedBy(operation), isTrue);
    expect(operation.record.subjects.single.beforeObjectId, _current);
    expect(operation.record.subjects.single.afterObjectId, _published);
    final spec = registry.lookup(_operationId)!;
    final targets = spec.entries.map((entry) => entry.targetPath).toSet();
    expect(
      targets,
      containsAll(<String>{
        layout.revisionBundlePath(_skillId),
        layout.repositoryCopyPath('sample'),
      }),
    );
    expect(spec.draftCleanups.single.targetPath, layout.draftPath(_skillId));
    expect(spec.draftCleanups.single.expectedBaseObjectId, _published);
    expect(
      operation.preparationSteps.length,
      envelope.preparationSteps.length + 1,
    );
  });

  test('Discard Draft is a recoverable one-stage deletion', () {
    final skill = _managedSkill();
    final operation = plans.createDiscardPlan(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(3),
      plan: DiscardDraftPlan(
        snapshotRevision: RepositoryRevision(3),
        skill: skill,
        state: _draftState(),
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            DeleteDraftWorkspace(_skillId),
          ],
        ),
      ),
    );

    expect(operation.preparationSteps, hasLength(1));
    expect(operation.applyingSteps, hasLength(1));
    final entry = registry.lookup(_operationId)!.entries.single;
    expect(entry.targetPath, layout.draftPath(_skillId));
    expect(entry.intendedKind, isNull);
  });

  test('Update Slot migration replaces old and new published paths', () {
    final activationRoot = path.join(temporaryDirectory.path, 'agent');
    final activation = SkillActivation(
      location: activationRoot,
      scope: ActivationScope.global,
      mode: ActivationMode.symbolicLink,
      agentIds: const <String>['agent'],
    );
    final skill = _managedSkillWith(
      slotKey: 'old-sample',
      activations: <SkillActivation>[activation],
    );
    final intent = UpdateRevisionPreparationIntent(
      managedSkillId: _skillId,
      expectedRepositoryRevision: RepositoryRevision(7),
      sourceLineage: _lineage,
      previousUpstream: _initial,
      currentEffective: _current,
      currentSlotKey: 'old-sample',
      currentDeclaredName: 'sample',
      currentDisplayName: 'Sample',
      activations: <SkillActivation>[activation],
      managedSkillCreatedAtMicros: 1,
      draftCreatedAtMicros: null,
      incomingTree: _acquiredSkill().tree,
      incomingDeclaredName: 'sample',
      incomingDescription: 'Description',
      incomingSlotKey: 'new-sample',
      resolvedSourceRevision: null,
      hadCleanDraft: false,
    );
    final preflight = UpdatePreparationRequired(
      managedSkillId: _skillId,
      snapshotRevision: RepositoryRevision(7),
      plannedAtMicros: 8,
      currentSkill: skill,
      revisionState: UpdateRevisionState(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        previousUpstream: _initial,
        currentEffective: _current,
        previousUpstreamContentHash: _oldHash,
        managedSkillCreatedAtMicros: 1,
        draftCreatedAtMicros: null,
      ),
      intent: intent,
    );
    final envelope = plans.createUpdateEnvelope(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(7),
      preflights: <UpdatePreparationRequired>[preflight],
    );
    final effective = RevisionAddress(
      sourceLineage: _lineage,
      objectId: _published,
    );
    final prepared = PreparedUpdatePlan(
      kind: PreparedUpdatePlanKind.published,
      businessChanges: WorkspaceBusinessChangeSet(
        mutations: <WorkspaceBusinessMutation>[
          _revisionMetadata(_published, _newHash),
        ],
      ),
      revisionSelectionChanges: <RevisionSelectionChangePlan>[
        RevisionSelectionChangePlan(
          managedSkillId: _skillId,
          previousUpstream: RevisionAddress(
            sourceLineage: _lineage,
            objectId: _initial,
          ),
          previousEffective: RevisionAddress(
            sourceLineage: _lineage,
            objectId: _current,
          ),
          intendedUpstream: RevisionAddress(
            sourceLineage: _lineage,
            objectId: _incoming,
          ),
          intendedEffective: effective,
        ),
      ],
      recoveryIntent: UpdateRevisionRecoveryIntent(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        retainedRoots: <RevisionObjectId>[_published],
        candidateRecoveryReference: operationRecoveryReference(
          _operationId,
          'candidate-${_skillId.value}',
        ),
        bundleRecoveryReference: operationRecoveryReference(
          _operationId,
          'bundle-${_skillId.value}',
        ),
      ),
      materializationIntents: <UpdateMaterializationIntent>[
        UpdateRepositoryMaterializationIntent(
          managedSkillId: _skillId,
          revision: effective,
          recoveryReference: operationRecoveryReference(
            _operationId,
            'materialization-${_skillId.value}',
          ),
          oldSlotKey: 'old-sample',
          newSlotKey: 'new-sample',
        ),
        UpdateActivationMaterializationIntent(
          managedSkillId: _skillId,
          revision: effective,
          recoveryReference: operationRecoveryReference(
            _operationId,
            'materialization-${_skillId.value}',
          ),
          activation: activation,
          oldSlotKey: 'old-sample',
          newSlotKey: 'new-sample',
        ),
      ],
    );

    final operation = plans.sealUpdatePlan(
      envelope: envelope,
      preflights: <UpdatePreparationRequired>[preflight],
      preparedPlans: <PreparedUpdatePlan>[prepared],
    );

    expect(envelope.isSealedBy(operation), isTrue);
    expect(operation.record.subjects.single.afterObjectId, _published);
    final entries = registry.lookup(_operationId)!.entries;
    expect(entries, hasLength(5));
    expect(
      entries.map((entry) => entry.targetPath),
      containsAll(<String>[
        layout.repositoryCopyPath('old-sample'),
        layout.repositoryCopyPath('new-sample'),
        path.join(activationRoot, 'old-sample'),
        path.join(activationRoot, 'new-sample'),
      ]),
    );
    expect(
      entries
          .singleWhere(
            (entry) =>
                entry.targetPath == path.join(activationRoot, 'new-sample'),
          )
          .intendedSymbolicLinkTarget,
      layout.repositoryCopyPath('new-sample'),
    );
  });

  test('Candidate Abandon replaces Bundle and removes Draft recoverably', () {
    final abandon = UpdateCandidateAbandonPlan(
      businessChanges: WorkspaceBusinessChangeSet(
        mutations: <WorkspaceBusinessMutation>[
          DeleteUpdateCandidateSession(_skillId),
          DeleteDraftWorkspace(_skillId),
        ],
      ),
      revisionSelectionChanges: const <RevisionSelectionChangePlan>[],
      cleanupIntent: UpdateCandidateCleanupIntent(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        previousUpstream: _initial,
        previousEffective: _current,
        incomingUpstream: _incoming,
        candidateObjectId: _published,
        retainedPublishedRoots: <RevisionObjectId>[_initial, _current],
      ),
    );
    final envelope = plans.createCandidateAbandonEnvelope(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(9),
      abandonPlan: abandon,
    );

    final operation = plans.sealCandidateAbandonPlan(
      envelope: envelope,
      abandonPlan: abandon,
      prepared: PreparedUpdateCandidateAbandon(
        managedSkillId: _skillId,
        sourceLineage: _lineage,
        retainedPublishedRoots: <RevisionObjectId>[_initial, _current],
        bundleRecoveryReference: operationRecoveryReference(
          _operationId,
          'bundle-${_skillId.value}',
        ),
      ),
    );

    expect(envelope.isSealedBy(operation), isTrue);
    expect(operation.revisionSelectionChanges, isEmpty);
    final entries = registry.lookup(_operationId)!.entries;
    expect(entries, hasLength(2));
    final bundle = entries.singleWhere(
      (entry) => entry.targetPath.startsWith(layout.revisionBundlesRoot),
    );
    expect(
      bundle.intendedSourcePath,
      layout.operationBundleCandidatePath(_operationId, _skillId),
    );
    final draft = entries.singleWhere(
      (entry) => entry.targetPath == layout.draftPath(_skillId),
    );
    expect(draft.intendedKind, isNull);
  });

  test('Restore Publish appends history and rematerializes the Skill', () {
    final skill = _managedSkill();
    final state = RestoreRevisionState(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      currentUpstream: _initial,
      currentEffective: _current,
      managedSkillCreatedAtMicros: 1,
      draftCreatedAtMicros: null,
    );
    final selected = HistoricalRevisionSelection(
      reference: OperationSubjectReference(
        operationId: OperationId('123e4567-e89b-42d3-a456-426614174021'),
        subjectId: '123e4567-e89b-42d3-a456-426614174022',
      ),
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      objectId: _initial,
      contentHash: _oldHash,
      declaredName: 'sample',
    );
    final preflight = RestorePublishPreflight(
      snapshotRevision: RepositoryRevision(9),
      plannedAtMicros: 10,
      skill: skill,
      selected: selected,
      state: state,
      hadCleanDraft: false,
    );
    final envelope = plans.createRestoreEnvelope(
      operationId: _operationId,
      expectedRepositoryRevision: RepositoryRevision(9),
      preflight: preflight,
    );
    final effective = RevisionAddress(
      sourceLineage: _lineage,
      objectId: _published,
    );
    final operation = plans.sealRestorePlan(
      envelope: envelope,
      preflight: preflight,
      preparedPlan: PreparedRestorePublishPlan(
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            _revisionMetadata(_published, _newHash),
          ],
        ),
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: _skillId,
            previousUpstream: RevisionAddress(
              sourceLineage: _lineage,
              objectId: _initial,
            ),
            previousEffective: RevisionAddress(
              sourceLineage: _lineage,
              objectId: _current,
            ),
            intendedUpstream: RevisionAddress(
              sourceLineage: _lineage,
              objectId: _initial,
            ),
            intendedEffective: effective,
          ),
        ],
        recoveryIntent: RestoreRevisionRecoveryIntent(
          managedSkillId: _skillId,
          sourceLineage: _lineage,
          retainedRoots: <RevisionObjectId>[_published],
          candidateRecoveryReference: operationRecoveryReference(
            _operationId,
            'candidate-${_skillId.value}',
          ),
          bundleRecoveryReference: operationRecoveryReference(
            _operationId,
            'bundle-${_skillId.value}',
          ),
          draftCleanup: null,
        ),
        materializationIntents: <RestoreMaterializationIntent>[
          RestoreRepositoryMaterializationIntent(
            managedSkillId: _skillId,
            revision: effective,
            recoveryReference: operationRecoveryReference(
              _operationId,
              'materialization-${_skillId.value}',
            ),
            slotKey: 'sample',
          ),
        ],
      ),
    );

    expect(envelope.isSealedBy(operation), isTrue);
    expect(operation.record.subjects.single.beforeObjectId, _current);
    expect(operation.record.subjects.single.afterObjectId, _published);
    expect(registry.lookup(_operationId)!.entries, hasLength(2));
  });
}

WorkspaceBusinessChangeSet _managedSkillChanges() => WorkspaceBusinessChangeSet(
  mutations: <WorkspaceBusinessMutation>[
    PutManagedSkill(
      managedSkillId: _skillId,
      slotKey: 'sample',
      declaredName: 'sample',
      displayName: 'sample',
      description: 'Description',
      activeSourceLineageId: _lineage.encoded,
      createdAtMicros: 1,
      updatedAtMicros: 1,
    ),
  ],
);

PutRevisionMetadata _revisionMetadata(RevisionObjectId objectId, String hash) =>
    PutRevisionMetadata(
      sourceLineageId: _lineage.encoded,
      objectId: objectId.value,
      contentHash: hash,
      fileCount: 1,
      byteSize: 10,
      declaredName: 'sample',
      validationState: WorkspaceRevisionValidationState.valid,
      validationCode: null,
      createdAtMicros: 4,
    );

DraftRevisionState _draftState() => DraftRevisionState(
  managedSkillId: _skillId,
  sourceLineage: _lineage,
  currentUpstream: _initial,
  currentEffective: _current,
  managedSkillCreatedAtMicros: 1,
  draftCreatedAtMicros: 2,
);

ManagedSkill _managedSkill({DraftSummary? draft}) => ManagedSkill(
  id: _skillId,
  slotKey: 'sample',
  declaredName: 'sample',
  displayName: 'Sample',
  description: 'Description',
  source: LocalSourceDescriptor(locator: Directory.systemTemp.absolute.path),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: _oldHash,
    fileCount: 1,
    byteSize: 10,
    publishedAt: DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true),
  ),
  draft: draft,
);

ManagedSkill _managedSkillWith({
  required String slotKey,
  required List<SkillActivation> activations,
}) => ManagedSkill(
  id: _skillId,
  slotKey: slotKey,
  declaredName: 'sample',
  displayName: 'Sample',
  description: 'Description',
  source: LocalSourceDescriptor(locator: Directory.systemTemp.absolute.path),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: _oldHash,
    fileCount: 1,
    byteSize: 10,
    publishedAt: DateTime.fromMicrosecondsSinceEpoch(1, isUtc: true),
  ),
  activations: activations,
);

AcquiredSourceSkill _acquiredSkill() {
  final tree = const SkillContentNormalizer().normalize(<SkillContentEntry>[
    SkillContentEntry.file(
      path: 'SKILL.md',
      bytes: utf8.encode('---\nname: sample\ndescription: Description\n---\n'),
      isExecutable: false,
    ),
  ]).valueOrNull!;
  return AcquiredSourceSkill(
    provenance: LocalSourceDescriptor(
      locator: Directory.systemTemp.absolute.path,
    ),
    declaredName: 'sample',
    description: 'Description',
    slotKey: 'sample',
    skillPath: '',
    frontmatter: const <String, Object?>{},
    tree: tree,
  );
}

final class _SubjectIdentities implements OperationSubjectIdentityPort {
  var _next = 10;

  @override
  String allocateOperationSubjectId() =>
      '123e4567-e89b-42d3-a456-4266141740${_next++}';
}

final class _TargetExpectations implements ActivationTargetExpectationPort {
  const _TargetExpectations();

  @override
  Future<bool> matches({
    required ManagedSkill skill,
    required ResolvedActivationTarget target,
    required String targetPath,
    required ActivationTargetExpectation expectation,
  }) async => true;
}

final _operationId = OperationId('123e4567-e89b-42d3-a456-426614174020');
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('lineage-1');
final _initial = RevisionObjectId('1' * 40);
final _current = RevisionObjectId('2' * 40);
final _published = RevisionObjectId('3' * 40);
final _incoming = RevisionObjectId('4' * 40);
const _oldHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _newHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
