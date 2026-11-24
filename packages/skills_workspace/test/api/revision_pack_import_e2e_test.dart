import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';

void main() {
  late Directory root;
  late WorkspaceLayout layout;
  late SkillsRepository repository;
  late ManagedSkillId skill;
  late String live;
  late Directory staging;
  late RevisionId base;
  late File baseline;
  late String donor;

  setUp(() async {
    final fixture = await DriftFacadeFixture.create(activate: false);
    root = fixture.temporaryRoot;
    layout = WorkspaceLayout(fixture.workspacePath);
    repository = fixture.repository;
    skill = fixture.managedSkillId;
    live = layout.revisionStorePath(skill);
    staging = Directory(layout.revisionPackStagingPath(skill));
    baseline = File(path.join(root.path, 'baseline.pack'));
    base = (await _success(
      repository.exportRevisionPack(
        ExportRevisionPackRequest(
          managedSkillId: skill,
          destinationPath: baseline.path,
        ),
      ),
    )).effective;
    donor = path.join(root.path, 'donor.git');
    await _git(donor, ['init', '--bare']);
    await File(
      path.join(donor, 'objects', 'info', 'alternates'),
    ).writeAsString('${path.join(live, 'objects')}\n');
  });

  SkillsOperation<RevisionPackImport> importPack(
    File file,
    RevisionId revision,
  ) => repository.importRevisionPack(
    ImportRevisionPackRequest(
      managedSkillId: skill,
      packPath: file.path,
      revisions: [revision],
    ),
  );

  Future<({RevisionId head, String tree, String blob})> transition() async {
    final blob = await _git(donor, [
      'hash-object',
      '-w',
      '--stdin',
    ], 'new content\n');
    final tree = await _git(donor, ['mktree'], '100644 blob $blob\tSKILL.md\n');
    final head = await _git(donor, [
      'commit-tree',
      tree,
      '-p',
      base.value,
    ], 'New\n');
    return (head: RevisionId(head), tree: tree, blob: blob);
  }

  Future<File> pack(List<String> objects) async {
    final input = File(path.join(root.path, 'input-${objects.length}.pack'));
    final bytes = await _runGit(donor, [
      'pack-objects',
      '--stdout',
    ], '${objects.join('\n')}\n');
    return input.writeAsBytes(bytes, flush: true);
  }

  Future<Map<String, List<int>>> authorityBytes() async => {
    ...await _fileBytes(live),
    for (final file in [
      File(layout.databasePath),
      File('${layout.databasePath}-wal'),
    ])
      if (await file.exists()) file.path: await file.readAsBytes(),
  };

  Future<void> expectNoTemporaryPacks() async {
    final temporary = Directory(
      layout.revisionStoresRoot,
    ).list().where((entry) => path.basename(entry.path).startsWith('.pack-'));
    expect(await temporary.isEmpty, isTrue);
  }

  test('stages a partial object set and handles duplicate imports', () async {
    final next = await transition();
    final input = await pack([next.head.value, next.tree, next.blob]);
    final original = await authorityBytes();
    final results = await Future.wait([
      importPack(input, next.head).completed,
      importPack(input, next.head).completed,
    ]);
    expect(results.map((result) => result.valueOrNull), [
      RevisionPackImport.imported,
      RevisionPackImport.imported,
    ]);
    final staged = await staging.list().single;
    final stagedBytes = await _fileBytes(staged.path);
    expect(stagedBytes, hasLength(2));
    expect(
      await _success(importPack(input, next.head)),
      RevisionPackImport.imported,
    );
    expect(await _fileBytes(staged.path), stagedBytes);
    expect(await staging.list().length, 1);
    final graph = utf8.decode(
      await _runGit(
        live,
        ['rev-list', '--objects', next.head.value],
        null,
        environment: {'GIT_ALTERNATE_OBJECT_DIRECTORIES': staged.path},
      ),
    );
    expect(
      graph,
      allOf(
        contains(next.head.value),
        contains(base.value),
        contains(next.blob),
      ),
    );
    expect(await authorityBytes(), original);
    await expectNoTemporaryPacks();
  });

  test('discards a valid pack when every object is already live', () async {
    final original = await authorityBytes();
    expect(
      await _success(importPack(baseline, base)),
      RevisionPackImport.imported,
    );
    expect(await staging.exists(), isFalse);
    expect(await authorityBytes(), original);
    await expectNoTemporaryPacks();
  });

  test(
    'reports incomplete when a named root or a reachable blob is missing',
    () async {
      final next = await transition();
      final missingBlob = await pack([next.head.value, next.tree]);
      final missingRoot = await pack([next.blob]);
      final original = await authorityBytes();
      for (final input in [missingBlob, missingRoot]) {
        expect(
          await _success(importPack(input, next.head)),
          RevisionPackImport.incomplete,
        );
      }
      expect(await staging.exists(), isFalse);
      expect(await authorityBytes(), original);
      await expectNoTemporaryPacks();
    },
  );

  test(
    'reports malformed for wrong format, truncated, and corrupt packs',
    () async {
      final bytes = await baseline.readAsBytes();
      final truncated = bytes.sublist(0, bytes.length - 1);
      final corrupt = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      final original = await authorityBytes();
      final input = File(path.join(root.path, 'malformed.pack'));
      for (final payload in [utf8.encode('wrong format'), truncated, corrupt]) {
        await input.writeAsBytes(payload);
        expect(
          await _success(importPack(input, base)),
          RevisionPackImport.malformed,
        );
      }
      expect(await staging.exists(), isFalse);
      expect(await authorityBytes(), original);
      await expectNoTemporaryPacks();
    },
  );

  test(
    'returns typed failures for unknown Skill, unreadable pack, and cancellation',
    () async {
      final missing = importPack(
        File(path.join(root.path, 'absent.pack')),
        base,
      );
      expect(
        await missing.completed,
        isA<SkillsFailure<RevisionPackImport>>()
            .having((result) => result.code, 'code', SkillsErrorCode.ioFailure)
            .having(
              (result) => result.context['reason'],
              'reason',
              'packUnreadable',
            ),
      );
      final unknown = repository.importRevisionPack(
        ImportRevisionPackRequest(
          managedSkillId: ManagedSkillId(
            '00000000-0000-4000-8000-000000000000',
          ),
          packPath: baseline.path,
          revisions: [base],
        ),
      );
      expect(
        await unknown.completed,
        isA<SkillsFailure<RevisionPackImport>>().having(
          (result) => result.code,
          'code',
          SkillsErrorCode.skillNotFound,
        ),
      );
      final cancelling = importPack(baseline, base);
      await cancelling.cancel();
      expect(
        await cancelling.completed,
        isA<SkillsFailure<RevisionPackImport>>().having(
          (result) => result.code,
          'code',
          SkillsErrorCode.operationCancelled,
        ),
      );
      expect(await staging.exists(), isFalse);
      await expectNoTemporaryPacks();
    },
  );

  test('cancellation during preparation discards the temporary pack', () async {
    final next = await transition();
    final input = await pack([next.head.value, next.tree, next.blob]);
    final original = await authorityBytes();
    final operation = importPack(input, next.head);
    final preparing = operation.progress.firstWhere(
      (progress) => progress.phase == OperationProgressPhase.preparing,
    );
    await preparing;
    await operation.cancel();
    expect(
      (await operation.completed).failureOrNull?.code,
      SkillsErrorCode.operationCancelled,
    );
    expect(await staging.exists(), isFalse);
    expect(await authorityBytes(), original);
    await expectNoTemporaryPacks();
  });
}

