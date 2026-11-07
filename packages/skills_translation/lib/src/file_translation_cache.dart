import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'atomic_file.dart';
import 'models.dart';
import 'translation_cache.dart';
import 'validation.dart';

const int _cacheFormatVersion = 1;
const int _descriptionCacheFormatVersion = 2;

/// Versioned, atomic file implementation of [TranslationCache].
final class FileTranslationCache implements TranslationCache {
  /// Creates a cache rooted at an app-owned directory outside Skill Workspace.
  FileTranslationCache({required Directory rootDirectory})
    : _rootDirectory = Directory(
        Platform.isWindows
            ? windowsExtendedPath(rootDirectory.absolute.path)
            : p.normalize(rootDirectory.absolute.path),
      ),
      _coordinator = _CacheCoordinator.forRoot(
        p.normalize(rootDirectory.absolute.path),
      );

  final Directory _rootDirectory;
  final _CacheCoordinator _coordinator;
  final AtomicFileWriter _atomicWriter = AtomicFileWriter();

  String get _entriesPath => p.join(_rootDirectory.path, 'entries');
  String get _lockPath => p.join(_rootDirectory.path, 'cache.lock');

  @override
  Future<CompletedTranslation?> read(TranslationCacheKey key) =>
      _coordinator.synchronized(() => _withFileLock(() => _readLocked(key)));

  @override
  Future<void> saveOrReplace(CompletedTranslation value) =>
      _coordinator.synchronized(() => _withFileLock(() => _saveLocked(value)));

  @override
  Future<void> evictStale({
    required String slotKey,
    required String currentContentHash,
  }) {
    requireNonBlank(slotKey, 'slotKey');
    requireNonBlank(currentContentHash, 'currentContentHash');
    return _coordinator.synchronized(
      () => _withFileLock(
        () => _evictStaleLocked(
          slotKey: slotKey,
          currentContentHash: currentContentHash,
        ),
      ),
    );
  }

  @override
  Future<void> deleteSlot({required String slotKey}) {
    requireNonBlank(slotKey, 'slotKey');
    return _coordinator.synchronized(
      () => _withFileLock(() => _deleteSlotLocked(slotKey)),
    );
  }

  @override
  Future<void> clear() => _coordinator.synchronized(
    () => _withFileLock(() async {
      final entries = Directory(_entriesPath);
      if (await entries.exists()) {
        await entries.delete(recursive: true);
      }
    }),
  );

  Future<T> _withFileLock<T>(Future<T> Function() action) async {
    await _rootDirectory.create(recursive: true);
    final handle = await File(_lockPath).open(mode: FileMode.append);
    try {
      await handle.lock(FileLock.blockingExclusive);
      return await action();
    } finally {
      try {
        await handle.unlock();
      } finally {
        await handle.close();
      }
    }
  }

  Future<CompletedTranslation?> _readLocked(TranslationCacheKey key) async {
    final path = _entryPath(key);
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    try {
      final decoded = jsonDecode(await readAtomicFileString(path));
      final entry = _decodeEntry(decoded);
      if (!_matchesKey(entry, key)) {
        await file.delete();
        return null;
      }
      return entry;
    } on FormatException {
      await _deleteIfPresent(file);
      return null;
    } on TypeError {
      await _deleteIfPresent(file);
      return null;
    }
  }

  Future<void> _saveLocked(CompletedTranslation value) async {
    final key = TranslationCacheKey(
      slotKey: value.slotKey,
      contentHash: value.contentHash,
      documentIdentifier: value.documentIdentifier,
      targetLanguage: value.targetLanguage,
      scope: value.scope,
    );
    final path = _entryPath(key);
    await AtomicFileWriter.cleanupTemporarySiblings(path);
    await _atomicWriter.writeString(path, jsonEncode(_encodeEntry(value)));

    final generationDirectory = File(path).parent;
    if (await generationDirectory.exists()) {
      await for (final entity in generationDirectory.list(followLinks: false)) {
        if (entity is File &&
            entity.path.endsWith('.json') &&
            p.normalize(entity.path) != p.normalize(path)) {
          await entity.delete();
        }
      }
    }
  }

