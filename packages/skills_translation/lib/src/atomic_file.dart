import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

const int _windowsFileNotFound = 2;
const int _windowsAccessDenied = 5;
const int _windowsSharingViolation = 32;
const int _windowsLockViolation = 33;
const int _atomicFileRetryAttempts = 500;
const Duration _atomicFileRetryDelay = Duration(milliseconds: 2);

/// Reads a cache entry while tolerating transient Windows replacement races.
Future<String> readAtomicFileString(String path) =>
    _retryWindowsSharingViolation(() => File(path).readAsString());

Future<T> _retryWindowsSharingViolation<T>(Future<T> Function() action) async {
  for (var attempt = 1; attempt <= _atomicFileRetryAttempts; attempt += 1) {
    try {
      return await action();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      final retryable =
          Platform.isWindows &&
          (code == _windowsFileNotFound ||
              code == _windowsSharingViolation ||
              code == _windowsLockViolation);
      if (!retryable || attempt == _atomicFileRetryAttempts) {
        rethrow;
      }
      await Future<void>.delayed(_atomicFileRetryDelay);
    }
  }
  throw StateError('Unreachable atomic-file retry state.');
}

/// Writes same-directory temporary files and replaces destinations atomically.
final class AtomicFileWriter {
  /// Creates an atomic writer.
  AtomicFileWriter({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  /// Durably writes [contents] and atomically replaces [destinationPath].
  Future<void> writeString(String destinationPath, String contents) async {
    final parent = p.dirname(destinationPath);
    await _ensureDirectory(parent);
    final temporaryPath = p.join(
      parent,
      '.${p.basename(destinationPath)}.$pid.'
      '${DateTime.now().microsecondsSinceEpoch}.${_random.nextInt(1 << 32)}.tmp',
    );
    final temporary = File(temporaryPath);
    RandomAccessFile? handle;
    try {
      handle = await temporary.open(mode: FileMode.write);
      await handle.writeString(contents);
      await handle.flush();
      await handle.close();
      handle = null;
      await _replace(temporaryPath, destinationPath);
      await _flushDirectory(parent);
    } finally {
      if (handle != null) {
        await handle.close();
      }
      if (await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  /// Removes temporary siblings left by an interrupted prior write.
  static Future<void> cleanupTemporarySiblings(String destinationPath) async {
    final parent = Directory(p.dirname(destinationPath));
    if (!await parent.exists()) {
      return;
    }
    final basename = RegExp.escape(p.basename(destinationPath));
    final pattern = RegExp('^\\.$basename\\.[0-9]+\\.[0-9]+\\.[0-9]+\\.tmp\$');
    await for (final entity in parent.list(followLinks: false)) {
      if (entity is File && pattern.hasMatch(p.basename(entity.path))) {
        await entity.delete();
      }
    }
  }
}

Future<void> _replace(String sourcePath, String destinationPath) async {
  if (!Platform.isWindows) {
    await File(sourcePath).rename(destinationPath);
    return;
  }
  var outcome = (result: 0, error: 0);
  for (var attempt = 1; attempt <= _atomicFileRetryAttempts; attempt += 1) {
    final destinationExists = await File(destinationPath).exists();
    outcome = using((arena) {
      final source = windowsExtendedPath(
        sourcePath,
      ).toNativeUtf16(allocator: arena);
      final destination = windowsExtendedPath(
        destinationPath,
      ).toNativeUtf16(allocator: arena);
      final result =
          destinationExists
              ? _replaceFileW(
                destination,
                source,
                nullptr.cast<Utf16>(),
                _replaceFileWriteThrough,
                nullptr,
                nullptr,
              )
              : _moveFileExW(
                source,
                destination,
                _moveFileReplaceExisting | _moveFileWriteThrough,
              );
      return (result: result, error: result == 0 ? _getLastError() : 0);
    });
    if (outcome.result != 0 ||
        (outcome.error != 0 &&
            outcome.error != _windowsAccessDenied &&
            outcome.error != _windowsSharingViolation &&
            outcome.error != _windowsLockViolation) ||
        attempt == _atomicFileRetryAttempts) {
      break;
    }
    await Future<void>.delayed(_atomicFileRetryDelay);
  }
  if (outcome.result == 0) {
    throw FileSystemException(
      'Atomic translation cache replacement failed with Windows error '
      '${outcome.error}.',
      destinationPath,
    );
  }
}

/// Returns an absolute extended-length path for Windows filesystem APIs.
String windowsExtendedPath(String path) {
  final normalized = p.windows.normalize(p.windows.absolute(path));
  if (normalized.startsWith(r'\\?\')) return normalized;
  if (normalized.startsWith(r'\\')) {
    return '${r'\\?\UNC\'}${normalized.substring(2)}';
  }
  return '${r'\\?\'}$normalized';
}

Future<void> _ensureDirectory(String path) async {
  final normalized = p.normalize(path);
  final missing = <String>[];
  var candidate = normalized;
  while (true) {
    final type = await FileSystemEntity.type(candidate, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      break;
    }
    if (type != FileSystemEntityType.notFound) {
      throw FileSystemException(
        'A non-directory entity blocks cache directory creation.',
        candidate,
      );
    }
    missing.add(candidate);
    final parent = p.dirname(candidate);
    if (parent == candidate) {
      break;
    }
    candidate = parent;
  }
  await Directory(normalized).create(recursive: true);
  if (Platform.isWindows) {
    return;
  }
  for (final directory in missing) {
    await _flushDirectory(directory);
  }
  await _flushDirectory(missing.isEmpty ? normalized : p.dirname(missing.last));
}

Future<void> _flushDirectory(String path) async {
  if (Platform.isWindows) {
    return;
  }
  final descriptor = using(
    (arena) => _posixOpen(path.toNativeUtf8(allocator: arena), _openReadOnly),
  );
  if (descriptor < 0) {
    throw FileSystemException(
      'Unable to open cache directory for flush.',
      path,
    );
  }
  int flushResult;
  int closeResult;
  try {
    flushResult = _posixFsync(descriptor);
  } finally {
    closeResult = _posixClose(descriptor);
  }
  if (flushResult != 0 || closeResult != 0) {
    throw FileSystemException(
      'Unable to flush cache directory metadata.',
      path,
    );
  }
}

const int _replaceFileWriteThrough = 0x00000001;
const int _moveFileReplaceExisting = 0x00000001;
const int _moveFileWriteThrough = 0x00000008;
const int _openReadOnly = 0;

typedef _ReplaceFileWNative =
    Int32 Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      Uint32,
      Pointer<Void>,
      Pointer<Void>,
    );
typedef _ReplaceFileWDart =
    int Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      Pointer<Utf16>,
      int,
      Pointer<Void>,
      Pointer<Void>,
    );
typedef _MoveFileExWNative =
    Int32 Function(Pointer<Utf16>, Pointer<Utf16>, Uint32);
typedef _MoveFileExWDart = int Function(Pointer<Utf16>, Pointer<Utf16>, int);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();
typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _FsyncNative = Int32 Function(Int32);
typedef _FsyncDart = int Function(int);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
final _ReplaceFileWDart _replaceFileW = _kernel32
    .lookupFunction<_ReplaceFileWNative, _ReplaceFileWDart>('ReplaceFileW');
final _MoveFileExWDart _moveFileExW = _kernel32
    .lookupFunction<_MoveFileExWNative, _MoveFileExWDart>('MoveFileExW');
final _GetLastErrorDart _getLastError = _kernel32
    .lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError');
final DynamicLibrary _process = DynamicLibrary.process();
final _OpenDart _posixOpen = _process.lookupFunction<_OpenNative, _OpenDart>(
  'open',
);
final _FsyncDart _posixFsync = _process
    .lookupFunction<_FsyncNative, _FsyncDart>('fsync');
final _CloseDart _posixClose = _process
    .lookupFunction<_CloseNative, _CloseDart>('close');
