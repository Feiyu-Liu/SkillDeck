import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as path;

import 'filesystem_primitives.dart';
import 'posix_filesystem_primitives.dart';
import 'windows_filesystem_primitives.dart';
import 'workspace_path_identity.dart';

enum DurableEntryKind { file, directory, symbolicLink }

final class StagedDirectoryFile {
  const StagedDirectoryFile({
    required this.relativePath,
    required this.bytes,
    required this.isExecutable,
  });

  final String relativePath;
  final List<int> bytes;
  final bool isExecutable;
}

typedef DurablePathVerifier = FutureOr<void> Function(String path);

typedef StagingNameGenerator =
    String Function(String destinationPath, String purpose, int attempt);

enum DurablePathMutationBarrier {
  beforeMutation,
  afterDestinationDisplaced,
  afterCandidatePublished,
  afterVerification,
}

typedef DurablePathMutationObserver =
    FutureOr<void> Function(
      DurablePathMutationBarrier barrier,
      String destinationPath,
    );

final class TargetVolumeStagingPath {
  const TargetVolumeStagingPath({
    required this.path,
    required this.destinationPath,
    required this.kind,
  });

  final String path;
  final String destinationPath;
  final DurableEntryKind kind;
}

final class ReadOnlyPermissionFailure {
  const ReadOnlyPermissionFailure({required this.path});

  final String path;
}

final class DurablePublication {
  DurablePublication({
    required this.destinationPath,
    required this.candidatePath,
    required this.kind,
    required this.destinationPreviouslyExisted,
    required this.displacedPath,
    required this.usedAtomicExchange,
    List<ReadOnlyPermissionFailure> readOnlyPermissionFailures = const [],
  }) : readOnlyPermissionFailures = List.unmodifiable(
         readOnlyPermissionFailures,
       );

  final String destinationPath;
  final String candidatePath;
  final DurableEntryKind kind;
  final bool destinationPreviouslyExisted;
  final String? displacedPath;
  final bool usedAtomicExchange;
  final List<ReadOnlyPermissionFailure> readOnlyPermissionFailures;
}

abstract interface class DurableWorkspaceFilesystem {
  Future<void> ensureDirectory(String directoryPath);

  /// Resolves links in the target's parent path while preserving the final
  /// entry itself. Recovery uses the returned path so a parent link cannot be
  /// retargeted between capture and apply, and a final Skill link is never
  /// followed when it is replaced or removed.
  Future<String> resolveMutationPath(String targetPath);

  Future<TargetVolumeStagingPath> createSiblingStagingPath(
    String destinationPath, {
    required DurableEntryKind kind,
    String purpose,
  });

  Future<void> writeDurableFile(String filePath, List<int> bytes);

  /// Materializes an unpublished directory and establishes one durability
  /// barrier after every entry has been written.
  ///
  /// Callers must not publish or reference [rootPath] until this Future
  /// completes. Journal, manifest, and backup files that become authoritative
  /// individually must continue to use [writeDurableFile].
  Future<void> materializeStagedDirectory({
    required String rootPath,
    required Iterable<StagedDirectoryFile> files,
    Iterable<String> directories = const <String>[],
    void Function()? checkCancelled,
  });

  Future<void> flushFile(String filePath);

  Future<void> flushDirectory(String directoryPath);

  Future<void> flushRecursively(String targetPath);

  Future<List<ReadOnlyPermissionFailure>> makeReadOnly(
    String targetPath,
    DurableEntryKind kind,
  );

  Future<WorkspacePathIdentity> pathIdentity(
    String targetPath, {
    bool followLinks,
  });

  Future<DurablePublication> publish({
    required String candidatePath,
    required String destinationPath,
    required DurableEntryKind kind,
    required DurablePathVerifier verify,
    bool makeReadOnly,
    bool requirePlainDirectory,
    String? knownDisplacedPath,
    DurablePathMutationObserver? onMutationBarrier,
  });

  /// Durably moves an existing entry to a caller-owned recovery sibling.
  ///
  /// The explicit sibling closes the crash window in which an internally
  /// generated rollback path would otherwise be undiscoverable after restart.
  Future<void> displace({
    required String destinationPath,
    required String displacedPath,
    required DurableEntryKind kind,
    required DurablePathVerifier verify,
    DurablePathMutationObserver? onMutationBarrier,
  });

  Future<void> rollbackPublication(
    DurablePublication publication, {
    DurablePathVerifier? verifyRestored,
  });

  Future<void> createSymbolicLink({
    required String linkPath,
    required String targetPath,
  });

  /// Applies only portable executable intent before a read-only publication.
  Future<void> setExecutableIntent(String filePath, bool executable);

  Future<void> removeOwnedPath({
    required String targetPath,
    required String ownerRoot,
  });
}

