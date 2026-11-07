import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../application/backup/control_plane_backup_models.dart';
import '../../application/ports/control_plane_backup_ports.dart';
import 'workspace_database_open_retry.dart';

part 'workspace_database.g.dart';

const int workspaceDatabaseSchemaVersion = 3;
const int minimumSupportedWorkspaceDatabaseSchemaVersion = 2;
const int currentSourcePayloadSchemaVersion = 1;

class WorkspaceMetadata extends Table {
  IntColumn get singleton => integer()();
  IntColumn get repositoryRevision => integer()();
  IntColumn get destructionEpoch => integer()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {singleton};

  @override
  List<String> get customConstraints => const [
    'CHECK (singleton = 1)',
    'CHECK (repository_revision >= 0)',
    'CHECK (destruction_epoch >= 0)',
    'CHECK (created_at_micros >= 0)',
    'CHECK (updated_at_micros >= created_at_micros)',
  ];
}

class ManagedSkills extends Table {
  TextColumn get id => text()();
  TextColumn get slotKey => text().unique()();
  TextColumn get declaredName => text()();
  TextColumn get displayName => text()();
  TextColumn get description => text()();
  TextColumn get activeSourceLineageId => text()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (length(id) = 36 AND lower(id) = id AND substr(id, 15, 1) = '4' "
        "AND substr(id, 20, 1) IN ('8', '9', 'a', 'b') "
        "AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' "
        "AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' "
        "AND id NOT GLOB '*[^0-9a-f-]*')",
    'CHECK (length(trim(slot_key)) > 0)',
    'CHECK (length(trim(declared_name)) > 0)',
    'CHECK (length(trim(display_name)) > 0)',
    'CHECK (length(trim(description)) > 0)',
    'CHECK (created_at_micros >= 0)',
    'CHECK (updated_at_micros >= created_at_micros)',
    'FOREIGN KEY (id, active_source_lineage_id) '
        'REFERENCES source_lineages(managed_skill_id, id) '
        'DEFERRABLE INITIALLY DEFERRED',
  ];
}

class SourceLineages extends Table {
  TextColumn get id => text()();
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get objectFormat => text()();
  IntColumn get createdAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {managedSkillId, id},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (length(id) = 36 AND lower(id) = id AND substr(id, 15, 1) = '4' "
        "AND substr(id, 20, 1) IN ('8', '9', 'a', 'b') "
        "AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' "
        "AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' "
        "AND id NOT GLOB '*[^0-9a-f-]*')",
    "CHECK (length(managed_skill_id) = 36 AND "
        "lower(managed_skill_id) = managed_skill_id AND "
        "substr(managed_skill_id, 15, 1) = '4' AND "
        "substr(managed_skill_id, 20, 1) IN ('8', '9', 'a', 'b') AND "
        "substr(managed_skill_id, 9, 1) = '-' AND "
        "substr(managed_skill_id, 14, 1) = '-' AND "
        "substr(managed_skill_id, 19, 1) = '-' AND "
        "substr(managed_skill_id, 24, 1) = '-' AND "
        "managed_skill_id NOT GLOB '*[^0-9a-f-]*')",
    "CHECK (object_format IN ('sha1', 'sha256'))",
    'CHECK (created_at_micros >= 0)',
  ];
}

