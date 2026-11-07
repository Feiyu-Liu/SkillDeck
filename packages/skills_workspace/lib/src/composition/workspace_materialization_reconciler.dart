import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;

import '../application/ports/published_artifact_ports.dart';
import '../application/ports/workspace_lifecycle_ports.dart';
import '../application/revision_store/managed_skill_revision_access_gate.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../domain/public_models.dart';
import '../domain/revision_content.dart';
import '../infrastructure/database/workspace_database.dart';
import '../infrastructure/workspace_layout.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';

final class _MaterializationSelection {
  _MaterializationSelection({
    required this.managedSkillId,
    required this.slotKey,
    required this.effectiveObjectId,
    required this.effectiveContentHash,
    required List<_ActivationSelection> activations,
  }) : activations = List.unmodifiable(activations);

  final ManagedSkillId managedSkillId;
  final String slotKey;
  final RevisionObjectId effectiveObjectId;
  final String effectiveContentHash;
  final List<_ActivationSelection> activations;
}

final class _ActivationSelection {
  const _ActivationSelection({
    required this.location,
    required this.symbolicLink,
    required this.scope,
    required this.agentIds,
    this.projectRootId,
    this.projectRootPath,
  });

  final String location;
  final bool symbolicLink;
  final ActivationScope scope;
  final List<String> agentIds;
  final String? projectRootId;
  final String? projectRootPath;

  SkillActivation get activation => SkillActivation(
    location: location,
    scope: scope,
    mode: symbolicLink ? ActivationMode.symbolicLink : ActivationMode.copy,
    agentIds: agentIds,
    projectRootId: projectRootId,
    projectRootPath: projectRootPath,
  );
}

final class _MaterializationRepairPlan {
  _MaterializationRepairPlan({
    required this.selection,
    required this.repositoryCopyPath,
    required List<String> directoryRepairs,
    required List<String> symbolicLinkRepairs,
    required this.mismatchingArtifactCount,
    required this.missingArtifactCount,
  }) : directoryRepairs = List.unmodifiable(directoryRepairs),
       symbolicLinkRepairs = List.unmodifiable(symbolicLinkRepairs);

  final _MaterializationSelection selection;
  final String repositoryCopyPath;
  final List<String> directoryRepairs;
  final List<String> symbolicLinkRepairs;
  final int mismatchingArtifactCount;
  final int missingArtifactCount;
}

