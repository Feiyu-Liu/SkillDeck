import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker.dart';
import 'package:test/test.dart';

void main() {
  late Directory scratch;
  late RevisionNativeEngine engine;
  late String source;
  late String target;
  late RevisionObjectId base;
  late RevisionObjectId left;
  late RevisionObjectId right;
  late RevisionObjectId merged;
  late RevisionObjectId tree;
  late RevisionObjectId existing;

  Future<String> git(
    List<String> arguments, {
    required String cwd,
    String? input,
  }) async {
    final process = await Process.start(
      'git',
      arguments,
      workingDirectory: cwd,
    );
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    if (input != null) process.stdin.write(input);
    await process.stdin.close();
    final code = await process.exitCode;
    await errors;
    if (code != 0) fail('Local Git fixture command failed.');
    return (await output).trim();
  }

  Future<void> deleteFixtureObject(File object) async {
    if (Platform.isWindows) {
      final result = await Process.run('attrib', ['-R', object.path]);
      if (result.exitCode != 0) {
        fail('Could not prepare disposable fault fixture.');
      }
    }
    await object.delete();
  }

  RevisionObjectId commit(
    List<RevisionObjectId> parents,
    RevisionCommitKind kind,
  ) => engine.createCommit(
    repositoryPath: source,
    request: RevisionCommitRequest(tree: tree, parents: parents, kind: kind),
  );

  Future<RevisionObjectId> rawCommit({
    List<RevisionObjectId>? parents,
    String message = 'opaque metadata',
    RevisionObjectId? selectedTree,
  }) async => RevisionObjectId(
    await git(
      ['hash-object', '-t', 'commit', '-w', '--stdin'],
      cwd: source,
      input:
          'tree ${(selectedTree ?? tree).value}\n${(parents ?? [left, right]).map((oid) => 'parent ${oid.value}\n').join()}author Fixture <fixture@example.invalid> 1 +0000\ncommitter Fixture <fixture@example.invalid> 1 +0000\n\n$message\n',
    ),
  );

  RevisionObjectImportReport import({
    String? staged,
    List<RevisionObjectId>? roots,
    RevisionObjectImportLimits limits = const RevisionObjectImportLimits(),
    int cancelFlagAddress = 0,
  }) => engine.importObjects(
    repositoryPath: target,
    stagedRepositoryPath: staged ?? source,
    retainedRoots: roots ?? [merged],
    limits: limits,
    cancelFlagAddress: cancelFlagAddress,
  );

  Future<Map<String, String>> selection() async => {
    'refs': await git([
      'for-each-ref',
      '--format=%(refname) %(objectname)',
    ], cwd: target),
    'head': await File(path.join(target, 'HEAD')).readAsString(),
    'config': await File(path.join(target, 'config')).readAsString(),
  };

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('revision-object-import-');
    engine = RevisionNativeEngine.open();
    source = path.join(scratch.path, 'source.git');
    target = path.join(scratch.path, 'canonical.git');
    engine.createStore(source);
    engine.createStore(target);
    final blob = engine.createBlob(
      source,
      Uint8List.fromList(utf8.encode('fixture\n')),
    );
    tree = RevisionObjectId(
      engine.createSingleBlobTree(
        repositoryPath: source,
        entryName: 'SKILL.md',
        blobOid: blob,
      ),
    );
    base = commit([], RevisionCommitKind.initial);
    final publishedBlob = engine.createBlob(
      source,
      Uint8List.fromList(utf8.encode('published fixture\n')),
    );
    tree = RevisionObjectId(
      engine.createSingleBlobTree(
        repositoryPath: source,
        entryName: 'SKILL.md',
        blobOid: publishedBlob,
      ),
    );
    left = commit([base], RevisionCommitKind.localPublish);
    right = commit([base], RevisionCommitKind.upstream);
    merged = commit([left, right], RevisionCommitKind.effectiveUpdate);
    final oldBlob = engine.createBlob(target, Uint8List.fromList([1, 2, 3]));
    final oldTree = RevisionObjectId(
      engine.createSingleBlobTree(
        repositoryPath: target,
        entryName: 'existing',
        blobOid: oldBlob,
      ),
    );
    existing = engine.createCommit(
      repositoryPath: target,
      request: RevisionCommitRequest(
        tree: oldTree,
        parents: [],
        kind: RevisionCommitKind.initial,
      ),
    );
    engine.replaceRetentionRefs(
      repositoryPath: target,
      references: [
        RevisionRetentionRef(
          name: 'refs/skills-workspace/selected',
          target: existing,
        ),
      ],
    );
  });

  tearDown(() async {
    engine.close();
    await scratch.delete(recursive: true);
  });

  test(
    'inspects root, ordered merge parents and opaque octopus topology',
    () async {
      final root = engine.inspectCommit(source, base);
      expect(root.tree, isNot(tree));
      expect(root.parents, isEmpty);
      expect(engine.inspectCommit(source, merged).parents, [left, right]);
      final octopus = await rawCommit(parents: [right, base, left]);
      final topology = engine.inspectCommit(source, octopus);
      expect(topology.tree, tree);
      expect(topology.parents, [right, base, left]);
      expect(() => topology.parents.add(base), throwsUnsupportedError);
      expect(topology.toString(), isNot(contains('opaque metadata')));
    },
  );

  test(
    'imports exact pack closure preserving every OID and merge parent without selecting',
    () async {
      final before = await selection();
      final opaque = await rawCommit(parents: [right, base, left]);
      final unrelated = await rawCommit(
        parents: [],
        message: 'unreachable and excluded',
      );
      final pack = Directory(path.join(scratch.path, 'pack'))..createSync();
      engine.createRecoveryPack(
        repositoryPath: source,
        bundleStagingPath: pack.path,
        retainedRoots: [opaque],
      );
      final staged = path.join(scratch.path, 'restored.git');
      engine.restoreRecoveryPack(
        stagedRepositoryPath: staged,
        packPath: path.join(pack.path, 'objects.pack'),
        indexPath: path.join(pack.path, 'objects.idx'),
        retainedRoots: [opaque],
      );
      final expectedCount = const LineSplitter()
          .convert(
            await git(['rev-list', '--objects', opaque.value], cwd: source),
          )
          .length;
      for (var attempt = 0; attempt < 2; attempt++) {
        final report = import(staged: staged, roots: [opaque, opaque]);
        expect(report.objectCount, expectedCount);
        expect(report.totalBytes, greaterThan(0));
        final topology = engine.inspectCommit(target, opaque);
        expect(topology.parents, [right, base, left]);
        expect(topology.tree, tree);
        expect(engine.inspectCommit(target, base).tree, isNot(tree));
        expect(
          engine.readTree(target, base).files.single.bytes,
          utf8.encode('fixture\n'),
        );
        expect(
          await git(['cat-file', '-p', opaque.value], cwd: target),
          await git(['cat-file', '-p', opaque.value], cwd: source),
        );
        expect(await selection(), before);
        expect(engine.inspectCommit(target, existing).parents, isEmpty);
      }
      expect(
        () => engine.inspectCommit(target, unrelated),
        throwsA(_native(RevisionNativeFailureCode.objectFailure)),
      );
    },
  );

  for (final missing in ['tree', 'parent', 'blob']) {
    test(
      'rejects missing $missing in staging even when canonical already has it',
      () async {
        import();
        final before = await selection();
        final oid = switch (missing) {
          'tree' => tree,
          'parent' => left,
          _ => RevisionObjectId(
            await git(['rev-parse', '${tree.value}:SKILL.md'], cwd: source),
          ),
        };
        final object = File(
          path.join(
            source,
            'objects',
            oid.value.substring(0, 2),
            oid.value.substring(2),
          ),
        );
        await deleteFixtureObject(object);
        expect(
          () => import(),
          throwsA(_native(RevisionNativeFailureCode.objectFailure)),
        );
        expect(await selection(), before);
        expect(engine.inspectCommit(target, merged).parents, [left, right]);
      },
    );
  }

  test(
    'staging alternates cannot borrow missing objects from the canonical target',
    () async {
      import();
      final before = await selection();
      final object = File(
        path.join(
          source,
          'objects',
          left.value.substring(0, 2),
          left.value.substring(2),
        ),
      );
      await deleteFixtureObject(object);
      final alternates = File(
        path.join(source, 'objects', 'info', 'alternates'),
      );
      await alternates.parent.create(recursive: true);
      await alternates.writeAsString('${path.join(target, 'objects')}\n');
      // Ordinary Git sees the object through the alternate; import must refuse.
      expect(await git(['cat-file', '-t', left.value], cwd: source), 'commit');
      expect(
        () => import(),
        throwsA(_native(RevisionNativeFailureCode.objectFailure)),
      );
      expect(await selection(), before);
    },
  );

  test(
    'rejects type confusion before writing any new canonical objects',
    () async {
      final invalid = await rawCommit(parents: [tree]);
      final before = await selection();
      expect(
        () => engine.inspectCommit(source, invalid),
        throwsA(_native(RevisionNativeFailureCode.verificationFailure)),
      );
      expect(
        () => import(roots: [invalid]),
        throwsA(_native(RevisionNativeFailureCode.verificationFailure)),
      );
      expect(
        () => engine.inspectCommit(target, invalid),
        throwsA(_native(RevisionNativeFailureCode.objectFailure)),
      );
      expect(await selection(), before);
    },
  );

  test(
    'rejects corrupt packed staging without changing canonical selection',
    () async {
      final before = await selection();
      final pack = Directory(path.join(scratch.path, 'pack'))..createSync();
      engine.createRecoveryPack(
        repositoryPath: source,
        bundleStagingPath: pack.path,
        retainedRoots: [merged],
      );
      final bytes = await File(
        path.join(pack.path, 'objects.pack'),
      ).readAsBytes();
      final name = bytes
          .sublist(bytes.length - 20)
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      bytes[bytes.length ~/ 2] ^= 0xff;
      final staged = path.join(scratch.path, 'corrupt.git');
      engine.createStore(staged);
      final packs = Directory(path.join(staged, 'objects', 'pack'))
        ..createSync(recursive: true);
      await File(path.join(packs.path, 'pack-$name.pack')).writeAsBytes(bytes);
      await File(
        path.join(pack.path, 'objects.idx'),
      ).copy(path.join(packs.path, 'pack-$name.idx'));
      expect(
        () => import(staged: staged),
        throwsA(isA<RevisionNativeException>()),
      );
      expect(await selection(), before);
      expect(
        () => engine.inspectCommit(target, merged),
        throwsA(_native(RevisionNativeFailureCode.objectFailure)),
      );
    },
  );

  for (final missing in ['parent', 'ancestorTree']) {
    test(
      'legacy recovery rejects an old pack missing $missing closure',
      () async {
        final before = await selection();
        final root = await rawCommit(parents: [base]);
        final blob = await git([
          'rev-parse',
          '${tree.value}:SKILL.md',
        ], cwd: source);
        final directory = Directory(path.join(scratch.path, 'legacy-$missing'))
          ..createSync();
        final prefix = path.join(directory.path, 'incomplete');
        final ids = [
          root.value,
          tree.value,
          blob,
          if (missing == 'ancestorTree') base.value,
        ];
        final packName = await git(
          ['pack-objects', prefix],
          cwd: source,
          input: '${ids.join('\n')}\n',
        );
        expect(
          () => engine.restoreRecoveryPack(
            stagedRepositoryPath: path.join(
              scratch.path,
              'rejected-$missing.git',
            ),
            packPath: '$prefix-$packName.pack',
            indexPath: '$prefix-$packName.idx',
            retainedRoots: [root],
          ),
          throwsA(_native(RevisionNativeFailureCode.bundleFailure)),
        );
        expect(await selection(), before);
      },
    );
  }

  test(
    'legacy recovery retains valid metadata while new seam budgets are caller-configurable',
    () async {
      final large = await rawCommit(
        message: 'x' * (65 * 1024),
        parents: List.filled(65, base),
      );
      final directory = Directory(path.join(scratch.path, 'legacy-valid'))
        ..createSync();
      engine.createRecoveryPack(
        repositoryPath: source,
        bundleStagingPath: directory.path,
        retainedRoots: [large],
      );
      final staged = path.join(scratch.path, 'legacy-valid.git');
      engine.restoreRecoveryPack(
        stagedRepositoryPath: staged,
        packPath: path.join(directory.path, 'objects.pack'),
        indexPath: path.join(directory.path, 'objects.idx'),
        retainedRoots: [large],
      );
      final topology = engine.inspectCommit(
        staged,
        large,
        limits: const RevisionCommitInspectionLimits(
          maximumCommitBytes: 128 * 1024,
          maximumParentCount: 128,
        ),
      );
      expect(topology.parents, List.filled(65, base));
      final before = await selection();
      import(
        staged: staged,
        roots: [large],
        limits: const RevisionObjectImportLimits(
          maximumCommitBytes: 128 * 1024,
          maximumParentCount: 128,
        ),
      );
      expect(
        engine
            .inspectCommit(
              target,
              large,
              limits: const RevisionCommitInspectionLimits(
                maximumCommitBytes: 128 * 1024,
                maximumParentCount: 128,
              ),
            )
            .parents,
        topology.parents,
      );
      expect(await selection(), before);
    },
  );

  test(
    'enforces object count, object size, total size, commit bytes and all-parent bounds',
    () async {
      final before = await selection();
      for (final limits in [
        const RevisionObjectImportLimits(maximumObjectCount: 1),
        const RevisionObjectImportLimits(maximumObjectBytes: 1),
        const RevisionObjectImportLimits(maximumTotalBytes: 1),
      ]) {
        expect(
          () => import(limits: limits),
          throwsA(_native(RevisionNativeFailureCode.limitExceeded)),
        );
      }
      for (final invalid in [
        await rawCommit(message: 'x' * (65 * 1024)),
        await rawCommit(parents: List.filled(65, base)),
      ]) {
        expect(
          () => engine.inspectCommit(source, invalid),
          throwsA(_native(RevisionNativeFailureCode.limitExceeded)),
        );
        expect(
          () => import(roots: [invalid]),
          throwsA(_native(RevisionNativeFailureCode.limitExceeded)),
        );
      }
      expect(await selection(), before);
      expect(
        () => engine.inspectCommit(target, merged),
        throwsA(_native(RevisionNativeFailureCode.objectFailure)),
      );
    },
  );

  test(
    'pre-cancel and target write failure leave refs, HEAD and config unchanged',
    () async {
      final before = await selection();
      final flag = calloc<ffi.Int32>()..value = 1;
      try {
        expect(
          () => import(cancelFlagAddress: flag.address),
          throwsA(_native(RevisionNativeFailureCode.cancelled)),
        );
      } finally {
        calloc.free(flag);
      }
      var failureRoot = merged;
      var index = 0;
      while (await Directory(
        path.join(target, 'objects', failureRoot.value.substring(0, 2)),
      ).exists()) {
        failureRoot = await rawCommit(
          message: 'write failure fixture ${index++}',
        );
      }
      final blocker = File(
        path.join(target, 'objects', failureRoot.value.substring(0, 2)),
      );
      await blocker.writeAsString('blocks object directory creation');
      expect(
        () => import(roots: [failureRoot]),
        throwsA(_native(RevisionNativeFailureCode.objectFailure)),
      );
      expect(await selection(), before);
      await blocker.delete();
      import(roots: [failureRoot]);
      expect(await selection(), before);
    },
  );

  test(
    'worker cancellation interrupts an import and does not poison subsequent work',
    () async {
      final bytes = Uint8List(32 * 1024 * 1024);
      final random = Random(74);
      for (var i = 0; i < bytes.length; i++) {
        bytes[i] = random.nextInt(256);
      }
      final blob = engine.createBlob(source, bytes);
      final largeTree = RevisionObjectId(
        engine.createSingleBlobTree(
          repositoryPath: source,
          entryName: 'large.bin',
          blobOid: blob,
        ),
      );
      final large = await rawCommit(selectedTree: largeTree);
      final before = await selection();
      final worker = await RevisionWorker.start();
      final cancellation = CancellationSource();
      try {
        final operation = worker.importObjects(
          repositoryPath: target,
          stagedRepositoryPath: source,
          retainedRoots: [large],
          cancellationToken: cancellation.token,
        );
        expect(worker.pendingRequestCount, 1);
        final timer = Timer(
          const Duration(milliseconds: 5),
          () => unawaited(cancellation.cancel()),
        );
        try {
          await expectLater(
            operation,
            throwsA(
              isA<RevisionEngineException>().having(
                (error) => error.code,
                'code',
                RevisionEngineFailureCode.cancelled,
              ),
            ),
          );
        } finally {
          timer.cancel();
        }
        expect(await selection(), before);
        final report = await worker.importObjects(
          repositoryPath: target,
          stagedRepositoryPath: source,
          retainedRoots: [merged],
        );
        expect(report.objectCount, greaterThan(0));
        expect((await worker.inspectCommit(target, merged)).parents, [
          left,
          right,
        ]);
        expect(await selection(), before);
      } finally {
        await worker.close();
      }
    },
  );
}

Matcher _native(RevisionNativeFailureCode code) =>
    isA<RevisionNativeException>().having((error) => error.code, 'code', code);
