import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as paths;

import '../../application/drift/drift_models.dart';
import '../../application/ports/draft_snapshot_ports.dart';
import '../../application/ports/published_artifact_ports.dart';
import '../../domain/cancellation.dart';
import 'durable_workspace_filesystem.dart';

/// Copies reviewed external bytes into an unpublished sibling before exposing
/// a writable export. Neither source links nor destination links are followed.
final class FileSystemSkillDriftExporter implements DriftArtifactExporterPort {
  const FileSystemSkillDriftExporter({
    required DurableWorkspaceFilesystem filesystem,
  }) : _filesystem = filesystem;

  final DurableWorkspaceFilesystem _filesystem;

  @override
  Future<DriftResult<String>> export({
    required String sourcePath,
    required String slotKey,
    required String destinationDirectory,
    required List<String> forbiddenRoots,
    required String expectedFingerprint,
    required PublishedArtifactInspectorPort inspector,
    required CancellationToken cancellationToken,
    required DateTime now,
  }) async {
    try {
      return await _export(
        sourcePath: sourcePath,
        slotKey: slotKey,
        destinationDirectory: destinationDirectory,
        forbiddenRoots: forbiddenRoots,
        expectedFingerprint: expectedFingerprint,
        inspector: inspector,
        cancellationToken: cancellationToken,
        now: now,
      );
    } on FileSystemException {
      // Includes failures while cleaning an unpublished candidate.
      return DriftFailure<String>(code: DriftFailureCode.ioFailure);
    }
  }

  Future<DriftResult<String>> _export({
    required String sourcePath,
    required String slotKey,
    required String destinationDirectory,
    required List<String> forbiddenRoots,
    required String expectedFingerprint,
    required PublishedArtifactInspectorPort inspector,
    required CancellationToken cancellationToken,
    required DateTime now,
  }) async {
    if (cancellationToken.isCancelled) return _cancelled();
    final filesystem = _filesystem;
    String? stagingPath;
    try {
      // Resolve the parent once, then operate on that canonical directory. A
      // subsequently retargeted parent alias cannot redirect the export.
      final destination = paths.normalize(paths.absolute(destinationDirectory));
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.directory) {
        return _unavailable();
      }
      final canonicalDestination = paths.normalize(
        await Directory(destination).resolveSymbolicLinks(),
      );
      for (final root in forbiddenRoots) {
        final absoluteRoot = paths.normalize(paths.absolute(root));
        final canonicalRoot = await filesystem.resolveMutationPath(
          absoluteRoot,
        );
        if (_contains(absoluteRoot, destination) ||
            _contains(canonicalRoot, canonicalDestination)) {
          return _unavailable();
        }
        // Workspace roots and directory activations may themselves be aliases.
        if (await FileSystemEntity.type(absoluteRoot) ==
            FileSystemEntityType.directory) {
          final resolvedRoot = paths.normalize(
            await Directory(absoluteRoot).resolveSymbolicLinks(),
          );
          if (_contains(resolvedRoot, canonicalDestination)) {
            return _unavailable();
          }
        }
      }
      if (slotKey.isEmpty ||
          slotKey == '.' ||
          slotKey == '..' ||
          slotKey.contains('/') ||
          slotKey.contains('\\')) {
        return _unavailable();
      }
      final before = await inspector.observe(
        path: sourcePath,
        cancellationToken: cancellationToken,
      );
      if (cancellationToken.isCancelled) return _cancelled();
      if (before.state == PublishedArtifactState.unsafe) return _unavailable();
      if (before.fingerprint != expectedFingerprint) return _stale();
      final sourceType = await FileSystemEntity.type(
        sourcePath,
        followLinks: false,
      );
      if (sourceType != FileSystemEntityType.directory &&
          sourceType != FileSystemEntityType.file) {
        return _unavailable();
      }
      final capture = _ExportCapture(cancellationToken);
      final captureFailure = sourceType == FileSystemEntityType.directory
          ? await capture.directory(sourcePath, '')
          : await capture.file(sourcePath, '');
      if (captureFailure != null) {
        return DriftFailure<String>(
          code: captureFailure.code,
          context: captureFailure.context,
        );
      }
      final utc = now.toUtc();
      String padded(int value, int length) =>
          value.toString().padLeft(length, '0');
      final timestamp =
          '${padded(utc.year, 4)}${padded(utc.month, 2)}${padded(utc.day, 2)}'
          '${padded(utc.hour, 2)}${padded(utc.minute, 2)}${padded(utc.second, 2)}';
      final basePath = paths.join(
        canonicalDestination,
        '$slotKey-external-$timestamp',
      );
      var exportedPath = basePath;
      var suffix = 2;
      while (await FileSystemEntity.type(exportedPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        exportedPath = '$basePath-${suffix++}';
      }
      final kind = sourceType == FileSystemEntityType.directory
          ? DurableEntryKind.directory
          : DurableEntryKind.file;
      final staging = await filesystem.createSiblingStagingPath(
        exportedPath,
        kind: kind,
        purpose: 'external-export',
      );
      stagingPath = staging.path;
      if (kind == DurableEntryKind.directory) {
        await filesystem.ensureDirectory(staging.path);
        for (final directory in capture.directories) {
          if (cancellationToken.isCancelled) return _cancelled();
          await filesystem.ensureDirectory(paths.join(staging.path, directory));
        }
      }
      for (final file in capture.files) {
        if (cancellationToken.isCancelled) return _cancelled();
        final target = kind == DurableEntryKind.file
            ? staging.path
            : paths.join(staging.path, file.relativePath);
        await filesystem.writeDurableFile(target, file.bytes);
        await filesystem.setExecutableIntent(target, file.isExecutable);
      }
      final captured = await inspector.observe(
        path: staging.path,
        cancellationToken: cancellationToken,
      );
      final after = await inspector.observe(
        path: sourcePath,
        cancellationToken: cancellationToken,
      );
      if (cancellationToken.isCancelled) return _cancelled();
      if (captured.state == PublishedArtifactState.unsafe ||
          after.state == PublishedArtifactState.unsafe) {
        return _unavailable();
      }
      if (captured.fingerprint != expectedFingerprint ||
          after.fingerprint != expectedFingerprint) {
        return _stale();
      }
      // Recheck occupancy immediately before the rename; an occupied name is
      // never deliberately replaced, including an occupied symbolic link.
      while (await FileSystemEntity.type(exportedPath, followLinks: false) !=
          FileSystemEntityType.notFound) {
        exportedPath = '$basePath-${suffix++}';
      }
      await filesystem.flushRecursively(staging.path);
      if (kind == DurableEntryKind.directory) {
        await Directory(staging.path).rename(exportedPath);
      } else {
        await File(staging.path).rename(exportedPath);
      }
      stagingPath = null;
      await filesystem.flushDirectory(canonicalDestination);
      return DriftSuccess<String>(value: exportedPath);
    } finally {
      if (stagingPath != null) {
        await filesystem.removeOwnedPath(
          targetPath: stagingPath,
          ownerRoot: paths.dirname(stagingPath),
        );
      }
    }
  }
}