final class PlatformDurableWorkspaceFilesystem
    implements DurableWorkspaceFilesystem {
  PlatformDurableWorkspaceFilesystem({
    FilesystemPrimitives? primitives,
    WorkspacePathIdentityResolver? identityResolver,
    Random? random,
    StagingNameGenerator? stagingNameGenerator,
  }) : _primitives = primitives ?? _platformPrimitives(),
       _random = random ?? Random.secure(),
       _stagingNameGenerator = stagingNameGenerator,
       _identityResolver =
           identityResolver ??
           WorkspacePathIdentityResolver(
             primitives: primitives ?? _platformPrimitives(),
           );

  PlatformDurableWorkspaceFilesystem.withPrimitives({
    required FilesystemPrimitives primitives,
    WorkspacePathFlavor? pathFlavor,
    Random? random,
    StagingNameGenerator? stagingNameGenerator,
  }) : _primitives = primitives,
       _identityResolver = WorkspacePathIdentityResolver(
         primitives: primitives,
         flavor: pathFlavor,
       ),
       _random = random ?? Random.secure(),
       _stagingNameGenerator = stagingNameGenerator;

  static const int _stagingAttempts = 100;
  static const int _windowsRetryAttempts = 500;
  static const Duration _windowsRetryDelay = Duration(milliseconds: 2);
  static const Duration _readOnlyTreeSettleDelay = Duration(milliseconds: 10);

  final FilesystemPrimitives _primitives;
  final WorkspacePathIdentityResolver _identityResolver;
  final Random _random;
  final StagingNameGenerator? _stagingNameGenerator;

  @override
  Future<void> ensureDirectory(String directoryPath) async {
    final normalized = path.normalize(path.absolute(directoryPath));
    final missing = <String>[];
    var cursor = normalized;
    while (true) {
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        break;
      }
      if (type != FileSystemEntityType.notFound) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.createDirectory,
          message: 'A non-directory entry blocks directory creation.',
          path: cursor,
        );
      }
      missing.add(cursor);
      final parent = path.dirname(cursor);
      if (parent == cursor) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.createDirectory,
          message: 'No existing ancestor can anchor directory creation.',
          path: normalized,
        );
      }
      cursor = parent;
    }

    for (final directory in missing.reversed) {
      await Directory(directory).create();
      await _primitives.flushDirectory(directory);
      await _primitives.flushDirectory(path.dirname(directory));
    }
  }

  @override
  Future<String> resolveMutationPath(String targetPath) async {
    final target = path.normalize(path.absolute(targetPath));
    final missingSegments = <String>[];
    var cursor = path.dirname(target);
    while (true) {
      final followed = await FileSystemEntity.type(cursor, followLinks: true);
      if (followed == FileSystemEntityType.directory) {
        final resolved = path.normalize(
          await Directory(cursor).resolveSymbolicLinks(),
        );
        return path.joinAll(<String>[
          resolved,
          ...missingSegments.reversed,
          path.basename(target),
        ]);
      }
      final lexical = await FileSystemEntity.type(cursor, followLinks: false);
      if (followed != FileSystemEntityType.notFound ||
          lexical != FileSystemEntityType.notFound) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.inspectPath,
          message: 'A non-directory or broken link blocks path resolution.',
          path: cursor,
        );
      }
      final parent = path.dirname(cursor);
      if (parent == cursor) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.inspectPath,
          message: 'No existing ancestor can anchor path resolution.',
          path: target,
        );
      }
      missingSegments.add(path.basename(cursor));
      cursor = parent;
    }
  }

  @override
  Future<TargetVolumeStagingPath> createSiblingStagingPath(
    String destinationPath, {
    required DurableEntryKind kind,
    String purpose = 'stage',
  }) async {
    final destination = path.normalize(path.absolute(destinationPath));
    final parent = path.dirname(destination);
    await ensureDirectory(parent);
    final safePurpose = _safePurpose(purpose);
    for (var attempt = 0; attempt < _stagingAttempts; attempt += 1) {
      final name =
          _stagingNameGenerator?.call(destination, safePurpose, attempt) ??
          _shortSiblingName();
      final stagingPath = path.join(parent, name);
      try {
        await File(stagingPath).create(exclusive: true);
      } on PathExistsException {
        continue;
      }
      try {
        switch (kind) {
          case DurableEntryKind.file:
            final handle = await File(stagingPath).open(mode: FileMode.write);
            try {
              await handle.flush();
            } finally {
              await handle.close();
            }
            await _primitives.flushFile(stagingPath);
            break;
          case DurableEntryKind.directory:
            await File(stagingPath).delete();
            await Directory(stagingPath).create();
            await _primitives.flushDirectory(stagingPath);
            break;
          case DurableEntryKind.symbolicLink:
            await File(stagingPath).delete();
            await _primitives.flushDirectory(parent);
            return TargetVolumeStagingPath(
              path: stagingPath,
              destinationPath: destination,
              kind: kind,
            );
        }
        await _primitives.flushDirectory(parent);
        return TargetVolumeStagingPath(
          path: stagingPath,
          destinationPath: destination,
          kind: kind,
        );
      } catch (error, stackTrace) {
        await _cleanupFailedStaging(stagingPath);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw DurableFilesystemException(
      operation: DurableFilesystemOperation.createStagingPath,
      message: 'Unable to allocate a unique target-volume staging path.',
      path: destination,
    );
  }

  @override
  Future<void> writeDurableFile(String filePath, List<int> bytes) async {
    final normalized = path.normalize(path.absolute(filePath));
    await ensureDirectory(path.dirname(normalized));
    RandomAccessFile? handle;
    try {
      handle = await File(normalized).open(mode: FileMode.write);
      await handle.writeFrom(bytes);
      await handle.truncate(bytes.length);
      await handle.flush();
      await handle.close();
      handle = null;
      await _primitives.flushFile(normalized);
      await _primitives.flushDirectory(path.dirname(normalized));
    } on FileSystemException catch (error) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.flushFile,
        message: 'Unable to write and flush the file.',
        path: normalized,
        platformCode: error.osError?.errorCode,
      );
    } finally {
      await handle?.close();
    }
  }

  @override
  Future<void> materializeStagedDirectory({
    required String rootPath,
    required Iterable<StagedDirectoryFile> files,
    Iterable<String> directories = const <String>[],
    void Function()? checkCancelled,
  }) async {
    final root = path.normalize(path.absolute(rootPath));
    final prepared = _prepareStagedDirectoryEntries(
      root: root,
      files: files,
      directories: directories,
    );
    checkCancelled?.call();
    await ensureDirectory(root);
    for (final directory in prepared.directories) {
      checkCancelled?.call();
      await ensureDirectory(directory);
    }
    for (final file in prepared.files) {
      checkCancelled?.call();
      final parent = path.dirname(file.path);
      // Recheck the complete no-follow directory chain immediately before
      // opening each file. This preserves the staged-tree batching benefit
      // without allowing an existing root or intermediate symbolic link to
      // redirect writes outside the unpublished candidate.
      await ensureDirectory(parent);
      await _writeStagedFile(file.path, file.bytes);
      await _applyExecutableIntent(file.path, file.isExecutable, flush: false);
    }
    checkCancelled?.call();
    await flushRecursively(root);
  }

  Future<void> _writeStagedFile(String filePath, List<int> bytes) async {
    await _primitives.writeNewFile(filePath, bytes);
  }

  @override
  Future<void> flushFile(String filePath) => _primitives.flushFile(filePath);

  @override
  Future<void> flushDirectory(String directoryPath) =>
      _primitives.flushDirectory(directoryPath);

  @override
  Future<void> flushRecursively(String targetPath) async {
    final normalized = path.normalize(path.absolute(targetPath));
    final temporarilyWritable = <String>[];
    Object? failure;
    StackTrace? failureStack;
    try {
      await _makeReadOnlyFilesWritable(normalized, temporarilyWritable);
      if (temporarilyWritable.isNotEmpty) {
        await Future<void>.delayed(_readOnlyTreeSettleDelay);
      }
      await _flushEntry(normalized);
    } on Object catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }

    Object? restorationFailure;
    StackTrace? restorationStack;
    for (final filePath in temporarilyWritable.reversed) {
      try {
        await _primitives.applyReadOnly(filePath, true);
      } on Object catch (error, stackTrace) {
        restorationFailure ??= error;
        restorationStack ??= stackTrace;
      }
    }
    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
    if (restorationFailure != null) {
      Error.throwWithStackTrace(restorationFailure, restorationStack!);
    }
  }

  Future<void> _makeReadOnlyFilesWritable(
    String targetPath,
    List<String> temporarilyWritable,
  ) async {
    final ioTarget = _platformIoPath(targetPath);
    final type = await FileSystemEntity.type(ioTarget, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        if (await _primitives.captureReadOnly(targetPath) == true) {
          await _primitives.applyReadOnly(targetPath, false);
          temporarilyWritable.add(targetPath);
        }
        return;
      case FileSystemEntityType.directory:
        final entries = await Directory(
          ioTarget,
        ).list(followLinks: false).toList();
        entries.sort((left, right) => left.path.compareTo(right.path));
        for (final entry in entries) {
          await _makeReadOnlyFilesWritable(entry.path, temporarilyWritable);
        }
        return;
      case FileSystemEntityType.link || FileSystemEntityType.notFound:
        return;
      default:
        return;
    }
  }

  Future<void> _flushEntry(String targetPath) async {
    final ioTarget = _platformIoPath(targetPath);
    final type = await FileSystemEntity.type(ioTarget, followLinks: false);
    switch (type) {
      case FileSystemEntityType.file:
        await _primitives.flushFile(targetPath);
        return;
      case FileSystemEntityType.directory:
        final entries = await Directory(
          ioTarget,
        ).list(followLinks: false).toList();
        entries.sort((left, right) => left.path.compareTo(right.path));
        for (final entry in entries) {
          await _flushEntry(entry.path);
        }
        await _primitives.flushDirectory(targetPath);
        return;
      case FileSystemEntityType.link:
        // A symbolic-link entry has no independently flushable byte stream.
        // Its containing directory is the durability boundary.
        return;
      case FileSystemEntityType.notFound:
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.flushTree,
          message: 'The durability candidate no longer exists.',
          path: targetPath,
        );
      default:
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.flushTree,
          message: 'Unsupported filesystem entry in durability candidate.',
          path: targetPath,
        );
    }
  }

  @override
  Future<WorkspacePathIdentity> pathIdentity(
    String targetPath, {
    bool followLinks = true,
  }) => _identityResolver.resolve(targetPath, followLinks: followLinks);

  @override
  Future<DurablePublication> publish({
    required String candidatePath,
    required String destinationPath,
    required DurableEntryKind kind,
    required DurablePathVerifier verify,
    bool makeReadOnly = false,
    bool requirePlainDirectory = true,
    String? knownDisplacedPath,
    DurablePathMutationObserver? onMutationBarrier,
  }) async {
    final candidate = path.normalize(path.absolute(candidatePath));
    final destination = path.normalize(path.absolute(destinationPath));
    final parent = path.dirname(destination);
    if (!_identityResolver.lexicallyEquals(path.dirname(candidate), parent)) {
      throw ArgumentError.value(
        candidatePath,
        'candidatePath',
        'must be a direct sibling of the destination',
      );
    }
    final requestedDisplaced = knownDisplacedPath == null
        ? null
        : path.normalize(path.absolute(knownDisplacedPath));
    if (requestedDisplaced != null &&
        (!_identityResolver.lexicallyEquals(
              path.dirname(requestedDisplaced),
              parent,
            ) ||
            _identityResolver.lexicallyEquals(requestedDisplaced, candidate) ||
            _identityResolver.lexicallyEquals(
              requestedDisplaced,
              destination,
            ))) {
      throw ArgumentError.value(
        knownDisplacedPath,
        'knownDisplacedPath',
        'must be a distinct direct sibling of the destination',
      );
    }
    final candidateParentIdentity = await pathIdentity(path.dirname(candidate));
    final destinationParentIdentity = await pathIdentity(parent);
    if (!candidateParentIdentity.sameObjectAs(destinationParentIdentity)) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.verify,
        message: 'Candidate and destination are not on the same parent.',
        path: destination,
      );
    }

    final expectedType = _fileSystemType(kind);
    final actualType = await FileSystemEntity.type(
      candidate,
      followLinks: false,
    );
    if (actualType != expectedType) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.verify,
        message: 'The candidate has an unexpected filesystem type.',
        path: candidate,
      );
    }
    if (kind == DurableEntryKind.directory && requirePlainDirectory) {
      await _verifyPlainDirectory(candidate);
    }

    await _flushCandidate(candidate, kind);
    await _reopenAndVerify(candidate, kind, verify);
    final candidateIdentity = await pathIdentity(
      candidate,
      followLinks: kind != DurableEntryKind.symbolicLink,
    );

    final destinationType = await FileSystemEntity.type(
      destination,
      followLinks: false,
    );
    final destinationExisted = destinationType != FileSystemEntityType.notFound;
    String? displacedPath;
    var usedExchange = false;
    await onMutationBarrier?.call(
      DurablePathMutationBarrier.beforeMutation,
      destination,
    );
    if (!destinationExisted) {
      await _renameWithRetry(
        parentPath: parent,
        sourceName: path.basename(candidate),
        destinationName: path.basename(destination),
        replaceExisting: false,
      );
      await onMutationBarrier?.call(
        DurablePathMutationBarrier.afterCandidatePublished,
        destination,
      );
    } else if (requestedDisplaced != null) {
      if (await FileSystemEntity.type(requestedDisplaced, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.verify,
          message: 'The requested displaced sibling already exists.',
          path: requestedDisplaced,
        );
      }
      displacedPath = requestedDisplaced;
      await _renameWithRetry(
        parentPath: parent,
        sourceName: path.basename(destination),
        destinationName: path.basename(requestedDisplaced),
        replaceExisting: false,
      );
      await _primitives.flushDirectory(parent);
      await onMutationBarrier?.call(
        DurablePathMutationBarrier.afterDestinationDisplaced,
        destination,
      );
      await _renameWithRetry(
        parentPath: parent,
        sourceName: path.basename(candidate),
        destinationName: path.basename(destination),
        replaceExisting: false,
      );
      await onMutationBarrier?.call(
        DurablePathMutationBarrier.afterCandidatePublished,
        destination,
      );
    } else {
      usedExchange = await _exchangeSameParent(
        parentPath: parent,
        firstName: path.basename(candidate),
        secondName: path.basename(destination),
      );
      if (usedExchange) {
        displacedPath = candidate;
        await onMutationBarrier?.call(
          DurablePathMutationBarrier.afterDestinationDisplaced,
          destination,
        );
        await onMutationBarrier?.call(
          DurablePathMutationBarrier.afterCandidatePublished,
          destination,
        );
      } else {
        displacedPath = await _unusedSiblingPath(destination);
        await _renameWithRetry(
          parentPath: parent,
          sourceName: path.basename(destination),
          destinationName: path.basename(displacedPath),
          replaceExisting: false,
        );
        await _primitives.flushDirectory(parent);
        await onMutationBarrier?.call(
          DurablePathMutationBarrier.afterDestinationDisplaced,
          destination,
        );
        try {
          await _renameWithRetry(
            parentPath: parent,
            sourceName: path.basename(candidate),
            destinationName: path.basename(destination),
            replaceExisting: false,
          );
          await onMutationBarrier?.call(
            DurablePathMutationBarrier.afterCandidatePublished,
            destination,
          );
        } catch (_) {
          await _renameWithRetry(
            parentPath: parent,
            sourceName: path.basename(displacedPath),
            destinationName: path.basename(destination),
            replaceExisting: false,
          );
          await _primitives.flushDirectory(parent);
          rethrow;
        }
      }
    }
    await _primitives.flushDirectory(parent);

    final publication = DurablePublication(
      destinationPath: destination,
      candidatePath: candidate,
      kind: kind,
      destinationPreviouslyExisted: destinationExisted,
      displacedPath: displacedPath,
      usedAtomicExchange: usedExchange,
    );
    try {
      await _reopenAndVerify(destination, kind, verify);
      final publishedIdentity = await pathIdentity(
        destination,
        followLinks: kind != DurableEntryKind.symbolicLink,
      );
      if (!candidateIdentity.sameObjectAs(publishedIdentity)) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.verify,
          message: 'Published path does not identify the verified candidate.',
          path: destination,
        );
      }
      final permissionFailures = makeReadOnly
          ? await this.makeReadOnly(destination, kind)
          : const <ReadOnlyPermissionFailure>[];
      await onMutationBarrier?.call(
        DurablePathMutationBarrier.afterVerification,
        destination,
      );
      return DurablePublication(
        destinationPath: destination,
        candidatePath: candidate,
        kind: kind,
        destinationPreviouslyExisted: destinationExisted,
        displacedPath: displacedPath,
        usedAtomicExchange: usedExchange,
        readOnlyPermissionFailures: permissionFailures,
      );
    } catch (_) {
      await rollbackPublication(publication);
      rethrow;
    }
  }

  @override
  Future<void> displace({
    required String destinationPath,
    required String displacedPath,
    required DurableEntryKind kind,
    required DurablePathVerifier verify,
    DurablePathMutationObserver? onMutationBarrier,
  }) async {
    final destination = path.normalize(path.absolute(destinationPath));
    final displaced = path.normalize(path.absolute(displacedPath));
    final parent = path.dirname(destination);
    if (!_identityResolver.lexicallyEquals(path.dirname(displaced), parent) ||
        _identityResolver.lexicallyEquals(displaced, destination)) {
      throw ArgumentError.value(
        displacedPath,
        'displacedPath',
        'must be a distinct direct sibling of the destination',
      );
    }
    if (await FileSystemEntity.type(displaced, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.verify,
        message: 'The requested displaced sibling already exists.',
        path: displaced,
      );
    }
    if (await FileSystemEntity.type(destination, followLinks: false) !=
        _fileSystemType(kind)) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.verify,
        message: 'The displaced source has an unexpected filesystem type.',
        path: destination,
      );
    }
    await _reopenAndVerify(destination, kind, verify);
    await onMutationBarrier?.call(
      DurablePathMutationBarrier.beforeMutation,
      destination,
    );
    await _renameWithRetry(
      parentPath: parent,
      sourceName: path.basename(destination),
      destinationName: path.basename(displaced),
      replaceExisting: false,
    );
    await _primitives.flushDirectory(parent);
    await onMutationBarrier?.call(
      DurablePathMutationBarrier.afterDestinationDisplaced,
      destination,
    );
    await _reopenAndVerify(displaced, kind, verify);
    await onMutationBarrier?.call(
      DurablePathMutationBarrier.afterVerification,
      destination,
    );
  }

  @override
  Future<void> rollbackPublication(
    DurablePublication publication, {
    DurablePathVerifier? verifyRestored,
  }) async {
    final destination = publication.destinationPath;
    final parent = path.dirname(destination);
    if (!publication.destinationPreviouslyExisted) {
      await _renameWithRetry(
        parentPath: parent,
        sourceName: path.basename(destination),
        destinationName: path.basename(publication.candidatePath),
        replaceExisting: false,
      );
      await _primitives.flushDirectory(parent);
      return;
    }

    final displaced = publication.displacedPath;
    if (displaced == null) {
      throw StateError(
        'A replaced destination must retain its displaced path.',
      );
    }
    if (publication.usedAtomicExchange) {
      final restored = await _exchangeSameParent(
        parentPath: parent,
        firstName: path.basename(destination),
        secondName: path.basename(displaced),
      );
      if (!restored) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.exchange,
          message: 'The atomic replacement could not be exchanged back.',
          path: destination,
        );
      }
    } else {
      final newResidue = publication.candidatePath;
      await _renameWithRetry(
        parentPath: parent,
        sourceName: path.basename(destination),
        destinationName: path.basename(newResidue),
        replaceExisting: false,
      );
      try {
        await _renameWithRetry(
          parentPath: parent,
          sourceName: path.basename(displaced),
          destinationName: path.basename(destination),
          replaceExisting: false,
        );
      } catch (_) {
        await _renameWithRetry(
          parentPath: parent,
          sourceName: path.basename(newResidue),
          destinationName: path.basename(destination),
          replaceExisting: false,
        );
        rethrow;
      }
    }
    await _primitives.flushDirectory(parent);
    if (verifyRestored != null) {
      await verifyRestored(destination);
    }
  }

  @override
  Future<void> createSymbolicLink({
    required String linkPath,
    required String targetPath,
  }) async {
    final normalized = path.normalize(path.absolute(linkPath));
    await ensureDirectory(path.dirname(normalized));
    await Link(normalized).create(targetPath);
    final actualTarget = await Link(normalized).target();
    if (actualTarget != targetPath) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.createLink,
        message: 'The symbolic link target could not be verified.',
        path: normalized,
      );
    }
    await _primitives.flushDirectory(path.dirname(normalized));
  }

  @override
  Future<void> setExecutableIntent(String filePath, bool executable) =>
      _applyExecutableIntent(filePath, executable, flush: true);

  @override
  Future<List<ReadOnlyPermissionFailure>> makeReadOnly(
    String targetPath,
    DurableEntryKind kind,
  ) async {
    final normalized = path.normalize(path.absolute(targetPath));
    final failures = await _makeReadOnlyBestEffort(normalized, kind);
    await _flushAfterPermissionChanges(normalized, kind);
    return failures;
  }

  Future<void> _applyExecutableIntent(
    String filePath,
    bool executable, {
    required bool flush,
  }) async {
    if (Platform.isWindows) return;
    final normalized = path.normalize(path.absolute(filePath));
    final metadata = await _primitives.stat(normalized, followLinks: false);
    if (metadata.kind != FilesystemEntryKind.file) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.applyPermissions,
        message: 'Executable intent applies only to regular files.',
        path: normalized,
      );
    }
    final current = (metadata.posixMode ?? 0x180) & 0x1ff;
    final mode = executable
        ? current | PosixFilesystemPrimitives.executablePermissionMask
        : current & ~PosixFilesystemPrimitives.executablePermissionMask;
    await _primitives.applyPosixMode(normalized, mode);
    if (flush) {
      await _primitives.flushFile(normalized);
      await _primitives.flushDirectory(path.dirname(normalized));
    }
  }

  @override
  Future<void> removeOwnedPath({
    required String targetPath,
    required String ownerRoot,
  }) async {
    final target = path.normalize(path.absolute(targetPath));
    final root = path.normalize(path.absolute(ownerRoot));
    if (_identityResolver.lexicallyEquals(target, root) ||
        !path.isWithin(root, target)) {
      throw ArgumentError.value(
        targetPath,
        'targetPath',
        'must be strictly contained by ownerRoot',
      );
    }
    final ioTarget = _platformIoPath(target);
    final type = await FileSystemEntity.type(ioTarget, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    final containment = await _captureOwnedContainment(
      ownerRoot: root,
      targetPath: target,
    );
    await _verifyOwnedContainment(containment);
    await _makeOwnedWritable(target, type);
    await _verifyOwnedContainment(containment);
    await FileSystemEntity.type(ioTarget, followLinks: false).then((entryType) {
      return switch (entryType) {
        FileSystemEntityType.file => File(ioTarget).delete(),
        FileSystemEntityType.directory => Directory(
          ioTarget,
        ).delete(recursive: true),
        FileSystemEntityType.link => Link(ioTarget).delete(),
        _ => throw DurableFilesystemException(
          operation: DurableFilesystemOperation.cleanup,
          message: 'Unsupported owned cleanup entry.',
          path: target,
        ),
      };
    });
    await _primitives.flushDirectory(path.dirname(target));
  }

  Future<_OwnedPathContainment> _captureOwnedContainment({
    required String ownerRoot,
    required String targetPath,
  }) async {
    final relative = path.relative(targetPath, from: ownerRoot);
    final segments = path.split(relative);
    final components = <_OwnedPathComponent>[];
    var current = ownerRoot;
    final rootIdentity = await pathIdentity(ownerRoot, followLinks: false);
    if (rootIdentity.metadata.kind != FilesystemEntryKind.directory) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.cleanup,
        message: 'The owned cleanup root is not a directory.',
        path: ownerRoot,
      );
    }
    components.add(
      _OwnedPathComponent(
        path: ownerRoot,
        identity: rootIdentity,
        kind: FilesystemEntryKind.directory,
      ),
    );
    for (var index = 0; index < segments.length; index += 1) {
      current = path.join(current, segments[index]);
      final identity = await pathIdentity(current, followLinks: false);
      final isTarget = index == segments.length - 1;
      if (!isTarget &&
          identity.metadata.kind != FilesystemEntryKind.directory) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.cleanup,
          message: 'Owned cleanup cannot traverse a non-directory component.',
          path: current,
        );
      }
      components.add(
        _OwnedPathComponent(
          path: current,
          identity: identity,
          kind: identity.metadata.kind,
        ),
      );
    }
    return _OwnedPathContainment(components);
  }

  Future<void> _verifyOwnedContainment(
    _OwnedPathContainment containment,
  ) async {
    for (final component in containment.components) {
      final current = await pathIdentity(component.path, followLinks: false);
      if (current.metadata.kind != component.kind ||
          !current.sameObjectAs(component.identity)) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.cleanup,
          message: 'Owned cleanup path identity changed before deletion.',
          path: component.path,
        );
      }
    }
  }

  Future<void> _cleanupFailedStaging(String stagingPath) async {
    try {
      final ioStagingPath = _platformIoPath(stagingPath);
      final type = await FileSystemEntity.type(
        ioStagingPath,
        followLinks: false,
      );
      switch (type) {
        case FileSystemEntityType.file:
          await File(ioStagingPath).delete();
          break;
        case FileSystemEntityType.directory:
          await Directory(ioStagingPath).delete(recursive: true);
          break;
        case FileSystemEntityType.link:
          await Link(ioStagingPath).delete();
          break;
        case FileSystemEntityType.notFound:
          return;
        default:
          return;
      }
      await _primitives.flushDirectory(path.dirname(stagingPath));
    } catch (_) {
      // The original durability failure remains the actionable failure.
    }
  }

  Future<void> _makeOwnedWritable(
    String targetPath,
    FileSystemEntityType type,
  ) async {
    if (type == FileSystemEntityType.link) {
      return;
    }
    if (type == FileSystemEntityType.directory) {
      await _setOwnedWritable(targetPath, directory: true);
      final entries = await Directory(
        _platformIoPath(targetPath),
      ).list(followLinks: false).toList();
      for (final entry in entries) {
        final entryType = await FileSystemEntity.type(
          entry.path,
          followLinks: false,
        );
        await _makeOwnedWritable(entry.path, entryType);
      }
      return;
    }
    await _setOwnedWritable(targetPath, directory: false);
  }

  Future<void> _setOwnedWritable(
    String targetPath, {
    required bool directory,
  }) async {
    if (Platform.isWindows) {
      await _primitives.applyReadOnly(targetPath, false);
      return;
    }
    final metadata = await _primitives.stat(targetPath, followLinks: false);
    final current = metadata.posixMode ?? (directory ? 0x1c0 : 0x180);
    await _primitives.applyPosixMode(
      targetPath,
      current | (directory ? 0x1c0 : 0x180),
    );
  }

  Future<void> _flushCandidate(String candidate, DurableEntryKind kind) async {
    switch (kind) {
      case DurableEntryKind.file:
        await _primitives.flushFile(candidate);
        return;
      case DurableEntryKind.directory:
        await flushRecursively(candidate);
        return;
      case DurableEntryKind.symbolicLink:
        await _primitives.flushDirectory(path.dirname(candidate));
        return;
    }
  }

  Future<void> _flushAfterPermissionChanges(
    String candidate,
    DurableEntryKind kind,
  ) async {
    if (Platform.isWindows) {
      if (kind == DurableEntryKind.directory) {
        await _flushDirectoriesOnly(candidate);
      }
      await _primitives.flushDirectory(path.dirname(candidate));
      return;
    }
    await _flushCandidate(candidate, kind);
    await _primitives.flushDirectory(path.dirname(candidate));
  }

  Future<void> _flushDirectoriesOnly(String directoryPath) async {
    final entries = await Directory(
      _platformIoPath(directoryPath),
    ).list(followLinks: false).toList();
    for (final entry in entries) {
      if (await FileSystemEntity.type(entry.path, followLinks: false) ==
          FileSystemEntityType.directory) {
        await _flushDirectoriesOnly(entry.path);
      }
    }
    await _primitives.flushDirectory(directoryPath);
  }

  Future<List<ReadOnlyPermissionFailure>> _makeReadOnlyBestEffort(
    String candidate,
    DurableEntryKind kind,
  ) async {
    final failures = <ReadOnlyPermissionFailure>[];
    Future<void> apply(String target, FileSystemEntityType type) async {
      if (type == FileSystemEntityType.link) {
        return;
      }
      if (type == FileSystemEntityType.directory) {
        final entries = await Directory(
          _platformIoPath(target),
        ).list(followLinks: false).toList();
        for (final entry in entries) {
          await apply(
            entry.path,
            await FileSystemEntity.type(entry.path, followLinks: false),
          );
        }
      }
      try {
        if (Platform.isWindows) {
          await _primitives.applyReadOnly(target, true);
        } else {
          final metadata = await _primitives.stat(target, followLinks: false);
          final executable =
              (metadata.posixMode ?? 0) &
                  PosixFilesystemPrimitives.executablePermissionMask !=
              0;
          await _primitives.applyPosixMode(
            target,
            type == FileSystemEntityType.directory || executable
                ? 0x16d
                : 0x124,
          );
        }
      } on FileSystemException {
        failures.add(ReadOnlyPermissionFailure(path: target));
      }
    }

    await apply(candidate, _fileSystemType(kind));
    return failures;
  }

  Future<void> _verifyPlainDirectory(String root) async {
    await for (final entity in Directory(
      _platformIoPath(root),
    ).list(recursive: true, followLinks: false)) {
      if (path.basename(entity.path).toUpperCase() == '.GIT') {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.verify,
          message: 'Plain materializations cannot contain Git metadata.',
          path: entity.path,
        );
      }
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.verify,
          message: 'Plain materializations cannot contain symbolic links.',
          path: entity.path,
        );
      }
      if (type != FileSystemEntityType.file &&
          type != FileSystemEntityType.directory) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.verify,
          message: 'Plain materialization contains an unsupported entry.',
          path: entity.path,
        );
      }
    }
  }

  String _platformIoPath(String targetPath) => Platform.isWindows
      ? WindowsFilesystemPrimitives.extendedPath(targetPath)
      : targetPath;

  Future<void> _reopenAndVerify(
    String targetPath,
    DurableEntryKind kind,
    DurablePathVerifier verify,
  ) async {
    final metadata = await _primitives.stat(
      targetPath,
      followLinks: kind != DurableEntryKind.symbolicLink,
    );
    if (metadata.kind != _metadataKind(kind)) {
      throw DurableFilesystemException(
        operation: DurableFilesystemOperation.verify,
        message: 'Reopened candidate has an unexpected filesystem type.',
        path: targetPath,
      );
    }
    await verify(targetPath);
  }

  Future<void> _renameWithRetry({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  }) async {
    final sourcePath = path.join(parentPath, sourceName);
    final destinationPath = path.join(parentPath, destinationName);
    final originalMode = await _makeMacOsDirectoryRenameable(sourcePath);
    var renamed = false;
    try {
      for (var attempt = 1; attempt <= _windowsRetryAttempts; attempt += 1) {
        try {
          await _primitives.renameSameParent(
            parentPath: parentPath,
            sourceName: sourceName,
            destinationName: destinationName,
            replaceExisting: replaceExisting,
          );
          renamed = true;
          await _restoreMacOsDirectoryMode(destinationPath, originalMode);
          return;
        } on DurableFilesystemException catch (error) {
          if (!Platform.isWindows ||
              !_retryableWindowsRename(error.platformCode) ||
              attempt == _windowsRetryAttempts) {
            rethrow;
          }
          await Future<void>.delayed(_windowsRetryDelay);
        }
      }
    } catch (_) {
      await _restoreMacOsDirectoryModeBestEffort(
        renamed ? destinationPath : sourcePath,
        originalMode,
      );
      rethrow;
    }
  }

  Future<bool> _exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  }) async {
    final firstPath = path.join(parentPath, firstName);
    final secondPath = path.join(parentPath, secondName);
    final firstMode = await _makeMacOsDirectoryRenameable(firstPath);
    int? secondMode;
    var exchanged = false;
    try {
      secondMode = await _makeMacOsDirectoryRenameable(secondPath);
      exchanged = await _primitives.exchangeSameParent(
        parentPath: parentPath,
        firstName: firstName,
        secondName: secondName,
      );
      await _restoreMacOsDirectoryMode(
        exchanged ? secondPath : firstPath,
        firstMode,
      );
      await _restoreMacOsDirectoryMode(
        exchanged ? firstPath : secondPath,
        secondMode,
      );
      return exchanged;
    } catch (_) {
      await _restoreMacOsDirectoryModeBestEffort(
        exchanged ? secondPath : firstPath,
        firstMode,
      );
      await _restoreMacOsDirectoryModeBestEffort(
        exchanged ? firstPath : secondPath,
        secondMode,
      );
      rethrow;
    }
  }

  Future<int?> _makeMacOsDirectoryRenameable(String targetPath) async {
    if (!Platform.isMacOS) return null;
    final metadata = await _primitives.stat(targetPath, followLinks: false);
    final mode = metadata.posixMode;
    if (metadata.kind != FilesystemEntryKind.directory ||
        mode == null ||
        mode & 0x80 != 0) {
      return null;
    }
    await _primitives.applyPosixMode(targetPath, mode | 0x80);
    try {
      await _primitives.flushDirectory(targetPath);
    } catch (_) {
      await _restoreMacOsDirectoryModeBestEffort(targetPath, mode);
      rethrow;
    }
    return mode;
  }

  Future<void> _restoreMacOsDirectoryMode(String targetPath, int? mode) async {
    if (mode == null) return;
    await _primitives.applyPosixMode(targetPath, mode);
    await _primitives.flushDirectory(targetPath);
  }

  Future<void> _restoreMacOsDirectoryModeBestEffort(
    String targetPath,
    int? mode,
  ) async {
    try {
      await _restoreMacOsDirectoryMode(targetPath, mode);
    } on Object {
      // Preserve the namespace or durability failure that triggered recovery.
    }
  }

  Future<String> _unusedSiblingPath(String destination) async {
    final parent = path.dirname(destination);
    for (var attempt = 0; attempt < _stagingAttempts; attempt += 1) {
      final candidate = path.join(parent, _shortSiblingName());
      if (await FileSystemEntity.type(candidate, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return candidate;
      }
    }
    throw DurableFilesystemException(
      operation: DurableFilesystemOperation.createStagingPath,
      message: 'Unable to reserve a rollback sibling path.',
      path: destination,
    );
  }

  static String _safePurpose(String purpose) {
    final safe = purpose
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'stage' : safe;
  }

  String _shortSiblingName() =>
      '.s-${_random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0')}';

  static bool _retryableWindowsRename(int? error) =>
      error == 2 || error == 5 || error == 32 || error == 33;

  static FileSystemEntityType _fileSystemType(DurableEntryKind kind) =>
      switch (kind) {
        DurableEntryKind.file => FileSystemEntityType.file,
        DurableEntryKind.directory => FileSystemEntityType.directory,
        DurableEntryKind.symbolicLink => FileSystemEntityType.link,
      };

  static FilesystemEntryKind _metadataKind(DurableEntryKind kind) =>
      switch (kind) {
        DurableEntryKind.file => FilesystemEntryKind.file,
        DurableEntryKind.directory => FilesystemEntryKind.directory,
        DurableEntryKind.symbolicLink => FilesystemEntryKind.symbolicLink,
      };

  static FilesystemPrimitives _platformPrimitives() => Platform.isWindows
      ? const WindowsFilesystemPrimitives()
      : const PosixFilesystemPrimitives();
}