class SkillSources extends Table {
  TextColumn get sourceLineageId =>
      text().references(SourceLineages, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  IntColumn get payloadSchemaVersion => integer()();
  TextColumn get payloadJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {sourceLineageId};

  @override
  List<String> get customConstraints => const [
    "CHECK (kind IN ('local', 'git', 'wellKnown', 'adoptedSnapshot'))",
    'CHECK (payload_schema_version = 1)',
    'CHECK (json_valid(payload_json))',
  ];
}

class RevisionMetadata extends Table {
  TextColumn get sourceLineageId =>
      text().references(SourceLineages, #id, onDelete: KeyAction.cascade)();
  TextColumn get objectId => text()();
  TextColumn get contentHash => text()();
  IntColumn get fileCount => integer()();
  IntColumn get byteSize => integer()();
  TextColumn get declaredName => text()();
  TextColumn get validationState => text()();
  TextColumn get validationCode => text().nullable()();
  IntColumn get createdAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {sourceLineageId, objectId};

  @override
  List<String> get customConstraints => [
    'CHECK (length(trim(object_id)) > 0)',
    "CHECK (length(content_hash) = 64 AND lower(content_hash) = content_hash "
        "AND content_hash NOT GLOB '*[^0-9a-f]*')",
    'CHECK (file_count >= 0)',
    'CHECK (byte_size >= 0)',
    'CHECK (length(trim(declared_name)) > 0)',
    "CHECK (validation_state IN ('valid', 'invalid'))",
    "CHECK ((validation_state = 'valid' AND validation_code IS NULL) OR "
        "(validation_state = 'invalid' AND length(trim(validation_code)) > 0))",
    'CHECK (created_at_micros >= 0)',
  ];
}

class CurrentRevisionSelection extends Table {
  @override
  String get tableName => 'current_revision_selection';

  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceLineageId => text()();
  TextColumn get upstreamObjectId => text()();
  TextColumn get effectiveObjectId => text()();

  @override
  Set<Column<Object>> get primaryKey => {managedSkillId};

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY (managed_skill_id, source_lineage_id) '
        'REFERENCES source_lineages(managed_skill_id, id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
    'FOREIGN KEY (source_lineage_id, upstream_object_id) '
        'REFERENCES revision_metadata(source_lineage_id, object_id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
    'FOREIGN KEY (source_lineage_id, effective_object_id) '
        'REFERENCES revision_metadata(source_lineage_id, object_id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
  ];
}

class DraftWorkspaces extends Table {
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceLineageId => text()();
  TextColumn get baseObjectId => text()();
  TextColumn get purpose => text()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {managedSkillId};

  @override
  List<String> get customConstraints => const [
    "CHECK (purpose IN ('customization', 'updateCandidateResolution'))",
    'CHECK (created_at_micros >= 0)',
    'CHECK (updated_at_micros >= created_at_micros)',
    'FOREIGN KEY (managed_skill_id, source_lineage_id) '
        'REFERENCES source_lineages(managed_skill_id, id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
    'FOREIGN KEY (source_lineage_id, base_object_id) '
        'REFERENCES revision_metadata(source_lineage_id, object_id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
  ];
}

class UpdateCandidateSessions extends Table {
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceLineageId => text()();
  TextColumn get previousUpstreamObjectId => text()();
  TextColumn get previousEffectiveObjectId => text()();
  TextColumn get incomingUpstreamObjectId => text()();
  TextColumn get candidateObjectId => text()();
  TextColumn get status => text()();
  TextColumn get validationCode => text().nullable()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {managedSkillId};

  @override
  List<String> get customConstraints => const [
    "CHECK (status IN ('conflicted', 'validationFailed'))",
    "CHECK ((status = 'conflicted' AND validation_code IS NULL) OR "
        "(status = 'validationFailed' AND length(trim(validation_code)) > 0))",
    'CHECK (length(trim(candidate_object_id)) > 0)',
    'CHECK (created_at_micros >= 0)',
    'CHECK (updated_at_micros >= created_at_micros)',
    'FOREIGN KEY (managed_skill_id, source_lineage_id) '
        'REFERENCES source_lineages(managed_skill_id, id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
    'FOREIGN KEY (source_lineage_id, previous_upstream_object_id) '
        'REFERENCES revision_metadata(source_lineage_id, object_id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
    'FOREIGN KEY (source_lineage_id, previous_effective_object_id) '
        'REFERENCES revision_metadata(source_lineage_id, object_id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
    'FOREIGN KEY (source_lineage_id, incoming_upstream_object_id) '
        'REFERENCES revision_metadata(source_lineage_id, object_id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
  ];
}

class UpdateCandidateItems extends Table {
  TextColumn get managedSkillId => text()();
  TextColumn get path => text()();
  TextColumn get kind => text()();
  TextColumn get state => text()();
  TextColumn get baseObjectId => text().nullable()();
  TextColumn get oursObjectId => text().nullable()();
  TextColumn get theirsObjectId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {managedSkillId, path};

