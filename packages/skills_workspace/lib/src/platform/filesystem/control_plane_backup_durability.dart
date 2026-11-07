import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

import '../../application/ports/control_plane_backup_ports.dart';
import 'durable_workspace_filesystem.dart';

/// Platform implementation of the application-owned Control Plane durability
/// port. All replacement semantics stay delegated to the shared durable
/// filesystem so backups and primary restores use the same crash boundaries as
/// the rest of the Workspace.
final class PlatformControlPlaneBackupDurability
    implements ControlPlaneBackupDurabilityPort {
  const PlatformControlPlaneBackupDurability(this._filesystem);

  final DurableWorkspaceFilesystem _filesystem;

  @override
  Future<bool> exists(String targetPath) async =>
      await FileSystemEntity.type(targetPath, followLinks: false) !=
      FileSystemEntityType.notFound;

  @override
  Future<int> fileSize(String filePath) async {
    _requireFile(filePath);
    return File(filePath).length();
  }

  @override
  Future<List<int>> readFile(String filePath) async {
    _requireFile(filePath);
    return File(filePath).readAsBytes();
  }

  @override
  Future<String> sha256File(String filePath) async {
    _requireFile(filePath);
    return (await sha256.bind(File(filePath).openRead()).first).toString();
  }

  @override
  Future<List<String>> listChildDirectories(String parentPath) async {
    final type = await FileSystemEntity.type(parentPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return const <String>[];
    if (type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Expected a directory while enumerating Control Plane backups.',
        parentPath,
      );
    }
    final entries = await Directory(
      parentPath,
    ).list(followLinks: false).toList();
    final directories = <String>[];
    for (final entry in entries) {
      if (await FileSystemEntity.type(entry.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        directories.add(path.normalize(path.absolute(entry.path)));
      }
    }
    directories.sort();
    return List<String>.unmodifiable(directories);
  }

  @override
  Future<String> createSiblingStagingPath(
    String destinationPath, {
    required ControlPlaneStagingKind kind,
  }) async {
    final staging = await _filesystem.createSiblingStagingPath(
      destinationPath,
      kind: _entryKind(kind),
      purpose: 'control-plane',
    );
    return staging.path;
  }

  @override
  Future<void> writeDurableFile(String filePath, List<int> bytes) =>
      _filesystem.writeDurableFile(filePath, bytes);

  @override
  Future<void> copyDurableFile({
    required String sourcePath,
    required String destinationPath,
  }) async {
    _requireFile(sourcePath);
    final destination = path.normalize(path.absolute(destinationPath));
    await _filesystem.ensureDirectory(path.dirname(destination));

    RandomAccessFile? source;
    RandomAccessFile? output;
    try {
      source = await File(sourcePath).open();
      output = await File(destination).open(mode: FileMode.write);
      await output.truncate(0);
      while (true) {
        final bytes = await source.read(1024 * 1024);
        if (bytes.isEmpty) break;
        await output.writeFrom(bytes);
      }
      await output.flush();
      await output.close();
      output = null;
      await source.close();
      source = null;
      await _filesystem.flushFile(destination);
      await _filesystem.flushDirectory(path.dirname(destination));
    } finally {
      await output?.close();
      await source?.close();
    }
  }

  @override
  Future<void> publish({
    required String candidatePath,
    required String destinationPath,
    required ControlPlaneStagingKind kind,
    required ControlPlanePathVerifier verify,
  }) async {
    final publication = await _filesystem.publish(
      candidatePath: candidatePath,
      destinationPath: destinationPath,
      kind: _entryKind(kind),
      verify: verify,
      requirePlainDirectory: true,
    );
    final displaced = publication.displacedPath;
    if (displaced != null) {
      await _filesystem.removeOwnedPath(
        targetPath: displaced,
        ownerRoot: path.dirname(publication.destinationPath),
      );
    }
  }

  @override
  Future<void> removeOwnedPath({
    required String targetPath,
    required String ownerRoot,
  }) =>
      _filesystem.removeOwnedPath(targetPath: targetPath, ownerRoot: ownerRoot);
}

DurableEntryKind _entryKind(ControlPlaneStagingKind kind) => switch (kind) {
  ControlPlaneStagingKind.file => DurableEntryKind.file,
  ControlPlaneStagingKind.directory => DurableEntryKind.directory,
};

void _requireFile(String filePath) {
  if (FileSystemEntity.typeSync(filePath, followLinks: false) !=
      FileSystemEntityType.file) {
    throw FileSystemException('Expected a regular file.', filePath);
  }
}
