import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/ports/operation_ports.dart';
import '../../domain/lock_wait_policy.dart';
import 'durable_workspace_filesystem.dart';

enum FilesystemLockMode { shared, exclusive }

enum FilesystemLockFailure { busy, cancelled, ioFailure }

final class FilesystemLockException implements Exception {
  const FilesystemLockException({
    required this.failure,
    required this.lockPath,
    this.platformCode,
  });

  final FilesystemLockFailure failure;
  final String lockPath;
  final int? platformCode;

  @override
  String toString() =>
      'FilesystemLockException(failure: $failure, '
      'platformCode: $platformCode)';
}

final class FilesystemLockWaitPolicy {
  const FilesystemLockWaitPolicy.failFast()
    : waits = false,
      timeout = Duration.zero,
      pollInterval = Duration.zero;

  factory FilesystemLockWaitPolicy.wait({
    Duration? timeout,
    Duration pollInterval = const Duration(milliseconds: 25),
  }) {
    if (timeout != null && timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (pollInterval <= Duration.zero) {
      throw ArgumentError.value(
        pollInterval,
        'pollInterval',
        'must be positive',
      );
    }
    return FilesystemLockWaitPolicy._(
      waits: true,
      timeout: timeout,
      pollInterval: pollInterval,
    );
  }

  const FilesystemLockWaitPolicy._({
    required this.waits,
    required this.timeout,
    required this.pollInterval,
  });

  final bool waits;
  final Duration? timeout;
  final Duration pollInterval;
}

final class FilesystemLockLease implements WorkspaceWriterLease {
  FilesystemLockLease._({
    required RandomAccessFile file,
    required _LocalLockLease localLease,
  }) : _file = file,
       _localLease = localLease;

  RandomAccessFile? _file;
  _LocalLockLease? _localLease;

  @override
  Future<void> release() async {
    final file = _file;
    final localLease = _localLease;
    if (file == null || localLease == null) {
      return;
    }
    _file = null;
    _localLease = null;
    try {
      await file.unlock();
    } finally {
      try {
        await file.close();
      } finally {
        localLease.release();
      }
    }
  }
}

final class WorkspaceFileLock implements WorkspaceWriterLockPort {
  WorkspaceFileLock({
    required this.lockPath,
    this.waitPolicy = const FilesystemLockWaitPolicy.failFast(),
    DurableWorkspaceFilesystem? filesystem,
  }) : _filesystem = filesystem ?? PlatformDurableWorkspaceFilesystem(),
       _processRegistry = _globalProcessLockRegistry;

  final String lockPath;
  final FilesystemLockWaitPolicy waitPolicy;
  final DurableWorkspaceFilesystem _filesystem;
  final _ProcessLockRegistry _processRegistry;

  @override
  Future<FilesystemLockLease> acquire({LockWaitPolicy? waitPolicy}) =>
      acquireMode(
        mode: FilesystemLockMode.exclusive,
        waitPolicy: waitPolicy == null
            ? this.waitPolicy
            : _filesystemPolicy(waitPolicy),
      );

  Future<FilesystemLockLease> acquireMode({
    required FilesystemLockMode mode,
    required FilesystemLockWaitPolicy waitPolicy,
    bool Function()? isCancelled,
  }) async {
    final normalized = path.normalize(path.absolute(lockPath));
    final localLease = await _processRegistry.acquire(
      key: _lexicalKey(normalized),
      mode: mode,
      waitPolicy: waitPolicy,
      isCancelled: isCancelled,
    );
    RandomAccessFile? file;
    try {
      final parent = path.dirname(normalized);
      await _filesystem.ensureDirectory(parent);
      final existed = await File(normalized).exists();
      file = await File(normalized).open(mode: FileMode.append);
      if (!existed) {
        await file.flush();
        await _filesystem.flushFile(normalized);
        await _filesystem.flushDirectory(parent);
      }
      final stopwatch = Stopwatch()..start();
      while (true) {
        if (isCancelled?.call() ?? false) {
          throw FilesystemLockException(
            failure: FilesystemLockFailure.cancelled,
            lockPath: normalized,
          );
        }
        try {
          await file.lock(
            mode == FilesystemLockMode.shared
                ? FileLock.shared
                : FileLock.exclusive,
          );
          return FilesystemLockLease._(file: file, localLease: localLease);
        } on FileSystemException catch (error) {
          if (!waitPolicy.waits ||
              (waitPolicy.timeout != null &&
                  stopwatch.elapsed >= waitPolicy.timeout!)) {
            throw FilesystemLockException(
              failure: FilesystemLockFailure.busy,
              lockPath: normalized,
              platformCode: error.osError?.errorCode,
            );
          }
          await Future<void>.delayed(waitPolicy.pollInterval);
        }
      }
    } on FilesystemLockException {
      await file?.close();
      localLease.release();
      rethrow;
    } on FileSystemException catch (error) {
      await file?.close();
      localLease.release();
      throw FilesystemLockException(
        failure: FilesystemLockFailure.ioFailure,
        lockPath: normalized,
        platformCode: error.osError?.errorCode,
      );
    } catch (_) {
      await file?.close();
      localLease.release();
      rethrow;
    }
  }

