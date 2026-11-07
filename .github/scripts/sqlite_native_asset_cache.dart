import 'dart:io';

const _sourceEnvironmentKey = 'SQLITE_NATIVE_ASSET_SOURCE';
const _cacheEnvironmentKey = 'SQLITE_NATIVE_ASSET_CACHE';
const _sqliteReleaseTag = 'sqlite3-3.5.2';
const _supportedModes = {
  'save',
  'seed-current-platform',
  'seed-macos',
  'restore',
};

const _macOsUniversalArtifacts = [
  _SqliteArtifact(
    sourceName: 'libsqlite3.arm64.macos.dylib',
    installedName: 'libsqlite3.dylib',
    sha256: '6d80ba56cff1fa44f62bebc3e6b6b71513cc628862a9745c223c7bea8bf813f3',
  ),
  _SqliteArtifact(
    sourceName: 'libsqlite3.x64.macos.dylib',
    installedName: 'libsqlite3.dylib',
    sha256: '4ee3335ce95e17c36e4002bfeede2a3b2f77d9ac8434d0b7ed421d3e2205b216',
  ),
];

const _linuxX64Artifact = _SqliteArtifact(
  sourceName: 'libsqlite3.x64.linux.so',
  installedName: 'libsqlite3.so',
  sha256: 'b17729184e5a2818055ecbddd5ed6642521bfe6e56aafa472330e483c0e2e0d2',
);

const _windowsX64Artifact = _SqliteArtifact(
  sourceName: 'sqlite3.x64.windows.dll',
  installedName: 'sqlite3.dll',
  sha256: '2bf39f2aadafdc59a90b260f582a8fccebc5b89eb94175fdbaa9148c1e1f084d',
);

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1 || !_supportedModes.contains(arguments[0])) {
    stderr.writeln(
      'Usage: dart sqlite_native_asset_cache.dart '
      '<save|seed-current-platform|seed-macos|restore>',
    );
    exitCode = 64;
    return;
  }

  final cache = Directory(_requiredEnvironment(_cacheEnvironmentKey));
  final mode = arguments.single;

  switch (mode) {
    case 'save':
      final source = Directory(_requiredEnvironment(_sourceEnvironmentKey));
      await _replaceCache(source: source, cache: cache);
    case 'seed-current-platform':
      await _seedArtifacts(cache, _currentPlatformArtifacts());
    case 'seed-macos':
      if (!Platform.isMacOS) {
        throw UnsupportedError('seed-macos is only supported on macOS.');
      }
      await _seedArtifacts(cache, _macOsUniversalArtifacts);
    case 'restore':
      final source = Directory(_requiredEnvironment(_sourceEnvironmentKey));
      await _restoreCache(source: source, cache: cache);
  }
}

String _requiredEnvironment(String name) {
  final value = Platform.environment[name];
  if (value == null || value.trim().isEmpty) {
    throw StateError('$name must be configured.');
  }
  return value;
}

Future<void> _replaceCache({
  required Directory source,
  required Directory cache,
}) async {
  final downloads = await _verifiedDownloadDirectories(source);
  if (downloads.isEmpty) {
    throw StateError(
      'No verified SQLite Native Asset downloads were found in ${source.path}.',
    );
  }

  await _moveAsideIfPresent(cache.path);
  await cache.create(recursive: true);
  for (final download in downloads) {
    await _copyDirectory(
      download.directory,
      _childDirectory(cache, _basename(download.directory)),
    );
  }
  stdout.writeln('Saved ${downloads.length} SQLite Native Asset download(s).');
}

Future<void> _restoreCache({
  required Directory source,
  required Directory cache,
}) async {
  final downloads = await _verifiedDownloadDirectories(cache);
  if (downloads.isEmpty) {
    throw StateError(
      'No preserved SQLite Native Asset downloads were found in ${cache.path}.',
    );
  }

  await _ensurePlainDirectory(source);
  for (final download in downloads) {
    final destination = _childDirectory(source, _basename(download.directory));
    await _moveAsideIfPresent(destination.path);
    await _copyDirectory(download.directory, destination);
  }
  stdout.writeln(
    'Restored ${downloads.length} SQLite Native Asset download(s).',
  );
}

