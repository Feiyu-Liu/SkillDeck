import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../application/runtime/normalized_skill_tree_hash.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/revision_content.dart';
import '../generated/skills_workspace_bindings_generated.dart' as bindings;

enum RevisionNativeFailureCode {
  invalidArgument,
  notInitialized,
  repositoryFailure,
  objectFailure,
  verificationFailure,
  bufferTooSmall,
  bundleFailure,
  closed,
  unexpectedFailure,
}

final class RevisionNativeException implements Exception {
  const RevisionNativeException({required this.code, required this.operation});

  final RevisionNativeFailureCode code;
  final String operation;

  @override
  String toString() =>
      'RevisionNativeException(operation: $operation, code: ${code.name})';
}

final class RevisionNativeVersion {
  const RevisionNativeVersion(this.major, this.minor, this.revision);

  final int major;
  final int minor;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is RevisionNativeVersion &&
      other.major == major &&
      other.minor == minor &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(major, minor, revision);

  @override
  String toString() => '$major.$minor.$revision';
}

/// Private synchronous boundary around the embedded local-only libgit2.
///
/// Callers must confine an instance to the Revision worker isolate. No native
/// handle, repository path or raw libgit2 diagnostic crosses this boundary.
final class RevisionNativeEngine {
  RevisionNativeEngine._();

  bool _closed = false;

  static RevisionNativeEngine open() {
    _checkStatus(
      bindings.skills_workspace_revision_init(),
      operation: 'initialize',
    );
    return RevisionNativeEngine._();
  }

  RevisionNativeVersion version() {
    _ensureOpen();
    return using((arena) {
      final major = arena<ffi.Int32>();
      final minor = arena<ffi.Int32>();
      final revision = arena<ffi.Int32>();
      _checkStatus(
        bindings.skills_workspace_revision_libgit2_version(
          major,
          minor,
          revision,
        ),
        operation: 'readVersion',
      );
      return RevisionNativeVersion(major.value, minor.value, revision.value);
    });
  }

  void createStore(String repositoryPath) {
    _ensureOpen();
    using((arena) {
      _checkStatus(
        bindings.skills_workspace_revision_store_create(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
        ),
        operation: 'createStore',
      );
    });
  }

  void verifyStore(String repositoryPath) {
    _ensureOpen();
    using((arena) {
      _checkStatus(
        bindings.skills_workspace_revision_store_open_verify(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
        ),
        operation: 'verifyStore',
      );
    });
  }

  String createBlob(String repositoryPath, Uint8List bytes) {
    _ensureOpen();
    return using((arena) {
      final nativeBytes = _copyBytes(bytes, arena);
      final output = arena<ffi.Char>(_oidCapacity);
      _checkStatus(
        bindings.skills_workspace_revision_blob_create(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          nativeBytes,
          bytes.length,
          output,
          _oidCapacity,
        ),
        operation: 'createBlob',
      );
      return output.cast<Utf8>().toDartString();
    });
  }

  String createSingleBlobTree({
    required String repositoryPath,
    required String entryName,
    required String blobOid,
  }) {
    _ensureOpen();
    return using((arena) {
      final output = arena<ffi.Char>(_oidCapacity);
      _checkStatus(
        bindings.skills_workspace_revision_tree_create_single(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          entryName.toNativeUtf8(allocator: arena).cast(),
          blobOid.toNativeUtf8(allocator: arena).cast(),
          output,
          _oidCapacity,
        ),
        operation: 'createSingleBlobTree',
      );
      return output.cast<Utf8>().toDartString();
    });
  }

  RevisionObjectId writeTree(String repositoryPath, NormalizedSkillTree tree) {
    _ensureOpen();
    return using((arena) {
      final count = tree.files.length;
      final paths = arena<ffi.Pointer<ffi.Char>>(count == 0 ? 1 : count);
      final fileBytes = arena<ffi.Pointer<ffi.Uint8>>(count == 0 ? 1 : count);
      final byteCounts = arena<ffi.IntPtr>(count == 0 ? 1 : count);
      final executableFlags = arena<ffi.Int32>(count == 0 ? 1 : count);
      for (var index = 0; index < count; index += 1) {
        final file = tree.files[index];
        paths[index] = file.relativePath.toNativeUtf8(allocator: arena).cast();
        fileBytes[index] = _copyBytes(Uint8List.fromList(file.bytes), arena);
        byteCounts[index] = file.bytes.length;
        executableFlags[index] = file.isExecutable ? 1 : 0;
      }
      final output = arena<ffi.Char>(_oidCapacity);
      _checkStatus(
        bindings.skills_workspace_revision_tree_create(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          paths,
          fileBytes,
          byteCounts,
          executableFlags,
          count,
          output,
          _oidCapacity,
        ),
        operation: 'writeTree',
      );
      return RevisionObjectId(output.cast<Utf8>().toDartString());
    });
  }

