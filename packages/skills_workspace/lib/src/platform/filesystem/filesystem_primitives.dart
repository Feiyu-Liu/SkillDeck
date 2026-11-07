import 'dart:io';

enum FilesystemEntryKind { file, directory, symbolicLink, other }

final class FilesystemPathMetadata {
  const FilesystemPathMetadata({
    required this.kind,
    required this.volumeId,
    required this.fileId,
    this.posixMode,
  });

  final FilesystemEntryKind kind;
  final String volumeId;
  final String fileId;
  final int? posixMode;

  String get physicalKey => '$volumeId:$fileId';
}

enum DurableFilesystemOperation {
  createDirectory,
  createStagingPath,
  writeFile,
  flushFile,
  flushDirectory,
  flushTree,
  inspectPath,
  rename,
  exchange,
  applyPermissions,
  createLink,
  verify,
  cleanup,
  lock,
}

final class DurableFilesystemException extends FileSystemException {
  DurableFilesystemException({
    required this.operation,
    required String message,
    String? path,
    this.platformCode,
  }) : super(
         message,
         path ?? '',
         platformCode == null
             ? null
             : OSError(
                 'Platform filesystem error $platformCode.',
                 platformCode,
               ),
       );

  final DurableFilesystemOperation operation;
  final int? platformCode;

  @override
  String toString() =>
      'DurableFilesystemException(operation: $operation, '
      'path: $path, platformCode: $platformCode, message: $message)';
}

abstract interface class FilesystemPrimitives {
  /// Creates and writes one new regular file without replacing or following an
  /// existing final path component.
  Future<void> writeNewFile(String path, List<int> bytes);

  Future<void> flushFile(String path);

  Future<void> flushDirectory(String path);

  Future<FilesystemPathMetadata> stat(String path, {required bool followLinks});

  Future<void> renameSameParent({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  });

  /// Exchanges two sibling entries and returns false when the host filesystem
  /// does not offer an atomic exchange primitive.
  Future<bool> exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  });

  Future<void> applyPosixMode(String path, int mode);

  Future<bool?> captureReadOnly(String path);

  Future<void> applyReadOnly(String path, bool readOnly);
}
