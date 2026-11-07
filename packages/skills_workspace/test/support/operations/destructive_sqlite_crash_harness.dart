import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/backup/control_plane_backup_codec.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_service.dart';
import 'package:skills_workspace/src/application/operations/destructive_recovery_intent.dart';
import 'package:skills_workspace/src/application/operations/operation_coordinator.dart';
import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/operations/operation_plan_assembler.dart';
import 'package:skills_workspace/src/application/operations/workspace_business_changes.dart';
import 'package:skills_workspace/src/application/ports/control_plane_backup_ports.dart';
import 'package:skills_workspace/src/application/ports/operation_ports.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/application/runtime/workspace_journal_recovery_adapter.dart';
import 'package:skills_workspace/src/composition/destructive_recovery_maintenance.dart';
import 'package:skills_workspace/src/composition/operation_recovery_backup_maintenance.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/infrastructure/database/drift_operation_control_plane.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/platform/filesystem/control_plane_backup_durability.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/workspace_file_lock.dart';
import 'package:skills_workspace/src/platform/operations/filesystem_operation_recovery.dart';
import 'package:skills_workspace/src/platform/operations/operation_recovery_bundle.dart';

const destructiveCrashSkillId = '123e4567-e89b-42d3-a456-426614174500';
const destructiveCrashLineageId = '123e4567-e89b-42d3-a456-426614174501';
const destructiveCrashOperationId = '123e4567-e89b-42d3-a456-426614174502';
const destructiveCrashTagId = '123e4567-e89b-42d3-a456-426614174506';
const sourceReplacementCrashLineageId = '123e4567-e89b-42d3-a456-426614174507';
const sourceReplacementCrashActivationId =
    '123e4567-e89b-42d3-a456-426614174508';

const _subjectId = '123e4567-e89b-42d3-a456-426614174503';
const _oldOperationId = '123e4567-e89b-42d3-a456-426614174504';
const _oldSubjectId = '123e4567-e89b-42d3-a456-426614174505';
const _objectId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _contentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _replacementObjectId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _replacementContentHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

enum DestructiveSqliteCrashPoint {
  beforeBarrierPublication,
  afterBarrierBeforeBusinessCommit,
  afterBusinessCommitBeforeBackup,
  afterNewBackupBeforeSteadyFence,
  beforeJournalCompletion,
}

final class DestructiveSqliteCrashState {
  const DestructiveSqliteCrashState({
    required this.repositoryRevision,
    required this.destructionEpoch,
    required this.journalPhase,
    required this.eligibility,
    required this.managedSkillCount,
    required this.sourceLineageCount,
    required this.personalTagCount,
    required this.skillTagAssignmentCount,
    required this.operationSubjectCount,
    required this.epochZeroBackupExists,
    required this.epochOneBackupExists,
  });

  final int repositoryRevision;
  final int destructionEpoch;
  final OperationJournalPhase journalPhase;
  final BackupEligibility eligibility;
  final int managedSkillCount;
  final int sourceLineageCount;
  final int personalTagCount;
  final int skillTagAssignmentCount;
  final int operationSubjectCount;
  final bool epochZeroBackupExists;
  final bool epochOneBackupExists;
}

final class SourceReplacementSqliteCrashState {
  const SourceReplacementSqliteCrashState({
    required this.repositoryRevision,
    required this.destructionEpoch,
    required this.journalPhase,
    required this.eligibility,
    required this.activeSourceLineageId,
    required this.sourceLineageIds,
    required this.sourcePayloads,
    required this.selectedSourceLineageId,
    required this.upstreamObjectId,
    required this.effectiveObjectId,
    required this.favorite,
    required this.note,
    required this.personalTagCount,
    required this.skillTagAssignmentCount,
    required this.activationCount,
    required this.activationAgentCount,
    required this.operationSubjectLineageIds,
    required this.epochZeroBackupExists,
    required this.epochOneBackupExists,
  });

  final int repositoryRevision;
  final int destructionEpoch;
  final OperationJournalPhase journalPhase;
  final BackupEligibility eligibility;
  final String activeSourceLineageId;
  final List<String> sourceLineageIds;
  final List<String> sourcePayloads;
  final String selectedSourceLineageId;
  final String upstreamObjectId;
  final String effectiveObjectId;
  final bool favorite;
  final String? note;
  final int personalTagCount;
  final int skillTagAssignmentCount;
  final int activationCount;
  final int activationAgentCount;
  final List<String?> operationSubjectLineageIds;
  final bool epochZeroBackupExists;
  final bool epochOneBackupExists;
}

