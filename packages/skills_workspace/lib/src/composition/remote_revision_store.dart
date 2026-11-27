import 'dart:io';

import 'package:path/path.dart' as path;

import '../application/runtime/revision_engine_port.dart';
import '../domain/cancellation.dart';
import '../domain/identifiers.dart';
import '../infrastructure/workspace_layout.dart';
import '../native/revision_worker/revision_worker_runtime.dart';

/// Prepares the isolated Store for remote apply while the caller owns the
/// Skill's Store permit. The operation owns cleanup and promotion of the
/// candidate, and carries the used staging paths in its recovery plan.
Future<
  ({
    String storePath,
    List<String> usedPackStaging,
    RevisionPackStageFailure? packFailure,
  })
>
prepareRemoteRevisionStore({
  required WorkspaceLayout layout,
  required RevisionWorkerRuntime revisions,
  required OperationId operationId,
  required ManagedSkillId managedSkillId,
  required List<RevisionObjectId> targetRevisions,
  String? packPath,
  bool createNewStore = false,
  bool usePreviouslyStagedPacks = true,
  required CancellationToken cancellationToken,
}) async {
  final liveStore = layout.revisionStorePath(managedSkillId);
  final candidate = layout.operationRevisionCandidateRoot(
    operationId,
    managedSkillId,
  );
  if (createNewStore) {
    await revisions.createStore(candidate);
  } else {
    await _copyStore(
      Directory(liveStore),
      Directory(candidate),
      cancellationToken,
    );
  }
  final candidatePacks = path.join(candidate, 'objects', 'pack');
  final used = <String>[];
  final staging = Directory(layout.revisionPackStagingPath(managedSkillId));
  final stagingType = createNewStore || !usePreviouslyStagedPacks
      ? FileSystemEntityType.notFound
      : await FileSystemEntity.type(staging.path, followLinks: false);
  if (stagingType != FileSystemEntityType.notFound) {
    if (stagingType != FileSystemEntityType.directory) {
      throw const RevisionEngineException(
        RevisionEngineFailureCode.objectUnavailable,
      );
    }
    await for (final entity in staging.list(followLinks: false)) {
      if (entity is! Directory) {
        throw const RevisionEngineException(
          RevisionEngineFailureCode.objectUnavailable,
        );
      }
      await _copyPack(
        source: entity.path,
        target: candidatePacks,
        name: path.basename(entity.path),
        cancellationToken: cancellationToken,
      );
      used.add(entity.path);
    }
  }
  RevisionPackStageFailure? failure;
  if (packPath != null) {
    try {
      if (packPath.isEmpty ||
          packPath.contains('\u0000') ||
          await FileSystemEntity.type(packPath) != FileSystemEntityType.file) {
        return (
          storePath: candidate,
          usedPackStaging: used,
          packFailure: RevisionPackStageFailure.unreadable,
        );
      }
    } on FileSystemException {
      return (
        storePath: candidate,
        usedPackStaging: used,
        packFailure: RevisionPackStageFailure.unreadable,
      );
    }
    final importRoot = path.join(
      layout.operationStagingPath(operationId),
      'remote-pack',
    );
    await Directory(path.join(importRoot, 'pack')).create(recursive: true);
    _throwIfCancelled(cancellationToken);
    final result = await revisions.stageRevisionPack(
      repositoryPath: candidate,
      stagingObjectsPath: importRoot,
      packPath: packPath,
      revisions: targetRevisions,
    );
    _throwIfCancelled(cancellationToken);
    failure = result.failure;
    if (result.packName case final name?) {
      await _copyPack(
        source: importRoot,
        target: candidatePacks,
        name: name,
        cancellationToken: cancellationToken,
      );
    }
  }
  await revisions.verifyStore(candidate);
  return (storePath: candidate, usedPackStaging: used, packFailure: failure);
}

typedef RemoteStoreAddition = ({
  String source,
  String target,
  bool isDirectory,
});