  @override
  List<String> get customConstraints => const [
    'FOREIGN KEY (managed_skill_id) REFERENCES update_candidate_sessions(managed_skill_id) '
        'ON DELETE CASCADE',
    'CHECK (length(trim(path)) > 0)',
    "CHECK (kind IN ('text', 'rename', 'deleteModify', 'binary', 'executableMode'))",
    "CHECK (state IN ('unresolved', 'resolved'))",
  ];
}

class ProjectRoots extends Table {
  TextColumn get id => text()();
  TextColumn get canonicalPath => text().unique()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(id)) > 0)',
    'CHECK (length(trim(canonical_path)) > 0)',
    'CHECK (created_at_micros >= 0)',
    'CHECK (updated_at_micros >= created_at_micros)',
  ];
}

class ActivationLocations extends Table {
  TextColumn get id => text()();
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get canonicalPath => text()();
  TextColumn get scope => text()();
  TextColumn get mode => text()();
  // Historical provenance, not a live reference. Unregistering a Project Root
  // must preserve existing project Activations and their absolute path
  // snapshots so they remain removable and auditable.
  TextColumn get projectRootId => text().nullable()();
  TextColumn get projectRootPath => text().nullable()();
  IntColumn get createdAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {managedSkillId, canonicalPath},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (length(id) = 36 AND lower(id) = id AND substr(id, 15, 1) = '4' "
        "AND substr(id, 20, 1) IN ('8', '9', 'a', 'b') "
        "AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' "
        "AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' "
        "AND id NOT GLOB '*[^0-9a-f-]*')",
    "CHECK (scope IN ('global', 'project'))",
    "CHECK (mode IN ('copy', 'symbolicLink'))",
    "CHECK ((scope = 'global' AND project_root_id IS NULL AND "
        "project_root_path IS NULL) OR (scope = 'project' AND "
        "length(trim(project_root_id)) > 0 AND "
        "length(trim(project_root_path)) > 0))",
    'CHECK (created_at_micros >= 0)',
  ];
}

class ActivationAgents extends Table {
  TextColumn get activationLocationId => text().references(
    ActivationLocations,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get agentId => text()();

  @override
  Set<Column<Object>> get primaryKey => {activationLocationId, agentId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(agent_id)) > 0)',
  ];
}

class SkillUserData extends Table {
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  IntColumn get favoriteChangedAtMicros => integer().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get noteUpdatedAtMicros => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {managedSkillId};

  @override
  List<String> get customConstraints => const [
    'CHECK ((favorite = 0 AND favorite_changed_at_micros IS NULL) OR '
        '(favorite = 1 AND favorite_changed_at_micros >= 0))',
    'CHECK ((note IS NULL AND note_updated_at_micros IS NULL) OR '
        '(length(trim(note)) > 0 AND note_updated_at_micros >= 0))',
  ];
}

class SkillUpdateCheckRecords extends Table {
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get basisFingerprint => text()();
  TextColumn get status => text()();
  TextColumn get currentContentHash => text().nullable()();
  TextColumn get availableContentHash => text().nullable()();
  TextColumn get resolvedSourceRevision => text().nullable()();
  IntColumn get checkedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {managedSkillId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(basis_fingerprint)) > 0)',
    "CHECK (status IN ('current', 'updateAvailable', 'sourceUnavailable', "
        "'updateUnsupported', 'resolutionRequired'))",
    'CHECK (checked_at_micros >= 0)',
  ];
}

