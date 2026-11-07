import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../../application/ports/draft_snapshot_ports.dart';
import '../../domain/draft_snapshot.dart';
import 'durable_workspace_filesystem.dart';

enum DraftFilesystemScanPurpose { capture, revalidation }

enum DraftFilesystemCaptureEvent {
  beforeScan,
  beforeFileRead,
  afterFileRead,
  afterScan,
}

typedef DraftFilesystemCaptureObserver =
    FutureOr<void> Function(
      DraftFilesystemScanPurpose purpose,
      DraftFilesystemCaptureEvent event,
      String? relativePath,
    );

/// Captures Draft bytes and physical evidence without content normalization.
final class FilesystemDraftSnapshotAdapter
    implements DraftSnapshotFilesystemPort {
  FilesystemDraftSnapshotAdapter({
    DurableWorkspaceFilesystem? filesystem,
    this.observer,
  }) : _filesystem = filesystem ?? PlatformDurableWorkspaceFilesystem();

  final DurableWorkspaceFilesystem _filesystem;
  final DraftFilesystemCaptureObserver? observer;

  @override
  Future<DraftSnapshotResult<DraftCapture>> capture(
    DraftCaptureRequest request,
  ) async {
    TargetVolumeStagingPath? staging;
    try {
      staging = await _filesystem.createSiblingStagingPath(
        request.stagingDestinationPath,
        kind: DurableEntryKind.directory,
        purpose: 'draft-capture',
      );
      final scan = await _scan(
        request,
        purpose: DraftFilesystemScanPurpose.capture,
      );
      await _filesystem.materializeStagedDirectory(
        rootPath: staging.path,
        directories: scan.directories,
        files: scan.files.map(
          (file) => StagedDirectoryFile(
            relativePath: file.relativePath,
            bytes: file.bytes,
            isExecutable: file.isExecutable,
          ),
        ),
        checkCancelled: () => _throwIfCancelled(request),
      );
      return DraftSnapshotSuccess<DraftCapture>(
        DraftCapture(
          liveDraftPath: path.normalize(path.absolute(request.liveDraftPath)),
          stagingPath: staging.path,
          fingerprint: scan.fingerprint,
          files: scan.files,
        ),
      );
    } catch (error) {
      if (staging != null) {
        await _discardPathBestEffort(staging.path);
      }
      return _captureFailure<DraftCapture>(error);
    }
  }

  @override
  Future<DraftSnapshotResult<DraftFingerprint>> fingerprint(
    DraftCaptureRequest request,
  ) async {
    try {
      final scan = await _scan(
        request,
        purpose: DraftFilesystemScanPurpose.revalidation,
      );
      return DraftSnapshotSuccess<DraftFingerprint>(scan.fingerprint);
    } catch (error) {
      return _captureFailure<DraftFingerprint>(error);
    }
  }

  @override
  Future<void> discardStaging(DraftCapture capture) async {
    await _filesystem.removeOwnedPath(
      targetPath: capture.stagingPath,
      ownerRoot: path.dirname(capture.stagingPath),
    );
  }

  Future<_DraftScan> _scan(
    DraftCaptureRequest request, {
    required DraftFilesystemScanPurpose purpose,
  }) async {
    _throwIfCancelled(request);
    await observer?.call(purpose, DraftFilesystemCaptureEvent.beforeScan, null);
    final liveRoot = path.normalize(path.absolute(request.liveDraftPath));
    final rootType = await FileSystemEntity.type(liveRoot, followLinks: false);
    if (rootType != FileSystemEntityType.directory) {
      throw const _DraftCaptureUnavailable('draftRootNotDirectory');
    }
    final canonicalRoot = path.normalize(
      await Directory(liveRoot).resolveSymbolicLinks(),
    );
    final collector = _DraftCollector(
      request: request,
      filesystem: _filesystem,
      canonicalRoot: canonicalRoot,
      purpose: purpose,
      observer: observer,
    );
    await collector.collectDirectory(
      entryPath: liveRoot,
      resolvedDirectoryPath: canonicalRoot,
      outputPrefix: '',
      kind: DraftFilesystemEntryKind.directory,
      activeCanonicalDirectories: <String>{canonicalRoot},
    );
    collector.evidence.sort(_compareEvidence);
    collector.files.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    collector.directories.sort();
    await observer?.call(purpose, DraftFilesystemCaptureEvent.afterScan, null);
    return _DraftScan(
      fingerprint: DraftFingerprint(collector.evidence),
      files: collector.files,
      directories: collector.directories,
    );
  }

  Future<void> _discardPathBestEffort(String stagingPath) async {
    try {
      await _filesystem.removeOwnedPath(
        targetPath: stagingPath,
        ownerRoot: path.dirname(stagingPath),
      );
    } catch (_) {
      // The capture failure remains the primary failure.
    }
  }
}

