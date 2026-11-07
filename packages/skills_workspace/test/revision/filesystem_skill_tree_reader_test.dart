import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:skills_workspace/src/infrastructure/content/content_result.dart';
import 'package:skills_workspace/src/infrastructure/content/filesystem_skill_tree_reader.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-tree-reader-',
    );
  });

  tearDown(() async {
    if (temporaryDirectory.existsSync()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  for (final limit in ['fileCount', 'byteSize']) {
    test('stops walking as soon as $limit is exceeded', () async {
      await File(paths.join(temporaryDirectory.path, 'a')).writeAsString('123');
      await File(paths.join(temporaryDirectory.path, 'b')).writeAsString('456');
      // This would fail capture if traversal continued past the limit.
      await Link(
        paths.join(temporaryDirectory.path, 'z-broken'),
      ).create('missing');
      final result = await FilesystemSkillTreeReader(
        normalizer: SkillContentNormalizer(
          maximumFileCount: limit == 'fileCount' ? 1 : 1000,
          maximumByteSize: limit == 'byteSize' ? 4 : 100,
        ),
      ).read(temporaryDirectory.path);
      expect(result.failureOrNull?.code, SkillContentFailureCode.limitExceeded);
      expect(result.failureOrNull?.context['limit'], limit);
      expect(
        result.failureOrNull?.context['actual'],
        limit == 'fileCount' ? 2 : 6,
      );
      expect(result.failureOrNull?.context['actualIsLowerBound'], isTrue);
    });
  }
  test('captures regular files and POSIX executable intent', () async {
    final file = File(paths.join(temporaryDirectory.path, 'bin', 'run'));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(const <int>[0, 255, 1]);
    if (!Platform.isWindows) {
      await Process.run('chmod', <String>['755', file.path]);
    }

    final result = await const FilesystemSkillTreeReader().read(
      temporaryDirectory.path,
    );

    expect(result, isA<SkillContentSuccess<NormalizedSkillTree>>());
    expect(result.valueOrNull!.files.single.relativePath, 'bin/run');
    expect(result.valueOrNull!.files.single.bytes, const <int>[0, 255, 1]);
    expect(
      result.valueOrNull!.files.single.isExecutable,
      Platform.isWindows ? isFalse : isTrue,
    );
  });

  test(
    'Windows policy preserves base intent and makes new files inert',
    () async {
      await File(
        paths.join(temporaryDirectory.path, 'existing'),
      ).writeAsString('old');
      await File(
        paths.join(temporaryDirectory.path, 'new'),
      ).writeAsString('new');

      final result = await const FilesystemSkillTreeReader(
        capturePosixExecutableIntent: false,
        executableIntentOverrides: <String, bool>{'existing': true},
      ).read(temporaryDirectory.path);
      final files = <String, NormalizedSkillFile>{
        for (final file in result.valueOrNull!.files) file.relativePath: file,
      };

      expect(files['existing']!.isExecutable, isTrue);
      expect(files['new']!.isExecutable, isFalse);
    },
  );

  test('rejects an empty Git metadata directory', () async {
    await Directory(paths.join(temporaryDirectory.path, '.GiT')).create();

    final result = await const FilesystemSkillTreeReader().read(
      temporaryDirectory.path,
    );

    expect(result.failureOrNull?.code, SkillContentFailureCode.invalidContent);
    expect(result.failureOrNull?.context['reason'], 'gitMetadataNotAllowed');
  });

  test('external source policy excludes Git metadata from the tree', () async {
    final source = Directory(paths.join(temporaryDirectory.path, 'source'));
    final plain = Directory(paths.join(temporaryDirectory.path, 'plain'));
    await source.create();
    await plain.create();
    for (final root in <Directory>[source, plain]) {
      await File(paths.join(root.path, 'SKILL.md')).writeAsString('skill');
      await File(paths.join(root.path, '.gitignore')).writeAsString('build/');
    }
    await Directory(paths.join(source.path, '.GiT')).create();
    await File(
      paths.join(source.path, '.GiT', 'config'),
    ).writeAsString('secret');

    final reader = const FilesystemSkillTreeReader(
      gitMetadataDisposition: GitMetadataDisposition.exclude,
    );
    final sourceResult = await reader.read(source.path);
    final plainResult = await reader.read(plain.path);

    expect(sourceResult.failureOrNull, isNull);
    expect(
      sourceResult.valueOrNull!.files.map((file) => file.relativePath),
      <String>['.gitignore', 'SKILL.md'],
    );
    expect(
      sourceResult.valueOrNull!.contentHash,
      plainResult.valueOrNull!.contentHash,
    );
  });

  test('external source policy excludes a Git worktree pointer file', () async {
    await File(
      paths.join(temporaryDirectory.path, 'SKILL.md'),
    ).writeAsString('skill');
    await File(
      paths.join(temporaryDirectory.path, '.git'),
    ).writeAsString('gitdir: /private/repository');

    final result = await const FilesystemSkillTreeReader(
      gitMetadataDisposition: GitMetadataDisposition.exclude,
    ).read(temporaryDirectory.path);

    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.files.map((file) => file.relativePath), <String>[
      'SKILL.md',
    ]);
  });

  test('external source policy never resolves a Git metadata link', () async {
    if (Platform.isWindows) return;
    final outside = await Directory.systemTemp.createTemp(
      'skills-workspace-git-metadata-',
    );
    addTearDown(() => outside.delete(recursive: true));
    await File(paths.join(outside.path, 'config')).writeAsString('secret');
    await File(
      paths.join(temporaryDirectory.path, 'SKILL.md'),
    ).writeAsString('skill');
    await Link(
      paths.join(temporaryDirectory.path, '.git'),
    ).create(outside.path);

    final result = await const FilesystemSkillTreeReader(
      gitMetadataDisposition: GitMetadataDisposition.exclude,
    ).read(temporaryDirectory.path);

    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.files.single.relativePath, 'SKILL.md');
  });

  test('rejects roots that are not directories', () async {
    final file = File(paths.join(temporaryDirectory.path, 'file'));
    await file.writeAsString('content');

    final result = await const FilesystemSkillTreeReader().read(file.path);

    expect(result.failureOrNull?.code, SkillContentFailureCode.unavailable);
    expect(result.failureOrNull?.context['reason'], 'sourceRootNotDirectory');
  });

  test('enforces normalization limits after dereferencing', () async {
    await File(paths.join(temporaryDirectory.path, 'a')).writeAsString('a');
    await File(paths.join(temporaryDirectory.path, 'b')).writeAsString('b');

    final result = await const FilesystemSkillTreeReader(
      normalizer: SkillContentNormalizer(maximumFileCount: 1),
    ).read(temporaryDirectory.path);

    expect(result.failureOrNull?.code, SkillContentFailureCode.limitExceeded);
  });

  test('honors cancellation before filesystem traversal', () async {
    final result = await const FilesystemSkillTreeReader().read(
      temporaryDirectory.path,
      isCancelled: () => true,
    );

    expect(result.failureOrNull?.code, SkillContentFailureCode.cancelled);
  });

  group('symbolic links', () {
    test('dereferences contained file and directory links', () async {
      if (Platform.isWindows) return;
      final target = File(paths.join(temporaryDirectory.path, 'data', 'file'));
      await target.parent.create(recursive: true);
      await target.writeAsString('content');
      await Link(
        paths.join(temporaryDirectory.path, 'file-link'),
      ).create(target.path);
      await Link(
        paths.join(temporaryDirectory.path, 'directory-link'),
      ).create(target.parent.path);

      final result = await const FilesystemSkillTreeReader().read(
        temporaryDirectory.path,
      );
      final pathsRead = result.valueOrNull!.files
          .map((file) => file.relativePath)
          .toList();

      expect(
        pathsRead,
        containsAll(<String>['data/file', 'file-link', 'directory-link/file']),
      );
    });

    test('rejects escaping links', () async {
      if (Platform.isWindows) return;
      final outside = await Directory.systemTemp.createTemp(
        'skills-workspace-outside-',
      );
      addTearDown(() => outside.delete(recursive: true));
      final target = File(paths.join(outside.path, 'secret'));
      await target.writeAsString('secret');
      await Link(
        paths.join(temporaryDirectory.path, 'escape'),
      ).create(target.path);

      final result = await const FilesystemSkillTreeReader().read(
        temporaryDirectory.path,
      );

      expect(
        result.failureOrNull?.code,
        SkillContentFailureCode.invalidContent,
      );
      expect(
        result.failureOrNull?.context['reason'],
        'symbolicLinkEscapesSkillRoot',
      );
    });

    test('rejects cyclic links', () async {
      if (Platform.isWindows) return;
      await Link(paths.join(temporaryDirectory.path, 'cycle')).create('.');

      final result = await const FilesystemSkillTreeReader().read(
        temporaryDirectory.path,
      );

      expect(
        result.failureOrNull?.code,
        SkillContentFailureCode.invalidContent,
      );
      expect(result.failureOrNull?.context['reason'], 'cyclicSymbolicLink');
    });
  });
}