Future<void> _seedArtifacts(
  Directory cache,
  List<_SqliteArtifact> artifacts,
) async {
  await _ensurePlainDirectory(cache);
  await _quarantineUnrecognizedDownloads(cache, artifacts);
  for (final artifact in artifacts) {
    final directory = _childDirectory(cache, artifact.directoryName);
    if (await _isVerifiedDownloadDirectory(directory, artifact)) {
      stdout.writeln('Reused verified ${artifact.sourceName}.');
      continue;
    }
    await _moveAsideIfPresent(directory.path);
    await _ensurePlainDirectory(directory);
    final destination = _childFile(directory, artifact.installedName);

    final temporary = File('${destination.path}.download');
    final uri = Uri.https(
      'github.com',
      '/simolus3/sqlite3.dart/releases/download/'
          '$_sqliteReleaseTag/${artifact.sourceName}',
    );
    final curl = Platform.isWindows ? 'curl.exe' : 'curl';
    final download = await Process.run(curl, [
      '--fail',
      '--location',
      '--http1.1',
      '--retry',
      '8',
      '--retry-all-errors',
      '--retry-max-time',
      '1200',
      '--retry-delay',
      '2',
      '--connect-timeout',
      '20',
      '--max-time',
      '300',
      '--output',
      temporary.path,
      uri.toString(),
    ]);
    if (download.exitCode != 0) {
      throw ProcessException(
        curl,
        [uri.toString()],
        '${download.stdout}\n${download.stderr}',
        download.exitCode,
      );
    }
    if (!await _hasSha256(temporary, artifact.sha256)) {
      final actual = await _sha256(temporary);
      await _moveAsideIfPresent(temporary.path);
      throw StateError(
        'Downloaded ${artifact.sourceName} did not match its pinned SHA-256: '
        '$actual, expected ${artifact.sha256}.',
      );
    }
    await temporary.rename(destination.path);
    stdout.writeln('Seeded verified ${artifact.sourceName}.');
  }
}

Future<bool> _hasSha256(File file, String expected) async {
  return await _sha256(file) == expected;
}

Future<String> _sha256(File file) async {
  final executable = Platform.isWindows ? 'certutil.exe' : 'shasum';
  final arguments = Platform.isWindows
      ? ['-hashfile', file.path, 'SHA256']
      : ['-a', '256', file.path];
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  final output = (result.stdout as String).trim();
  final actual = RegExp(
    r'(?<![0-9a-fA-F])[0-9a-fA-F]{64}(?![0-9a-fA-F])',
  ).firstMatch(output)?.group(0)?.toLowerCase();
  if (actual == null || actual.isEmpty) {
    throw StateError('$executable returned no digest for ${file.path}.');
  }
  return actual;
}

Future<List<_VerifiedDownload>> _verifiedDownloadDirectories(
  Directory parent,
) async {
  if (!await parent.exists()) return const [];
  final expected = {
    for (final artifact in _currentPlatformArtifacts())
      artifact.directoryName: artifact,
  };
  final downloads = <_VerifiedDownload>[];
  await for (final entity in parent.list(followLinks: false)) {
    if (entity is! Directory || !_basename(entity).startsWith('download-')) {
      continue;
    }
    final name = _basename(entity);
    final artifact = expected[name];
    if (artifact == null) {
      throw StateError('Unexpected SQLite Native Asset cache entry: $name.');
    }
    if (!await _isVerifiedDownloadDirectory(entity, artifact)) {
      throw StateError(
        'SQLite Native Asset cache entry $name failed its pinned manifest.',
      );
    }
    downloads.add(_VerifiedDownload(entity));
  }
  downloads.sort(
    (left, right) => left.directory.path.compareTo(right.directory.path),
  );
  return downloads;
}

