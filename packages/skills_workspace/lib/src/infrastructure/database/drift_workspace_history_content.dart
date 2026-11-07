import 'dart:convert';

import 'package:drift/drift.dart';

import '../../application/history/history_models.dart';
import '../../application/history/history_ports.dart';
import '../../application/operations/operation_models.dart';
import '../../application/ports/revision_store_access_ports.dart';
import '../../application/ports/update_ports.dart';
import '../../application/revision_store/managed_skill_revision_access_gate.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../application/update/update_models.dart';
import '../../domain/cancellation.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart';
import '../../domain/revision_content.dart';
import 'workspace_database.dart' as db;

/// Drift + Revision Store adapter for historical Subject resolution, diff,
/// Restore preflight state, and authoritative Draft dirty inspection.
///
/// Historical Store reads acquire shared canonical Store admission and then
/// revalidate every SQLite Subject while the permit is held.
final class DriftWorkspaceHistoryContent
    implements WorkspaceHistoryContentPort {
  DriftWorkspaceHistoryContent({
    required db.WorkspaceDatabase database,
    required ManagedSkillRevisionAccessGate accessGate,
    required RevisionStorePathResolver storePath,
    required RevisionEnginePort revisionEngine,
    required UpdateDraftInspectionPort draftInspection,
  }) : _database = database,
       _accessGate = accessGate,
       _storePath = storePath,
       _revisionEngine = revisionEngine,
       _draftInspection = draftInspection;

  final db.WorkspaceDatabase _database;
  final ManagedSkillRevisionAccessGate _accessGate;
  final RevisionStorePathResolver _storePath;
  final RevisionEnginePort _revisionEngine;
  final UpdateDraftInspectionPort _draftInspection;

  @override
  Future<HistoricalRevisionSelection?> resolvePublishedRevision({
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference reference,
  }) => _database.transaction(
    () => _resolvePublishedRevision(
      managedSkillId: managedSkillId,
      reference: reference,
    ),
  );

  @override
  Future<HistoryResult<SkillDiff>> compare({
    required ManagedSkillId managedSkillId,
    required HistoricalRevisionSelection? from,
    required HistoricalRevisionSelection to,
    required CancellationToken cancellationToken,
  }) async {
    if (cancellationToken.isCancelled) {
      return _failure(HistoryFailureCode.operationCancelled);
    }
    ManagedSkillRevisionAccessPermit permit;
    try {
      permit = await _accessGate.acquireRead(
        managedSkillId,
        cancellationToken: cancellationToken,
      );
    } on ManagedSkillRevisionAccessCancelled {
      return _failure(HistoryFailureCode.operationCancelled);
    } on Object {
      return _failure(HistoryFailureCode.revisionStoreUnavailable);
    }
    try {
      if (cancellationToken.isCancelled) {
        return _failure(HistoryFailureCode.operationCancelled);
      }
      final revalidatedTo = await resolvePublishedRevision(
        managedSkillId: managedSkillId,
        reference: to.reference,
      );
      final revalidatedFrom = from == null
          ? null
          : await resolvePublishedRevision(
              managedSkillId: managedSkillId,
              reference: from.reference,
            );
      if (revalidatedTo != to || (from != null && revalidatedFrom != from)) {
        return _failure(
          HistoryFailureCode.historicalRevisionOutsideCurrentLineage,
        );
      }
      final repositoryPath = _storePath(managedSkillId);
      final files = from == null
          ? await _initialDiff(repositoryPath, to.objectId)
          : await _revisionDiff(repositoryPath, from.objectId, to.objectId);
      return HistorySuccess<SkillDiff>(
        SkillDiff(
          managedSkillId: managedSkillId,
          from: from?.reference,
          to: to.reference,
          files: files,
        ),
      );
    } on RevisionEngineException catch (error) {
      return _failure(
        error.code == RevisionEngineFailureCode.objectUnavailable
            ? HistoryFailureCode.historicalRevisionNotFound
            : HistoryFailureCode.revisionStoreUnavailable,
      );
    } on Object {
      return _failure(HistoryFailureCode.ioFailure);
    } finally {
      await permit.release();
    }
  }

  @override
  Future<RestoreRevisionState?> readRestoreState(
    ManagedSkillId managedSkillId,
  ) async {
    final selections = _database.currentRevisionSelection;
    final lineages = _database.sourceLineages;
    final skills = _database.managedSkills;
    final drafts = _database.draftWorkspaces;
    final query =
        _database.select(selections).join(<Join<HasResultSet, dynamic>>[
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
          leftOuterJoin(
            drafts,
            drafts.managedSkillId.equalsExp(selections.managedSkillId),
          ),
        ])..where(selections.managedSkillId.equals(managedSkillId.value));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final selection = row.readTable(selections);
    final lineage = row.readTable(lineages);
    final skill = row.readTable(skills);
    final draft = row.readTableOrNull(drafts);
    return RestoreRevisionState(
      managedSkillId: managedSkillId,
      sourceLineage: SourceLineageReference(lineage.id),
      currentUpstream: RevisionObjectId(selection.upstreamObjectId),
      currentEffective: RevisionObjectId(selection.effectiveObjectId),
      managedSkillCreatedAtMicros: skill.createdAtMicros,
      draftCreatedAtMicros: draft?.createdAtMicros,
    );
  }

  @override
  Future<HistoryResult<bool>> inspectDraftDirty({
    required ManagedSkill skill,
    required RestoreRevisionState state,
    required CancellationToken cancellationToken,
  }) async {
    final result = await _draftInspection.inspectForUpdate(
      skill: skill,
      cancellationToken: cancellationToken,
    );
    return switch (result) {
      UpdateDraftInspectionSuccess(:final inspection) => HistorySuccess<bool>(
        inspection.isDirty,
      ),
      UpdateDraftInspectionFailure(:final reason) => HistoryFailure<bool>(
        code: HistoryFailureCode.draftInspectionFailed,
        context: <String, Object?>{'reason': reason},
      ),
    };
  }

  Future<HistoricalRevisionSelection?> _resolvePublishedRevision({
    required ManagedSkillId managedSkillId,
    required OperationSubjectReference reference,
  }) async {
    final subjects = _database.operationSubjects;
    final records = _database.operationRecords;
    final lineages = _database.sourceLineages;
    final revisions = _database.revisionMetadata;
    final query =
        _database.select(subjects).join(<Join<HasResultSet, dynamic>>[
            innerJoin(
              records,
              records.operationId.equalsExp(subjects.operationId),
            ),
            innerJoin(
              lineages,
              lineages.id.equalsExp(subjects.sourceLineageId) &
                  lineages.managedSkillId.equalsExp(subjects.managedSkillId),
            ),
            innerJoin(
              revisions,
              revisions.sourceLineageId.equalsExp(subjects.sourceLineageId) &
                  revisions.objectId.equalsExp(subjects.afterObjectId),
            ),
          ])
          ..where(
            subjects.subjectId.equals(reference.subjectId) &
                subjects.operationId.equals(reference.operationId.value) &
                subjects.managedSkillId.equals(managedSkillId.value) &
                subjects.afterObjectId.isNotNull() &
                subjects.afterContentHash.isNotNull() &
                records.status.equals('succeeded'),
          )
          ..limit(1);
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    final subject = row.readTable(subjects);
    final lineage = row.readTable(lineages);
    final revision = row.readTable(revisions);
    if (subject.afterContentHash != revision.contentHash) return null;
    return HistoricalRevisionSelection(
      reference: reference,
      managedSkillId: managedSkillId,
      sourceLineage: SourceLineageReference(lineage.id),
      objectId: RevisionObjectId(revision.objectId),
      contentHash: revision.contentHash,
      declaredName: revision.declaredName,
    );
  }

  Future<List<SkillFileDiff>> _initialDiff(
    String repositoryPath,
    RevisionObjectId to,
  ) async {
    final tree = await _revisionEngine.readTree(repositoryPath, to);
    return tree.files
        .map((file) => _addedFileDiff(file))
        .toList(growable: false)
      ..sort((left, right) => left.path.compareTo(right.path));
  }

  Future<List<SkillFileDiff>> _revisionDiff(
    String repositoryPath,
    RevisionObjectId from,
    RevisionObjectId to,
  ) async {
    final changes = await _revisionEngine.diff(
      repositoryPath: repositoryPath,
      oldCommit: from,
      newCommit: to,
    );
    final oldTree = await _revisionEngine.readTree(repositoryPath, from);
    final newTree = await _revisionEngine.readTree(repositoryPath, to);
    final oldFiles = <String, NormalizedSkillFile>{
      for (final file in oldTree.files) file.relativePath: file,
    };
    final newFiles = <String, NormalizedSkillFile>{
      for (final file in newTree.files) file.relativePath: file,
    };
    final files = changes
        .map(
          (change) => _fileDiff(
            change,
            oldFile: change.oldPath == null ? null : oldFiles[change.oldPath],
            newFile: change.newPath == null ? null : newFiles[change.newPath],
          ),
        )
        .toList(growable: false);
    files.sort((left, right) => left.path.compareTo(right.path));
    return files;
  }
}