Future<void> runDestructiveSqliteCrashChild({
  required String workspaceRoot,
  required DestructiveSqliteCrashPoint crashPoint,
}) async {
  final layout = WorkspaceLayout(workspaceRoot);
  final filesystem = PlatformDurableWorkspaceFilesystem();
  final platformDurability = PlatformControlPlaneBackupDurability(filesystem);
  final crashDurability = _CrashBackupDurability(
    delegate: platformDurability,
    layout: layout,
    crashPoint: crashPoint,
  );
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  await database.workspaceMetadata.select().getSingle();
  await _seedControlPlane(database);
  await _seedFilesystem(layout);

  final backups = _backups(
    database: database,
    durability: crashDurability,
    layout: layout,
  );
  await backups.initializeSteadyEligibility();
  await backups.createBackup();

  final operationId = OperationId(destructiveCrashOperationId);
  final registry = OperationRecoverySpecRegistry()
    ..stageDestructiveEntries(operationId, <OperationRecoveryEntrySpec>[
      OperationRecoveryEntrySpec(
        entryId: 'revision-store',
        targetPath: layout.revisionStorePath(
          ManagedSkillId(destructiveCrashSkillId),
        ),
        intendedSourcePath: null,
        intendedKind: null,
        makeReadOnly: false,
        requirePlainDirectory: false,
      ),
      OperationRecoveryEntrySpec(
        entryId: 'revision-bundle',
        targetPath: layout.revisionBundlePath(
          ManagedSkillId(destructiveCrashSkillId),
        ),
        intendedSourcePath: null,
        intendedKind: null,
        makeReadOnly: false,
        requirePlainDirectory: false,
      ),
      OperationRecoveryEntrySpec(
        entryId: 'repository-copy',
        targetPath: layout.repositoryCopyPath('reviewer'),
        intendedSourcePath: null,
        intendedKind: null,
        makeReadOnly: false,
        requirePlainDirectory: false,
      ),
    ]);
  final recoveryIntent = _removalIntent();
  final plan =
      OperationPlanAssembler(
        subjectIdentities: const _FixedSubjectIdentity(),
        recoveryPlans: OperationRecoveryPlanFactory(registry: registry),
      ).destructive(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(0),
        kind: WorkspaceOperationKind.remove,
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            DeleteManagedSkill(ManagedSkillId(destructiveCrashSkillId)),
          ],
          incrementsDestructionEpoch: true,
        ),
        recoveryIntent: recoveryIntent,
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: ManagedSkillId(destructiveCrashSkillId),
            previousUpstream: _revisionAddress,
            previousEffective: _revisionAddress,
            intendedUpstream: null,
            intendedEffective: null,
          ),
        ],
        subjects: <OperationSubjectIntent>[
          OperationSubjectIntent(
            managedSkillId: ManagedSkillId(destructiveCrashSkillId),
            displayName: 'Reviewer',
            sourceLineage: SourceLineageReference(destructiveCrashLineageId),
            beforeObjectId: RevisionObjectId(_objectId),
            beforeContentHash: _contentHash,
          ),
        ],
      );

  final backupMaintenance = _CrashBackupMaintenance(
    delegate: WorkspaceOperationRecoveryBackupMaintenance(
      backups: backups,
      database: database,
    ),
    layout: layout,
    crashPoint: crashPoint,
  );
  final destructiveMaintenance = _destructiveMaintenance(layout, filesystem);
  final recovery = FilesystemOperationRecovery(
    layout: layout,
    filesystem: filesystem,
    registry: registry,
    backupMaintenance: backupMaintenance,
    destructiveMaintenance: destructiveMaintenance,
  );
  final durableControlPlane = DriftOperationControlPlane(database: database);
  final controlPlane = _CrashControlPlane(
    delegate: durableControlPlane,
    layout: layout,
    crashPoint: crashPoint,
  );
  final operations = OperationCoordinator(
    writerLock: _writerLock(layout, filesystem),
    controlPlane: controlPlane,
    recovery: recovery,
    referenceMaintenance: const _NoopReferenceMaintenance(),
  );

  final outcome = await operations.execute(
    operationId: operationId,
    expectedRepositoryRevision: RepositoryRevision(0),
    buildPlan: (_, _) => plan,
  );
  throw StateError(
    'Crash boundary ${crashPoint.name} was not reached; outcome=$outcome',
  );
}