final class _DraftCollector {
  _DraftCollector({
    required this.request,
    required this.filesystem,
    required this.canonicalRoot,
    required this.purpose,
    required this.observer,
  });

  final DraftCaptureRequest request;
  final DurableWorkspaceFilesystem filesystem;
  final String canonicalRoot;
  final DraftFilesystemScanPurpose purpose;
  final DraftFilesystemCaptureObserver? observer;
  final List<DraftEntryEvidence> evidence = <DraftEntryEvidence>[];
  final List<CapturedDraftFile> files = <CapturedDraftFile>[];
  final List<String> directories = <String>[];
  var byteSize = 0;

  Future<void> collectDirectory({
    required String entryPath,
    required String resolvedDirectoryPath,
    required String outputPrefix,
    required DraftFilesystemEntryKind kind,
    required Set<String> activeCanonicalDirectories,
  }) async {
    _throwIfCancelled(request);
    final beforeEntry = await _identity(entryPath, followLinks: false);
    final beforeResolved = await _identity(entryPath, followLinks: true);
    final beforeStat = await Directory(resolvedDirectoryPath).stat();
    final beforeTarget = kind == DraftFilesystemEntryKind.symbolicLink
        ? await Link(entryPath).target()
        : null;
    final beforeChildren = await _directoryChildren(resolvedDirectoryPath);

    for (final child in beforeChildren) {
      _throwIfCancelled(request);
      final name = path.basename(child.path);
      if (_portableSegmentKey(name) == '.GIT') {
        throw const _DraftCaptureInvalid('gitMetadataNotAllowed');
      }
      final outputPath = outputPrefix.isEmpty ? name : '$outputPrefix/$name';
      final type = await FileSystemEntity.type(child.path, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          final canonical = path.normalize(
            await Directory(child.path).resolveSymbolicLinks(),
          );
          _requireContained(canonical);
          if (activeCanonicalDirectories.contains(canonical)) {
            throw const _DraftCaptureInvalid('cyclicDirectory');
          }
          await collectDirectory(
            entryPath: child.path,
            resolvedDirectoryPath: canonical,
            outputPrefix: outputPath,
            kind: DraftFilesystemEntryKind.directory,
            activeCanonicalDirectories: <String>{
              ...activeCanonicalDirectories,
              canonical,
            },
          );
        case FileSystemEntityType.file:
          await collectFile(
            entryPath: child.path,
            outputPath: outputPath,
            kind: DraftFilesystemEntryKind.file,
          );
        case FileSystemEntityType.link:
          await _collectSymbolicLink(
            linkPath: child.path,
            outputPath: outputPath,
            activeCanonicalDirectories: activeCanonicalDirectories,
          );
        case FileSystemEntityType.notFound:
          throw const _DraftCaptureChanged('entryDisappeared');
        default:
          throw const _DraftCaptureInvalid('unsupportedFilesystemEntry');
      }
    }

    final afterChildren = await _directoryChildren(resolvedDirectoryPath);
    final afterEntry = await _identity(entryPath, followLinks: false);
    final afterResolved = await _identity(entryPath, followLinks: true);
    final afterStat = await Directory(resolvedDirectoryPath).stat();
    final afterTarget = kind == DraftFilesystemEntryKind.symbolicLink
        ? await Link(entryPath).target()
        : null;
    if (!_sameDirectoryListing(beforeChildren, afterChildren) ||
        beforeEntry != afterEntry ||
        beforeResolved != afterResolved ||
        !_sameStat(beforeStat, afterStat) ||
        beforeTarget != afterTarget) {
      throw const _DraftCaptureChanged('directoryChanged');
    }
    if (outputPrefix.isNotEmpty) {
      directories.add(outputPrefix);
    }
    evidence.add(
      DraftEntryEvidence(
        relativePath: outputPrefix,
        kind: kind,
        entryIdentity: beforeEntry,
        resolvedIdentity: beforeResolved,
        modifiedAtMicrosecondsUtc: _modifiedMicros(beforeStat),
        byteSize: null,
        contentHash: null,
        isExecutable: false,
        symbolicLinkTarget: beforeTarget,
      ),
    );
  }