final class _OwnedPathContainment {
  _OwnedPathContainment(List<_OwnedPathComponent> components)
    : components = List.unmodifiable(components);

  final List<_OwnedPathComponent> components;
}

final class _PreparedStagedDirectory {
  const _PreparedStagedDirectory({
    required this.directories,
    required this.files,
  });

  final List<String> directories;
  final List<_PreparedStagedFile> files;
}

final class _PreparedStagedFile {
  const _PreparedStagedFile({
    required this.path,
    required this.bytes,
    required this.isExecutable,
  });

  final String path;
  final List<int> bytes;
  final bool isExecutable;
}

_PreparedStagedDirectory _prepareStagedDirectoryEntries({
  required String root,
  required Iterable<StagedDirectoryFile> files,
  required Iterable<String> directories,
}) {
  final preparedDirectories = <String>[];
  final preparedFiles = <_PreparedStagedFile>[];
  final directoryKeys = <String>{};
  final fileKeys = <String>{};

  for (final relativePath in directories) {
    final target = _stagedChild(root, relativePath);
    final key = _stagedPathKey(target);
    if (!directoryKeys.add(key)) {
      throw _invalidStagedEntry(
        relativePath,
        'A staged directory path is duplicated.',
      );
    }
    preparedDirectories.add(target);
  }
  for (final file in files) {
    final target = _stagedChild(root, file.relativePath);
    final key = _stagedPathKey(target);
    if (!fileKeys.add(key)) {
      throw _invalidStagedEntry(
        file.relativePath,
        'A staged file path is duplicated.',
      );
    }
    preparedFiles.add(
      _PreparedStagedFile(
        path: target,
        bytes: file.bytes,
        isExecutable: file.isExecutable,
      ),
    );
  }

  if (directoryKeys.intersection(fileKeys).isNotEmpty) {
    throw _invalidStagedEntry(
      root,
      'A staged path cannot be both a file and a directory.',
    );
  }
  for (final target in <String>[
    ...preparedDirectories,
    ...preparedFiles.map((file) => file.path),
  ]) {
    var parent = path.dirname(target);
    while (path.isWithin(root, parent)) {
      if (fileKeys.contains(_stagedPathKey(parent))) {
        throw _invalidStagedEntry(
          target,
          'A staged file cannot contain another entry.',
        );
      }
      parent = path.dirname(parent);
    }
  }

  preparedDirectories.sort((left, right) {
    final depth = path.split(left).length.compareTo(path.split(right).length);
    return depth != 0 ? depth : left.compareTo(right);
  });
  preparedFiles.sort((left, right) => left.path.compareTo(right.path));
  return _PreparedStagedDirectory(
    directories: List.unmodifiable(preparedDirectories),
    files: List.unmodifiable(preparedFiles),
  );
}