Future<void> runSourceReplacementSqliteCrashChild({
  required String workspaceRoot,
  required DestructiveSqliteCrashPoint crashPoint,
}) async {
  final layout = WorkspaceLayout(workspaceRoot);
  final filesystem = PlatformDurableWorkspaceFilesystem();
  final platformDurability = PlatformControlPlaneBackupDurability(filesystem);
  final crashDurability = _CrashBackupDurability(
    delegate: platformDurability,
    layout: layout,
    crashPoint: crashPoint,
  );
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  await database.workspaceMetadata.select().getSingle();
  await _seedSourceReplacementControlPlane(database, layout);
  await _seedSourceReplacementFilesystem(layout);

  final backups = _backups(
    database: database,
    durability: crashDurability,
    layout: layout,
  );
  await backups.initializeSteadyEligibility();
  await backups.createBackup();

  final operationId = OperationId(destructiveCrashOperationId);
  final registry = OperationRecoverySpecRegistry()
    ..stageDestructiveEntries(
      operationId,
      _sourceReplacementEntries(layout, operationId),
    );
  final recoveryIntent = _sourceReplacementIntent();
  final replacementAddress = RevisionAddress(
    sourceLineage: SourceLineageReference(sourceReplacementCrashLineageId),
    objectId: RevisionObjectId(_replacementObjectId),
  );
  final plan =
      OperationPlanAssembler(
        subjectIdentities: const _FixedSubjectIdentity(),
        recoveryPlans: OperationRecoveryPlanFactory(registry: registry),
      ).destructive(
        operationId: operationId,
        expectedRepositoryRevision: RepositoryRevision(0),
        kind: WorkspaceOperationKind.replaceSource,
        businessChanges: WorkspaceBusinessChangeSet(
          mutations: <WorkspaceBusinessMutation>[
            PutSourceLineage(
              sourceLineageId: sourceReplacementCrashLineageId,
              managedSkillId: ManagedSkillId(destructiveCrashSkillId),
              objectFormat: WorkspaceObjectFormat.sha1,
              createdAtMicros: 2,
            ),
            PutSkillSource(
              sourceLineageId: sourceReplacementCrashLineageId,
              kind: WorkspaceSourceKind.local,
              payloadSchemaVersion: currentSourcePayloadSchemaVersion,
              payloadJson: '{"path":"/skills/reviewer-new"}',
            ),
            PutRevisionMetadata(
              sourceLineageId: sourceReplacementCrashLineageId,
              objectId: _replacementObjectId,
              contentHash: _replacementContentHash,
              fileCount: 1,
              byteSize: 3,
              declaredName: 'reviewer',
              validationState: WorkspaceRevisionValidationState.valid,
              validationCode: null,
              createdAtMicros: 2,
            ),
            PutManagedSkill(
              managedSkillId: ManagedSkillId(destructiveCrashSkillId),
              slotKey: 'reviewer',
              declaredName: 'reviewer',
              displayName: 'Reviewer',
              description: 'Reviews replacement code.',
              activeSourceLineageId: sourceReplacementCrashLineageId,
              createdAtMicros: 1,
              updatedAtMicros: 2,
            ),
            DeleteSourceLineage(destructiveCrashLineageId),
          ],
          incrementsDestructionEpoch: true,
        ),
        recoveryIntent: recoveryIntent,
        revisionSelectionChanges: <RevisionSelectionChangePlan>[
          RevisionSelectionChangePlan(
            managedSkillId: ManagedSkillId(destructiveCrashSkillId),
            previousUpstream: _revisionAddress,
            previousEffective: _revisionAddress,
            intendedUpstream: replacementAddress,
            intendedEffective: replacementAddress,
          ),
        ],
        subjects: <OperationSubjectIntent>[
          OperationSubjectIntent(
            managedSkillId: ManagedSkillId(destructiveCrashSkillId),
            displayName: 'Reviewer',
            sourceLineage: SourceLineageReference(
              sourceReplacementCrashLineageId,
            ),
            afterObjectId: RevisionObjectId(_replacementObjectId),
            afterContentHash: _replacementContentHash,
          ),
        ],
      );

  final backupMaintenance = _CrashBackupMaintenance(
    delegate: WorkspaceOperationRecoveryBackupMaintenance(
      backups: backups,
      database: database,
    ),
    layout: layout,
    crashPoint: crashPoint,
  );
  final destructiveMaintenance = _destructiveMaintenance(layout, filesystem);
  final recovery = FilesystemOperationRecovery(
    layout: layout,
    filesystem: filesystem,
    registry: registry,
    backupMaintenance: backupMaintenance,
    destructiveMaintenance: destructiveMaintenance,
  );
  final durableControlPlane = DriftOperationControlPlane(database: database);
  final controlPlane = _CrashControlPlane(
    delegate: durableControlPlane,
    layout: layout,
    crashPoint: crashPoint,
  );
  final operations = OperationCoordinator(
    writerLock: _writerLock(layout, filesystem),
    controlPlane: controlPlane,
    recovery: recovery,
    referenceMaintenance: const _NoopReferenceMaintenance(),
  );

  final outcome = await operations.execute(
    operationId: operationId,
    expectedRepositoryRevision: RepositoryRevision(0),
    buildPlan: (_, _) => plan,
  );
  throw StateError(
    'Crash boundary ${crashPoint.name} was not reached; outcome=$outcome',
  );
}

Future<DestructiveSqliteCrashState> inspectDestructiveSqliteCrashState(
  String workspaceRoot,
) async {
  final layout = WorkspaceLayout(workspaceRoot);
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  try {
    final metadata = await database.workspaceMetadata.select().getSingle();
    final journal = await database.operationJournals.select().getSingle();
    final eligibility = const ControlPlaneBackupCodec().decodeEligibility(
      await File(layout.backupEligibilityPath).readAsBytes(),
    );
    return DestructiveSqliteCrashState(
      repositoryRevision: metadata.repositoryRevision,
      destructionEpoch: metadata.destructionEpoch,
      journalPhase: OperationJournalPhase.values.byName(journal.phase),
      eligibility: eligibility,
      managedSkillCount: await database.managedSkills.count().getSingle(),
      sourceLineageCount: await database.sourceLineages.count().getSingle(),
      personalTagCount: await database.personalTags.count().getSingle(),
      skillTagAssignmentCount: await database.skillTagAssignments
          .count()
          .getSingle(),
      operationSubjectCount: await database.operationSubjects
          .count()
          .getSingle(),
      epochZeroBackupExists: await Directory(
        path.join(layout.controlPlaneBackupsRoot, '0'),
      ).exists(),
      epochOneBackupExists: await Directory(
        path.join(layout.controlPlaneBackupsRoot, '1'),
      ).exists(),
    );
  } finally {
    await database.close();
  }
}

