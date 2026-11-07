import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late RevisionNativeEngine engine;
  final tree = const SkillContentNormalizer().normalize([
    SkillContentEntry.file(
      path: 'SKILL.md',
      bytes: utf8.encode(
        '---\nname: fixture\ndescription: Test\n---\n# Fixture\n',
      ),
    ),
  ]).valueOrNull!;

  setUp(() {
    // Keep Store paths below libgit2's separate repository-path budget.
    temporary = Directory.systemTemp.createTempSync('rp-');
    engine = RevisionNativeEngine.open();
  });
  tearDown(() {
    engine.close();
    temporary.deleteSync(recursive: true);
  });

  RevisionObjectId commit(String store) {
    engine.createStore(store);
    return engine.createCommit(
      repositoryPath: store,
      request: RevisionCommitRequest(
        tree: engine.writeTree(store, tree),
        parents: const [],
        kind: RevisionCommitKind.initial,
      ),
    );
  }

  void roundTrip(String store, String bundle, String restored) {
    final root = commit(store);
    Directory(bundle).createSync(recursive: true);
    engine.createRecoveryPack(
      repositoryPath: store,
      bundleStagingPath: bundle,
      retainedRoots: [root],
    );
    expect(
      Directory(bundle).listSync().map((entry) => p.basename(entry.path)),
      unorderedEquals(['objects.pack', 'objects.idx']),
    );
    engine.restoreRecoveryPack(
      stagedRepositoryPath: restored,
      packPath: p.join(bundle, 'objects.pack'),
      indexPath: p.join(bundle, 'objects.idx'),
      retainedRoots: [root],
    );
    expect(engine.readTree(restored, root).contentHash, tree.contentHash);
  }

  for (final store in ['store', '仓库']) {
    for (final bundle in ['bundle', '恢复包']) {
      for (final restored in ['restored', '还原']) {
        test('round trips $store / $bundle / $restored paths', () {
          roundTrip(
            p.join(temporary.path, '$store.git'),
            p.join(temporary.path, bundle),
            p.join(temporary.path, '$restored.git'),
          );
        });
      }
    }
  }

  test('round trips relative Unicode Bundle paths', () {
    roundTrip(
      p.join(temporary.path, 'store.git'),
      p.relative(p.join(temporary.path, '恢复包')),
      p.join(temporary.path, 'restored.git'),
    );
  });

  for (final length in [241, 259, 261, 281]) {
    test('round trips a generated Pack path of $length characters', () {
      final prefix = p.join(temporary.path, 'bundle');
      final suffixLength = p.join('', 'pack-${'0' * 40}.pack').length + 1;
      final bundle = p.join(
        prefix,
        'x' * (length - suffixLength - prefix.length - 1),
      );
      expect(p.join(bundle, 'pack-${'0' * 40}.pack').length, length);
      roundTrip(
        p.join(temporary.path, 'store.git'),
        bundle,
        p.join(temporary.path, 'restored.git'),
      );
    });
  }

  for (final occupied in ['objects.pack', 'objects.idx']) {
    test('preserves an existing Chinese Bundle $occupied', () {
      final store = p.join(temporary.path, '仓库.git');
      final root = commit(store);
      final bundle = Directory(p.join(temporary.path, '恢复包'))..createSync();
      final existing = File(p.join(bundle.path, occupied))
        ..writeAsStringSync('keep');
      expect(
        () => engine.createRecoveryPack(
          repositoryPath: store,
          bundleStagingPath: bundle.path,
          retainedRoots: [root],
        ),
        throwsA(
          isA<RevisionNativeException>().having(
            (error) => error.code,
            'code',
            RevisionNativeFailureCode.bundleFailure,
          ),
        ),
      );
      expect(existing.readAsStringSync(), 'keep');
      expect(bundle.listSync().map((entry) => p.basename(entry.path)), [
        occupied,
      ]);
    });
  }

  test(
    'failed Index rename rolls back the Chinese Pack without a half Bundle',
    () {
      final store = p.join(temporary.path, '仓库.git');
      final root = commit(store);
      final bundle = Directory(p.join(temporary.path, '恢复包'))..createSync();
      Directory(p.join(bundle.path, 'objects.idx')).createSync();
      expect(
        () => engine.createRecoveryPack(
          repositoryPath: store,
          bundleStagingPath: bundle.path,
          retainedRoots: [root],
        ),
        throwsA(isA<RevisionNativeException>()),
      );
      expect(File(p.join(bundle.path, 'objects.pack')).existsSync(), isFalse);
      expect(
        Directory(p.join(bundle.path, 'objects.idx')).existsSync(),
        isTrue,
      );
      if (Platform.isWindows) {
        // Windows fopen rejects directories: the second rename fails after the
        // first succeeds. POSIX may reject the directory in the existence check.
        expect(
          bundle.listSync().whereType<File>().map(
            (file) => p.extension(file.path),
          ),
          unorderedEquals(['.pack', '.idx']),
        );
      }
    },
  );

  test('missing Chinese source Index leaves no destination Index', () {
    final store = p.join(temporary.path, '仓库.git');
    final bundle = Directory(p.join(temporary.path, '恢复包'))..createSync();
    final root = commit(store);
    engine.createRecoveryPack(
      repositoryPath: store,
      bundleStagingPath: bundle.path,
      retainedRoots: [root],
    );
    final restored = p.join(temporary.path, '还原.git');
    expect(
      () => engine.restoreRecoveryPack(
        stagedRepositoryPath: restored,
        packPath: p.join(bundle.path, 'objects.pack'),
        indexPath: p.join(bundle.path, '缺少.idx'),
        retainedRoots: [root],
      ),
      throwsA(isA<RevisionNativeException>()),
    );
    expect(
      Directory(p.join(restored, 'objects', 'pack'))
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.idx')),
      isEmpty,
    );
  });
  test('an unreadable Chinese Index stream removes the failed copy', () {
    final store = p.join(temporary.path, '仓库.git');
    final bundle = Directory(p.join(temporary.path, '恢复包'))..createSync();
    final root = commit(store);
    engine.createRecoveryPack(
      repositoryPath: store,
      bundleStagingPath: bundle.path,
      retainedRoots: [root],
    );
    final unreadable = Directory(p.join(bundle.path, '目录.idx'))..createSync();
    final restored = p.join(temporary.path, '还原.git');
    expect(
      () => engine.restoreRecoveryPack(
        stagedRepositoryPath: restored,
        packPath: p.join(bundle.path, 'objects.pack'),
        indexPath: unreadable.path,
        retainedRoots: [root],
      ),
      throwsA(isA<RevisionNativeException>()),
    );
    expect(
      Directory(p.join(restored, 'objects', 'pack'))
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.idx')),
      isEmpty,
    );
  });
}