Future<void> _quarantineUnrecognizedDownloads(
  Directory cache,
  List<_SqliteArtifact> artifacts,
) async {
  final expected = {
    for (final artifact in artifacts) artifact.directoryName: artifact,
  };
  final entries = await cache.list(followLinks: false).toList();
  for (final entry in entries) {
    final name = _basename(entry);
    if (!name.startsWith('download-')) continue;
    final artifact = expected[name];
    if (entry is! Directory ||
        artifact == null ||
        !await _isVerifiedDownloadDirectory(entry, artifact)) {
      await _moveAsideIfPresent(entry.path);
    }
  }
}

Future<bool> _isVerifiedDownloadDirectory(
  Directory directory,
  _SqliteArtifact artifact,
) async {
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    return false;
  }
  final entries = await directory.list(followLinks: false).toList();
  if (entries.length != 1 || entries.single is! File) return false;
  final file = entries.single as File;
  return _basename(file) == artifact.installedName &&
      await _hasSha256(file, artifact.sha256);
}

List<_SqliteArtifact> _currentPlatformArtifacts() {
  if (Platform.isMacOS) return _macOsUniversalArtifacts;
  final runnerArchitecture = Platform.environment['RUNNER_ARCH']
      ?.trim()
      .toUpperCase();
  if (runnerArchitecture != null &&
      runnerArchitecture.isNotEmpty &&
      runnerArchitecture != 'X64') {
    throw UnsupportedError(
      'SQLite Native Asset CI seeding is not configured for '
      '$runnerArchitecture on ${Platform.operatingSystem}.',
    );
  }
  if (Platform.isLinux) return const [_linuxX64Artifact];
  if (Platform.isWindows) return const [_windowsX64Artifact];
  throw UnsupportedError(
    'SQLite Native Asset CI seeding is unsupported on '
    '${Platform.operatingSystem}.',
  );
}

Future<void> _moveAsideIfPresent(String targetPath) async {
  final type = await FileSystemEntity.type(targetPath, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final quarantineRoot = File(targetPath).parent;
  final name = _basename(File(targetPath));
  final quarantine = _childFile(
    quarantineRoot,
    '.sqlite-native-asset-quarantine-$name-$timestamp',
  ).path;
  switch (type) {
    case FileSystemEntityType.file:
      await File(targetPath).rename(quarantine);
    case FileSystemEntityType.directory:
      await Directory(targetPath).rename(quarantine);
    case FileSystemEntityType.link:
      await Link(targetPath).rename(quarantine);
    default:
      throw StateError('Unsupported cache entry: $targetPath.');
  }
  stderr.writeln('Moved an existing cache entry to $quarantine.');
}

Future<void> _ensurePlainDirectory(Directory directory) async {
  final type = await FileSystemEntity.type(directory.path, followLinks: false);
  if (type == FileSystemEntityType.directory) return;
  if (type != FileSystemEntityType.notFound) {
    await _moveAsideIfPresent(directory.path);
  }
  await directory.create(recursive: true);
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    final name = _basename(entity);
    if (entity is Directory) {
      await _copyDirectory(entity, _childDirectory(destination, name));
    } else if (entity is File) {
      await entity.copy(_childFile(destination, name).path);
    } else {
      throw StateError('Unsupported cache entry: ${entity.path}');
    }
  }
}

Directory _childDirectory(Directory parent, String name) {
  return Directory.fromUri(parent.uri.resolve('$name/'));
}

File _childFile(Directory parent, String name) {
  return File.fromUri(parent.uri.resolve(name));
}

String _basename(FileSystemEntity entity) {
  return entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
}

final class _SqliteArtifact {
  const _SqliteArtifact({
    required this.sourceName,
    required this.installedName,
    required this.sha256,
  });

  final String sourceName;
  final String installedName;
  final String sha256;

  String get directoryName => 'download-${sha256.substring(0, 8)}';
}

final class _VerifiedDownload {
  const _VerifiedDownload(this.directory);

  final Directory directory;
}