  NormalizedSkillTree readTree(
    String repositoryPath,
    RevisionObjectId commitOrTree,
  ) {
    _ensureOpen();
    final listing = _readVariableBufferWithArena(
      operation: 'listTree',
      invoke: (arena, output, capacity, required) =>
          bindings.skills_workspace_revision_tree_list(
            repositoryPath.toNativeUtf8(allocator: arena).cast(),
            commitOrTree.value.toNativeUtf8(allocator: arena).cast(),
            output,
            capacity,
            required,
          ),
    );
    final files = <NormalizedSkillFile>[];
    var byteSize = 0;
    if (listing.isNotEmpty) {
      final records = utf8.decode(listing).split('\n');
      for (final record in records) {
        if (record.isEmpty) continue;
        final fields = record.split('\t');
        if (fields.length != 4) {
          throw const RevisionNativeException(
            code: RevisionNativeFailureCode.verificationFailure,
            operation: 'decodeTreeListing',
          );
        }
        final mode = int.tryParse(fields[1]);
        final expectedSize = int.tryParse(fields[3]);
        if (mode == null || expectedSize == null || expectedSize < 0) {
          throw const RevisionNativeException(
            code: RevisionNativeFailureCode.verificationFailure,
            operation: 'decodeTreeListing',
          );
        }
        if (mode != _gitRegularBlobMode && mode != _gitExecutableBlobMode) {
          throw const RevisionNativeException(
            code: RevisionNativeFailureCode.verificationFailure,
            operation: 'verifyTreeMode',
          );
        }
        final bytes = _readBlob(repositoryPath, fields[2]);
        if (bytes.length != expectedSize) {
          throw const RevisionNativeException(
            code: RevisionNativeFailureCode.verificationFailure,
            operation: 'verifyTreeListing',
          );
        }
        byteSize += bytes.length;
        files.add(
          NormalizedSkillFile(
            relativePath: fields[0],
            bytes: bytes,
            isExecutable: mode == _gitExecutableBlobMode,
          ),
        );
      }
    }
    files.sort(
      (left, right) => left.relativePath.compareTo(right.relativePath),
    );
    return NormalizedSkillTree(
      files: files,
      contentHash: computeNormalizedSkillTreeHash(files),
      byteSize: byteSize,
    );
  }

  Uint8List _readBlob(String repositoryPath, String blobOid) {
    return _readVariableBufferWithArena(
      operation: 'readBlob',
      invoke: (arena, output, capacity, required) =>
          bindings.skills_workspace_revision_blob_read(
            repositoryPath.toNativeUtf8(allocator: arena).cast(),
            blobOid.toNativeUtf8(allocator: arena).cast(),
            output,
            capacity,
            required,
          ),
    );
  }

  RevisionObjectId createCommit({
    required String repositoryPath,
    required RevisionCommitRequest request,
  }) {
    _ensureOpen();
    return using((arena) {
      final parents = _copyObjectIds(request.parents, arena);
      final output = arena<ffi.Char>(_oidCapacity);
      _checkStatus(
        bindings.skills_workspace_revision_commit_create(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          request.tree.value.toNativeUtf8(allocator: arena).cast(),
          parents,
          request.parents.length,
          request.kind.index,
          output,
          _oidCapacity,
        ),
        operation: 'createCommit',
      );
      return RevisionObjectId(output.cast<Utf8>().toDartString());
    });
  }

  String createRootCommit({
    required String repositoryPath,
    required String treeOid,
  }) {
    return createCommit(
      repositoryPath: repositoryPath,
      request: RevisionCommitRequest(
        tree: RevisionObjectId(treeOid),
        parents: const [],
        kind: RevisionCommitKind.initial,
      ),
    ).value;
  }