  Future<void> _evictStaleLocked({
    required String slotKey,
    required String currentContentHash,
  }) async {
    final slotDirectory = Directory(_slotPath(slotKey));
    if (!await slotDirectory.exists()) {
      return;
    }
    await for (final entity in slotDirectory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File || !entity.path.endsWith('.json')) {
        continue;
      }
      final entry = await _tryDecodeFile(entity);
      if (entry == null ||
          entry.slotKey != slotKey ||
          entry.contentHash != currentContentHash) {
        await _deleteIfPresent(entity);
      }
    }
    await _deleteEmptyDirectories(slotDirectory);
  }

  Future<void> _deleteSlotLocked(String slotKey) async {
    final slotDirectory = Directory(_slotPath(slotKey));
    if (await slotDirectory.exists()) {
      await slotDirectory.delete(recursive: true);
    }
  }

  Future<CompletedTranslation?> _tryDecodeFile(File file) async {
    try {
      return _decodeEntry(jsonDecode(await readAtomicFileString(file.path)));
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  String _entryPath(TranslationCacheKey key) => p.joinAll([
    _slotPath(key.slotKey),
    _digest(key.documentIdentifier),
    _digest(key.targetLanguage.identifier),
    if (key.scope == TranslationScope.descriptionOnly) 'description-only',
    '${_digest(key.contentHash)}.json',
  ]);

  String _slotPath(String slotKey) => p.join(_entriesPath, _digest(slotKey));
}

Map<String, Object?> _encodeEntry(CompletedTranslation value) => {
  'version':
      value.scope == TranslationScope.fullDocument
          ? _cacheFormatVersion
          : _descriptionCacheFormatVersion,
  if (value.scope == TranslationScope.descriptionOnly)
    'scope': 'descriptionOnly',
  'slotKey': value.slotKey,
  'contentHash': value.contentHash,
  'documentIdentifier': value.documentIdentifier,
  'targetLanguage': value.targetLanguage.identifier,
  'translatedContent': value.translatedContent,
  'provenance': {
    'providerIdentifier': value.provenance.providerIdentifier,
    if (value.provenance.modelIdentifier != null)
      'modelIdentifier': value.provenance.modelIdentifier,
  },
};

CompletedTranslation _decodeEntry(Object? value) {
  final json = _jsonObject(value, 'entry');
  final version = json['version'];
  if (version != _cacheFormatVersion &&
      version != _descriptionCacheFormatVersion) {
    throw const FormatException('Unsupported translation cache version.');
  }
  final scope = switch ((version, json['scope'])) {
    (1, null) => TranslationScope.fullDocument,
    (_descriptionCacheFormatVersion, 'descriptionOnly') =>
      TranslationScope.descriptionOnly,
    _ => throw const FormatException('Invalid translation scope.'),
  };
  final provenance = _jsonObject(json['provenance'], 'provenance');
  return CompletedTranslation(
    slotKey: _jsonString(json, 'slotKey'),
    contentHash: _jsonString(json, 'contentHash'),
    documentIdentifier: _jsonString(json, 'documentIdentifier'),
    targetLanguage: TargetLanguage(_jsonString(json, 'targetLanguage')),
    translatedContent: _jsonString(json, 'translatedContent'),
    scope: scope,
    provenance: TranslationProvenance(
      providerIdentifier: _jsonString(provenance, 'providerIdentifier'),
      modelIdentifier: _nullableJsonString(provenance, 'modelIdentifier'),
    ),
  );
}

bool _matchesKey(CompletedTranslation value, TranslationCacheKey key) =>
    value.slotKey == key.slotKey &&
    value.contentHash == key.contentHash &&
    value.documentIdentifier == key.documentIdentifier &&
    value.targetLanguage == key.targetLanguage &&
    value.scope == key.scope;

Map<String, Object?> _jsonObject(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('$name must be a JSON object.');
  }
  return Map<String, Object?>.from(value);
}

String _jsonString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-blank string.');
  }
  return value;
}

String? _nullableJsonString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be null or a non-blank string.');
  }
  return value;
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

Future<void> _deleteIfPresent(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

Future<void> _deleteEmptyDirectories(Directory root) async {
  if (!await root.exists()) {
    return;
  }
  final directories =
      await root
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is Directory)
          .cast<Directory>()
          .toList();
  directories.sort(
    (left, right) => right.path.length.compareTo(left.path.length),
  );
  for (final directory in [...directories, root]) {
    if (await directory.exists() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }
}

final class _CacheCoordinator {
  _CacheCoordinator._();

  static final Map<String, _CacheCoordinator> _byRoot = {};

  static _CacheCoordinator forRoot(String root) =>
      _byRoot.putIfAbsent(root, _CacheCoordinator._);

  Future<void> _tail = Future<void>.value();

  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = previous.then<void>(
      (_) => release.future,
      onError: (_) => release.future,
    );
    return () async {
      try {
        await previous;
      } catch (_) {
        // A failed operation must not poison the cache's in-process queue.
      }
      try {
        return await action();
      } finally {
        release.complete();
      }
    }();
  }
}