class SkillUpdateCheckMetadata extends Table {
  IntColumn get singleton => integer()();
  IntColumn get lastFullSweepAtMicros => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {singleton};

  @override
  List<String> get customConstraints => const ['CHECK (singleton = 1)'];
}

class PersonalTags extends Table {
  TextColumn get id => text()();
  TextColumn get normalizedKey => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get color => text().nullable()();
  IntColumn get createdAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (length(id) = 36 AND lower(id) = id AND substr(id, 15, 1) = '4' "
        "AND substr(id, 20, 1) IN ('8', '9', 'a', 'b') "
        "AND substr(id, 9, 1) = '-' AND substr(id, 14, 1) = '-' "
        "AND substr(id, 19, 1) = '-' AND substr(id, 24, 1) = '-' "
        "AND id NOT GLOB '*[^0-9a-f-]*')",
    'CHECK (length(trim(normalized_key)) > 0)',
    'CHECK (length(trim(display_name)) > 0)',
    "CHECK (color IS NULL OR (length(color) = 7 AND substr(color, 1, 1) = '#'))",
    'CHECK (created_at_micros >= 0)',
    'CHECK (updated_at_micros >= created_at_micros)',
  ];
}

class SkillTagAssignments extends Table {
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get personalTagId =>
      text().references(PersonalTags, #id, onDelete: KeyAction.cascade)();
  IntColumn get createdAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {managedSkillId, personalTagId};

  @override
  List<String> get customConstraints => const [
    'CHECK (created_at_micros >= 0)',
  ];
}

class OperationJournals extends Table {
  TextColumn get operationId => text()();
  TextColumn get kind => text()();
  TextColumn get phase => text()();
  IntColumn get planSchemaVersion => integer()();
  TextColumn get planJson => text()();
  IntColumn get operationGeneration => integer()();
  IntColumn get committedRepositoryRevision => integer().nullable()();
  IntColumn get startedAtMicros => integer()();
  IntColumn get updatedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};

  @override
  List<String> get customConstraints => [
    "CHECK (length(operation_id) = 36 AND lower(operation_id) = operation_id "
        "AND substr(operation_id, 15, 1) = '4' AND "
        "substr(operation_id, 20, 1) IN ('8', '9', 'a', 'b') AND "
        "substr(operation_id, 9, 1) = '-' AND "
        "substr(operation_id, 14, 1) = '-' AND "
        "substr(operation_id, 19, 1) = '-' AND "
        "substr(operation_id, 24, 1) = '-' AND "
        "operation_id NOT GLOB '*[^0-9a-f-]*')",
    'CHECK (length(trim(kind)) > 0)',
    "CHECK (phase IN ('prepared', 'applying', 'committed', 'finalizing', 'completed'))",
    'CHECK (plan_schema_version >= 1)',
    'CHECK (json_valid(plan_json))',
    'CHECK (operation_generation >= 1)',
    "CHECK ((phase IN ('prepared', 'applying') AND "
        "committed_repository_revision IS NULL) OR (phase IN "
        "('committed', 'finalizing', 'completed') AND "
        "committed_repository_revision >= 0))",
    'CHECK (started_at_micros >= 0)',
    'CHECK (updated_at_micros >= started_at_micros)',
  ];
}

class OperationJournalSteps extends Table {
  TextColumn get operationId => text().references(
    OperationJournals,
    #operationId,
    onDelete: KeyAction.cascade,
  )();
  IntColumn get sequence => integer()();
  TextColumn get stepId => text()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  TextColumn get recoveryReference => text()();

  @override
  Set<Column<Object>> get primaryKey => {operationId, sequence};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {operationId, stepId},
  ];

  @override
  List<String> get customConstraints => const [
    'CHECK (sequence >= 0)',
    'CHECK (length(trim(step_id)) > 0)',
    'CHECK (length(trim(kind)) > 0)',
    "CHECK (status IN ('planned', 'started', 'completed'))",
    'CHECK (length(trim(recovery_reference)) > 0)',
  ];
}