  void verifyCommit({
    required String repositoryPath,
    required RevisionObjectId commit,
    required RevisionCommitRequest expected,
  }) {
    _ensureOpen();
    using((arena) {
      final parents = _copyObjectIds(expected.parents, arena);
      _checkStatus(
        bindings.skills_workspace_revision_commit_verify(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          commit.value.toNativeUtf8(allocator: arena).cast(),
          expected.tree.value.toNativeUtf8(allocator: arena).cast(),
          parents,
          expected.parents.length,
          expected.kind.index,
        ),
        operation: 'verifyCommit',
      );
    });
  }

  bool isAncestor({
    required String repositoryPath,
    required RevisionObjectId ancestor,
    required RevisionObjectId descendant,
  }) {
    _ensureOpen();
    return using((arena) {
      final output = arena<ffi.Int32>();
      _checkStatus(
        bindings.skills_workspace_revision_commit_is_ancestor(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          ancestor.value.toNativeUtf8(allocator: arena).cast(),
          descendant.value.toNativeUtf8(allocator: arena).cast(),
          output,
        ),
        operation: 'isAncestor',
      );
      return output.value == 1;
    });
  }

  List<RevisionChange> diff({
    required String repositoryPath,
    required RevisionObjectId oldCommit,
    required RevisionObjectId newCommit,
  }) {
    _ensureOpen();
    final encoded = _readVariableBufferWithArena(
      operation: 'diff',
      invoke: (arena, output, capacity, required) =>
          bindings.skills_workspace_revision_diff(
            repositoryPath.toNativeUtf8(allocator: arena).cast(),
            oldCommit.value.toNativeUtf8(allocator: arena).cast(),
            newCommit.value.toNativeUtf8(allocator: arena).cast(),
            output,
            capacity,
            required,
          ),
    );
    if (encoded.isEmpty) return const [];
    return utf8
        .decode(encoded)
        .split('\n')
        .where((line) => line.isNotEmpty)
        .map((line) {
          final fields = line.split('\t');
          if (fields.length != 6) {
            throw const RevisionNativeException(
              code: RevisionNativeFailureCode.verificationFailure,
              operation: 'decodeDiff',
            );
          }
          final oldMode = int.tryParse(fields[3]);
          final newMode = int.tryParse(fields[4]);
          if (oldMode == null || newMode == null) {
            throw const RevisionNativeException(
              code: RevisionNativeFailureCode.verificationFailure,
              operation: 'decodeDiff',
            );
          }
          return RevisionChange(
            kind: switch (fields[0]) {
              'A' => RevisionChangeKind.added,
              'D' => RevisionChangeKind.deleted,
              'R' => RevisionChangeKind.renamed,
              'T' => RevisionChangeKind.typeChanged,
              _ => RevisionChangeKind.modified,
            },
            oldPath: fields[1].isEmpty ? null : fields[1],
            newPath: fields[2].isEmpty ? null : fields[2],
            oldExecutable: oldMode == _gitExecutableBlobMode,
            newExecutable: newMode == _gitExecutableBlobMode,
            binary: fields[5] == '1',
          );
        })
        .toList(growable: false);
  }