  static String _lexicalKey(String lockPath) => Platform.isWindows
      ? path.windows.normalize(lockPath).toUpperCase()
      : path.posix.normalize(lockPath);
}

FilesystemLockWaitPolicy _filesystemPolicy(LockWaitPolicy policy) =>
    policy.waits
    ? FilesystemLockWaitPolicy.wait(
        timeout: policy.timeout,
        pollInterval: policy.pollInterval,
      )
    : const FilesystemLockWaitPolicy.failFast();

final _globalProcessLockRegistry = _ProcessLockRegistry();

final class _ProcessLockRegistry {
  final Map<String, _ProcessLockEntry> _entries = {};

  Future<_LocalLockLease> acquire({
    required String key,
    required FilesystemLockMode mode,
    required FilesystemLockWaitPolicy waitPolicy,
    bool Function()? isCancelled,
  }) async {
    final entry = _entries.putIfAbsent(key, _ProcessLockEntry.new);
    entry.participants += 1;
    if (mode == FilesystemLockMode.exclusive) {
      entry.waitingExclusive += 1;
    }
    final stopwatch = Stopwatch()..start();
    while (!entry.canAcquire(mode)) {
      if (isCancelled?.call() ?? false) {
        _cancelWait(key, entry, mode);
        throw FilesystemLockException(
          failure: FilesystemLockFailure.cancelled,
          lockPath: key,
        );
      }
      if (!waitPolicy.waits ||
          (waitPolicy.timeout != null &&
              stopwatch.elapsed >= waitPolicy.timeout!)) {
        _cancelWait(key, entry, mode);
        throw FilesystemLockException(
          failure: FilesystemLockFailure.busy,
          lockPath: key,
        );
      }
      await Future<void>.delayed(waitPolicy.pollInterval);
    }
    if (isCancelled?.call() ?? false) {
      _cancelWait(key, entry, mode);
      throw FilesystemLockException(
        failure: FilesystemLockFailure.cancelled,
        lockPath: key,
      );
    }
    if (mode == FilesystemLockMode.exclusive) {
      entry.waitingExclusive -= 1;
      entry.exclusiveHeld = true;
    } else {
      entry.sharedHolders += 1;
    }
    return _LocalLockLease(() {
      if (mode == FilesystemLockMode.exclusive) {
        entry.exclusiveHeld = false;
      } else {
        entry.sharedHolders -= 1;
      }
      _detach(key, entry);
    });
  }

  void _cancelWait(
    String key,
    _ProcessLockEntry entry,
    FilesystemLockMode mode,
  ) {
    if (mode == FilesystemLockMode.exclusive) {
      entry.waitingExclusive -= 1;
    }
    _detach(key, entry);
  }

  void _detach(String key, _ProcessLockEntry entry) {
    entry.participants -= 1;
    if (entry.participants == 0 && identical(_entries[key], entry)) {
      _entries.remove(key);
    }
  }
}

final class _ProcessLockEntry {
  int sharedHolders = 0;
  int waitingExclusive = 0;
  bool exclusiveHeld = false;
  int participants = 0;

  bool canAcquire(FilesystemLockMode mode) => switch (mode) {
    FilesystemLockMode.shared => !exclusiveHeld && waitingExclusive == 0,
    FilesystemLockMode.exclusive => !exclusiveHeld && sharedHolders == 0,
  };
}

final class _LocalLockLease {
  _LocalLockLease(this._release);

  void Function()? _release;

  void release() {
    final release = _release;
    if (release == null) {
      return;
    }
    _release = null;
    release();
  }
}