Future<SourceReplacementSqliteCrashState>
inspectSourceReplacementSqliteCrashState(String workspaceRoot) async {
  final layout = WorkspaceLayout(workspaceRoot);
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  try {
    final metadata = await database.workspaceMetadata.select().getSingle();
    final journal = await database.operationJournals.select().getSingle();
    final eligibility = const ControlPlaneBackupCodec().decodeEligibility(
      await File(layout.backupEligibilityPath).readAsBytes(),
    );
    final managedSkill = await database.managedSkills.select().getSingle();
    final lineages =
        await (database.sourceLineages.select()
              ..orderBy([(row) => OrderingTerm.asc(row.id)]))
            .get();
    final sources =
        await (database.skillSources.select()
              ..orderBy([(row) => OrderingTerm.asc(row.sourceLineageId)]))
            .get();
    final selection = await database.currentRevisionSelection
        .select()
        .getSingle();
    final userData = await database.skillUserData.select().getSingle();
    final subjects =
        await (database.operationSubjects.select()
              ..orderBy([(row) => OrderingTerm.asc(row.subjectId)]))
            .get();
    return SourceReplacementSqliteCrashState(
      repositoryRevision: metadata.repositoryRevision,
      destructionEpoch: metadata.destructionEpoch,
      journalPhase: OperationJournalPhase.values.byName(journal.phase),
      eligibility: eligibility,
      activeSourceLineageId: managedSkill.activeSourceLineageId,
      sourceLineageIds: [for (final lineage in lineages) lineage.id],
      sourcePayloads: [for (final source in sources) source.payloadJson],
      selectedSourceLineageId: selection.sourceLineageId,
      upstreamObjectId: selection.upstreamObjectId,
      effectiveObjectId: selection.effectiveObjectId,
      favorite: userData.favorite,
      note: userData.note,
      personalTagCount: await database.personalTags.count().getSingle(),
      skillTagAssignmentCount: await database.skillTagAssignments
          .count()
          .getSingle(),
      activationCount: await database.activationLocations.count().getSingle(),
      activationAgentCount: await database.activationAgents.count().getSingle(),
      operationSubjectLineageIds: [
        for (final subject in subjects) subject.sourceLineageId,
      ],
      epochZeroBackupExists: await Directory(
        path.join(layout.controlPlaneBackupsRoot, '0'),
      ).exists(),
      epochOneBackupExists: await Directory(
        path.join(layout.controlPlaneBackupsRoot, '1'),
      ).exists(),
    );
  } finally {
    await database.close();
  }
}

Future<ControlPlaneStartupResult> recoverDestructiveSqliteCrash(
  String workspaceRoot,
) async {
  final layout = WorkspaceLayout(workspaceRoot);
  final filesystem = PlatformDurableWorkspaceFilesystem();
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  final backups = _backups(
    database: database,
    durability: PlatformControlPlaneBackupDurability(filesystem),
    layout: layout,
  );
  final writerLock = _writerLock(layout, filesystem);
  final lease = await writerLock.acquire();
  try {
    final startup = await backups.recoverPrimaryForStartup();
    if (startup is ControlPlaneStartupBlocked) return startup;
    final controlPlane = DriftOperationControlPlane(database: database);
    final registry = OperationRecoverySpecRegistry();
    final recovery = FilesystemOperationRecovery(
      layout: layout,
      filesystem: filesystem,
      registry: registry,
      backupMaintenance: WorkspaceOperationRecoveryBackupMaintenance(
        backups: backups,
        database: database,
      ),
      destructiveMaintenance: _destructiveMaintenance(layout, filesystem),
    );
    final operations = OperationCoordinator(
      writerLock: writerLock,
      controlPlane: controlPlane,
      recovery: recovery,
      referenceMaintenance: const _NoopReferenceMaintenance(),
    );
    await WorkspaceJournalRecoveryAdapter(
      controlPlane: controlPlane,
      operations: operations,
    ).recoverUnderWriterLock(
      armedBarrier: switch (startup) {
        ControlPlaneArmedBarrierNeedsResolution(:final eligibility) =>
          eligibility,
        _ => null,
      },
      isolatedSkillIds: const {},
    );
    return startup;
  } finally {
    await lease.release();
    await database.close();
  }
}

