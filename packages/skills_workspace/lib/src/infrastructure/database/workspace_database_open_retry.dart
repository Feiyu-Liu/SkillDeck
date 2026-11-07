import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

typedef WorkspaceDatabaseSyncSleeper = void Function(Duration duration);
typedef WorkspaceDatabaseAsyncSleeper =
    Future<void> Function(Duration duration);

/// Bounded retry policy for Windows SQLite opens immediately after a forced
/// process termination.
///
/// Windows filesystem filters can briefly retain WAL/SHM handles after the
/// owning process has exited. SQLite then reports a narrow set of locking or
/// VFS I/O result codes while reopening or truncating those files. Retrying
/// only those codes keeps genuine corruption and permission failures fail-fast.
final class WorkspaceDatabaseOpenRetryPolicy {
  const WorkspaceDatabaseOpenRetryPolicy({
    required this.isWindows,
    this.timeout = const Duration(seconds: 10),
    this.initialDelay = const Duration(milliseconds: 2),
    this.maximumDelay = const Duration(milliseconds: 100),
  });

  factory WorkspaceDatabaseOpenRetryPolicy.current() =>
      WorkspaceDatabaseOpenRetryPolicy(isWindows: Platform.isWindows);

  final bool isWindows;
  final Duration timeout;
  final Duration initialDelay;
  final Duration maximumDelay;

  bool isRetryableError(Object error) {
    if (!isWindows || error is! sqlite.SqliteException) return false;
    if (error.resultCode == sqlite.SqlError.SQLITE_BUSY ||
        error.resultCode == sqlite.SqlError.SQLITE_LOCKED) {
      return true;
    }
    return switch (error.extendedResultCode) {
      sqlite.SqlExtendedError.SQLITE_IOERR_TRUNCATE ||
      sqlite.SqlExtendedError.SQLITE_IOERR_UNLOCK ||
      sqlite.SqlExtendedError.SQLITE_IOERR_RDLOCK ||
      sqlite.SqlExtendedError.SQLITE_IOERR_DELETE ||
      sqlite.SqlExtendedError.SQLITE_IOERR_ACCESS ||
      sqlite.SqlExtendedError.SQLITE_IOERR_CHECKRESERVEDLOCK ||
      sqlite.SqlExtendedError.SQLITE_IOERR_LOCK ||
      sqlite.SqlExtendedError.SQLITE_IOERR_CLOSE ||
      sqlite.SqlExtendedError.SQLITE_IOERR_SHMOPEN ||
      sqlite.SqlExtendedError.SQLITE_IOERR_SHMSIZE ||
      sqlite.SqlExtendedError.SQLITE_IOERR_SHMMAP => true,
      _ => false,
    };
  }

  T runSync<T>(T Function() action, {WorkspaceDatabaseSyncSleeper? sleeper}) {
    final delays = _retryDelays().iterator;
    while (true) {
      try {
        return action();
      } on Object catch (error) {
        if (!isRetryableError(error) || !delays.moveNext()) rethrow;
        (sleeper ?? sleep)(delays.current);
      }
    }
  }

  Future<T> runAsync<T>(
    Future<T> Function() action, {
    WorkspaceDatabaseAsyncSleeper? sleeper,
  }) async {
    final delays = _retryDelays().iterator;
    while (true) {
      try {
        return await action();
      } on Object catch (error) {
        if (!isRetryableError(error) || !delays.moveNext()) rethrow;
        await (sleeper ?? Future<void>.delayed)(delays.current);
      }
    }
  }

  Iterable<Duration> _retryDelays() sync* {
    if (timeout <= Duration.zero ||
        initialDelay <= Duration.zero ||
        maximumDelay <= Duration.zero) {
      return;
    }
    var elapsed = Duration.zero;
    var delay = initialDelay;
    while (elapsed < timeout) {
      final remaining = timeout - elapsed;
      final current = delay < remaining ? delay : remaining;
      yield current;
      elapsed += current;
      final doubled = delay * 2;
      delay = doubled < maximumDelay ? doubled : maximumDelay;
    }
  }
}