  Future<void> _collectSymbolicLink({
    required String linkPath,
    required String outputPath,
    required Set<String> activeCanonicalDirectories,
  }) async {
    String canonical;
    try {
      canonical = path.normalize(await Link(linkPath).resolveSymbolicLinks());
    } on FileSystemException {
      throw const _DraftCaptureInvalid('brokenOrCyclicSymbolicLink');
    }
    _requireContained(canonical);
    final sourceRelative = path.relative(canonical, from: canonicalRoot);
    if (path
        .split(sourceRelative)
        .any((segment) => _portableSegmentKey(segment) == '.GIT')) {
      throw const _DraftCaptureInvalid('gitMetadataNotAllowed');
    }
    final targetType = await FileSystemEntity.type(
      canonical,
      followLinks: true,
    );
    if (targetType == FileSystemEntityType.file) {
      await collectFile(
        entryPath: linkPath,
        outputPath: outputPath,
        kind: DraftFilesystemEntryKind.symbolicLink,
      );
      return;
    }
    if (targetType == FileSystemEntityType.directory) {
      if (activeCanonicalDirectories.contains(canonical)) {
        throw const _DraftCaptureInvalid('cyclicSymbolicLink');
      }
      await collectDirectory(
        entryPath: linkPath,
        resolvedDirectoryPath: canonical,
        outputPrefix: outputPath,
        kind: DraftFilesystemEntryKind.symbolicLink,
        activeCanonicalDirectories: <String>{
          ...activeCanonicalDirectories,
          canonical,
        },
      );
      return;
    }
    throw const _DraftCaptureInvalid('unsupportedSymbolicLinkTarget');
  }

  Future<void> collectFile({
    required String entryPath,
    required String outputPath,
    required DraftFilesystemEntryKind kind,
  }) async {
    _throwIfCancelled(request);
    if (files.length >= request.maximumFileCount) {
      throw const _DraftCaptureLimit('fileCount');
    }
    final beforeEntry = await _identity(entryPath, followLinks: false);
    final beforeResolved = await _identity(entryPath, followLinks: true);
    final beforeStat = await File(entryPath).stat();
    final beforeTarget = kind == DraftFilesystemEntryKind.symbolicLink
        ? await Link(entryPath).target()
        : null;
    if (beforeStat.type != FileSystemEntityType.file) {
      throw const _DraftCaptureChanged('fileTypeChanged');
    }
    if (beforeStat.size > request.maximumByteSize - byteSize) {
      throw const _DraftCaptureLimit('byteSize');
    }
    await observer?.call(
      purpose,
      DraftFilesystemCaptureEvent.beforeFileRead,
      outputPath,
    );
    final bytes = await File(entryPath).readAsBytes();
    await observer?.call(
      purpose,
      DraftFilesystemCaptureEvent.afterFileRead,
      outputPath,
    );
    _throwIfCancelled(request);
    final afterStat = await File(entryPath).stat();
    final afterEntry = await _identity(entryPath, followLinks: false);
    final afterResolved = await _identity(entryPath, followLinks: true);
    final afterTarget = kind == DraftFilesystemEntryKind.symbolicLink
        ? await Link(entryPath).target()
        : null;
    final executable = _executableIntent(outputPath, beforeStat.mode);
    if (beforeEntry != afterEntry ||
        beforeResolved != afterResolved ||
        !_sameStat(beforeStat, afterStat) ||
        beforeTarget != afterTarget ||
        bytes.length != beforeStat.size ||
        executable != _executableIntent(outputPath, afterStat.mode)) {
      throw const _DraftCaptureChanged('fileChanged');
    }
    if (bytes.length > request.maximumByteSize - byteSize) {
      throw const _DraftCaptureLimit('byteSize');
    }
    byteSize += bytes.length;
    final digest = sha256.convert(bytes).toString();
    files.add(
      CapturedDraftFile(
        relativePath: outputPath,
        bytes: bytes,
        isExecutable: executable,
      ),
    );
    evidence.add(
      DraftEntryEvidence(
        relativePath: outputPath,
        kind: kind,
        entryIdentity: beforeEntry,
        resolvedIdentity: beforeResolved,
        modifiedAtMicrosecondsUtc: _modifiedMicros(beforeStat),
        byteSize: bytes.length,
        contentHash: digest,
        isExecutable: executable,
        symbolicLinkTarget: beforeTarget,
      ),
    );
  }