Future<ControlPlaneStartupResult> corruptPrimaryAndRestoreSameEpoch(
  String workspaceRoot,
) async {
  final layout = WorkspaceLayout(workspaceRoot);
  await File(layout.databasePath).writeAsString('corrupt primary', flush: true);
  final probeRoot = await Directory.systemTemp.createTemp(
    'skills-workspace-crash-probe-',
  );
  final probeDatabase = WorkspaceDatabase.forFile(
    File(path.join(probeRoot.path, 'probe.sqlite')),
  );
  await probeDatabase.workspaceMetadata.select().getSingle();
  try {
    return await _backups(
      database: probeDatabase,
      durability: PlatformControlPlaneBackupDurability(
        PlatformDurableWorkspaceFilesystem(),
      ),
      layout: layout,
    ).recoverPrimaryForStartup();
  } finally {
    await probeDatabase.close();
    await probeRoot.delete(recursive: true);
  }
}

Future<void> waitForDestructiveCrashMarker(
  String workspaceRoot,
  DestructiveSqliteCrashPoint point, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final marker = File(_crashMarkerPath(WorkspaceLayout(workspaceRoot)));
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (await marker.exists() && await marker.readAsString() == point.name) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  throw TimeoutException('Child did not reach ${point.name}.', timeout);
}

ControlPlaneBackupService _backups({
  required ControlPlaneBackupDatabasePort database,
  required ControlPlaneBackupDurabilityPort durability,
  required WorkspaceLayout layout,
}) => ControlPlaneBackupService(
  database: database,
  durability: durability,
  paths: ControlPlaneBackupPaths(
    workspaceRoot: layout.rootPath,
    primaryDatabasePath: layout.databasePath,
    backupRoot: layout.controlPlaneBackupsRoot,
    eligibilityPath: layout.backupEligibilityPath,
  ),
);

WorkspaceFileLock _writerLock(
  WorkspaceLayout layout,
  DurableWorkspaceFilesystem filesystem,
) => WorkspaceFileLock(
  lockPath: layout.operationWriterLockPath,
  waitPolicy: FilesystemLockWaitPolicy.wait(
    timeout: const Duration(seconds: 5),
  ),
  filesystem: filesystem,
);

WorkspaceDestructiveRecoveryMaintenance _destructiveMaintenance(
  WorkspaceLayout layout,
  DurableWorkspaceFilesystem filesystem,
) => WorkspaceDestructiveRecoveryMaintenance(
  accessGate: ManagedSkillRevisionAccessGate(),
);

Future<void> _seedControlPlane(WorkspaceDatabase database) =>
    database.transaction(() async {
      await database
          .into(database.managedSkills)
          .insert(
            ManagedSkillsCompanion.insert(
              id: destructiveCrashSkillId,
              slotKey: 'reviewer',
              declaredName: 'reviewer',
              displayName: 'Reviewer',
              description: 'Reviews code.',
              activeSourceLineageId: destructiveCrashLineageId,
              createdAtMicros: 1,
              updatedAtMicros: 1,
            ),
          );
      await database
          .into(database.sourceLineages)
          .insert(
            SourceLineagesCompanion.insert(
              id: destructiveCrashLineageId,
              managedSkillId: destructiveCrashSkillId,
              objectFormat: WorkspaceObjectFormat.sha1.name,
              createdAtMicros: 1,
            ),
          );
      await database
          .into(database.skillSources)
          .insert(
            SkillSourcesCompanion.insert(
              sourceLineageId: destructiveCrashLineageId,
              kind: WorkspaceSourceKind.local.name,
              payloadSchemaVersion: currentSourcePayloadSchemaVersion,
              payloadJson: '{"path":"/skills/reviewer"}',
            ),
          );
      await database
          .into(database.revisionMetadata)
          .insert(
            RevisionMetadataCompanion.insert(
              sourceLineageId: destructiveCrashLineageId,
              objectId: _objectId,
              contentHash: _contentHash,
              fileCount: 1,
              byteSize: 3,
              declaredName: 'reviewer',
              validationState: WorkspaceRevisionValidationState.valid.name,
              createdAtMicros: 1,
            ),
          );
      await database
          .into(database.currentRevisionSelection)
          .insert(
            CurrentRevisionSelectionCompanion.insert(
              managedSkillId: destructiveCrashSkillId,
              sourceLineageId: destructiveCrashLineageId,
              upstreamObjectId: _objectId,
              effectiveObjectId: _objectId,
            ),
          );
      await database
          .into(database.skillUserData)
          .insert(
            SkillUserDataCompanion.insert(
              managedSkillId: destructiveCrashSkillId,
              favorite: const Value(true),
              favoriteChangedAtMicros: const Value(1),
              note: const Value('Important'),
              noteUpdatedAtMicros: const Value(1),
            ),
          );
      await database
          .into(database.personalTags)
          .insert(
            PersonalTagsCompanion.insert(
              id: destructiveCrashTagId,
              normalizedKey: 'work',
              displayName: 'Work',
              createdAtMicros: 1,
              updatedAtMicros: 1,
            ),
          );
      await database
          .into(database.skillTagAssignments)
          .insert(
            SkillTagAssignmentsCompanion.insert(
              managedSkillId: destructiveCrashSkillId,
              personalTagId: destructiveCrashTagId,
              createdAtMicros: 1,
            ),
          );
      await database
          .into(database.operationRecords)
          .insert(
            OperationRecordsCompanion.insert(
              operationId: _oldOperationId,
              kind: WorkspaceOperationKind.install.name,
              status: 'succeeded',
              startedAtMicros: 1,
              completedAtMicros: 2,
            ),
          );
      await database
          .into(database.operationSubjects)
          .insert(
            OperationSubjectsCompanion.insert(
              subjectId: _oldSubjectId,
              operationId: _oldOperationId,
              managedSkillId: destructiveCrashSkillId,
              sourceLineageId: const Value(destructiveCrashLineageId),
              beforeObjectId: const Value(_objectId),
              afterObjectId: const Value(_objectId),
              beforeContentHash: const Value(_contentHash),
              afterContentHash: const Value(_contentHash),
              displayName: 'Reviewer',
            ),
          );
    });

