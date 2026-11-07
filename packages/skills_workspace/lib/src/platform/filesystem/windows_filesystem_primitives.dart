import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart' as win32;

import 'filesystem_primitives.dart';

final class WindowsFilesystemPrimitives implements FilesystemPrimitives {
  const WindowsFilesystemPrimitives();

  static const int readOnlyAttribute = 0x00000001;
  static const int normalAttribute = 0x00000080;
  static const int invalidFileAttributes = 0xffffffff;
  // Newly-created immutable Git objects may remain briefly held by filesystem
  // scanners even after libgit2 closes its repository handles.
  static const Duration _flushRetryTimeout = Duration(seconds: 10);
  static const Duration _flushRetryInitialDelay = Duration(milliseconds: 2);
  static const Duration _flushRetryMaximumDelay = Duration(milliseconds: 100);
  static const Duration _readOnlyAttributeSettleDelay = Duration(
    milliseconds: 10,
  );

  @override
  Future<void> writeNewFile(String filePath, List<int> bytes) async {
    _requireWindows();
    final normalized = extendedPath(filePath);
    final handleResult = using(
      (arena) => win32.CreateFile(
        normalized.toPcwstr(allocator: arena),
        win32.GENERIC_WRITE,
        win32.FILE_SHARE_READ |
            win32.FILE_SHARE_WRITE |
            win32.FILE_SHARE_DELETE,
        null,
        win32.CREATE_NEW,
        win32.FILE_ATTRIBUTE_NORMAL | win32.FILE_FLAG_OPEN_REPARSE_POINT,
        null,
      ),
    );
    final handle = handleResult.value;
    if (!handle.isValid) {
      _throwWindows(
        DurableFilesystemOperation.writeFile,
        filePath,
        handleResult.error,
      );
    }
    try {
      using((arena) {
        final written = arena<Uint32>();
        Pointer<Uint8>? buffer;
        if (bytes.isNotEmpty) {
          buffer = arena<Uint8>(bytes.length);
          buffer.asTypedList(bytes.length).setAll(0, bytes);
        }
        final result = win32.WriteFile(
          handle,
          buffer,
          bytes.length,
          written,
          null,
        );
        if (!result.value || written.value != bytes.length) {
          _throwWindows(
            DurableFilesystemOperation.writeFile,
            filePath,
            result.value ? win32.ERROR_WRITE_FAULT : result.error,
          );
        }
      });
    } finally {
      final close = handle.close();
      if (!close.value) {
        _throwWindows(
          DurableFilesystemOperation.writeFile,
          filePath,
          close.error,
        );
      }
    }
  }

  @override
  Future<void> flushFile(String filePath) => _flush(filePath, directory: false);

  @override
  Future<void> flushDirectory(String directoryPath) =>
      _flush(directoryPath, directory: true);

  Future<void> _flush(String targetPath, {required bool directory}) async {
    _requireWindows();
    final normalized = extendedPath(targetPath);
    var originalAttributes = invalidFileAttributes;
    var handleResult = _openFlushHandle(normalized, directory: directory);
    if (!directory &&
        !handleResult.value.isValid &&
        _retryableFlushOpen(handleResult.error.code)) {
      if (handleResult.error == win32.ERROR_ACCESS_DENIED) {
        final attributes = _getAttributes(normalized);
        if (attributes.value != invalidFileAttributes &&
            attributes.value & readOnlyAttribute != 0) {
          originalAttributes = attributes.value;
          final writableAttributes = originalAttributes & ~readOnlyAttribute;
          handleResult = await _openReadOnlyFlushHandleWithRetry(
            normalized: normalized,
            writableAttributes: writableAttributes == 0
                ? normalAttribute
                : writableAttributes,
            targetPath: targetPath,
          );
        }
      }
      if (!handleResult.value.isValid &&
          originalAttributes == invalidFileAttributes) {
        handleResult = await _openFlushHandleWithRetry(normalized);
      }
    }
    win32.HANDLE? handle;
    try {
      handle = handleResult.value;
      if (!handle.isValid) {
        final error = handleResult.error.code == win32.ERROR_SUCCESS
            ? win32.ERROR_ACCESS_DENIED
            : handleResult.error.code;
        _throwWindows(
          directory
              ? DurableFilesystemOperation.flushDirectory
              : DurableFilesystemOperation.flushFile,
          targetPath,
          error,
        );
      }
      final flush = win32.FlushFileBuffers(handle);
      if (!flush.value) {
        _throwWindows(
          directory
              ? DurableFilesystemOperation.flushDirectory
              : DurableFilesystemOperation.flushFile,
          targetPath,
          flush.error,
        );
      }
    } finally {
      if (handle case final opened? when opened.isValid) {
        final close = opened.close();
        if (!close.value) {
          _throwWindows(
            directory
                ? DurableFilesystemOperation.flushDirectory
                : DurableFilesystemOperation.flushFile,
            targetPath,
            close.error,
          );
        }
      }
      if (originalAttributes != invalidFileAttributes) {
        _setAttributes(normalized, originalAttributes, targetPath: targetPath);
      }
    }
  }