  RevisionMergeResult merge({
    required String repositoryPath,
    required RevisionObjectId previousUpstream,
    required RevisionObjectId currentEffective,
    required RevisionObjectId incomingUpstream,
  }) {
    _ensureOpen();
    return using((arena) {
      final repository = repositoryPath
          .toNativeUtf8(allocator: arena)
          .cast<ffi.Char>();
      final previous = previousUpstream.value
          .toNativeUtf8(allocator: arena)
          .cast<ffi.Char>();
      final current = currentEffective.value
          .toNativeUtf8(allocator: arena)
          .cast<ffi.Char>();
      final incoming = incomingUpstream.value
          .toNativeUtf8(allocator: arena)
          .cast<ffi.Char>();
      final treeOutput = arena<ffi.Char>(_oidCapacity);
      final required = arena<ffi.IntPtr>();
      final count = arena<ffi.IntPtr>();
      final initialStatus = bindings.skills_workspace_revision_merge(
        repository,
        previous,
        current,
        incoming,
        treeOutput,
        _oidCapacity,
        ffi.nullptr,
        0,
        required,
        count,
      );
      if (initialStatus == _statusOk) {
        if (count.value != 0 || required.value != 0) {
          throw const RevisionNativeException(
            code: RevisionNativeFailureCode.verificationFailure,
            operation: 'mergeResult',
          );
        }
        return RevisionMergeClean(
          RevisionObjectId(treeOutput.cast<Utf8>().toDartString()),
        );
      }
      if (initialStatus != _statusBufferTooSmall ||
          required.value <= 0 ||
          count.value <= 0) {
        _checkStatus(initialStatus, operation: 'merge');
      }
      final conflicts = arena<ffi.Uint8>(required.value);
      _checkStatus(
        bindings.skills_workspace_revision_merge(
          repository,
          previous,
          current,
          incoming,
          treeOutput,
          _oidCapacity,
          conflicts,
          required.value,
          required,
          count,
        ),
        operation: 'merge',
      );
      final fields = _splitNullTerminated(
        conflicts.asTypedList(required.value),
      );
      if (fields.length != count.value * 3) {
        throw const RevisionNativeException(
          code: RevisionNativeFailureCode.verificationFailure,
          operation: 'decodeMergeConflicts',
        );
      }
      final decoded = <RevisionMergeConflict>[];
      for (var index = 0; index < fields.length; index += 3) {
        decoded.add(
          RevisionMergeConflict(
            ancestorPath: _nullableUtf8(fields[index]),
            currentPath: _nullableUtf8(fields[index + 1]),
            incomingPath: _nullableUtf8(fields[index + 2]),
          ),
        );
      }
      return RevisionMergeConflicted(
        tree: RevisionObjectId(treeOutput.cast<Utf8>().toDartString()),
        conflicts: decoded,
      );
    });
  }

  void createRecoveryPack({
    required String repositoryPath,
    required String bundleStagingPath,
    required List<RevisionObjectId> retainedRoots,
  }) {
    _ensureOpen();
    using((arena) {
      final roots = _copyObjectIds(retainedRoots, arena);
      _checkStatus(
        bindings.skills_workspace_revision_recovery_pack_create(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          bundleStagingPath.toNativeUtf8(allocator: arena).cast(),
          roots,
          retainedRoots.length,
        ),
        operation: 'createRecoveryPack',
      );
    });
  }

  void restoreRecoveryPack({
    required String stagedRepositoryPath,
    required String packPath,
    required String indexPath,
    required List<RevisionObjectId> retainedRoots,
  }) {
    _ensureOpen();
    using((arena) {
      final roots = _copyObjectIds(retainedRoots, arena);
      _checkStatus(
        bindings.skills_workspace_revision_recovery_pack_restore(
          stagedRepositoryPath.toNativeUtf8(allocator: arena).cast(),
          packPath.toNativeUtf8(allocator: arena).cast(),
          indexPath.toNativeUtf8(allocator: arena).cast(),
          roots,
          retainedRoots.length,
        ),
        operation: 'restoreRecoveryPack',
      );
    });
  }

  void replaceRetentionRefs({
    required String repositoryPath,
    required List<RevisionRetentionRef> references,
  }) {
    _ensureOpen();
    using((arena) {
      final names = arena<ffi.Pointer<ffi.Char>>(
        references.isEmpty ? 1 : references.length,
      );
      final targets = arena<ffi.Pointer<ffi.Char>>(
        references.isEmpty ? 1 : references.length,
      );
      for (var index = 0; index < references.length; index += 1) {
        final reference = references[index];
        names[index] = reference.name.toNativeUtf8(allocator: arena).cast();
        targets[index] = reference.target.value
            .toNativeUtf8(allocator: arena)
            .cast();
      }
      _checkStatus(
        bindings.skills_workspace_revision_retention_refs_replace(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          names,
          targets,
          references.length,
        ),
        operation: 'replaceRetentionRefs',
      );
    });
  }