Future<void> _seedFilesystem(WorkspaceLayout layout) async {
  final repository = Directory(layout.repositoryCopyPath('reviewer'));
  await repository.create(recursive: true);
  await File(
    path.join(repository.path, 'SKILL.md'),
  ).writeAsString('old', flush: true);
  final store = Directory(
    layout.revisionStorePath(ManagedSkillId(destructiveCrashSkillId)),
  );
  await store.create(recursive: true);
  await File(
    path.join(store.path, 'store.marker'),
  ).writeAsString('old-store', flush: true);
  final bundle = Directory(
    layout.revisionBundlePath(ManagedSkillId(destructiveCrashSkillId)),
  );
  await bundle.create(recursive: true);
  await File(
    path.join(bundle.path, 'bundle.marker'),
  ).writeAsString('old-bundle', flush: true);
}

Future<void> _seedSourceReplacementControlPlane(
  WorkspaceDatabase database,
  WorkspaceLayout layout,
) async {
  await _seedControlPlane(database);
  await database.transaction(() async {
    await database
        .into(database.activationLocations)
        .insert(
          ActivationLocationsCompanion.insert(
            id: sourceReplacementCrashActivationId,
            managedSkillId: destructiveCrashSkillId,
            canonicalPath: path.join(layout.rootPath, 'agent-skills'),
            scope: WorkspaceActivationScope.global.name,
            mode: WorkspaceActivationMode.copy.name,
            projectRootId: const Value.absent(),
            projectRootPath: const Value.absent(),
            createdAtMicros: 1,
          ),
        );
    await database
        .into(database.activationAgents)
        .insert(
          ActivationAgentsCompanion.insert(
            activationLocationId: sourceReplacementCrashActivationId,
            agentId: 'claude-code',
          ),
        );
  });
}

Future<void> _seedSourceReplacementFilesystem(WorkspaceLayout layout) async {
  await _seedFilesystem(layout);
  final activation = Directory(
    path.join(layout.rootPath, 'agent-skills', 'reviewer'),
  );
  await activation.create(recursive: true);
  await File(
    path.join(activation.path, 'SKILL.md'),
  ).writeAsString('old', flush: true);

  final operationId = OperationId(destructiveCrashOperationId);
  final candidateStore = Directory(
    layout.operationSourceReplacementStore(operationId),
  );
  await candidateStore.create(recursive: true);
  await File(
    path.join(candidateStore.path, 'store.marker'),
  ).writeAsString('new-store', flush: true);
  final candidateBundle = Directory(
    layout.operationSourceReplacementBundle(operationId),
  );
  await candidateBundle.create(recursive: true);
  await File(
    path.join(candidateBundle.path, 'bundle.marker'),
  ).writeAsString('new-bundle', flush: true);
  final candidateTree = Directory(
    path.join(layout.operationSourceReplacementRoot(operationId), 'tree'),
  );
  await candidateTree.create(recursive: true);
  await File(
    path.join(candidateTree.path, 'SKILL.md'),
  ).writeAsString('new', flush: true);
}

List<OperationRecoveryEntrySpec> _sourceReplacementEntries(
  WorkspaceLayout layout,
  OperationId operationId,
) => <OperationRecoveryEntrySpec>[
  OperationRecoveryEntrySpec(
    entryId: 'replacement-store',
    targetPath: layout.revisionStorePath(
      ManagedSkillId(destructiveCrashSkillId),
    ),
    intendedSourcePath: layout.operationSourceReplacementStore(operationId),
    intendedKind: OperationRecoveryEntryKind.directory,
    makeReadOnly: false,
    requirePlainDirectory: false,
  ),
  OperationRecoveryEntrySpec(
    entryId: 'replacement-bundle',
    targetPath: layout.revisionBundlePath(
      ManagedSkillId(destructiveCrashSkillId),
    ),
    intendedSourcePath: layout.operationSourceReplacementBundle(operationId),
    intendedKind: OperationRecoveryEntryKind.directory,
  ),
  OperationRecoveryEntrySpec(
    entryId: 'replacement-repository-copy',
    targetPath: layout.repositoryCopyPath('reviewer'),
    intendedSourcePath: path.join(
      layout.operationSourceReplacementRoot(operationId),
      'tree',
    ),
    intendedKind: OperationRecoveryEntryKind.directory,
  ),
  OperationRecoveryEntrySpec(
    entryId: 'replacement-activation-copy',
    targetPath: path.join(layout.rootPath, 'agent-skills', 'reviewer'),
    intendedSourcePath: path.join(
      layout.operationSourceReplacementRoot(operationId),
      'tree',
    ),
    intendedKind: OperationRecoveryEntryKind.directory,
  ),
];

