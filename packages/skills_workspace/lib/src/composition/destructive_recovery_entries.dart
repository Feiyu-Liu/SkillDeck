import 'dart:io';

import 'package:path/path.dart' as path;

import '../application/operations/destructive_recovery_intent.dart';
import '../application/ports/destructive_operation_ports.dart';
import '../application/runtime/revision_engine_port.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../domain/revision_content.dart';
import '../infrastructure/database/workspace_database.dart' as db;
import '../infrastructure/workspace_layout.dart';
import '../platform/filesystem/durable_workspace_filesystem.dart';
import '../platform/operations/operation_recovery_bundle.dart';

/// Resolves path-free destructive intent into operation-owned recovery entries.
///
/// This runs under the Workspace Writer Lock. It may create only staging bytes
/// and stage an in-memory recovery specification; live paths remain untouched
/// until the Journaled applying phase.
final class WorkspaceDestructiveRecoveryEntries
    implements DestructiveRecoveryEntryPreparationPort {
  const WorkspaceDestructiveRecoveryEntries({
    required db.WorkspaceDatabase database,
    required WorkspaceLayout layout,
    required RevisionEnginePort revisions,
    required DurableWorkspaceFilesystem filesystem,
    required OperationRecoverySpecRegistry recoverySpecs,
  }) : _database = database,
       _layout = layout,
       _revisions = revisions,
       _filesystem = filesystem,
       _recoverySpecs = recoverySpecs;

  final db.WorkspaceDatabase _database;
  final WorkspaceLayout _layout;
  final RevisionEnginePort _revisions;
  final DurableWorkspaceFilesystem _filesystem;
  final OperationRecoverySpecRegistry _recoverySpecs;

  @override
  Future<void> prepareRecoveryEntries({
    required OperationId operationId,
    required DestructiveOperationRecoveryIntent intent,
    required CancellationToken cancellationToken,
  }) async {
    _throwIfCancelled(cancellationToken);
    final activations = await _readActivations(intent);
    final entries = <String, OperationRecoveryEntrySpec>{};
    var nextEntry = 1;

    void add(OperationRecoveryEntrySpec entry) {
      final key = _identity(entry.targetPath);
      if (entries.containsKey(key)) {
        throw StateError('Destructive intent targets one path twice.');
      }
      entries[key] = entry;
      nextEntry += 1;
    }

    String entryId(String role) =>
        'destructive-${nextEntry.toString().padLeft(4, '0')}-$role';

    switch (intent) {
      case final SourceReplacementRecoveryIntent replacement:
        final skill = replacement.skill;
        final candidateStore = _layout.operationSourceReplacementStore(
          operationId,
        );
        final candidateBundle = _layout.operationSourceReplacementBundle(
          operationId,
        );
        final candidateTree = path.join(
          _layout.operationSourceReplacementRoot(operationId),
          'tree',
        );
        final tree = await _revisions.readTree(
          candidateStore,
          replacement.intendedObjectId,
        );
        await _writeTree(candidateTree, tree, cancellationToken);

        add(
          OperationRecoveryEntrySpec(
            entryId: entryId('store'),
            targetPath: _layout.revisionStorePath(skill.managedSkillId),
            intendedSourcePath: candidateStore,
            intendedKind: OperationRecoveryEntryKind.directory,
            makeReadOnly: false,
            requirePlainDirectory: false,
          ),
        );
        add(
          OperationRecoveryEntrySpec(
            entryId: entryId('bundle'),
            targetPath: _layout.revisionBundlePath(skill.managedSkillId),
            intendedSourcePath: candidateBundle,
            intendedKind: OperationRecoveryEntryKind.directory,
          ),
        );

        final oldRepository = _layout.repositoryCopyPath(skill.slotKey);
        final newRepository = _layout.repositoryCopyPath(
          replacement.intendedSlotKey,
        );
        if (!path.equals(oldRepository, newRepository)) {
          add(_absent(entryId('old-repository'), oldRepository));
        }
        add(_directory(entryId('repository'), newRepository, candidateTree));
        for (final activation in activations) {
          _throwIfCancelled(cancellationToken);
          final oldTarget = path.join(activation.canonicalPath, skill.slotKey);
          final newTarget = path.join(
            activation.canonicalPath,
            replacement.intendedSlotKey,
          );
          if (!path.equals(oldTarget, newTarget)) {
            add(_absent(entryId('old-activation'), oldTarget));
          }
          add(
            activation.mode == 'symbolicLink'
                ? _symbolicLink(
                    entryId('activation-link'),
                    newTarget,
                    newRepository,
                  )
                : _directory(
                    entryId('activation-copy'),
                    newTarget,
                    candidateTree,
                  ),
          );
        }
        if (skill.hasDraft) {
          add(
            _absent(entryId('draft'), _layout.draftPath(skill.managedSkillId)),
          );
        }
      case final RemovalRecoveryIntent removal:
        for (final skill in removal.skills) {
          _throwIfCancelled(cancellationToken);
          add(
            _absent(
              entryId('store'),
              _layout.revisionStorePath(skill.managedSkillId),
            ),
          );
          add(
            _absent(
              entryId('bundle'),
              _layout.revisionBundlePath(skill.managedSkillId),
            ),
          );
          add(
            _absent(
              entryId('repository'),
              _layout.repositoryCopyPath(skill.slotKey),
            ),
          );
          for (final activation in activations.where(
            (row) => row.managedSkillId == skill.managedSkillId.value,
          )) {
            add(
              _absent(
                entryId('activation'),
                path.join(activation.canonicalPath, skill.slotKey),
              ),
            );
          }
          if (skill.hasDraft) {
            add(
              _absent(
                entryId('draft'),
                _layout.draftPath(skill.managedSkillId),
              ),
            );
          }
        }
    }
    _recoverySpecs.stageDestructiveEntries(
      operationId,
      entries.values.toList(growable: false),
    );
  }

  Future<List<db.ActivationLocation>> _readActivations(
    DestructiveOperationRecoveryIntent intent,
  ) async {
    final expected = <String, ManagedSkillId>{
      for (final skill in intent.skills)
        for (final id in skill.activationIds) id: skill.managedSkillId,
    };
    if (expected.isEmpty) return const <db.ActivationLocation>[];
    final rows = await (_database.select(
      _database.activationLocations,
    )..where((row) => row.id.isIn(expected.keys))).get();
    if (rows.length != expected.length) {
      throw StateError('A destructive Activation disappeared.');
    }
    for (final row in rows) {
      if (row.managedSkillId != expected[row.id]!.value ||
          (row.mode != 'copy' && row.mode != 'symbolicLink') ||
          !path.isAbsolute(row.canonicalPath)) {
        throw StateError('A destructive Activation changed identity.');
      }
    }
    rows.sort((left, right) => left.id.compareTo(right.id));
    return rows;
  }

  Future<void> _writeTree(
    String root,
    NormalizedSkillTree tree,
    CancellationToken token,
  ) async {
    await _filesystem.removeOwnedPath(
      targetPath: root,
      ownerRoot: _layout.stagingRoot,
    );
    await _filesystem.materializeStagedDirectory(
      rootPath: root,
      files: tree.files.map(
        (file) => StagedDirectoryFile(
          relativePath: file.relativePath,
          bytes: file.bytes,
          isExecutable: file.isExecutable,
        ),
      ),
      checkCancelled: () => _throwIfCancelled(token),
    );
  }

  OperationRecoveryEntrySpec _directory(
    String id,
    String target,
    String source,
  ) => OperationRecoveryEntrySpec(
    entryId: id,
    targetPath: target,
    intendedSourcePath: source,
    intendedKind: OperationRecoveryEntryKind.directory,
  );

  OperationRecoveryEntrySpec _symbolicLink(
    String id,
    String target,
    String linkTarget,
  ) => OperationRecoveryEntrySpec(
    entryId: id,
    targetPath: target,
    intendedSourcePath: null,
    intendedKind: OperationRecoveryEntryKind.symbolicLink,
    intendedSymbolicLinkTarget: linkTarget,
    makeReadOnly: false,
    requirePlainDirectory: false,
  );

  OperationRecoveryEntrySpec _absent(String id, String target) =>
      OperationRecoveryEntrySpec(
        entryId: id,
        targetPath: target,
        intendedSourcePath: null,
        intendedKind: null,
        makeReadOnly: false,
        requirePlainDirectory: false,
      );
}

String _identity(String value) => Platform.isWindows
    ? path.windows.normalize(value).toUpperCase()
    : path.posix.normalize(value);

void _throwIfCancelled(CancellationToken token) {
  if (token.isCancelled) throw StateError('Destructive operation cancelled.');
}