final class _ExportCapture {
  _ExportCapture(this.cancellationToken);

  final CancellationToken cancellationToken;
  final List<StagedDirectoryFile> files = [];
  final List<String> directories = [];
  var byteSize = 0;

  Future<DriftFailure<void>?> directory(String source, String prefix) async {
    await for (final entry in Directory(source).list(followLinks: false)) {
      if (cancellationToken.isCancelled) return _captureCancelled();
      final relative = paths.join(prefix, paths.basename(entry.path));
      final type = await FileSystemEntity.type(entry.path, followLinks: false);
      DriftFailure<void>? failure;
      if (type == FileSystemEntityType.directory) {
        directories.add(relative);
        failure = await directory(entry.path, relative);
      } else if (type == FileSystemEntityType.file) {
        failure = await file(entry.path, relative);
      } else {
        return DriftFailure<void>(
          code: DriftFailureCode.driftResolutionUnavailable,
          context: const {'reason': 'exportNotAllowed'},
        );
      }
      if (failure != null) return failure;
    }
    return null;
  }

  Future<DriftFailure<void>?> file(String source, String relative) async {
    if (files.length >= defaultDraftSnapshotFileLimit) return _limit();
    final stat = await File(source).stat();
    if (byteSize + stat.size > defaultDraftSnapshotByteLimit) return _limit();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in File(source).openRead()) {
      if (cancellationToken.isCancelled) return _captureCancelled();
      byteSize += chunk.length;
      if (byteSize > defaultDraftSnapshotByteLimit) return _limit();
      bytes.add(chunk);
    }
    if (await FileSystemEntity.type(source, followLinks: false) !=
        FileSystemEntityType.file) {
      return DriftFailure<void>(
        code: DriftFailureCode.staleDriftReview,
        context: const {'reason': 'artifactChanged'},
      );
    }
    files.add(
      StagedDirectoryFile(
        relativePath: relative,
        bytes: bytes.takeBytes(),
        isExecutable: !Platform.isWindows && stat.mode & 0x49 != 0,
      ),
    );
    return null;
  }
}

bool _contains(String root, String path) =>
    paths.equals(root, path) || paths.isWithin(root, path);

DriftFailure<String> _unavailable() => DriftFailure<String>(
  code: DriftFailureCode.driftResolutionUnavailable,
  context: const {'reason': 'exportNotAllowed'},
);

DriftFailure<String> _stale() => DriftFailure<String>(
  code: DriftFailureCode.staleDriftReview,
  context: const {'reason': 'artifactChanged'},
);

DriftFailure<String> _cancelled() =>
    DriftFailure<String>(code: DriftFailureCode.operationCancelled);

DriftFailure<void> _captureCancelled() =>
    DriftFailure<void>(code: DriftFailureCode.operationCancelled);

DriftFailure<void> _limit() =>
    DriftFailure<void>(code: DriftFailureCode.skillContentLimitExceeded);