SkillFileDiff _fileDiff(
  RevisionChange change, {
  NormalizedSkillFile? oldFile,
  NormalizedSkillFile? newFile,
}) {
  final path = change.newPath ?? change.oldPath!;
  final binary =
      change.binary ||
      oldFile?.bytes.contains(0) == true ||
      newFile?.bytes.contains(0) == true;
  final hunks = binary ? const <DiffHunk>[] : _contentHunks(oldFile, newFile);
  return SkillFileDiff(
    path: path,
    previousPath: change.kind == RevisionChangeKind.renamed
        ? change.oldPath
        : null,
    status: switch (change.kind) {
      RevisionChangeKind.added => DiffFileStatus.added,
      RevisionChangeKind.deleted => DiffFileStatus.deleted,
      RevisionChangeKind.modified => DiffFileStatus.modified,
      RevisionChangeKind.renamed => DiffFileStatus.renamed,
      RevisionChangeKind.typeChanged => DiffFileStatus.modeChanged,
    },
    isBinary: binary,
    additions: hunks.fold<int>(
      0,
      (sum, hunk) =>
          sum +
          hunk.lines.where((line) => line.kind == DiffLineKind.addition).length,
    ),
    deletions: hunks.fold<int>(
      0,
      (sum, hunk) =>
          sum +
          hunk.lines.where((line) => line.kind == DiffLineKind.deletion).length,
    ),
    hunks: hunks,
  );
}

