import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

import '../../native/generated/skills_workspace_bindings_generated.dart'
    as native;
import 'filesystem_primitives.dart';

final class PosixFilesystemPrimitives implements FilesystemPrimitives {
  const PosixFilesystemPrimitives();

  static const int ordinaryPermissionMask = 0x1ff;
  static const int executablePermissionMask = 0x49;
  static const int unsupportedExchangeErrnoLinux = 38;
  static const int unsupportedExchangeErrnoMacOS = 45;
  static const int operationNotSupportedErrnoLinux = 95;
  static const int operationNotSupportedErrnoMacOS = 102;

  static int sanitizedMode(int mode) => mode & ordinaryPermissionMask;

  @override
  Future<void> writeNewFile(String filePath, List<int> bytes) async {
    _requirePosix();
    final normalized = path.normalize(path.absolute(filePath));
    final parent = path.dirname(normalized);
    final name = path.basename(normalized);
    _requireSingleName(name, 'fileName');
    final error = using((arena) {
      final buffer = arena<ffi.Uint8>(bytes.length);
      if (bytes.isNotEmpty) {
        buffer.asTypedList(bytes.length).setAll(0, bytes);
      }
      return native.skills_workspace_posix_write_new_at(
        parent.toNativeUtf8(allocator: arena).cast(),
        name.toNativeUtf8(allocator: arena).cast(),
        buffer,
        bytes.length,
      );
    });
    _throwIfError(error, DurableFilesystemOperation.writeFile, normalized);
  }

  @override
  Future<void> flushFile(String filePath) => _flush(filePath, directory: false);

  @override
  Future<void> flushDirectory(String directoryPath) =>
      _flush(directoryPath, directory: true);

  Future<void> _flush(String targetPath, {required bool directory}) async {
    _requirePosix();
    final normalized = path.normalize(path.absolute(targetPath));
    final parent = path.dirname(normalized);
    final name = path.basename(normalized);
    final error = using((arena) {
      if (parent == normalized || name == path.separator) {
        return native.skills_workspace_posix_flush_path(
          normalized.toNativeUtf8(allocator: arena).cast(),
          directory ? 1 : 0,
        );
      }
      return native.skills_workspace_posix_flush_at(
        parent.toNativeUtf8(allocator: arena).cast(),
        name.toNativeUtf8(allocator: arena).cast(),
        directory ? 1 : 0,
      );
    });
    _throwIfError(
      error,
      directory
          ? DurableFilesystemOperation.flushDirectory
          : DurableFilesystemOperation.flushFile,
      normalized,
    );
  }

  @override
  Future<FilesystemPathMetadata> stat(
    String targetPath, {
    required bool followLinks,
  }) async {
    _requirePosix();
    final normalized = path.normalize(path.absolute(targetPath));
    return using((arena) {
      final device = arena<ffi.Uint64>();
      final inode = arena<ffi.Uint64>();
      final mode = arena<ffi.Uint32>();
      final kind = arena<ffi.Int32>();
      final error = native.skills_workspace_posix_stat(
        normalized.toNativeUtf8(allocator: arena).cast(),
        followLinks ? 1 : 0,
        device,
        inode,
        mode,
        kind,
      );
      _throwIfError(error, DurableFilesystemOperation.inspectPath, normalized);
      return FilesystemPathMetadata(
        kind: _entryKind(kind.value),
        volumeId: device.value.toRadixString(16),
        fileId: inode.value.toRadixString(16),
        posixMode: sanitizedMode(mode.value),
      );
    });
  }

  @override
  Future<void> renameSameParent({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  }) async {
    _requirePosix();
    _requireSingleName(sourceName, 'sourceName');
    _requireSingleName(destinationName, 'destinationName');
    if (!replaceExisting) {
      final destination = path.join(parentPath, destinationName);
      if (await FileSystemEntity.type(destination, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw DurableFilesystemException(
          operation: DurableFilesystemOperation.rename,
          message: 'The destination already exists.',
          path: destination,
        );
      }
    }
    final normalizedParent = path.normalize(path.absolute(parentPath));
    final error = using(
      (arena) => native.skills_workspace_posix_rename_at(
        normalizedParent.toNativeUtf8(allocator: arena).cast(),
        sourceName.toNativeUtf8(allocator: arena).cast(),
        destinationName.toNativeUtf8(allocator: arena).cast(),
      ),
    );
    _throwIfError(
      error,
      DurableFilesystemOperation.rename,
      path.join(normalizedParent, destinationName),
    );
  }

  @override
  Future<bool> exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  }) async {
    _requirePosix();
    _requireSingleName(firstName, 'firstName');
    _requireSingleName(secondName, 'secondName');
    final normalizedParent = path.normalize(path.absolute(parentPath));
    final error = using(
      (arena) => native.skills_workspace_posix_exchange_at(
        normalizedParent.toNativeUtf8(allocator: arena).cast(),
        firstName.toNativeUtf8(allocator: arena).cast(),
        secondName.toNativeUtf8(allocator: arena).cast(),
      ),
    );
    if (_exchangeUnsupported(error)) {
      return false;
    }
    _throwIfError(error, DurableFilesystemOperation.exchange, normalizedParent);
    return true;
  }

  @override
  Future<void> applyPosixMode(String targetPath, int mode) async {
    _requirePosix();
    final normalized = path.normalize(path.absolute(targetPath));
    final error = using(
      (arena) => native.skills_workspace_posix_chmod(
        normalized.toNativeUtf8(allocator: arena).cast(),
        sanitizedMode(mode),
      ),
    );
    _throwIfError(
      error,
      DurableFilesystemOperation.applyPermissions,
      normalized,
    );
  }

  @override
  Future<bool?> captureReadOnly(String targetPath) async => null;

  @override
  Future<void> applyReadOnly(String targetPath, bool readOnly) async {}

  static bool _exchangeUnsupported(int error) =>
      error == unsupportedExchangeErrnoLinux ||
      error == unsupportedExchangeErrnoMacOS ||
      error == operationNotSupportedErrnoLinux ||
      error == operationNotSupportedErrnoMacOS;

  static FilesystemEntryKind _entryKind(int nativeKind) => switch (nativeKind) {
    1 => FilesystemEntryKind.file,
    2 => FilesystemEntryKind.directory,
    3 => FilesystemEntryKind.symbolicLink,
    _ => FilesystemEntryKind.other,
  };

  static void _requirePosix() {
    if (Platform.isWindows) {
      throw UnsupportedError('POSIX filesystem primitives are unavailable.');
    }
  }

  static void _requireSingleName(String value, String argumentName) {
    if (value.isEmpty ||
        value == '.' ||
        value == '..' ||
        value.contains('/') ||
        value.contains(r'\')) {
      throw ArgumentError.value(value, argumentName, 'must be one path name');
    }
  }

  static void _throwIfError(
    int error,
    DurableFilesystemOperation operation,
    String targetPath,
  ) {
    if (error == 0) {
      return;
    }
    throw DurableFilesystemException(
      operation: operation,
      message: 'The POSIX filesystem operation failed.',
      path: targetPath,
      platformCode: error,
    );
  }
}