/// Captures only new Git object files for journaled promotion. A new object
/// directory can be promoted in one entry, with its pack and index together.
Future<List<RemoteStoreAddition>> readRemoteStoreAdditions({
  required String candidateStore,
  required String liveStore,
  required CancellationToken cancellationToken,
}) async {
  _throwIfCancelled(cancellationToken);
  final sourceObjects = path.join(candidateStore, 'objects');
  final targetObjects = path.join(liveStore, 'objects');
  for (final objects in [sourceObjects, targetObjects]) {
    if (await _entryType(objects) != FileSystemEntityType.directory) {
      throw const RevisionEngineException(
        RevisionEngineFailureCode.storeUnavailable,
      );
    }
  }

  final additions = <RemoteStoreAddition>[];
  final directories =
      await Directory(sourceObjects).list(followLinks: false).toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  for (final directory in directories) {
    _throwIfCancelled(cancellationToken);
    final name = path.basename(directory.path);
    if (directory is! Directory) throw _invalidObjectPath;
    if (name == 'info') continue;
    final isPack = name == 'pack';
    if (!isPack && !_looseDirectoryPattern.hasMatch(name)) {
      throw _invalidObjectPath;
    }

    final targetDirectory = path.join(targetObjects, name);
    final liveType = await _entryType(targetDirectory);
    if (liveType != FileSystemEntityType.notFound &&
        liveType != FileSystemEntityType.directory) {
      throw _invalidObjectPath;
    }
    final files = await directory.list(followLinks: false).toList();
    files.sort((left, right) {
      if (isPack) {
        final byExtension = path
            .extension(right.path)
            .compareTo(path.extension(left.path));
        if (byExtension != 0) return byExtension;
      }
      return left.path.compareTo(right.path);
    });
    final names = files.map((file) => path.basename(file.path)).toSet();
    final directoryAdditions = <RemoteStoreAddition>[];
    for (final file in files) {
      _throwIfCancelled(cancellationToken);
      if (file is! File) throw _invalidObjectPath;
      final fileName = path.basename(file.path);
      final target = path.join(targetDirectory, fileName);
      final type = await _entryType(target);
      if (type == FileSystemEntityType.file) continue;
      if (type != FileSystemEntityType.notFound) throw _invalidObjectPath;
      if (isPack) {
        final match = _packFilePattern.firstMatch(fileName);
        if (match == null) throw _invalidObjectPath;
        final pairedExtension = match.group(2) == 'pack' ? 'idx' : 'pack';
        if (!names.contains('pack-${match.group(1)}.$pairedExtension')) {
          throw _invalidObjectPath;
        }
      } else if (!_looseObjectPattern.hasMatch(fileName)) {
        throw _invalidObjectPath;
      }
      directoryAdditions.add((
        source: file.path,
        target: target,
        isDirectory: false,
      ));
    }
    if (liveType == FileSystemEntityType.notFound &&
        directoryAdditions.isNotEmpty) {
      additions.add((
        source: directory.path,
        target: targetDirectory,
        isDirectory: true,
      ));
    } else {
      additions.addAll(directoryAdditions);
    }
  }
  return additions;
}

Future<FileSystemEntityType> _entryType(String path) =>
    FileSystemEntity.type(path, followLinks: false);

final _looseDirectoryPattern = RegExp(r'^[0-9a-f]{2}$');
final _looseObjectPattern = RegExp(r'^[0-9a-f]{38}$');
final _packFilePattern = RegExp(r'^pack-([0-9a-f]{40})\.(pack|idx)$');
const _invalidObjectPath = RevisionEngineException(
  RevisionEngineFailureCode.objectUnavailable,
);

Future<void> _copyStore(
  Directory source,
  Directory target,
  CancellationToken cancellationToken,
) async {
  await target.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    _throwIfCancelled(cancellationToken);
    final destination = path.join(target.path, path.basename(entity.path));
    switch (entity) {
      case final File file:
        await file.copy(destination);
      case final Directory directory:
        await _copyStore(directory, Directory(destination), cancellationToken);
      default:
        throw const RevisionEngineException(
          RevisionEngineFailureCode.storeUnavailable,
        );
    }
  }
}

Future<void> _copyPack({
  required String source,
  required String target,
  required String name,
  required CancellationToken cancellationToken,
}) async {
  final packDirectory = path.join(source, 'pack');
  if (name.length != 40 ||
      !_packNamePattern.hasMatch(name) ||
      await FileSystemEntity.type(packDirectory, followLinks: false) !=
          FileSystemEntityType.directory) {
    throw const RevisionEngineException(
      RevisionEngineFailureCode.objectUnavailable,
    );
  }
  for (final extension in ['pack', 'idx']) {
    _throwIfCancelled(cancellationToken);
    final filename = 'pack-$name.$extension';
    final origin = path.join(packDirectory, filename);
    if (await FileSystemEntity.type(origin, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const RevisionEngineException(
        RevisionEngineFailureCode.objectUnavailable,
      );
    }
    final destination = File(path.join(target, filename));
    if (!await destination.exists()) await File(origin).copy(destination.path);
  }
}

final _packNamePattern = RegExp(r'^[0-9a-f]{40}$');

void _throwIfCancelled(CancellationToken cancellationToken) {
  if (cancellationToken.isCancelled) {
    throw const ManagedRemoteStoreCancelled();
  }
}

final class ManagedRemoteStoreCancelled implements Exception {
  const ManagedRemoteStoreCancelled();
}