  bool _executableIntent(String outputPath, int mode) {
    final lookupPath = outputPath
        .replaceAll(r'\', '/')
        .split('/')
        .map(unicode.nfc)
        .join('/');
    return request.executableIntentOverrides[lookupPath] ??
        (request.capturePosixExecutableIntent &&
            !Platform.isWindows &&
            mode & 0x49 != 0);
  }

  void _requireContained(String candidate) {
    if (!path.equals(canonicalRoot, candidate) &&
        !path.isWithin(canonicalRoot, candidate)) {
      throw const _DraftCaptureInvalid('symbolicLinkEscapesDraft');
    }
  }

  Future<DraftPhysicalIdentity> _identity(
    String targetPath, {
    required bool followLinks,
  }) async {
    final identity = await filesystem.pathIdentity(
      targetPath,
      followLinks: followLinks,
    );
    return DraftPhysicalIdentity(
      volumeId: identity.metadata.volumeId,
      fileId: identity.metadata.fileId,
    );
  }
}

final class _DraftScan {
  const _DraftScan({
    required this.fingerprint,
    required this.files,
    required this.directories,
  });

  final DraftFingerprint fingerprint;
  final List<CapturedDraftFile> files;
  final List<String> directories;
}

sealed class _DraftCaptureException implements Exception {
  const _DraftCaptureException(this.reason);

  final String reason;
}

final class _DraftCaptureChanged extends _DraftCaptureException {
  const _DraftCaptureChanged(super.reason);
}

final class _DraftCaptureInvalid extends _DraftCaptureException {
  const _DraftCaptureInvalid(super.reason);
}

final class _DraftCaptureLimit extends _DraftCaptureException {
  const _DraftCaptureLimit(super.reason);
}

final class _DraftCaptureUnavailable extends _DraftCaptureException {
  const _DraftCaptureUnavailable(super.reason);
}

final class _DraftCaptureCancelled extends _DraftCaptureException {
  const _DraftCaptureCancelled() : super('cancelled');
}

DraftSnapshotFailure<T> _captureFailure<T>(Object error) => switch (error) {
  _DraftCaptureChanged(:final reason) => DraftSnapshotFailure<T>(
    code: DraftSnapshotFailureCode.draftChangedDuringPublish,
    context: <String, Object?>{'reason': reason},
  ),
  _DraftCaptureInvalid(:final reason) => DraftSnapshotFailure<T>(
    code: DraftSnapshotFailureCode.invalidSkill,
    context: <String, Object?>{'reason': reason},
  ),
  _DraftCaptureLimit(:final reason) => DraftSnapshotFailure<T>(
    code: DraftSnapshotFailureCode.skillContentLimitExceeded,
    context: <String, Object?>{'limit': reason},
  ),
  _DraftCaptureCancelled() => DraftSnapshotFailure<T>(
    code: DraftSnapshotFailureCode.operationCancelled,
  ),
  _ => DraftSnapshotFailure<T>(code: DraftSnapshotFailureCode.ioFailure),
};

void _throwIfCancelled(DraftCaptureRequest request) {
  if (request.isCancelled?.call() ?? false) {
    throw const _DraftCaptureCancelled();
  }
}

Future<List<FileSystemEntity>> _directoryChildren(String directoryPath) async {
  final children = await Directory(
    directoryPath,
  ).list(followLinks: false).toList();
  children.sort(
    (left, right) =>
        path.basename(left.path).compareTo(path.basename(right.path)),
  );
  return children;
}

bool _sameDirectoryListing(
  List<FileSystemEntity> before,
  List<FileSystemEntity> after,
) {
  if (before.length != after.length) return false;
  for (var index = 0; index < before.length; index += 1) {
    if (path.basename(before[index].path) != path.basename(after[index].path)) {
      return false;
    }
  }
  return true;
}

bool _sameStat(FileStat before, FileStat after) =>
    before.type == after.type &&
    before.size == after.size &&
    before.mode == after.mode &&
    _modifiedMicros(before) == _modifiedMicros(after);

int _modifiedMicros(FileStat stat) =>
    stat.modified.toUtc().microsecondsSinceEpoch;

int _compareEvidence(DraftEntryEvidence left, DraftEntryEvidence right) {
  final pathOrder = left.relativePath.compareTo(right.relativePath);
  if (pathOrder != 0) return pathOrder;
  return left.kind.index.compareTo(right.kind.index);
}

String _portableSegmentKey(String segment) =>
    unicode.nfkc(unicode.nfc(segment).toUpperCase());
