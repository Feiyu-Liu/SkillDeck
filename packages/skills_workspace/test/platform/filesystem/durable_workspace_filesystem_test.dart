import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/filesystem_primitives.dart';
import 'package:skills_workspace/src/platform/filesystem/posix_filesystem_primitives.dart';
import 'package:skills_workspace/src/platform/filesystem/windows_filesystem_primitives.dart';
import 'package:test/test.dart';

import '../../support/filesystem/fault_injecting_filesystem_primitives.dart';

void main() {
  late Directory temporary;
  late PlatformDurableWorkspaceFilesystem filesystem;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-durable-filesystem-',
    );
    filesystem = PlatformDurableWorkspaceFilesystem();
  });

  tearDown(() async {
    if (!await temporary.exists()) {
      return;
    }
    await for (final entity in temporary.list(followLinks: false)) {
      await filesystem.removeOwnedPath(
        targetPath: entity.path,
        ownerRoot: temporary.path,
      );
    }
    await temporary.delete();
  });

  test('creates and flushes every missing directory ancestor', () async {
    final nested = path.join(temporary.path, 'one', 'two', 'three');

    await filesystem.ensureDirectory(nested);

    expect(await Directory(nested).exists(), isTrue);
    final identity = await filesystem.pathIdentity(nested);
    expect(identity.metadata.kind, FilesystemEntryKind.directory);
  });

  test(
    'resolves linked parents while preserving the final mutation entry',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('Covered by the Windows junction validation probe.');
        return;
      }
      final physicalParent = Directory(
        path.join(temporary.path, 'physical', 'skills'),
      );
      final externalSkill = Directory(path.join(temporary.path, 'external'));
      await physicalParent.create(recursive: true);
      await externalSkill.create();
      final linkedParent = path.join(temporary.path, 'legacy-skills');
      await Link(linkedParent).create(physicalParent.path);
      final finalLink = path.join(physicalParent.path, 'review');
      await Link(finalLink).create(externalSkill.path);

      final resolved = await filesystem.resolveMutationPath(
        path.join(linkedParent, 'review'),
      );
      final resolvedParent = await physicalParent.resolveSymbolicLinks();

      expect(resolved, path.join(resolvedParent, 'review'));
      expect(
        await FileSystemEntity.type(resolved, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );

  test('resolves existing parents for a missing mutation descendant', () async {
    if (Platform.isWindows) {
      markTestSkipped('Covered by the Windows junction validation probe.');
      return;
    }
    final physicalParent = Directory(
      path.join(temporary.path, 'physical', 'skills'),
    );
    await physicalParent.create(recursive: true);
    final linkedParent = path.join(temporary.path, 'legacy-skills');
    await Link(linkedParent).create(physicalParent.path);

    final resolved = await filesystem.resolveMutationPath(
      path.join(linkedParent, 'missing', 'review'),
    );
    final resolvedParent = await physicalParent.resolveSymbolicLinks();

    expect(resolved, path.join(resolvedParent, 'missing', 'review'));
  });

  test('allocates staging directly beside its destination', () async {
    final destination = path.join(temporary.path, 'published');

    final staging = await filesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
      purpose: 'repository-copy',
    );

    expect(path.dirname(staging.path), path.dirname(destination));
    expect(staging.path, isNot(destination));
    expect(await Directory(staging.path).exists(), isTrue);
    expect(path.basename(staging.path), startsWith('.s-'));
    expect(path.basename(staging.path).length, 10);
  });

  test('retries only an exclusive staging-name collision', () async {
    final destination = path.join(temporary.path, 'published');
    final collision = File(path.join(temporary.path, '.reserved-0'));
    await collision.writeAsString('belongs to another operation');
    final deterministicFilesystem = PlatformDurableWorkspaceFilesystem(
      stagingNameGenerator: (_, _, attempt) => '.reserved-$attempt',
    );

    final staging = await deterministicFilesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
    );

    expect(staging.path, path.join(temporary.path, '.reserved-1'));
    expect(await collision.readAsString(), 'belongs to another operation');
    expect(await Directory(staging.path).exists(), isTrue);
  });

  test(
    'a post-create flush failure cleans staging and preserves the error',
    () async {
      final destination = path.join(temporary.path, 'published');
      final platformPrimitives = Platform.isWindows
          ? const WindowsFilesystemPrimitives()
          : const PosixFilesystemPrimitives();
      final injected = DurableFilesystemException(
        operation: DurableFilesystemOperation.flushFile,
        message: 'Injected staging flush failure.',
        path: path.join(temporary.path, '.flush-failure'),
      );
      final faultingFilesystem =
          PlatformDurableWorkspaceFilesystem.withPrimitives(
            primitives: FaultInjectingFilesystemPrimitives(
              delegate: platformPrimitives,
              beforeOperation: (operation, _) {
                if (operation == DurableFilesystemOperation.flushFile) {
                  throw injected;
                }
              },
            ),
            stagingNameGenerator: (_, _, _) => '.flush-failure',
          );

      await expectLater(
        faultingFilesystem.createSiblingStagingPath(
          destination,
          kind: DurableEntryKind.file,
        ),
        throwsA(same(injected)),
      );

      expect(
        await FileSystemEntity.type(
          path.join(temporary.path, '.flush-failure'),
          followLinks: false,
        ),
        FileSystemEntityType.notFound,
      );
    },
  );

  test(
    'writes file bytes through file and parent durability barriers',
    () async {
      final target = path.join(temporary.path, 'data', 'manifest.json');

      await filesystem.writeDurableFile(target, [1, 2, 3, 4]);

      expect(await File(target).readAsBytes(), [1, 2, 3, 4]);
      expect(
        (await filesystem.pathIdentity(target)).metadata.kind,
        FilesystemEntryKind.file,
      );
    },
  );

  test(
    'materializes a staged directory behind one recursive barrier',
    () async {
      final root = path.join(temporary.path, 'candidate');
      final delegate = Platform.isWindows
          ? const WindowsFilesystemPrimitives()
          : const PosixFilesystemPrimitives();
      final probe = _FlushCountingPrimitives(delegate);
      final batched = PlatformDurableWorkspaceFilesystem.withPrimitives(
        primitives: probe,
      );

      await batched.materializeStagedDirectory(
        rootPath: root,
        directories: const ['empty', 'nested/deeper'],
        files: const [
          StagedDirectoryFile(
            relativePath: 'SKILL.md',
            bytes: [35, 32, 83, 107, 105, 108, 108],
            isExecutable: false,
          ),
          StagedDirectoryFile(
            relativePath: 'nested/deeper/data.bin',
            bytes: [0, 1, 127, 128, 255],
            isExecutable: false,
          ),
          StagedDirectoryFile(
            relativePath: 'tools/run.sh',
            bytes: [35, 33, 47, 98, 105, 110, 47, 115, 104, 10],
            isExecutable: true,
          ),
        ],
      );

      expect(await Directory(path.join(root, 'empty')).exists(), isTrue);
      expect(await File(path.join(root, 'SKILL.md')).readAsString(), '# Skill');
      expect(
        await File(
          path.join(root, 'nested', 'deeper', 'data.bin'),
        ).readAsBytes(),
        [0, 1, 127, 128, 255],
      );
      expect(probe.flushedFiles, hasLength(3));
      expect(
        probe.flushedDirectories.where(
          (directory) => directory == path.normalize(temporary.path),
        ),
        hasLength(1),
      );
      if (!Platform.isWindows) {
        expect(
          (await File(path.join(root, 'tools', 'run.sh')).stat()).mode & 0x49,
          0x49,
        );
      }
    },
  );

  test(
    'does not repeat the root-parent barrier for a precreated staging root',
    () async {
      final destination = path.join(temporary.path, 'published');
      final delegate = Platform.isWindows
          ? const WindowsFilesystemPrimitives()
          : const PosixFilesystemPrimitives();
      final probe = _FlushCountingPrimitives(delegate);
      final batched = PlatformDurableWorkspaceFilesystem.withPrimitives(
        primitives: probe,
      );
      final staging = await batched.createSiblingStagingPath(
        destination,
        kind: DurableEntryKind.directory,
      );
      probe.clear();

      await batched.materializeStagedDirectory(
        rootPath: staging.path,
        files: const [
          StagedDirectoryFile(
            relativePath: 'SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      );

      expect(
        probe.flushedDirectories,
        isNot(contains(path.normalize(temporary.path))),
      );
      expect(probe.flushedFiles, hasLength(1));
    },
  );

  test('rejects a staged root that is a symbolic link', () async {
    final outside = Directory(path.join(temporary.path, 'outside'));
    await outside.create();
    final root = path.join(temporary.path, 'candidate');
    try {
      await Link(root).create(outside.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable at this location.');
      return;
    }

    await expectLater(
      filesystem.materializeStagedDirectory(
        rootPath: root,
        files: const [
          StagedDirectoryFile(
            relativePath: 'SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      ),
      throwsA(
        isA<DurableFilesystemException>().having(
          (error) => error.operation,
          'operation',
          DurableFilesystemOperation.createDirectory,
        ),
      ),
    );

    expect(await File(path.join(outside.path, 'SKILL.md')).exists(), isFalse);
  });

  test('rejects a staged parent that is a symbolic link', () async {
    final root = Directory(path.join(temporary.path, 'candidate'));
    final outside = Directory(path.join(temporary.path, 'outside'));
    await root.create();
    await outside.create();
    final nested = path.join(root.path, 'nested');
    try {
      await Link(nested).create(outside.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable at this location.');
      return;
    }

    await expectLater(
      filesystem.materializeStagedDirectory(
        rootPath: root.path,
        files: const [
          StagedDirectoryFile(
            relativePath: 'nested/SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      ),
      throwsA(
        isA<DurableFilesystemException>().having(
          (error) => error.operation,
          'operation',
          DurableFilesystemOperation.createDirectory,
        ),
      ),
    );

    expect(await File(path.join(outside.path, 'SKILL.md')).exists(), isFalse);
  });

  test('rejects a staged file leaf that is a symbolic link', () async {
    final root = Directory(path.join(temporary.path, 'candidate'));
    final outside = File(path.join(temporary.path, 'outside.md'));
    await root.create();
    await outside.writeAsString('outside');
    final leaf = path.join(root.path, 'SKILL.md');
    try {
      await Link(leaf).create(outside.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable at this location.');
      return;
    }

    await expectLater(
      filesystem.materializeStagedDirectory(
        rootPath: root.path,
        files: const [
          StagedDirectoryFile(
            relativePath: 'SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      ),
      throwsA(
        isA<DurableFilesystemException>().having(
          (error) => error.operation,
          'operation',
          DurableFilesystemOperation.writeFile,
        ),
      ),
    );

    expect(await outside.readAsString(), 'outside');
  });

  test('rejects an existing staged regular-file leaf', () async {
    final root = Directory(path.join(temporary.path, 'candidate'));
    await root.create();
    final leaf = File(path.join(root.path, 'SKILL.md'));
    await leaf.writeAsString('existing');

    await expectLater(
      filesystem.materializeStagedDirectory(
        rootPath: root.path,
        files: const [
          StagedDirectoryFile(
            relativePath: 'SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      ),
      throwsA(
        isA<DurableFilesystemException>().having(
          (error) => error.operation,
          'operation',
          DurableFilesystemOperation.writeFile,
        ),
      ),
    );

    expect(await leaf.readAsString(), 'existing');
  });

  test('rejects a staged parent swapped after directory validation', () async {
    if (Platform.isWindows) return;
    final root = Directory(path.join(temporary.path, 'candidate'));
    final nested = Directory(path.join(root.path, 'nested'));
    final displaced = Directory(path.join(root.path, 'nested-displaced'));
    final outside = Directory(path.join(temporary.path, 'outside'));
    await nested.create(recursive: true);
    await outside.create();
    var mutated = false;
    final guarded = PlatformDurableWorkspaceFilesystem.withPrimitives(
      primitives: FaultInjectingFilesystemPrimitives(
        delegate: const PosixFilesystemPrimitives(),
        beforeOperation: (operation, _) {
          if (operation != DurableFilesystemOperation.writeFile || mutated) {
            return;
          }
          mutated = true;
          nested.renameSync(displaced.path);
          Link(nested.path).createSync(outside.path);
        },
      ),
    );

    await expectLater(
      guarded.materializeStagedDirectory(
        rootPath: root.path,
        files: const [
          StagedDirectoryFile(
            relativePath: 'nested/SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      ),
      throwsA(
        isA<DurableFilesystemException>().having(
          (error) => error.operation,
          'operation',
          DurableFilesystemOperation.writeFile,
        ),
      ),
    );

    expect(mutated, isTrue);
    expect(await File(path.join(outside.path, 'SKILL.md')).exists(), isFalse);
  });

  test('surfaces the staged root-parent durability failure', () async {
    final root = path.join(temporary.path, 'candidate');
    final parent = path.normalize(path.absolute(temporary.path));
    final delegate = Platform.isWindows
        ? const WindowsFilesystemPrimitives()
        : const PosixFilesystemPrimitives();
    final injected = DurableFilesystemException(
      operation: DurableFilesystemOperation.flushDirectory,
      message: 'Injected root-parent barrier failure.',
      path: parent,
    );
    final faulting = PlatformDurableWorkspaceFilesystem.withPrimitives(
      primitives: FaultInjectingFilesystemPrimitives(
        delegate: delegate,
        beforeOperation: (operation, target) {
          if (operation == DurableFilesystemOperation.flushDirectory &&
              path.normalize(path.absolute(target)) == parent) {
            throw injected;
          }
        },
      ),
    );

    await expectLater(
      faulting.materializeStagedDirectory(
        rootPath: root,
        files: const [
          StagedDirectoryFile(
            relativePath: 'SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      ),
      throwsA(same(injected)),
    );
  });

  test('rejects unsafe or colliding staged directory entries', () async {
    final root = path.join(temporary.path, 'candidate');

    Future<void> expectRejected({
      Iterable<String> directories = const <String>[],
      Iterable<StagedDirectoryFile> files = const <StagedDirectoryFile>[],
    }) => expectLater(
      filesystem.materializeStagedDirectory(
        rootPath: root,
        directories: directories,
        files: files,
      ),
      throwsA(
        isA<DurableFilesystemException>().having(
          (error) => error.operation,
          'operation',
          DurableFilesystemOperation.verify,
        ),
      ),
    );

    await expectRejected(
      files: const [
        StagedDirectoryFile(
          relativePath: '../escape',
          bytes: [],
          isExecutable: false,
        ),
      ],
    );
    await expectRejected(
      files: [
        StagedDirectoryFile(
          relativePath: path.join(temporary.path, 'absolute'),
          bytes: const [],
          isExecutable: false,
        ),
      ],
    );
    await expectRejected(
      files: const [
        StagedDirectoryFile(
          relativePath: 'duplicate',
          bytes: [1],
          isExecutable: false,
        ),
        StagedDirectoryFile(
          relativePath: 'duplicate',
          bytes: [2],
          isExecutable: false,
        ),
      ],
    );
    await expectRejected(
      directories: const ['collision'],
      files: const [
        StagedDirectoryFile(
          relativePath: 'collision',
          bytes: [],
          isExecutable: false,
        ),
      ],
    );
    await expectRejected(
      files: const [
        StagedDirectoryFile(
          relativePath: 'parent',
          bytes: [],
          isExecutable: false,
        ),
        StagedDirectoryFile(
          relativePath: 'parent/child',
          bytes: [],
          isExecutable: false,
        ),
      ],
    );

    expect(await Directory(root).exists(), isFalse);
  });

  test('surfaces the final staged-directory durability failure', () async {
    final root = path.join(temporary.path, 'candidate');
    final delegate = Platform.isWindows
        ? const WindowsFilesystemPrimitives()
        : const PosixFilesystemPrimitives();
    final injected = DurableFilesystemException(
      operation: DurableFilesystemOperation.flushFile,
      message: 'Injected final barrier failure.',
      path: path.join(root, 'SKILL.md'),
    );
    final faulting = PlatformDurableWorkspaceFilesystem.withPrimitives(
      primitives: FaultInjectingFilesystemPrimitives(
        delegate: delegate,
        beforeOperation: (operation, _) {
          if (operation == DurableFilesystemOperation.flushFile) {
            throw injected;
          }
        },
      ),
    );

    await expectLater(
      faulting.materializeStagedDirectory(
        rootPath: root,
        files: const [
          StagedDirectoryFile(
            relativePath: 'SKILL.md',
            bytes: [1, 2, 3],
            isExecutable: false,
          ),
        ],
      ),
      throwsA(same(injected)),
    );

    expect(await File(path.join(root, 'SKILL.md')).readAsBytes(), [1, 2, 3]);
  });

  test('flushes a Windows read-only file and restores its attribute', () async {
    if (!Platform.isWindows) return;
    final target = File(path.join(temporary.path, 'immutable-object'));
    await target.writeAsString('object');
    const primitives = WindowsFilesystemPrimitives();
    await primitives.applyReadOnly(target.path, true);

    await primitives.flushFile(target.path);

    expect(await primitives.captureReadOnly(target.path), isTrue);
  });

  test(
    'recursive flush batches read-only transitions around barriers',
    () async {
      final root = Directory(path.join(temporary.path, 'revision-store'));
      final nested = Directory(path.join(root.path, 'objects', 'ab'));
      await nested.create(recursive: true);
      final first = File(path.join(root.path, 'config'));
      final second = File(path.join(nested.path, 'object'));
      await first.writeAsString('config');
      await second.writeAsString('object');
      final readOnlyPaths = <String>{
        path.normalize(path.absolute(first.path)),
        path.normalize(path.absolute(second.path)),
      };
      final probe = _ReadOnlyBatchProbe(
        delegate: Platform.isWindows
            ? const WindowsFilesystemPrimitives()
            : const PosixFilesystemPrimitives(),
        readOnlyPaths: readOnlyPaths,
      );
      final guarded = PlatformDurableWorkspaceFilesystem.withPrimitives(
        primitives: probe,
      );

      await guarded.flushRecursively(root.path);

      expect(probe.flushObservedReadOnly, isFalse);
      expect(probe.readOnlyPaths, readOnlyPaths);
      expect(
        probe.transitions.where((transition) => !transition.readOnly),
        hasLength(2),
      );
      expect(
        probe.transitions.where((transition) => transition.readOnly),
        hasLength(2),
      );
    },
  );

  test('publishes, reopens, and rolls back a new directory', () async {
    final destination = path.join(temporary.path, 'repository-copy');
    final staging = await filesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
    );
    await File(path.join(staging.path, 'SKILL.md')).writeAsString('new');
    var verificationCount = 0;

    final publication = await filesystem.publish(
      candidatePath: staging.path,
      destinationPath: destination,
      kind: DurableEntryKind.directory,
      verify: (publishedPath) async {
        verificationCount += 1;
        expect(
          await File(path.join(publishedPath, 'SKILL.md')).readAsString(),
          'new',
        );
      },
    );

    expect(verificationCount, 2);
    expect(publication.destinationPreviouslyExisted, isFalse);
    expect(await Directory(destination).exists(), isTrue);

    await filesystem.rollbackPublication(publication);

    expect(await Directory(destination).exists(), isFalse);
    expect(
      await File(path.join(staging.path, 'SKILL.md')).readAsString(),
      'new',
    );
  });

  test('replacement retains the displaced entry until finalization', () async {
    final destination = Directory(path.join(temporary.path, 'active'));
    await destination.create();
    await File(path.join(destination.path, 'SKILL.md')).writeAsString('old');
    final staging = await filesystem.createSiblingStagingPath(
      destination.path,
      kind: DurableEntryKind.directory,
    );
    await File(path.join(staging.path, 'SKILL.md')).writeAsString('new');

    final publication = await filesystem.publish(
      candidatePath: staging.path,
      destinationPath: destination.path,
      kind: DurableEntryKind.directory,
      verify: (publishedPath) async {
        final contents = await File(
          path.join(publishedPath, 'SKILL.md'),
        ).readAsString();
        expect(contents, anyOf('old', 'new'));
      },
    );

    expect(
      await File(path.join(destination.path, 'SKILL.md')).readAsString(),
      'new',
    );
    expect(publication.displacedPath, isNotNull);
    expect(
      await File(
        path.join(publication.displacedPath!, 'SKILL.md'),
      ).readAsString(),
      'old',
    );

    await filesystem.rollbackPublication(
      publication,
      verifyRestored: (restoredPath) async {
        expect(
          await File(path.join(restoredPath, 'SKILL.md')).readAsString(),
          'old',
        );
      },
    );

    expect(
      await File(path.join(destination.path, 'SKILL.md')).readAsString(),
      'old',
    );
    expect(
      await File(path.join(staging.path, 'SKILL.md')).readAsString(),
      'new',
    );
  });

  test(
    'recoverable replacement uses the caller-owned displaced sibling',
    () async {
      final destination = Directory(path.join(temporary.path, 'active'));
      await destination.create();
      await File(path.join(destination.path, 'SKILL.md')).writeAsString('old');
      final staging = await filesystem.createSiblingStagingPath(
        destination.path,
        kind: DurableEntryKind.directory,
      );
      await File(path.join(staging.path, 'SKILL.md')).writeAsString('new');
      final displaced = path.join(temporary.path, '.active.recovery-old');
      final barriers = <DurablePathMutationBarrier>[];

      final publication = await filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destination.path,
        kind: DurableEntryKind.directory,
        knownDisplacedPath: displaced,
        onMutationBarrier: (barrier, _) => barriers.add(barrier),
        verify: (candidate) async {
          expect(
            await File(path.join(candidate, 'SKILL.md')).readAsString(),
            anyOf('old', 'new'),
          );
        },
      );

      expect(publication.displacedPath, displaced);
      expect(publication.usedAtomicExchange, isFalse);
      expect(
        await File(path.join(displaced, 'SKILL.md')).readAsString(),
        'old',
      );
      expect(
        await File(path.join(destination.path, 'SKILL.md')).readAsString(),
        'new',
      );
      expect(barriers, [
        DurablePathMutationBarrier.beforeMutation,
        DurablePathMutationBarrier.afterDestinationDisplaced,
        DurablePathMutationBarrier.afterCandidatePublished,
        DurablePathMutationBarrier.afterVerification,
      ]);
    },
  );

  test('durably displaces a path to a known recovery sibling', () async {
    final destination = Directory(path.join(temporary.path, 'active'));
    await destination.create();
    await File(path.join(destination.path, 'SKILL.md')).writeAsString('old');
    final displaced = path.join(temporary.path, '.active.recovery-absent');
    final barriers = <DurablePathMutationBarrier>[];

    await filesystem.displace(
      destinationPath: destination.path,
      displacedPath: displaced,
      kind: DurableEntryKind.directory,
      onMutationBarrier: (barrier, _) => barriers.add(barrier),
      verify: (candidate) async {
        expect(
          await File(path.join(candidate, 'SKILL.md')).readAsString(),
          'old',
        );
      },
    );

    expect(await destination.exists(), isFalse);
    expect(await File(path.join(displaced, 'SKILL.md')).readAsString(), 'old');
    expect(barriers, [
      DurablePathMutationBarrier.beforeMutation,
      DurablePathMutationBarrier.afterDestinationDisplaced,
      DurablePathMutationBarrier.afterVerification,
    ]);
  });

  test('failed post-publication verification restores old bytes', () async {
    final destination = Directory(path.join(temporary.path, 'active'));
    await destination.create();
    await File(path.join(destination.path, 'SKILL.md')).writeAsString('old');
    final staging = await filesystem.createSiblingStagingPath(
      destination.path,
      kind: DurableEntryKind.directory,
    );
    await File(path.join(staging.path, 'SKILL.md')).writeAsString('new');
    var calls = 0;

    await expectLater(
      filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destination.path,
        kind: DurableEntryKind.directory,
        verify: (_) {
          calls += 1;
          if (calls == 2) {
            throw StateError('injected reopen verification failure');
          }
        },
      ),
      throwsStateError,
    );

    expect(
      await File(path.join(destination.path, 'SKILL.md')).readAsString(),
      'old',
    );
    expect(
      await File(path.join(staging.path, 'SKILL.md')).readAsString(),
      'new',
    );
  });

  test(
    'fallback replacement restores the old path when second rename fails',
    () async {
      final destination = Directory(path.join(temporary.path, 'active'));
      await destination.create();
      await File(path.join(destination.path, 'SKILL.md')).writeAsString('old');
      final platformPrimitives = Platform.isWindows
          ? const WindowsFilesystemPrimitives()
          : const PosixFilesystemPrimitives();
      var renameCount = 0;
      final faultingPrimitives = FaultInjectingFilesystemPrimitives(
        delegate: platformPrimitives,
        forceExchangeUnsupported: true,
        beforeOperation: (operation, faultPath) {
          if (operation == DurableFilesystemOperation.rename &&
              ++renameCount == 2) {
            throw DurableFilesystemException(
              operation: operation,
              message: 'Injected second rename failure.',
              path: faultPath,
            );
          }
        },
      );
      final faultingFilesystem =
          PlatformDurableWorkspaceFilesystem.withPrimitives(
            primitives: faultingPrimitives,
          );
      final staging = await faultingFilesystem.createSiblingStagingPath(
        destination.path,
        kind: DurableEntryKind.directory,
      );
      await File(path.join(staging.path, 'SKILL.md')).writeAsString('new');

      await expectLater(
        faultingFilesystem.publish(
          candidatePath: staging.path,
          destinationPath: destination.path,
          kind: DurableEntryKind.directory,
          verify: (_) {},
        ),
        throwsA(isA<DurableFilesystemException>()),
      );

      expect(renameCount, 3);
      expect(
        await File(path.join(destination.path, 'SKILL.md')).readAsString(),
        'old',
      );
      expect(
        await File(path.join(staging.path, 'SKILL.md')).readAsString(),
        'new',
      );
    },
  );

  test('plain materializations reject Git metadata', () async {
    final destination = path.join(temporary.path, 'active');
    final staging = await filesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
    );
    await Directory(path.join(staging.path, '.git')).create();

    await expectLater(
      filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destination,
        kind: DurableEntryKind.directory,
        verify: (_) {},
      ),
      throwsA(isA<DurableFilesystemException>()),
    );

    expect(await Directory(staging.path).exists(), isTrue);
    expect(await Directory(destination).exists(), isFalse);
  });

  test('plain materializations reject internal symbolic links', () async {
    final destination = path.join(temporary.path, 'active');
    final staging = await filesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
    );
    final file = File(path.join(staging.path, 'SKILL.md'));
    await file.writeAsString('skill');
    try {
      await Link(path.join(staging.path, 'alias.md')).create(file.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable at this location.');
      return;
    }

    await expectLater(
      filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destination,
        kind: DurableEntryKind.directory,
        verify: (_) {},
      ),
      throwsA(isA<DurableFilesystemException>()),
    );
  });

  test(
    'published POSIX materialization is read-only and keeps executables',
    () async {
      final destination = path.join(temporary.path, 'active');
      final staging = await filesystem.createSiblingStagingPath(
        destination,
        kind: DurableEntryKind.directory,
      );
      final markdown = File(path.join(staging.path, 'SKILL.md'));
      final executable = File(path.join(staging.path, 'run.sh'));
      await markdown.writeAsString('skill');
      await executable.writeAsString('#!/bin/sh\n');
      const primitives = PosixFilesystemPrimitives();
      await primitives.applyPosixMode(executable.path, 0x1ed);

      final publication = await filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destination,
        kind: DurableEntryKind.directory,
        makeReadOnly: true,
        verify: (_) {},
      );

      expect(publication.readOnlyPermissionFailures, isEmpty);
      expect((await Directory(destination).stat()).mode & 0x1ff, 0x16d);
      expect(
        (await File(path.join(destination, 'SKILL.md')).stat()).mode & 0x1ff,
        0x124,
      );
      expect(
        (await File(path.join(destination, 'run.sh')).stat()).mode & 0x1ff,
        0x16d,
      );
    },
    skip: Platform.isWindows,
  );

  test('replaces and rolls back read-only POSIX directories', () async {
    final destination = path.join(temporary.path, 'active');
    await Directory(destination).create();
    await File(path.join(destination, 'SKILL.md')).writeAsString('old');
    await filesystem.makeReadOnly(destination, DurableEntryKind.directory);
    final staging = await filesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
    );
    await File(path.join(staging.path, 'SKILL.md')).writeAsString('new');

    final publication = await filesystem.publish(
      candidatePath: staging.path,
      destinationPath: destination,
      kind: DurableEntryKind.directory,
      makeReadOnly: true,
      verify: (candidate) async {
        expect(
          await File(path.join(candidate, 'SKILL.md')).readAsString(),
          anyOf('old', 'new'),
        );
      },
    );

    expect(
      await File(path.join(destination, 'SKILL.md')).readAsString(),
      'new',
    );
    expect((await Directory(destination).stat()).mode & 0x1ff, 0x16d);
    expect(
      (await Directory(publication.displacedPath!).stat()).mode & 0x1ff,
      0x16d,
    );

    await filesystem.rollbackPublication(publication);

    expect(
      await File(path.join(destination, 'SKILL.md')).readAsString(),
      'old',
    );
    expect(
      await File(path.join(staging.path, 'SKILL.md')).readAsString(),
      'new',
    );
    expect((await Directory(destination).stat()).mode & 0x1ff, 0x16d);
    expect((await Directory(staging.path).stat()).mode & 0x1ff, 0x16d);
  }, skip: Platform.isWindows);

  test('durably displaces a read-only POSIX directory', () async {
    final destination = path.join(temporary.path, 'active');
    final displaced = path.join(temporary.path, '.active.recovery');
    await Directory(destination).create();
    await File(path.join(destination, 'SKILL.md')).writeAsString('old');
    await filesystem.makeReadOnly(destination, DurableEntryKind.directory);

    await filesystem.displace(
      destinationPath: destination,
      displacedPath: displaced,
      kind: DurableEntryKind.directory,
      verify: (_) {},
    );

    expect(await Directory(destination).exists(), isFalse);
    expect(await File(path.join(displaced, 'SKILL.md')).readAsString(), 'old');
    expect((await Directory(displaced).stat()).mode & 0x1ff, 0x16d);
  }, skip: Platform.isWindows);

  test(
    'symbolic-link publication verifies the link without following it',
    () async {
      final target = Directory(path.join(temporary.path, 'target'));
      await target.create();
      final destination = path.join(temporary.path, 'activation');
      final staging = await filesystem.createSiblingStagingPath(
        destination,
        kind: DurableEntryKind.symbolicLink,
      );
      try {
        await filesystem.createSymbolicLink(
          linkPath: staging.path,
          targetPath: target.path,
        );
      } on FileSystemException {
        markTestSkipped('Symbolic links are unavailable at this location.');
        return;
      }

      await filesystem.publish(
        candidatePath: staging.path,
        destinationPath: destination,
        kind: DurableEntryKind.symbolicLink,
        requirePlainDirectory: false,
        verify: (publishedPath) async {
          expect(await Link(publishedPath).target(), target.path);
        },
      );

      expect(
        await FileSystemEntity.type(destination, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );

  test('owned cleanup rejects an intermediate symbolic-link escape', () async {
    final owner = Directory(path.join(temporary.path, 'owned'));
    final outside = Directory(path.join(temporary.path, 'outside'));
    await owner.create();
    await outside.create();
    final sentinel = File(path.join(outside.path, 'keep.txt'));
    await sentinel.writeAsString('must survive');
    final escape = Link(path.join(owner.path, 'escape'));
    try {
      await escape.create(outside.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable at this location.');
      return;
    }

    await expectLater(
      filesystem.removeOwnedPath(
        targetPath: path.join(escape.path, 'keep.txt'),
        ownerRoot: owner.path,
      ),
      throwsA(
        isA<DurableFilesystemException>().having(
          (error) => error.operation,
          'operation',
          DurableFilesystemOperation.cleanup,
        ),
      ),
    );

    expect(await sentinel.readAsString(), 'must survive');
    expect(
      await FileSystemEntity.type(escape.path, followLinks: false),
      FileSystemEntityType.link,
    );
  });

  test(
    'owned cleanup revalidates every component identity before mutation',
    () async {
      final owner = Directory(path.join(temporary.path, 'owned'));
      final parent = Directory(path.join(owner.path, 'parent'));
      final target = File(path.join(parent.path, 'target.txt'));
      final outside = Directory(path.join(temporary.path, 'outside'));
      await parent.create(recursive: true);
      await target.writeAsString('owned');
      await outside.create();
      final outsideSentinel = File(path.join(outside.path, 'target.txt'));
      await outsideSentinel.writeAsString('must survive');
      final platformPrimitives = Platform.isWindows
          ? const WindowsFilesystemPrimitives()
          : const PosixFilesystemPrimitives();
      var inspections = 0;
      var swapped = false;
      final guardedFilesystem =
          PlatformDurableWorkspaceFilesystem.withPrimitives(
            primitives: FaultInjectingFilesystemPrimitives(
              delegate: platformPrimitives,
              beforeOperation: (operation, _) {
                if (operation != DurableFilesystemOperation.inspectPath ||
                    ++inspections != 4 ||
                    swapped) {
                  return;
                }
                final displaced = '${parent.path}.displaced';
                parent.renameSync(displaced);
                Link(parent.path).createSync(outside.path);
                swapped = true;
              },
            ),
          );

      await expectLater(
        guardedFilesystem.removeOwnedPath(
          targetPath: target.path,
          ownerRoot: owner.path,
        ),
        throwsA(isA<DurableFilesystemException>()),
      );

      expect(swapped, isTrue);
      expect(await outsideSentinel.readAsString(), 'must survive');
      expect(
        await FileSystemEntity.type(parent.path, followLinks: false),
        FileSystemEntityType.link,
      );
    },
  );

  test('handles a long target-volume staging path', () async {
    var parent = temporary.path;
    for (var index = 0; index < 12; index += 1) {
      parent = path.join(
        parent,
        'segment-${index.toString().padLeft(2, '0')}-xxxxxxxxxxxx',
      );
    }
    final destination = path.join(parent, 'published-skill');

    final staging = await filesystem.createSiblingStagingPath(
      destination,
      kind: DurableEntryKind.directory,
    );

    expect(path.dirname(staging.path), path.dirname(destination));
    expect(path.basename(staging.path).length, 10);
    expect(await Directory(staging.path).exists(), isTrue);
  });
}

final class _FlushCountingPrimitives implements FilesystemPrimitives {
  _FlushCountingPrimitives(this._delegate);

  final FilesystemPrimitives _delegate;
  final List<String> flushedFiles = <String>[];
  final List<String> flushedDirectories = <String>[];

  void clear() {
    flushedFiles.clear();
    flushedDirectories.clear();
  }

  @override
  Future<void> writeNewFile(String filePath, List<int> bytes) =>
      _delegate.writeNewFile(filePath, bytes);

  @override
  Future<void> flushFile(String filePath) async {
    flushedFiles.add(path.normalize(path.absolute(filePath)));
    await _delegate.flushFile(filePath);
  }

  @override
  Future<void> flushDirectory(String directoryPath) async {
    flushedDirectories.add(path.normalize(path.absolute(directoryPath)));
    await _delegate.flushDirectory(directoryPath);
  }

  @override
  Future<FilesystemPathMetadata> stat(
    String targetPath, {
    required bool followLinks,
  }) => _delegate.stat(targetPath, followLinks: followLinks);

  @override
  Future<void> renameSameParent({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  }) => _delegate.renameSameParent(
    parentPath: parentPath,
    sourceName: sourceName,
    destinationName: destinationName,
    replaceExisting: replaceExisting,
  );

  @override
  Future<bool> exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  }) => _delegate.exchangeSameParent(
    parentPath: parentPath,
    firstName: firstName,
    secondName: secondName,
  );

  @override
  Future<void> applyPosixMode(String targetPath, int mode) =>
      _delegate.applyPosixMode(targetPath, mode);

  @override
  Future<bool?> captureReadOnly(String targetPath) =>
      _delegate.captureReadOnly(targetPath);

  @override
  Future<void> applyReadOnly(String targetPath, bool readOnly) =>
      _delegate.applyReadOnly(targetPath, readOnly);
}

final class _ReadOnlyBatchProbe implements FilesystemPrimitives {
  _ReadOnlyBatchProbe({
    required FilesystemPrimitives delegate,
    required Set<String> readOnlyPaths,
  }) : _delegate = delegate,
       readOnlyPaths = <String>{...readOnlyPaths};

  final FilesystemPrimitives _delegate;
  final Set<String> readOnlyPaths;
  final List<({String path, bool readOnly})> transitions = [];
  bool flushObservedReadOnly = false;

  String _normalized(String value) {
    var candidate = value;
    if (Platform.isWindows) {
      if (candidate.startsWith(r'\\?\UNC\')) {
        candidate = r'\\' + candidate.substring(r'\\?\UNC\'.length);
      } else if (candidate.startsWith(r'\\?\')) {
        candidate = candidate.substring(r'\\?\'.length);
      }
    }
    return path.normalize(path.absolute(candidate));
  }

  @override
  Future<void> writeNewFile(String filePath, List<int> bytes) =>
      _delegate.writeNewFile(filePath, bytes);

  @override
  Future<void> flushFile(String filePath) async {
    if (readOnlyPaths.isNotEmpty) flushObservedReadOnly = true;
    await _delegate.flushFile(filePath);
  }

  @override
  Future<void> flushDirectory(String directoryPath) =>
      _delegate.flushDirectory(directoryPath);

  @override
  Future<FilesystemPathMetadata> stat(
    String targetPath, {
    required bool followLinks,
  }) => _delegate.stat(targetPath, followLinks: followLinks);

  @override
  Future<void> renameSameParent({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  }) => _delegate.renameSameParent(
    parentPath: parentPath,
    sourceName: sourceName,
    destinationName: destinationName,
    replaceExisting: replaceExisting,
  );

  @override
  Future<bool> exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  }) => _delegate.exchangeSameParent(
    parentPath: parentPath,
    firstName: firstName,
    secondName: secondName,
  );

  @override
  Future<void> applyPosixMode(String targetPath, int mode) =>
      _delegate.applyPosixMode(targetPath, mode);

  @override
  Future<bool?> captureReadOnly(String targetPath) async =>
      readOnlyPaths.contains(_normalized(targetPath));

  @override
  Future<void> applyReadOnly(String targetPath, bool readOnly) async {
    final normalized = _normalized(targetPath);
    transitions.add((path: normalized, readOnly: readOnly));
    if (readOnly) {
      readOnlyPaths.add(normalized);
    } else {
      readOnlyPaths.remove(normalized);
    }
  }
}