class OperationRecords extends Table {
  TextColumn get operationId => text()();
  TextColumn get kind => text()();
  TextColumn get status => text()();
  BoolColumn get retainWithoutSubjects =>
      boolean().withDefault(const Constant(false))();
  IntColumn get startedAtMicros => integer()();
  IntColumn get completedAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};

  @override
  List<String> get customConstraints => [
    "CHECK (length(operation_id) = 36 AND lower(operation_id) = operation_id "
        "AND substr(operation_id, 15, 1) = '4' AND "
        "substr(operation_id, 20, 1) IN ('8', '9', 'a', 'b') AND "
        "substr(operation_id, 9, 1) = '-' AND "
        "substr(operation_id, 14, 1) = '-' AND "
        "substr(operation_id, 19, 1) = '-' AND "
        "substr(operation_id, 24, 1) = '-' AND "
        "operation_id NOT GLOB '*[^0-9a-f-]*')",
    'CHECK (length(trim(kind)) > 0)',
    "CHECK (status IN ('succeeded', 'failed', 'cancelled'))",
    'CHECK (started_at_micros >= 0)',
    'CHECK (completed_at_micros >= started_at_micros)',
  ];
}

class OperationSubjects extends Table {
  TextColumn get subjectId => text()();
  TextColumn get operationId => text().references(
    OperationRecords,
    #operationId,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get managedSkillId =>
      text().references(ManagedSkills, #id, onDelete: KeyAction.cascade)();
  TextColumn get sourceLineageId => text().nullable().references(
    SourceLineages,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get beforeObjectId => text().nullable()();
  TextColumn get afterObjectId => text().nullable()();
  TextColumn get beforeContentHash => text().nullable()();
  TextColumn get afterContentHash => text().nullable()();
  TextColumn get displayName => text()();

  @override
  Set<Column<Object>> get primaryKey => {subjectId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {operationId, managedSkillId},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (length(subject_id) = 36 AND lower(subject_id) = subject_id "
        "AND substr(subject_id, 15, 1) = '4' AND "
        "substr(subject_id, 20, 1) IN ('8', '9', 'a', 'b') AND "
        "substr(subject_id, 9, 1) = '-' AND "
        "substr(subject_id, 14, 1) = '-' AND "
        "substr(subject_id, 19, 1) = '-' AND "
        "substr(subject_id, 24, 1) = '-' AND "
        "subject_id NOT GLOB '*[^0-9a-f-]*')",
    'CHECK (length(trim(display_name)) > 0)',
    "CHECK (source_lineage_id IS NOT NULL OR (before_object_id IS NULL "
        "AND after_object_id IS NULL))",
    'FOREIGN KEY (managed_skill_id, source_lineage_id) '
        'REFERENCES source_lineages(managed_skill_id, id) '
        'ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED',
    "CHECK (before_content_hash IS NULL OR (length(before_content_hash) = 64 "
        "AND lower(before_content_hash) = before_content_hash AND "
        "before_content_hash NOT GLOB '*[^0-9a-f]*'))",
    "CHECK (after_content_hash IS NULL OR (length(after_content_hash) = 64 "
        "AND lower(after_content_hash) = after_content_hash AND "
        "after_content_hash NOT GLOB '*[^0-9a-f]*'))",
  ];
}

@DriftDatabase(
  tables: [
    WorkspaceMetadata,
    ManagedSkills,
    SourceLineages,
    SkillSources,
    RevisionMetadata,
    CurrentRevisionSelection,
    DraftWorkspaces,
    UpdateCandidateSessions,
    UpdateCandidateItems,
    ProjectRoots,
    ActivationLocations,
    ActivationAgents,
    SkillUserData,
    SkillUpdateCheckRecords,
    SkillUpdateCheckMetadata,
    PersonalTags,
    SkillTagAssignments,
    OperationJournals,
    OperationJournalSteps,
    OperationRecords,
    OperationSubjects,
  ],
)
class WorkspaceDatabase extends _$WorkspaceDatabase
    implements ControlPlaneBackupDatabasePort {
  factory WorkspaceDatabase.forFile(
    File file, {
    Duration busyTimeout = const Duration(seconds: 5),
    QueryExecutor Function()? backgroundExecutorFactory,
    WorkspaceDatabaseOpenRetryPolicy? openRetryPolicy,
  }) {
    final retry = openRetryPolicy ?? WorkspaceDatabaseOpenRetryPolicy.current();
    return WorkspaceDatabase._(
      LazyDatabase(
        backgroundExecutorFactory ??
            () => NativeDatabase.createInBackground(
              file,
              readPool: 0,
              setup: (database) => retry.runSync(() {
                database.execute(
                  'PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}',
                );
                database.execute('PRAGMA journal_mode = WAL');
                database.execute('PRAGMA synchronous = FULL');
                database.execute('PRAGMA foreign_keys = ON');
              }),
            ),
      ),
      retry,
    );
  }

  WorkspaceDatabase.forTesting(
    super.executor, {
    MigrationStrategy? migrationOverride,
    int? schemaVersionOverride,
    WorkspaceDatabaseOpenRetryPolicy? openRetryPolicy,
  }) : _migrationOverride = migrationOverride,
       _schemaVersionOverride = schemaVersionOverride,
       _openRetryPolicy =
           openRetryPolicy ?? WorkspaceDatabaseOpenRetryPolicy.current();

  WorkspaceDatabase._(super.connection, this._openRetryPolicy)
    : _migrationOverride = null,
      _schemaVersionOverride = null;

  final MigrationStrategy? _migrationOverride;
  final int? _schemaVersionOverride;
  final WorkspaceDatabaseOpenRetryPolicy _openRetryPolicy;

  @override
  int get schemaVersion =>
      _schemaVersionOverride ?? workspaceDatabaseSchemaVersion;

  @override
  MigrationStrategy get migration {
    final delegate =
        _migrationOverride ??
        MigrationStrategy(
          onCreate: (migrator) async {
            await migrator.createAll();
            await _createTriggers();
            final now = DateTime.now().toUtc().microsecondsSinceEpoch;
            await into(workspaceMetadata).insert(
              WorkspaceMetadataCompanion.insert(
                singleton: const Value(1),
                repositoryRevision: 0,
                destructionEpoch: 0,
                createdAtMicros: now,
                updatedAtMicros: now,
              ),
            );
            await into(skillUpdateCheckMetadata).insert(
              SkillUpdateCheckMetadataCompanion.insert(
                singleton: const Value(1),
              ),
            );
          },
          onUpgrade: (migrator, from, to) async {
            if (from == 2 && to == 3) {
              await migrator.createTable(skillUpdateCheckRecords);
              await migrator.createTable(skillUpdateCheckMetadata);
              await into(skillUpdateCheckMetadata).insert(
                SkillUpdateCheckMetadataCompanion.insert(
                  singleton: const Value(1),
                ),
              );
              return;
            }
            throw StateError(
              'Unsupported workspace schema migration $from->$to',
            );
          },
        );
    return MigrationStrategy(
      onCreate: (migrator) => transaction(() => delegate.onCreate(migrator)),
      onUpgrade: (migrator, from, to) =>
          transaction(() => delegate.onUpgrade(migrator, from, to)),
      beforeOpen: delegate.beforeOpen,
    );
  }

  Future<void> _createTriggers() async {
    await customStatement('''
      CREATE TRIGGER operation_subject_delete_prunes_empty_record
      AFTER DELETE ON operation_subjects
      BEGIN
        DELETE FROM operation_records
        WHERE operation_id = OLD.operation_id
          AND retain_without_subjects = 0
          AND NOT EXISTS (
            SELECT 1 FROM operation_subjects
            WHERE operation_id = OLD.operation_id
          );
      END
    ''');
  }

  Future<T> transactionAtRevision<T>(
    int expectedRevision,
    Future<T> Function() action,
  ) => transaction(() async {
    final metadata = await select(workspaceMetadata).getSingle();
    if (metadata.repositoryRevision != expectedRevision) {
      throw StaleControlPlaneRevision(
        expected: expectedRevision,
        actual: metadata.repositoryRevision,
      );
    }
    final result = await action();
    final now = DateTime.now().toUtc().microsecondsSinceEpoch;
    await (update(
      workspaceMetadata,
    )..where((row) => row.singleton.equals(1))).write(
      WorkspaceMetadataCompanion(
        repositoryRevision: Value(expectedRevision + 1),
        updatedAtMicros: Value(now),
      ),
    );
    return result;
  });

  @override
  Future<ControlPlaneIdentity> liveIdentity() async {
    final metadata = await select(workspaceMetadata).getSingle();
    return ControlPlaneIdentity(
      schemaVersion: schemaVersion,
      repositoryRevision: metadata.repositoryRevision,
      destructionEpoch: metadata.destructionEpoch,
    );
  }

  @override
  Future<void> vacuumInto(String destinationPath) async {
    if (await FileSystemEntity.type(destinationPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw ArgumentError.value(
        destinationPath,
        'destinationPath',
        'must not exist before VACUUM INTO',
      );
    }
    await customStatement('VACUUM INTO ?', <Object?>[destinationPath]);
  }

  @override
  Future<ControlPlaneProbeResult> probeDatabase(
    String databasePath, {
    required ControlPlaneIntegrityLevel integrityLevel,
  }) async {
    try {
      return await _openRetryPolicy.runAsync(
        () => _probeDatabaseOnce(databasePath, integrityLevel),
      );
    } on Object {
      return const ControlPlaneUnusable(
        ControlPlaneProbeFailureReason.cannotOpen,
      );
    }
  }

  Future<ControlPlaneProbeResult> _probeDatabaseOnce(
    String databasePath,
    ControlPlaneIntegrityLevel integrityLevel,
  ) async {
    final file = File(databasePath);
    final databaseType = await FileSystemEntity.type(
      databasePath,
      followLinks: false,
    );
    if (databaseType == FileSystemEntityType.notFound) {
      return const ControlPlaneUnusable(ControlPlaneProbeFailureReason.missing);
    }
    if (databaseType != FileSystemEntityType.file) {
      return const ControlPlaneUnusable(
        ControlPlaneProbeFailureReason.cannotOpen,
      );
    }

    _WorkspaceProbeDatabase? probe;
    try {
      probe = _WorkspaceProbeDatabase(
        NativeDatabase.createBackgroundConnection(
          file,
          readPool: 0,
          enableMigrations: false,
          setup: (database) {
            database.execute('PRAGMA query_only = ON');
            database.execute('PRAGMA foreign_keys = ON');
          },
        ),
      );

      final int userVersion;
      try {
        final row = await probe.customSelect('PRAGMA user_version').getSingle();
        userVersion = row.read<int>('user_version');
      } on Object catch (error) {
        if (_openRetryPolicy.isRetryableError(error)) rethrow;
        return const ControlPlaneUnusable(
          ControlPlaneProbeFailureReason.cannotOpen,
        );
      }
      if (userVersion < minimumSupportedWorkspaceDatabaseSchemaVersion ||
          userVersion > workspaceDatabaseSchemaVersion) {
        return const ControlPlaneUnusable(
          ControlPlaneProbeFailureReason.schemaMismatch,
        );
      }

      final checkName = switch (integrityLevel) {
        ControlPlaneIntegrityLevel.quick => 'quick_check',
        ControlPlaneIntegrityLevel.full => 'integrity_check',
      };
      try {
        final rows = await probe.customSelect('PRAGMA $checkName').get();
        if (rows.length != 1 || rows.single.read<String>(checkName) != 'ok') {
          return const ControlPlaneUnusable(
            ControlPlaneProbeFailureReason.integrityCheckFailed,
          );
        }
      } on Object catch (error) {
        if (_openRetryPolicy.isRetryableError(error)) rethrow;
        return const ControlPlaneUnusable(
          ControlPlaneProbeFailureReason.integrityCheckFailed,
        );
      }

      try {
        final violations = await probe
            .customSelect('PRAGMA foreign_key_check')
            .get();
        if (violations.isNotEmpty) {
          return const ControlPlaneUnusable(
            ControlPlaneProbeFailureReason.foreignKeyCheckFailed,
          );
        }
      } on Object catch (error) {
        if (_openRetryPolicy.isRetryableError(error)) rethrow;
        return const ControlPlaneUnusable(
          ControlPlaneProbeFailureReason.foreignKeyCheckFailed,
        );
      }

      try {
        final metadata = await probe
            .select(probe.workspaceMetadata)
            .getSingleOrNull();
        if (metadata == null) {
          return const ControlPlaneUnusable(
            ControlPlaneProbeFailureReason.metadataUnavailable,
          );
        }
        return ControlPlaneHealthy(
          ControlPlaneIdentity(
            schemaVersion: userVersion,
            repositoryRevision: metadata.repositoryRevision,
            destructionEpoch: metadata.destructionEpoch,
          ),
        );
      } on Object catch (error) {
        if (_openRetryPolicy.isRetryableError(error)) rethrow;
        return const ControlPlaneUnusable(
          ControlPlaneProbeFailureReason.metadataUnavailable,
        );
      }
    } on Object catch (error) {
      if (_openRetryPolicy.isRetryableError(error)) rethrow;
      return const ControlPlaneUnusable(
        ControlPlaneProbeFailureReason.cannotOpen,
      );
    } finally {
      await probe?.close();
    }
  }

  Future<List<OperationRecord>> operationHistoryPage({
    OperationHistoryCursor? before,
    int limit = 50,
  }) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final query = select(operationRecords);
    if (before != null) {
      query.where(
        (row) =>
            row.startedAtMicros.isSmallerThanValue(before.startedAtMicros) |
            (row.startedAtMicros.equals(before.startedAtMicros) &
                row.operationId.isSmallerThanValue(before.operationId)),
      );
    }
    query
      ..orderBy([
        (row) => OrderingTerm.desc(row.startedAtMicros),
        (row) => OrderingTerm.desc(row.operationId),
      ])
      ..limit(limit);
    return query.get();
  }
}

final class StaleControlPlaneRevision implements Exception {
  const StaleControlPlaneRevision({
    required this.expected,
    required this.actual,
  });

  final int expected;
  final int actual;

  @override
  String toString() =>
      'StaleControlPlaneRevision(expected: $expected, actual: $actual)';
}

final class OperationHistoryCursor {
  const OperationHistoryCursor({
    required this.startedAtMicros,
    required this.operationId,
  });

  final int startedAtMicros;
  final String operationId;
}

/// Read-only generated-Drift facade used only for independent integrity
/// probes. Keeping a distinct runtime type avoids Drift treating the probe as
/// a second application database instance, while `enableMigrations: false`
/// prevents a probe from mutating or upgrading the inspected file.
final class _WorkspaceProbeDatabase extends _$WorkspaceDatabase {
  _WorkspaceProbeDatabase(super.connection);

  @override
  int get schemaVersion => workspaceDatabaseSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => throw StateError('A probe must not create a schema.'),
    onUpgrade: (_, from, to) =>
        throw StateError('A probe must not migrate schema $from->$to.'),
  );
}