  void verifyRootCommit({
    required String repositoryPath,
    required String commitOid,
    required String entryName,
    required Uint8List expectedBytes,
  }) {
    _ensureOpen();
    using((arena) {
      final nativeBytes = _copyBytes(expectedBytes, arena);
      _checkStatus(
        bindings.skills_workspace_revision_commit_verify_root(
          repositoryPath.toNativeUtf8(allocator: arena).cast(),
          commitOid.toNativeUtf8(allocator: arena).cast(),
          entryName.toNativeUtf8(allocator: arena).cast(),
          nativeBytes,
          expectedBytes.length,
        ),
        operation: 'verifyRootCommit',
      );
    });
  }

  void close() {
    if (_closed) return;
    _checkStatus(
      bindings.skills_workspace_revision_shutdown(),
      operation: 'shutdown',
    );
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw const RevisionNativeException(
        code: RevisionNativeFailureCode.closed,
        operation: 'useAfterClose',
      );
    }
  }
}

const _oidCapacity = bindings.SKILLS_WORKSPACE_REVISION_OID_HEX_SIZE + 1;
const _gitRegularBlobMode = 0x81a4;
const _gitExecutableBlobMode = 0x81ed;
const _statusOk = 0;
const _statusBufferTooSmall = 6;

ffi.Pointer<ffi.Uint8> _copyBytes(Uint8List bytes, ffi.Allocator allocator) {
  final output = allocator<ffi.Uint8>(bytes.isEmpty ? 1 : bytes.length);
  if (bytes.isNotEmpty) {
    output.asTypedList(bytes.length).setAll(0, bytes);
  }
  return output;
}

ffi.Pointer<ffi.Pointer<ffi.Char>> _copyObjectIds(
  List<RevisionObjectId> objectIds,
  Arena arena,
) {
  final output = arena<ffi.Pointer<ffi.Char>>(
    objectIds.isEmpty ? 1 : objectIds.length,
  );
  for (var index = 0; index < objectIds.length; index += 1) {
    output[index] = objectIds[index].value
        .toNativeUtf8(allocator: arena)
        .cast();
  }
  return output;
}

typedef _ArenaVariableBufferInvocation =
    int Function(
      Arena arena,
      ffi.Pointer<ffi.Uint8> output,
      int capacity,
      ffi.Pointer<ffi.IntPtr> required,
    );

Uint8List _readVariableBufferWithArena({
  required String operation,
  required _ArenaVariableBufferInvocation invoke,
}) {
  return using((arena) {
    final required = arena<ffi.IntPtr>();
    final initialStatus = invoke(arena, ffi.nullptr, 0, required);
    if (initialStatus == _statusOk && required.value == 0) {
      return Uint8List(0);
    }
    if (initialStatus != _statusBufferTooSmall || required.value <= 0) {
      _checkStatus(initialStatus, operation: operation);
    }
    final output = arena<ffi.Uint8>(required.value);
    _checkStatus(
      invoke(arena, output, required.value, required),
      operation: operation,
    );
    return Uint8List.fromList(output.asTypedList(required.value));
  });
}

List<Uint8List> _splitNullTerminated(Uint8List bytes) {
  final output = <Uint8List>[];
  var start = 0;
  for (var index = 0; index < bytes.length; index += 1) {
    if (bytes[index] == 0) {
      output.add(Uint8List.fromList(bytes.sublist(start, index)));
      start = index + 1;
    }
  }
  if (start != bytes.length) {
    throw const RevisionNativeException(
      code: RevisionNativeFailureCode.verificationFailure,
      operation: 'decodeNullTerminatedPayload',
    );
  }
  return output;
}

String? _nullableUtf8(Uint8List bytes) =>
    bytes.isEmpty ? null : utf8.decode(bytes, allowMalformed: false);

void _checkStatus(int status, {required String operation}) {
  if (status == _statusOk) return;
  final code = switch (status) {
    1 => RevisionNativeFailureCode.invalidArgument,
    2 => RevisionNativeFailureCode.notInitialized,
    3 => RevisionNativeFailureCode.repositoryFailure,
    4 => RevisionNativeFailureCode.objectFailure,
    5 => RevisionNativeFailureCode.verificationFailure,
    6 => RevisionNativeFailureCode.bufferTooSmall,
    7 => RevisionNativeFailureCode.bundleFailure,
    _ => RevisionNativeFailureCode.unexpectedFailure,
  };
  throw RevisionNativeException(code: code, operation: operation);
}