  static win32.Win32Result<win32.HANDLE> _openFlushHandle(
    String normalized, {
    required bool directory,
  }) => using(
    (arena) => win32.CreateFile(
      normalized.toPcwstr(allocator: arena),
      win32.GENERIC_WRITE,
      win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE | win32.FILE_SHARE_DELETE,
      null,
      win32.OPEN_EXISTING,
      (directory
              ? win32.FILE_FLAG_BACKUP_SEMANTICS
              : win32.FILE_ATTRIBUTE_NORMAL) |
          win32.FILE_FLAG_WRITE_THROUGH,
      null,
    ),
  );

  static Future<win32.Win32Result<win32.HANDLE>> _openFlushHandleWithRetry(
    String normalized,
  ) async {
    var result = _openFlushHandle(normalized, directory: false);
    final elapsed = Stopwatch()..start();
    var delay = _flushRetryInitialDelay;
    while (!result.value.isValid &&
        elapsed.elapsed < _flushRetryTimeout &&
        _retryableFlushOpen(result.error.code)) {
      final remaining = _flushRetryTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero) break;
      await Future<void>.delayed(delay < remaining ? delay : remaining);
      result = _openFlushHandle(normalized, directory: false);
      final doubled = delay * 2;
      delay = doubled < _flushRetryMaximumDelay
          ? doubled
          : _flushRetryMaximumDelay;
    }
    return result;
  }

  static Future<win32.Win32Result<win32.HANDLE>>
  _openReadOnlyFlushHandleWithRetry({
    required String normalized,
    required int writableAttributes,
    required String targetPath,
  }) async {
    final elapsed = Stopwatch()..start();
    var delay = _readOnlyAttributeSettleDelay;
    while (true) {
      _setAttributes(normalized, writableAttributes, targetPath: targetPath);
      final remaining = _flushRetryTimeout - elapsed.elapsed;
      if (remaining <= Duration.zero) {
        return _openFlushHandle(normalized, directory: false);
      }
      await Future<void>.delayed(delay < remaining ? delay : remaining);
      final result = _openFlushHandle(normalized, directory: false);
      if (result.value.isValid || !_retryableFlushOpen(result.error.code)) {
        return result;
      }
      final doubled = delay * 2;
      delay = doubled < _flushRetryMaximumDelay
          ? doubled
          : _flushRetryMaximumDelay;
    }
  }

  static bool _retryableFlushOpen(int error) =>
      error == win32.ERROR_SUCCESS ||
      error == win32.ERROR_FILE_NOT_FOUND ||
      error == win32.ERROR_ACCESS_DENIED ||
      error == win32.ERROR_SHARING_VIOLATION ||
      error == win32.ERROR_LOCK_VIOLATION;

  static win32.Win32Result<int> _getAttributes(String normalized) => using(
    (arena) => win32.GetFileAttributes(normalized.toPcwstr(allocator: arena)),
  );

  static void _setAttributes(
    String normalized,
    int attributes, {
    required String targetPath,
  }) {
    final result = using(
      (arena) => win32.SetFileAttributes(
        normalized.toPcwstr(allocator: arena),
        win32.FILE_FLAGS_AND_ATTRIBUTES(attributes),
      ),
    );
    if (!result.value) {
      _throwWindows(
        DurableFilesystemOperation.applyPermissions,
        targetPath,
        result.error,
      );
    }
  }

  @override
  Future<FilesystemPathMetadata> stat(
    String targetPath, {
    required bool followLinks,
  }) async {
    _requireWindows();
    final normalized = extendedPath(targetPath);
    final handleResult = using(
      (arena) => win32.CreateFile(
        normalized.toPcwstr(allocator: arena),
        win32.FILE_READ_ATTRIBUTES,
        win32.FILE_SHARE_READ |
            win32.FILE_SHARE_WRITE |
            win32.FILE_SHARE_DELETE,
        null,
        win32.OPEN_EXISTING,
        win32.FILE_FLAG_BACKUP_SEMANTICS |
            (followLinks
                ? win32.FILE_ATTRIBUTE_NORMAL
                : win32.FILE_FLAG_OPEN_REPARSE_POINT),
        null,
      ),
    );
    final handle = handleResult.value;
    if (!handle.isValid) {
      _throwWindows(
        DurableFilesystemOperation.inspectPath,
        targetPath,
        handleResult.error,
      );
    }
    try {
      return using<FilesystemPathMetadata>((arena) {
        final information = arena<win32.BY_HANDLE_FILE_INFORMATION>();
        final result = win32.GetFileInformationByHandle(handle, information);
        if (!result.value) {
          _throwWindows(
            DurableFilesystemOperation.inspectPath,
            targetPath,
            result.error,
          );
        }
        final value = information.ref;
        final isReparsePoint =
            value.dwFileAttributes & win32.FILE_ATTRIBUTE_REPARSE_POINT != 0;
        final isDirectory =
            value.dwFileAttributes & win32.FILE_ATTRIBUTE_DIRECTORY != 0;
        final kind = !followLinks && isReparsePoint
            ? FilesystemEntryKind.symbolicLink
            : isDirectory
            ? FilesystemEntryKind.directory
            : FilesystemEntryKind.file;
        final fileIndex = (value.nFileIndexHigh << 32) | value.nFileIndexLow;
        return FilesystemPathMetadata(
          kind: kind,
          volumeId: value.dwVolumeSerialNumber.toRadixString(16),
          fileId: fileIndex.toRadixString(16),
        );
      });
    } finally {
      final close = handle.close();
      if (!close.value) {
        _throwWindows(
          DurableFilesystemOperation.inspectPath,
          targetPath,
          close.error,
        );
      }
    }
  }

  @override
  Future<void> renameSameParent({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  }) async {
    _requireWindows();
    _requireSingleName(sourceName, 'sourceName');
    _requireSingleName(destinationName, 'destinationName');
    final sourcePath = extendedPath(path.join(parentPath, sourceName));
    final destinationPath = extendedPath(
      path.join(parentPath, destinationName),
    );
    final elapsed = Stopwatch()..start();
    var attempt = 0;
    while (true) {
      final result = using(
        (arena) => win32.MoveFileEx(
          sourcePath.toPcwstr(allocator: arena),
          destinationPath.toPcwstr(allocator: arena),
          win32.MOVEFILE_WRITE_THROUGH |
              (replaceExisting
                  ? win32.MOVEFILE_REPLACE_EXISTING
                  : const win32.MOVE_FILE_FLAGS(0)),
        ),
      );
      final delay = windowsMoveRetryDelay(
        result.error.code,
        attempt++,
        elapsed.elapsed,
      );
      if (result.value || delay == null) {
        if (!result.value) {
          _throwWindows(
            DurableFilesystemOperation.rename,
            path.join(parentPath, destinationName),
            result.error,
          );
        }
        return;
      }
      await Future<void>.delayed(delay);
    }
  }

  @override
  Future<bool> exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  }) async {
    _requireWindows();
    return false;
  }

  @override
  Future<void> applyPosixMode(String targetPath, int mode) async {}

  @override
  Future<bool?> captureReadOnly(String targetPath) async {
    _requireWindows();
    final result = using(
      (arena) => win32.GetFileAttributes(
        extendedPath(targetPath).toPcwstr(allocator: arena),
      ),
    );
    if (result.value == invalidFileAttributes) {
      _throwWindows(
        DurableFilesystemOperation.inspectPath,
        targetPath,
        result.error,
      );
    }
    return result.value & readOnlyAttribute != 0;
  }

  @override
  Future<void> applyReadOnly(String targetPath, bool readOnly) async {
    _requireWindows();
    final extended = extendedPath(targetPath);
    final current = using(
      (arena) => win32.GetFileAttributes(extended.toPcwstr(allocator: arena)),
    );
    if (current.value == invalidFileAttributes) {
      _throwWindows(
        DurableFilesystemOperation.applyPermissions,
        targetPath,
        current.error,
      );
    }
    var updated = readOnly
        ? current.value | readOnlyAttribute
        : current.value & ~readOnlyAttribute;
    if (updated == 0) {
      updated = normalAttribute;
    }
    if (updated == current.value) {
      return;
    }
    final result = using(
      (arena) => win32.SetFileAttributes(
        extended.toPcwstr(allocator: arena),
        win32.FILE_FLAGS_AND_ATTRIBUTES(updated),
      ),
    );
    if (!result.value) {
      _throwWindows(
        DurableFilesystemOperation.applyPermissions,
        targetPath,
        result.error,
      );
    }
  }

  static String extendedPath(String targetPath) {
    final normalized = path.windows.normalize(
      path.windows.absolute(targetPath),
    );
    if (normalized.startsWith(r'\\?\')) {
      return normalized;
    }
    if (normalized.startsWith(r'\\')) {
      return '${r'\\?\UNC\'}${normalized.substring(2)}';
    }
    return '${r'\\?\'}$normalized';
  }

  static void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows filesystem primitives are unavailable.');
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

  static Never _throwWindows(
    DurableFilesystemOperation operation,
    String targetPath,
    int error,
  ) {
    throw DurableFilesystemException(
      operation: operation,
      message: 'The Windows filesystem operation failed.',
      path: targetPath,
      platformCode: error,
    );
  }
}

/// A bounded retry for transient directory locks; all other errors fail once.
Duration? windowsMoveRetryDelay(int error, int attempt, Duration elapsed) {
  const timeout = Duration(seconds: 2);
  if ((error != 5 && error != 32) || elapsed >= timeout) return null;
  final delay = Duration(milliseconds: 2 * (1 << attempt.clamp(0, 6)));
  final capped = delay < const Duration(milliseconds: 100)
      ? delay
      : const Duration(milliseconds: 100);
  final remaining = timeout - elapsed;
  return capped < remaining ? capped : remaining;
}