RemovalRecoveryIntent _removalIntent() => RemovalRecoveryIntent(
  skills: <DestructiveSkillRecoveryIntent>[
    DestructiveSkillRecoveryIntent(
      managedSkillId: ManagedSkillId(destructiveCrashSkillId),
      slotKey: 'reviewer',
      sourceLineages: <RecoverySourceLineageIntent>[
        RecoverySourceLineageIntent(
          sourceLineage: SourceLineageReference(destructiveCrashLineageId),
        ),
      ],
      activationIds: <String>[],
      hasDraft: false,
      hasUpdateCandidateSession: false,
    ),
  ],
);

SourceReplacementRecoveryIntent _sourceReplacementIntent() =>
    SourceReplacementRecoveryIntent(
      skill: DestructiveSkillRecoveryIntent(
        managedSkillId: ManagedSkillId(destructiveCrashSkillId),
        slotKey: 'reviewer',
        sourceLineages: <RecoverySourceLineageIntent>[
          RecoverySourceLineageIntent(
            sourceLineage: SourceLineageReference(destructiveCrashLineageId),
          ),
        ],
        activationIds: <String>[sourceReplacementCrashActivationId],
        hasDraft: false,
        hasUpdateCandidateSession: false,
      ),
      intendedSourceLineage: SourceLineageReference(
        sourceReplacementCrashLineageId,
      ),
      intendedSlotKey: 'reviewer',
      intendedObjectId: RevisionObjectId(_replacementObjectId),
      intendedContentHash: _replacementContentHash,
      intendedObjectFormat: WorkspaceObjectFormat.sha1,
    );

final _revisionAddress = RevisionAddress(
  sourceLineage: SourceLineageReference(destructiveCrashLineageId),
  objectId: RevisionObjectId(_objectId),
);

String _crashMarkerPath(WorkspaceLayout layout) =>
    path.join(layout.rootPath, '.destructive-crash-ready');

Never _blockAt(WorkspaceLayout layout, DestructiveSqliteCrashPoint point) {
  File(_crashMarkerPath(layout)).writeAsStringSync(point.name, flush: true);
  while (true) {
    sleep(const Duration(seconds: 30));
  }
}

final class _FixedSubjectIdentity implements OperationSubjectIdentityPort {
  const _FixedSubjectIdentity();

  @override
  String allocateOperationSubjectId() => _subjectId;
}

final class _NoopReferenceMaintenance
    implements OperationRevisionReferenceMaintenancePort {
  const _NoopReferenceMaintenance();

  @override
  Future<void> reconcileRevisionReferences({
    Set<ManagedSkillId>? isolatedSkillIds,
    Set<ManagedSkillId>? selectedSkillIds,
  }) async {}
}

final class _CrashBackupMaintenance
    implements OperationRecoveryBackupMaintenancePort {
  const _CrashBackupMaintenance({
    required OperationRecoveryBackupMaintenancePort delegate,
    required WorkspaceLayout layout,
    required DestructiveSqliteCrashPoint crashPoint,
  }) : _delegate = delegate,
       _layout = layout,
       _crashPoint = crashPoint;

  final OperationRecoveryBackupMaintenancePort _delegate;
  final WorkspaceLayout _layout;
  final DestructiveSqliteCrashPoint _crashPoint;

  @override
  Future<void> armDestructiveBarrier(OperationRecoveryContext context) async {
    await _delegate.armDestructiveBarrier(context);
    if (_crashPoint ==
        DestructiveSqliteCrashPoint.afterBarrierBeforeBusinessCommit) {
      _blockAt(_layout, _crashPoint);
    }
  }

  @override
  Future<void> completeCommittedDestruction(OperationRecoveryContext context) =>
      _delegate.completeCommittedDestruction(context);

  @override
  Future<void> restoreSteadyAfterProvenRollback(
    OperationRecoveryContext context,
  ) => _delegate.restoreSteadyAfterProvenRollback(context);

  @override
  Future<void> rotate(OperationRecoveryContext context) =>
      _delegate.rotate(context);
}

final class _CrashBackupDurability implements ControlPlaneBackupDurabilityPort {
  const _CrashBackupDurability({
    required ControlPlaneBackupDurabilityPort delegate,
    required WorkspaceLayout layout,
    required DestructiveSqliteCrashPoint crashPoint,
  }) : _delegate = delegate,
       _layout = layout,
       _crashPoint = crashPoint;

  final ControlPlaneBackupDurabilityPort _delegate;
  final WorkspaceLayout _layout;
  final DestructiveSqliteCrashPoint _crashPoint;