String _stagedChild(String root, String relativePath) {
  if (relativePath.isEmpty || path.isAbsolute(relativePath)) {
    throw _invalidStagedEntry(
      relativePath,
      'A staged entry requires a relative child path.',
    );
  }
  final normalized = path.normalize(relativePath);
  if (normalized == '.' ||
      normalized == '..' ||
      path.split(normalized).contains('..')) {
    throw _invalidStagedEntry(
      relativePath,
      'A staged entry cannot escape its directory root.',
    );
  }
  final target = path.normalize(path.join(root, normalized));
  if (!path.isWithin(root, target)) {
    throw _invalidStagedEntry(
      relativePath,
      'A staged entry cannot escape its directory root.',
    );
  }
  return target;
}

String _stagedPathKey(String target) {
  final normalized = path.normalize(path.absolute(target));
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}

DurableFilesystemException _invalidStagedEntry(
  String entryPath,
  String message,
) => DurableFilesystemException(
  operation: DurableFilesystemOperation.verify,
  message: message,
  path: entryPath,
);

final class _OwnedPathComponent {
  const _OwnedPathComponent({
    required this.path,
    required this.identity,
    required this.kind,
  });

  final String path;
  final WorkspacePathIdentity identity;
  final FilesystemEntryKind kind;
}
