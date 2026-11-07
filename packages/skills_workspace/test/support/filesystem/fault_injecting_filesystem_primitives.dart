import 'package:skills_workspace/src/platform/filesystem/filesystem_primitives.dart';

typedef FilesystemFaultCallback =
    void Function(DurableFilesystemOperation operation, String path);

final class FaultInjectingFilesystemPrimitives implements FilesystemPrimitives {
  FaultInjectingFilesystemPrimitives({
    required FilesystemPrimitives delegate,
    required FilesystemFaultCallback beforeOperation,
    this.forceExchangeUnsupported = false,
  }) : _delegate = delegate,
       _beforeOperation = beforeOperation;

  final FilesystemPrimitives _delegate;
  final FilesystemFaultCallback _beforeOperation;
  final bool forceExchangeUnsupported;

  @override
  Future<void> writeNewFile(String path, List<int> bytes) async {
    _beforeOperation(DurableFilesystemOperation.writeFile, path);
    await _delegate.writeNewFile(path, bytes);
  }

  @override
  Future<void> flushFile(String path) async {
    _beforeOperation(DurableFilesystemOperation.flushFile, path);
    await _delegate.flushFile(path);
  }

  @override
  Future<void> flushDirectory(String path) async {
    _beforeOperation(DurableFilesystemOperation.flushDirectory, path);
    await _delegate.flushDirectory(path);
  }

  @override
  Future<FilesystemPathMetadata> stat(
    String path, {
    required bool followLinks,
  }) async {
    _beforeOperation(DurableFilesystemOperation.inspectPath, path);
    return _delegate.stat(path, followLinks: followLinks);
  }

  @override
  Future<void> renameSameParent({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  }) async {
    _beforeOperation(
      DurableFilesystemOperation.rename,
      '$parentPath/$sourceName->$destinationName',
    );
    await _delegate.renameSameParent(
      parentPath: parentPath,
      sourceName: sourceName,
      destinationName: destinationName,
      replaceExisting: replaceExisting,
    );
  }

  @override
  Future<bool> exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  }) async {
    _beforeOperation(
      DurableFilesystemOperation.exchange,
      '$parentPath/$firstName<->$secondName',
    );
    if (forceExchangeUnsupported) {
      return false;
    }
    return _delegate.exchangeSameParent(
      parentPath: parentPath,
      firstName: firstName,
      secondName: secondName,
    );
  }

  @override
  Future<void> applyPosixMode(String path, int mode) async {
    _beforeOperation(DurableFilesystemOperation.applyPermissions, path);
    await _delegate.applyPosixMode(path, mode);
  }

  @override
  Future<bool?> captureReadOnly(String path) async {
    _beforeOperation(DurableFilesystemOperation.inspectPath, path);
    return _delegate.captureReadOnly(path);
  }

  @override
  Future<void> applyReadOnly(String path, bool readOnly) async {
    _beforeOperation(DurableFilesystemOperation.applyPermissions, path);
    await _delegate.applyReadOnly(path, readOnly);
  }
}