/// Rebuilds every non-isolated Repository Copy and Activation from SQLite's
/// selected Effective Revision.
///
/// This runs under the Workspace Writer Lock after Journal recovery. It may
/// therefore repair published-artifact drift directly: these paths are
/// rebuildable projections and never become revision authority.
final class DriftWorkspaceMaterializationReconciler
    implements WorkspaceMaterializationReconciliationPort {
  static const int _inspectionConcurrency = 4;

  const DriftWorkspaceMaterializationReconciler({
    required WorkspaceDatabase database,
    required WorkspaceLayout layout,
    required RevisionEnginePort revisionEngine,
    required DurableWorkspaceFilesystem filesystem,
    required PublishedArtifactInspectorPort artifactInspector,
    required ManagedSkillRevisionAccessGate accessGate,
  }) : _database = database,
       _layout = layout,
       _revisionEngine = revisionEngine,
       _filesystem = filesystem,
       _artifactInspector = artifactInspector,
       _accessGate = accessGate;

  final WorkspaceDatabase _database;
  final WorkspaceLayout _layout;
  final RevisionEnginePort _revisionEngine;
  final DurableWorkspaceFilesystem _filesystem;
  final PublishedArtifactInspectorPort _artifactInspector;
  final ManagedSkillRevisionAccessGate _accessGate;

  @override
  Future<SkillMaterializationInspection> inspectSkillMaterializations(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  }) async {
    final token = cancellationToken ?? CancellationToken.none();
    final selection = (await _readSelections()).singleWhere(
      (selection) => selection.managedSkillId == managedSkillId,
    );
    final repositoryCopyPath = _layout.repositoryCopyPath(selection.slotKey);
    final artifacts = <SkillMaterializationArtifact>[];

    Future<void> addArtifact(SkillMaterializationArtifact artifact) async {
      var inspected = artifact.inspection;
      if (inspected.mismatchKind ==
          PublishedArtifactMismatchKind.wrongEntryType) {
        final observed = await _artifactInspector.observe(
          path: artifact.targetPath,
          cancellationToken: token,
        );
        if (observed.state == PublishedArtifactState.matching) {
          inspected = observed;
        } else if (observed.observedEntryKind == ObservedEntryKind.directory ||
            observed.observedEntryKind == ObservedEntryKind.file) {
          inspected = await _artifactInspector.observeMetadata(
            path: artifact.targetPath,
            cancellationToken: token,
          );
        } else {
          throw const SkillDriftUnsafe();
        }
        if (inspected.state != PublishedArtifactState.matching ||
            inspected.observedEntryKind !=
                artifact.inspection.observedEntryKind) {
          throw const SkillDriftUnsafe();
        }
      } else if (inspected.mismatchKind ==
          PublishedArtifactMismatchKind.contentChanged) {
        final metadata = await _artifactInspector.observeMetadata(
          path: artifact.targetPath,
          cancellationToken: token,
        );
        if (metadata.state != PublishedArtifactState.matching ||
            metadata.observedEntryKind != inspected.observedEntryKind) {
          throw const SkillDriftUnsafe();
        }
        inspected = PublishedArtifactInspection(
          state: inspected.state,
          observedEntryKind: inspected.observedEntryKind,
          mismatchKind: inspected.mismatchKind,
          fingerprint: inspected.fingerprint,
          metadataFingerprint: metadata.metadataFingerprint,
          containsSymbolicLinks: metadata.containsSymbolicLinks,
          fileCount: inspected.fileCount,
          byteSize: inspected.byteSize,
        );
      }
      if (inspected.state == PublishedArtifactState.unsafe ||
          (artifact.inspection.state == PublishedArtifactState.mismatching &&
              inspected.fingerprint == null &&
              inspected.metadataFingerprint == null)) {
        throw const SkillDriftUnsafe();
      }
      artifacts.add(
        SkillMaterializationArtifact(
          locationKind: artifact.locationKind,
          targetPath: artifact.targetPath,
          activation: artifact.activation,
          inspection: PublishedArtifactInspection(
            state: artifact.inspection.state,
            mismatchKind: artifact.inspection.mismatchKind,
            observedEntryKind: inspected.observedEntryKind,
            fingerprint: inspected.fingerprint,
            metadataFingerprint: inspected.metadataFingerprint,
            containsSymbolicLinks: inspected.containsSymbolicLinks,
            fileCount: inspected.fileCount,
            byteSize: inspected.byteSize,
          ),
        ),
      );
    }

    await addArtifact(
      SkillMaterializationArtifact(
        locationKind: SkillDriftLocationKind.repositoryCopy,
        targetPath: repositoryCopyPath,
        inspection: await _artifactInspector.inspectDirectory(
          path: repositoryCopyPath,
          expectedContentHash: selection.effectiveContentHash,
          cancellationToken: token,
        ),
      ),
    );
    for (final activation in selection.activations) {
      final targetPath = path.join(activation.location, selection.slotKey);
      await addArtifact(
        SkillMaterializationArtifact(
          locationKind: activation.symbolicLink
              ? SkillDriftLocationKind.symbolicLinkActivation
              : SkillDriftLocationKind.copyActivation,
          targetPath: targetPath,
          activation: activation.activation,
          inspection: activation.symbolicLink
              ? await _artifactInspector.inspectSymbolicLink(
                  path: targetPath,
                  expectedTarget: repositoryCopyPath,
                  cancellationToken: token,
                )
              : await _artifactInspector.inspectDirectory(
                  path: targetPath,
                  expectedContentHash: selection.effectiveContentHash,
                  cancellationToken: token,
                ),
        ),
      );
    }
    return SkillMaterializationInspection(
      effectiveObjectId: selection.effectiveObjectId,
      effectiveContentHash: selection.effectiveContentHash,
      artifacts: artifacts,
    );
  }

  @override
  Future<WorkspaceMaterializationReconciliationReport>
  reconcileMaterializations({
    required Set<ManagedSkillId> isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
    bool repairMismatching = true,
    bool repairMissing = true,
  }) async {
    var inspectedArtifactCount = 0;
    var inspectedFileCount = 0;
    var inspectedByteCount = 0;
    var repairedArtifactCount = 0;
    var mismatchingArtifactCount = 0;
    var missingArtifactCount = 0;
    final mismatchingSkillIds = <ManagedSkillId>{};
    final missingSkillIds = <ManagedSkillId>{};
    final cancellationToken = CancellationToken.none();

    Future<PublishedArtifactInspection> inspectDirectory(
      String targetPath,
      String expectedContentHash,
    ) async {
      final inspection = await _artifactInspector.inspectDirectory(
        path: targetPath,
        expectedContentHash: expectedContentHash,
        cancellationToken: cancellationToken,
      );
      inspectedArtifactCount += 1;
      inspectedFileCount += inspection.fileCount;
      inspectedByteCount += inspection.byteSize;
      return inspection;
    }

    Future<PublishedArtifactInspection> inspectSymbolicLink(
      String targetPath,
      String expectedTarget,
    ) async {
      final inspection = await _artifactInspector.inspectSymbolicLink(
        path: targetPath,
        expectedTarget: expectedTarget,
        cancellationToken: cancellationToken,
      );
      inspectedArtifactCount += 1;
      return inspection;
    }

    Future<_MaterializationRepairPlan> inspectSelection(
      _MaterializationSelection selection,
    ) async {
      final repositoryCopyPath = _layout.repositoryCopyPath(selection.slotKey);
      final repositoryInspection = await inspectDirectory(
        repositoryCopyPath,
        selection.effectiveContentHash,
      );
      _throwIfUnsafe(repositoryInspection);
      final directoryRepairs = <String>[
        if ((repairMissing &&
                repositoryInspection.state == PublishedArtifactState.missing) ||
            (repairMismatching && repositoryInspection.needsRepair))
          repositoryCopyPath,
      ];
      var selectionMissingArtifactCount =
          repositoryInspection.state == PublishedArtifactState.missing ? 1 : 0;
      var selectionMismatchingArtifactCount =
          repositoryInspection.state == PublishedArtifactState.mismatching
          ? 1
          : 0;
      final symbolicLinkRepairs = <String>[];
      for (final activation in selection.activations) {
        final targetPath = path.join(activation.location, selection.slotKey);
        if (activation.symbolicLink) {
          final inspection = await inspectSymbolicLink(
            targetPath,
            repositoryCopyPath,
          );
          _throwIfUnsafe(inspection);
          if ((repairMissing &&
                  inspection.state == PublishedArtifactState.missing) ||
              (repairMismatching && inspection.needsRepair)) {
            symbolicLinkRepairs.add(targetPath);
          }
          if (inspection.state == PublishedArtifactState.mismatching) {
            selectionMismatchingArtifactCount += 1;
          }
          if (inspection.state == PublishedArtifactState.missing) {
            selectionMissingArtifactCount += 1;
          }
        } else {
          final inspection = await inspectDirectory(
            targetPath,
            selection.effectiveContentHash,
          );
          _throwIfUnsafe(inspection);
          if ((repairMissing &&
                  inspection.state == PublishedArtifactState.missing) ||
              (repairMismatching && inspection.needsRepair)) {
            directoryRepairs.add(targetPath);
          }
          if (inspection.state == PublishedArtifactState.mismatching) {
            selectionMismatchingArtifactCount += 1;
          }
          if (inspection.state == PublishedArtifactState.missing) {
            selectionMissingArtifactCount += 1;
          }
        }
      }
      directoryRepairs.sort();
      symbolicLinkRepairs.sort();
      return _MaterializationRepairPlan(
        selection: selection,
        repositoryCopyPath: repositoryCopyPath,
        directoryRepairs: directoryRepairs,
        symbolicLinkRepairs: symbolicLinkRepairs,
        mismatchingArtifactCount: selectionMismatchingArtifactCount,
        missingArtifactCount: selectionMissingArtifactCount,
      );
    }

    final selections = (await _readSelections())
        .where(
          (selection) =>
              !isolatedSkillIds.contains(selection.managedSkillId) &&
              (selectedSkillIds == null ||
                  selectedSkillIds.contains(selection.managedSkillId)),
        )
        .toList(growable: false);
    final inspectionElapsed = Stopwatch()..start();
    final repairs = await _mapConcurrent(
      selections,
      concurrency: _inspectionConcurrency,
      operation: inspectSelection,
    );
    inspectionElapsed.stop();

    final repairElapsed = Stopwatch()..start();
    for (final repair in repairs) {
      mismatchingArtifactCount += repair.mismatchingArtifactCount;
      missingArtifactCount += repair.missingArtifactCount;
      if (repair.mismatchingArtifactCount > 0) {
        mismatchingSkillIds.add(repair.selection.managedSkillId);
      }
      if (repair.missingArtifactCount > 0) {
        missingSkillIds.add(repair.selection.managedSkillId);
      }
      final selection = repair.selection;
      NormalizedSkillTree? tree;
      final directoryRepairs = repair.directoryRepairs;
      if (directoryRepairs.isNotEmpty) {
        final permit = await _accessGate.acquireRead(selection.managedSkillId);
        try {
          tree = await _revisionEngine.readTree(
            _layout.revisionStorePath(selection.managedSkillId),
            selection.effectiveObjectId,
          );
        } finally {
          await permit.release();
        }
        for (final targetPath in directoryRepairs) {
          await _replaceDirectory(targetPath, tree);
          repairedArtifactCount += 1;
        }
      }
      final symbolicLinkRepairs = repair.symbolicLinkRepairs;
      if (symbolicLinkRepairs.isNotEmpty) {
        for (final targetPath in symbolicLinkRepairs) {
          await _replaceSymbolicLink(targetPath, repair.repositoryCopyPath);
          repairedArtifactCount += 1;
        }
      }
    }
    repairElapsed.stop();
    return WorkspaceMaterializationReconciliationReport(
      inspectedArtifactCount: inspectedArtifactCount,
      inspectedFileCount: inspectedFileCount,
      inspectedByteCount: inspectedByteCount,
      repairedArtifactCount: repairedArtifactCount,
      mismatchingArtifactCount: mismatchingArtifactCount,
      mismatchingSkillIds: mismatchingSkillIds.toList(growable: false),
      missingArtifactCount: missingArtifactCount,
      missingSkillIds: missingSkillIds.toList(growable: false),
      inspectionElapsed: inspectionElapsed.elapsed,
      repairElapsed: repairElapsed.elapsed,
    );
  }

  Future<List<_MaterializationSelection>> _readSelections() {
    return _database.transaction(() async {
      final selections = _database.currentRevisionSelection;
      final lineages = _database.sourceLineages;
      final skills = _database.managedSkills;
      final revisions = _database.revisionMetadata;
      final rows =
          await _database.select(selections).join(<Join<HasResultSet, dynamic>>[
            innerJoin(
              lineages,
              lineages.id.equalsExp(selections.sourceLineageId) &
                  lineages.managedSkillId.equalsExp(selections.managedSkillId),
            ),
            innerJoin(
              skills,
              skills.id.equalsExp(selections.managedSkillId) &
                  skills.activeSourceLineageId.equalsExp(
                    selections.sourceLineageId,
                  ),
            ),
            innerJoin(
              revisions,
              revisions.sourceLineageId.equalsExp(selections.sourceLineageId) &
                  revisions.objectId.equalsExp(selections.effectiveObjectId),
            ),
          ]).get();
      final activationRows = await _database
          .select(_database.activationLocations)
          .get();
      final activationAgentRows = await _database
          .select(_database.activationAgents)
          .get();
      final agentIdsByLocation = <String, List<String>>{};
      for (final agent in activationAgentRows) {
        agentIdsByLocation
            .putIfAbsent(agent.activationLocationId, () => <String>[])
            .add(agent.agentId);
      }
      final activationsBySkill = <String, List<_ActivationSelection>>{};
      for (final activation in activationRows) {
        if (!path.isAbsolute(activation.canonicalPath) ||
            path.isRootRelative(activation.canonicalPath)) {
          throw StateError('Persisted Activation location is not absolute.');
        }
        activationsBySkill
            .putIfAbsent(
              activation.managedSkillId,
              () => <_ActivationSelection>[],
            )
            .add(
              _ActivationSelection(
                location: path.normalize(activation.canonicalPath),
                scope: switch (activation.scope) {
                  'global' => ActivationScope.global,
                  'project' => ActivationScope.project,
                  _ => throw StateError('Unknown Activation scope.'),
                },
                agentIds: List.unmodifiable(
                  (agentIdsByLocation[activation.id] ?? <String>[])..sort(),
                ),
                projectRootId: activation.projectRootId,
                projectRootPath: activation.projectRootPath,
                symbolicLink: switch (activation.mode) {
                  'copy' => false,
                  'symbolicLink' => true,
                  _ => throw StateError('Unknown Activation mode.'),
                },
              ),
            );
      }
      final result = <_MaterializationSelection>[];
      for (final row in rows) {
        final selection = row.readTable(selections);
        final skill = row.readTable(skills);
        final effectiveRevision = row.readTable(revisions);
        final activations = activationsBySkill[skill.id] ?? [];
        activations.sort(
          (left, right) => left.location.compareTo(right.location),
        );
        result.add(
          _MaterializationSelection(
            managedSkillId: ManagedSkillId(skill.id),
            slotKey: skill.slotKey,
            effectiveObjectId: RevisionObjectId(selection.effectiveObjectId),
            effectiveContentHash: effectiveRevision.contentHash,
            activations: activations,
          ),
        );
      }
      result.sort(
        (left, right) =>
            left.managedSkillId.value.compareTo(right.managedSkillId.value),
      );
      return List<_MaterializationSelection>.unmodifiable(result);
    });
  }

  void _throwIfUnsafe(PublishedArtifactInspection inspection) {
    if (inspection.state == PublishedArtifactState.unsafe) {
      throw StateError('Published materialization could not be inspected.');
    }
  }

  Future<void> _replaceDirectory(
    String destinationPath,
    NormalizedSkillTree tree,
  ) async {
    TargetVolumeStagingPath? staging;
    try {
      staging = await _filesystem.createSiblingStagingPath(
        destinationPath,
        kind: DurableEntryKind.directory,
        purpose: 'reconcile',
      );
      await _filesystem.materializeStagedDirectory(
        rootPath: staging.path,
        files: tree.files.map(
          (file) => StagedDirectoryFile(
            relativePath: file.relativePath,
            bytes: file.bytes,
            isExecutable: file.isExecutable,
          ),
        ),
      );
      await _verifyTree(staging.path, tree);
      final publication = await _filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destinationPath,
        kind: DurableEntryKind.directory,
        makeReadOnly: true,
        requirePlainDirectory: true,
        verify: (candidate) => _verifyTree(candidate, tree),
      );
      staging = null;
      await _cleanupDisplaced(publication, destinationPath);
    } finally {
      final pending = staging;
      if (pending != null) {
        await _removeBestEffort(pending.path, path.dirname(destinationPath));
      }
    }
  }

  Future<void> _replaceSymbolicLink(
    String destinationPath,
    String targetPath,
  ) async {
    TargetVolumeStagingPath? staging;
    try {
      staging = await _filesystem.createSiblingStagingPath(
        destinationPath,
        kind: DurableEntryKind.symbolicLink,
        purpose: 'reconcile',
      );
      await _filesystem.createSymbolicLink(
        linkPath: staging.path,
        targetPath: targetPath,
      );
      final publication = await _filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destinationPath,
        kind: DurableEntryKind.symbolicLink,
        makeReadOnly: false,
        requirePlainDirectory: false,
        verify: (candidate) async {
          final actual = await Link(candidate).target();
          if (!path.equals(
            path.normalize(path.absolute(actual)),
            path.normalize(path.absolute(targetPath)),
          )) {
            throw StateError('Activation symbolic link target changed.');
          }
        },
      );
      staging = null;
      await _cleanupDisplaced(publication, destinationPath);
    } finally {
      final pending = staging;
      if (pending != null) {
        await _removeBestEffort(pending.path, path.dirname(destinationPath));
      }
    }
  }

  Future<void> _verifyTree(String rootPath, NormalizedSkillTree tree) async {
    final expectedFiles = <String, NormalizedSkillFile>{
      for (final file in tree.files) file.relativePath: file,
    };
    final expectedDirectories = <String>{};
    for (final relativePath in expectedFiles.keys) {
      final segments = relativePath.split('/');
      for (var length = 1; length < segments.length; length += 1) {
        expectedDirectories.add(segments.take(length).join('/'));
      }
    }
    final actualFiles = <String>{};
    final actualDirectories = <String>{};
    await for (final entity in Directory(
      rootPath,
    ).list(recursive: true, followLinks: false)) {
      final relativePath = path
          .relative(entity.path, from: rootPath)
          .split(path.separator)
          .join('/');
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          actualDirectories.add(relativePath);
        case FileSystemEntityType.file:
          final expected = expectedFiles[relativePath];
          if (expected == null ||
              !_sameBytes(
                await File(entity.path).readAsBytes(),
                expected.bytes,
              )) {
            throw StateError('Materialized Skill bytes changed.');
          }
          if (!Platform.isWindows) {
            final executable =
                (await File(entity.path).stat()).mode & 0x49 != 0;
            if (executable != expected.isExecutable) {
              throw StateError('Materialized executable intent changed.');
            }
          }
          actualFiles.add(relativePath);
        default:
          throw StateError('Materialized Skill contains a special entry.');
      }
    }
    if (!_sameStrings(actualFiles, expectedFiles.keys.toSet()) ||
        !_sameStrings(actualDirectories, expectedDirectories)) {
      throw StateError('Materialized Skill path set changed.');
    }
  }

  Future<void> _cleanupDisplaced(
    DurablePublication publication,
    String destinationPath,
  ) async {
    final displaced = publication.displacedPath;
    if (displaced != null) {
      await _removeBestEffort(displaced, path.dirname(destinationPath));
    }
  }

  Future<void> _removeBestEffort(String targetPath, String ownerRoot) async {
    try {
      await _filesystem.removeOwnedPath(
        targetPath: targetPath,
        ownerRoot: ownerRoot,
      );
    } on Object {
      // The selected materialization has already been verified and published.
    }
  }
}

Future<List<TResult>> _mapConcurrent<TSource, TResult>(
  List<TSource> source, {
  required int concurrency,
  required Future<TResult> Function(TSource value) operation,
}) async {
  if (source.isEmpty) return <TResult>[];
  final results = List<TResult?>.filled(source.length, null);
  var nextIndex = 0;

  Future<void> runWorker() async {
    while (nextIndex < source.length) {
      final index = nextIndex;
      nextIndex += 1;
      results[index] = await operation(source[index]);
    }
  }

  await Future.wait(<Future<void>>[
    for (
      var worker = 0;
      worker < concurrency && worker < source.length;
      worker += 1
    )
      runWorker(),
  ]);
  return List<TResult>.unmodifiable(results.cast<TResult>());
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameStrings(Set<String> left, Set<String> right) =>
    left.length == right.length && left.containsAll(right);