SkillFileDiff _addedFileDiff(NormalizedSkillFile file) {
  final binary = file.bytes.contains(0);
  final hunks = binary ? const <DiffHunk>[] : _contentHunks(null, file);
  return SkillFileDiff(
    path: file.relativePath,
    status: DiffFileStatus.added,
    isBinary: binary,
    additions: _lineCount(file),
    deletions: 0,
    hunks: hunks,
  );
}

List<DiffHunk> _contentHunks(
  NormalizedSkillFile? oldFile,
  NormalizedSkillFile? newFile,
) {
  final oldLines = _textLines(oldFile);
  final newLines = _textLines(newFile);
  if (oldLines.isEmpty && newLines.isEmpty) return const <DiffHunk>[];
  final lines = <DiffLine>[
    for (var index = 0; index < oldLines.length; index += 1)
      DiffLine(
        kind: DiffLineKind.deletion,
        text: oldLines[index],
        oldLineNumber: index + 1,
      ),
    for (var index = 0; index < newLines.length; index += 1)
      DiffLine(
        kind: DiffLineKind.addition,
        text: newLines[index],
        newLineNumber: index + 1,
      ),
  ];
  return <DiffHunk>[
    DiffHunk(
      header: '@@ -1,${oldLines.length} +1,${newLines.length} @@',
      lines: lines,
    ),
  ];
}

List<String> _textLines(NormalizedSkillFile? file) {
  if (file == null || file.bytes.contains(0)) return const <String>[];
  try {
    final decoded = utf8
        .decode(file.bytes, allowMalformed: false)
        .split('\n')
        .map(
          (line) =>
              line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
        )
        .toList(growable: false);
    if (decoded.isNotEmpty && decoded.last.isEmpty) {
      return decoded.sublist(0, decoded.length - 1);
    }
    return decoded;
  } on FormatException {
    return const <String>[];
  }
}

int _lineCount(NormalizedSkillFile file) {
  if (file.bytes.isEmpty || file.bytes.contains(0)) return 0;
  var lines = 0;
  for (final byte in file.bytes) {
    if (byte == 0x0a) lines += 1;
  }
  return file.bytes.last == 0x0a ? lines : lines + 1;
}

HistoryFailure<T> _failure<T>(HistoryFailureCode code) =>
    HistoryFailure<T>(code: code);
