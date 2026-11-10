import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_translation/skills_translation.dart';
import 'package:skills_translation/src/atomic_file.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late FileTranslationCache cache;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-translation-cache-',
    );
    root = Directory(p.join(temporary.path, 'translations'));
    if (Platform.isWindows) {
      root = Directory(windowsExtendedPath(root.path));
    }
    cache = FileTranslationCache(rootDirectory: root);
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test('persists a versioned Completed Translation across instances', () async {
    final value = _translation(translatedContent: '# 译文');

    await cache.saveOrReplace(value);
    final reopened = FileTranslationCache(rootDirectory: root);

    expect(await reopened.read(_keyFor(value)), value);
    final jsonFile = await _singleJsonFile(root);
    final json =
        jsonDecode(await jsonFile.readAsString()) as Map<String, Object?>;
    expect(json['version'], 1);
    expect(json, isNot(contains('sourceDocument')));
    expect(json, isNot(contains('apiKey')));
  });

  test('keeps full and description caches separate across reopen', () async {
    final full = _translation(translatedContent: '# 全文');
    final description = _translation(
      scope: TranslationScope.descriptionOnly,
      translatedContent: '简短说明',
    );
    await cache.saveOrReplace(full);
    await cache.saveOrReplace(description);
    final reopened = FileTranslationCache(rootDirectory: root);

    expect(await reopened.read(_keyFor(full)), full);
    expect(await reopened.read(_keyFor(description)), description);
    final replacement = _translation(
      scope: TranslationScope.descriptionOnly,
      translatedContent: '更新的简短说明',
    );
    await reopened.saveOrReplace(replacement);
    expect(await reopened.read(_keyFor(full)), full);
    expect(await reopened.read(_keyFor(description)), replacement);
    expect(await _jsonFiles(root), hasLength(2));
    await reopened.deleteSlot(slotKey: full.slotKey);
    expect(await reopened.read(_keyFor(full)), isNull);
    expect(await reopened.read(_keyFor(description)), isNull);
  });

  test(
    'replaces provider history and removes the prior content generation',
    () async {
      final first = _translation(
        contentHash: 'hash-1',
        translatedContent: 'first',
        providerIdentifier: 'provider-one',
      );
      final replacement = _translation(
        contentHash: 'hash-2',
        translatedContent: 'second',
        providerIdentifier: 'provider-two',
      );

      await cache.saveOrReplace(first);
      await cache.saveOrReplace(replacement);

      expect(await cache.read(_keyFor(first)), isNull);
      expect(await cache.read(_keyFor(replacement)), replacement);
      expect(await _jsonFiles(root), hasLength(1));
    },
  );

  test(
    'keeps documents and languages isolated then evicts stale slot data',
    () async {
      final currentSkill = _translation(
        contentHash: 'current',
        documentIdentifier: 'SKILL.md',
        targetLanguage: 'zh-Hans',
        translatedContent: 'current skill',
      );
      final currentReference = _translation(
        contentHash: 'current',
        documentIdentifier: 'references/guide.md',
        targetLanguage: 'ja',
        translatedContent: 'current reference',
      );
      final staleReference = _translation(
        contentHash: 'stale',
        documentIdentifier: 'references/old.md',
        targetLanguage: 'fr',
        translatedContent: 'stale reference',
      );
      await Future.wait([
        cache.saveOrReplace(currentSkill),
        cache.saveOrReplace(currentReference),
        cache.saveOrReplace(staleReference),
      ]);

      await cache.evictStale(
        slotKey: currentSkill.slotKey,
        currentContentHash: 'current',
      );

      expect(await cache.read(_keyFor(currentSkill)), currentSkill);
      expect(await cache.read(_keyFor(currentReference)), currentReference);
      expect(await cache.read(_keyFor(staleReference)), isNull);
    },
  );

  test('treats a corrupt entry as a miss and removes it', () async {
    final value = _translation(translatedContent: 'valid');
    await cache.saveOrReplace(value);
    final jsonFile = await _singleJsonFile(root);
    await jsonFile.writeAsString('{corrupt');

    expect(await cache.read(_keyFor(value)), isNull);
    expect(await jsonFile.exists(), isFalse);
  });

  test(
    'hashes hostile identity values without escaping the cache root',
    () async {
      final outside = File(p.join(temporary.path, 'outside.json'));
      await outside.writeAsString('untouched');
      final value = _translation(
        slotKey: '../../outside',
        documentIdentifier: '../../../../private/SKILL.md',
        targetLanguage: '../zh-Hans',
        translatedContent: 'safe',
      );

      await cache.saveOrReplace(value);

      expect(await outside.readAsString(), 'untouched');
      await for (final entity in root.list(recursive: true)) {
        expect(p.isWithin(root.path, entity.path), isTrue);
      }
      expect(await cache.read(_keyFor(value)), value);
    },
  );

  test('serializes concurrent writers targeting the same cache root', () async {
    final secondInstance = FileTranslationCache(rootDirectory: root);
    final writes = <Future<void>>[];
    for (var index = 0; index < 30; index += 1) {
      final target = index.isEven ? cache : secondInstance;
      writes.add(
        target.saveOrReplace(
          _translation(translatedContent: 'generation-$index'),
        ),
      );
    }

    await Future.wait(writes);
    final result = await cache.read(_keyFor(_translation()));

    expect(result, isNotNull);
    expect(result!.translatedContent, startsWith('generation-'));
    expect(await _jsonFiles(root), hasLength(1));
  });

  Future<void> waitForExternalCacheLock() async {
    await root.create(recursive: true);
    final lockHandle = await File(
      p.join(root.path, 'cache.lock'),
    ).open(mode: FileMode.append);
    await lockHandle.lock(FileLock.exclusive);
    var lockReleased = false;
    final child = await Process.start(_flutterExecutable, [
      'test',
      '--no-pub',
      '--reporter=expanded',
      '--dart-define=CACHE_ROOT=${root.path}',
      'test/support/locked_cache_writer.dart',
    ], workingDirectory: Directory.current.path);
    final ready = Completer<void>();
    final done = Completer<void>();
    final outputSubscription = child.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.contains('cache-child-ready') && !ready.isCompleted) {
            ready.complete();
          }
          if (line.contains('cache-child-done') && !done.isCompleted) {
            done.complete();
          }
        });
    final stderr = child.stderr.transform(utf8.decoder).join();
    addTearDown(() async {
      if (!lockReleased) {
        await lockHandle.unlock();
        await lockHandle.close();
      }
      await outputSubscription.cancel();
      child.kill();
      await child.exitCode;
    });

    await ready.future.timeout(const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(done.isCompleted, isFalse);

    await lockHandle.unlock();
    await lockHandle.close();
    lockReleased = true;

    final completion = await Future.any([
      done.future.then((_) => 'done'),
      child.exitCode.then((_) => 'exit'),
    ]).timeout(const Duration(seconds: 30));
    if (completion == 'exit' && !done.isCompleted) {
      fail('Cache writer exited before completing:\n${await stderr}');
    }
    expect(await child.exitCode, 0, reason: await stderr);
    expect(
      await cache.read(
        TranslationCacheKey(
          slotKey: 'child-slot',
          contentHash: 'child-hash',
          documentIdentifier: 'SKILL.md',
          targetLanguage: TargetLanguage('zh-Hans'),
        ),
      ),
      isNotNull,
    );
  }

  test(
    'waits for an OS file lock held by another process',
    waitForExternalCacheLock,
    timeout: const Timeout(Duration(seconds: 90)),
  );

  test(
    'deletes one Slot or clears all entries without deleting the root',
    () async {
      final first = _translation(slotKey: 'first-slot');
      final second = _translation(slotKey: 'second-slot');
      await cache.saveOrReplace(first);
      await cache.saveOrReplace(second);

      await cache.deleteSlot(slotKey: first.slotKey);

      expect(await cache.read(_keyFor(first)), isNull);
      expect(await cache.read(_keyFor(second)), second);

      await cache.clear();

      expect(await cache.read(_keyFor(second)), isNull);
      expect(await root.exists(), isTrue);
      expect(await File(p.join(root.path, 'cache.lock')).exists(), isTrue);
    },
  );

  test(
    'external readers observe only complete atomic JSON generations',
    () async {
      const contentLength = 64 * 1024;
      final first = _translation(
        translatedContent: List.filled(contentLength, 'A').join(),
      );
      final second = _translation(
        translatedContent: List.filled(contentLength, 'B').join(),
      );
      await cache.saveOrReplace(first);
      final jsonPath = (await _singleJsonFile(root)).path;
      final stopPath = p.join(temporary.path, 'reader.stop');
      final child = await Process.start(_flutterExecutable, [
        'test',
        '--no-pub',
        '--reporter=expanded',
        '--dart-define=ENTRY_PATH=$jsonPath',
        '--dart-define=STOP_PATH=$stopPath',
        '--dart-define=CONTENT_LENGTH=$contentLength',
        'test/support/atomic_cache_reader.dart',
      ], workingDirectory: Directory.current.path);
      final stderr = child.stderr.transform(utf8.decoder).join();
      final ready = Completer<void>();
      final outputSubscription = child.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.contains('cache-reader-ready') && !ready.isCompleted) {
              ready.complete();
            }
          });
      addTearDown(() async {
        await outputSubscription.cancel();
        child.kill();
        await child.exitCode;
      });
      await ready.future.timeout(const Duration(seconds: 30));

      for (var index = 0; index < 30; index += 1) {
        await cache.saveOrReplace(index.isEven ? second : first);
      }
      await File(stopPath).writeAsString('stop');

      expect(await child.exitCode, 0, reason: await stderr);
      await outputSubscription.cancel();
    },
    timeout: const Timeout(Duration(seconds: 90)),
  );
}