  @override
  Future<void> publish({
    required String candidatePath,
    required String destinationPath,
    required ControlPlaneStagingKind kind,
    required ControlPlanePathVerifier verify,
  }) async {
    if (path.equals(destinationPath, _layout.backupEligibilityPath)) {
      final eligibility = const ControlPlaneBackupCodec().decodeEligibility(
        await _delegate.readFile(candidatePath),
      );
      final matches = switch (_crashPoint) {
        DestructiveSqliteCrashPoint.beforeBarrierPublication =>
          eligibility is ArmedBackupEligibility,
        DestructiveSqliteCrashPoint.afterNewBackupBeforeSteadyFence =>
          eligibility is SteadyBackupEligibility &&
              eligibility.destructionEpoch == 1,
        _ => false,
      };
      if (matches) _blockAt(_layout, _crashPoint);
    }
    await _delegate.publish(
      candidatePath: candidatePath,
      destinationPath: destinationPath,
      kind: kind,
      verify: verify,
    );
  }

  @override
  Future<void> copyDurableFile({
    required String sourcePath,
    required String destinationPath,
  }) => _delegate.copyDurableFile(
    sourcePath: sourcePath,
    destinationPath: destinationPath,
  );

  @override
  Future<String> createSiblingStagingPath(
    String destinationPath, {
    required ControlPlaneStagingKind kind,
  }) => _delegate.createSiblingStagingPath(destinationPath, kind: kind);

  @override
  Future<bool> exists(String targetPath) => _delegate.exists(targetPath);

  @override
  Future<int> fileSize(String filePath) => _delegate.fileSize(filePath);

  @override
  Future<List<String>> listChildDirectories(String parentPath) =>
      _delegate.listChildDirectories(parentPath);

  @override
  Future<List<int>> readFile(String filePath) => _delegate.readFile(filePath);

  @override
  Future<void> removeOwnedPath({
    required String targetPath,
    required String ownerRoot,
  }) => _delegate.removeOwnedPath(targetPath: targetPath, ownerRoot: ownerRoot);

  @override
  Future<String> sha256File(String filePath) => _delegate.sha256File(filePath);

  @override
  Future<void> writeDurableFile(String filePath, List<int> bytes) =>
      _delegate.writeDurableFile(filePath, bytes);
}

final class _CrashControlPlane implements OperationControlPlanePort {
  const _CrashControlPlane({
    required OperationControlPlanePort delegate,
    required WorkspaceLayout layout,
    required DestructiveSqliteCrashPoint crashPoint,
  }) : _delegate = delegate,
       _layout = layout,
       _crashPoint = crashPoint;

  final OperationControlPlanePort _delegate;
  final WorkspaceLayout _layout;
  final DestructiveSqliteCrashPoint _crashPoint;

  @override
  Future<void> commitBusinessState(OperationPlan plan) async {
    await _delegate.commitBusinessState(plan);
    if (_crashPoint ==
        DestructiveSqliteCrashPoint.afterBusinessCommitBeforeBackup) {
      _blockAt(_layout, _crashPoint);
    }
  }

  @override
  Future<void> complete(OperationPlan plan) async {
    if (_crashPoint == DestructiveSqliteCrashPoint.beforeJournalCompletion) {
      _blockAt(_layout, _crashPoint);
    }
    await _delegate.complete(plan);
  }

  @override
  Future<void> applyFinalizationEffect(
    OperationId operationId,
    OperationFinalizationEffect effect,
  ) => _delegate.applyFinalizationEffect(operationId, effect);

  @override
  Future<void> completePreparedEnvelopeRollback(
    PreparedOperationEnvelope envelope,
    OperationAbortReason reason,
  ) => _delegate.completePreparedEnvelopeRollback(envelope, reason);

  @override
  Future<void> completeRollback(
    OperationPlan plan,
    OperationAbortReason reason,
  ) => _delegate.completeRollback(plan, reason);

  @override
  Future<void> deleteCompletedJournal(OperationId operationId) =>
      _delegate.deleteCompletedJournal(operationId);

  @override
  Future<List<JournaledOperation>> loadRecoverableOperations() =>
      _delegate.loadRecoverableOperations();

  @override
  Future<void> markApplying(OperationId operationId) =>
      _delegate.markApplying(operationId);

  @override
  Future<void> markFinalizing(OperationId operationId) =>
      _delegate.markFinalizing(operationId);

  @override
  Future<void> markStepCompleted(OperationId operationId, String stepId) =>
      _delegate.markStepCompleted(operationId, stepId);

  @override
  Future<void> markStepStarted(OperationId operationId, String stepId) =>
      _delegate.markStepStarted(operationId, stepId);

  @override
  Future<void> persistPrepared(OperationPlan plan) =>
      _delegate.persistPrepared(plan);

  @override
  Future<void> persistPreparedEnvelope(PreparedOperationEnvelope envelope) =>
      _delegate.persistPreparedEnvelope(envelope);

  @override
  Future<RepositoryRevision> readRepositoryRevision() =>
      _delegate.readRepositoryRevision();

  @override
  Future<void> sealPreparedPlan(
    PreparedOperationEnvelope envelope,
    OperationPlan plan,
  ) => _delegate.sealPreparedPlan(envelope, plan);
}