Future<T> _success<T>(SkillsOperation<T> operation) async {
  final result = await operation.completed;
  expect(result, isA<SkillsSuccess<T>>(), reason: '$result');
  return result.valueOrNull as T;
}

Future<Map<String, List<int>>> _fileBytes(String root) async => {
  await for (final entry in Directory(root).list(recursive: true))
    if (entry is File)
      path.relative(entry.path, from: root): await entry.readAsBytes(),
};

Future<String> _git(String store, List<String> args, [String? input]) async =>
    utf8.decode(await _runGit(store, args, input)).trim();

Future<List<int>> _runGit(
  String store,
  List<String> args,
  String? input, {
  Map<String, String> environment = const {},
}) async {
  final process = await Process.start(
    'git',
    ['--git-dir=$store', ...args],
    environment: {
      'GIT_AUTHOR_NAME': 'Revision Pack Fixture',
      'GIT_AUTHOR_EMAIL': 'fixture@example.invalid',
      'GIT_COMMITTER_NAME': 'Revision Pack Fixture',
      'GIT_COMMITTER_EMAIL': 'fixture@example.invalid',
      ...environment,
    },
  );
  final output = process.stdout.expand((chunk) => chunk).toList();
  final errors = process.stderr.transform(utf8.decoder).join();
  if (input != null) process.stdin.write(input);
  await process.stdin.close();
  expect(await process.exitCode, 0, reason: '${args.first}: ${await errors}');
  return output;
}