String get _flutterExecutable {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null || flutterRoot.isEmpty) return 'flutter';
  return p.join(
    flutterRoot,
    'bin',
    Platform.isWindows ? 'flutter.bat' : 'flutter',
  );
}

CompletedTranslation _translation({
  String slotKey = 'slot-key',
  String contentHash = 'content-hash',
  String documentIdentifier = 'SKILL.md',
  String targetLanguage = 'zh-Hans',
  String translatedContent = 'translated',
  String providerIdentifier = 'provider',
  TranslationScope scope = TranslationScope.fullDocument,
}) => CompletedTranslation(
  slotKey: slotKey,
  contentHash: contentHash,
  documentIdentifier: documentIdentifier,
  targetLanguage: TargetLanguage(targetLanguage),
  translatedContent: translatedContent,
  scope: scope,
  provenance: TranslationProvenance(
    providerIdentifier: providerIdentifier,
    modelIdentifier: 'model',
  ),
);

TranslationCacheKey _keyFor(CompletedTranslation value) => TranslationCacheKey(
  slotKey: value.slotKey,
  contentHash: value.contentHash,
  documentIdentifier: value.documentIdentifier,
  targetLanguage: value.targetLanguage,
  scope: value.scope,
);

Future<List<File>> _jsonFiles(Directory root) async =>
    root
        .list(recursive: true, followLinks: false)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();

Future<File> _singleJsonFile(Directory root) async {
  final files = await _jsonFiles(root);
  expect(files, hasLength(1));
  return files.single;
}
