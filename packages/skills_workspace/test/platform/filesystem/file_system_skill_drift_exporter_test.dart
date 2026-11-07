import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:skills_workspace/src/application/drift/drift_models.dart';
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_skill_drift_exporter.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';

import '../../support/content/drift_export_inspector.dart';

void main() {
  final exporter = FileSystemSkillDriftExporter(
    filesystem: PlatformDurableWorkspaceFilesystem(),
  );
  const realInspector = FileSystemPublishedArtifactInspector(
    contentWorker: DirectRevisionContentWorker(),
    metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
  );
  late Directory temp;
  late Directory source;
  late Directory destination;
  late String fingerprint;

  Future<DriftResult<String>> export({
    String? sourcePath,
    String? destinationPath,
    List<String> forbiddenRoots = const [],
    PublishedArtifactInspectorPort inspector = realInspector,
    CancellationToken? token,
    String? expectedFingerprint,
  }) => exporter.export(
    sourcePath: sourcePath ?? source.path,
    slotKey: 'sample',
    destinationDirectory: destinationPath ?? destination.path,
    forbiddenRoots: forbiddenRoots,
    expectedFingerprint: expectedFingerprint ?? fingerprint,
    inspector: inspector,
    cancellationToken: token ?? CancellationToken.none(),
    now: DateTime.utc(2026, 10, 14, 1, 2, 3),
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('drift-export-test-');
    source = await Directory(paths.join(temp.path, 'source')).create();
    destination = await Directory(
      paths.join(temp.path, 'destination'),
    ).create();
    await File(paths.join(source.path, 'SKILL.md')).writeAsString('external');
    fingerprint = (await realInspector.observe(
      path: source.path,
      cancellationToken: CancellationToken.none(),
    )).fingerprint!;
  });
  tearDown(() => temp.delete(recursive: true));

  test('exports reviewed directory as writable bytes with UTC name', () async {
    final file = File(paths.join(source.path, 'SKILL.md'));
    await PlatformDurableWorkspaceFilesystem().makeReadOnly(
      file.path,
      DurableEntryKind.file,
    );
    final result = await export();
    expect(result, isA<DriftSuccess<String>>());
    expect(
      paths.basename(result.valueOrNull!),
      'sample-external-20261014010203',
    );
    final exportedFile = File(paths.join(result.valueOrNull!, 'SKILL.md'));
    expect(await exportedFile.readAsString(), 'external');
    await exportedFile.writeAsString('edited export');
    expect(await file.readAsString(), 'external');
    expect(await destination.list().length, 1);
  });

  test(
    'exports wrong-entry-type file without converting it to directory',
    () async {
      final file = File(paths.join(temp.path, 'external-file'));
      await file.writeAsString('external file');
      final observed = await realInspector.observe(
        path: file.path,
        cancellationToken: CancellationToken.none(),
      );
      final result = await export(
        sourcePath: file.path,
        expectedFingerprint: observed.fingerprint,
      );
      expect(result, isA<DriftSuccess<String>>());
      expect(await File(result.valueOrNull!).readAsString(), 'external file');
      await File(result.valueOrNull!).writeAsString('writable');
    },
  );

  test('preserves executable intent in the captured fingerprint', () async {
    final executable = File(paths.join(source.path, 'run.sh'));
    await executable.writeAsString('executable bytes');
    await PlatformDurableWorkspaceFilesystem().setExecutableIntent(
      executable.path,
      true,
    );
    fingerprint = (await realInspector.observe(
      path: source.path,
      cancellationToken: CancellationToken.none(),
    )).fingerprint!;
    final result = await export();
    expect(result, isA<DriftSuccess<String>>());
    if (!Platform.isWindows) {
      expect(
        (await File(paths.join(result.valueOrNull!, 'run.sh')).stat()).mode &
            0x49,
        isNot(0),
      );
    }
  });

  test(
    'collision uses -2 and -3 without overwriting an existing export',
    () async {
      final first = await export();
      final second = await export();
      final third = await export();
      expect(second.valueOrNull, '${first.valueOrNull}-2');
      expect(third.valueOrNull, '${first.valueOrNull}-3');
    },
  );

  test('rejects destinations in workspace and activation locations', () async {
    final child = await Directory(paths.join(source.path, 'child')).create();
    for (final path in [source.path, child.path]) {
      final result = await export(
        destinationPath: path,
        forbiddenRoots: [source.path],
      );
      expect(
        result.failureOrNull?.code,
        DriftFailureCode.driftResolutionUnavailable,
      );
      expect(result.failureOrNull?.context['reason'], 'exportNotAllowed');
    }
  });

  test(
    'rejects symlink destination and aliases into forbidden ancestors',
    () async {
      final alias = Link(paths.join(temp.path, 'alias'));
      await alias.create(source.path);
      final direct = await export(destinationPath: alias.path);
      expect(direct.failureOrNull?.context['reason'], 'exportNotAllowed');
      final child = await Directory(paths.join(source.path, 'child')).create();
      final indirect = await export(
        destinationPath: paths.join(alias.path, paths.basename(child.path)),
        forbiddenRoots: [source.path],
      );
      expect(indirect.failureOrNull?.context['reason'], 'exportNotAllowed');
    },
    skip: Platform.isWindows ? 'Requires symbolic-link privileges.' : false,
  );

  test('rejects a source link and never reads its target', () async {
    final link = Link(paths.join(temp.path, 'external-link'));
    await link.create(source.path);
    final observed = await realInspector.observe(
      path: link.path,
      cancellationToken: CancellationToken.none(),
    );
    final result = await export(
      sourcePath: link.path,
      expectedFingerprint: observed.fingerprint,
    );
    expect(result.failureOrNull?.context['reason'], 'exportNotAllowed');
    expect(await destination.list().isEmpty, isTrue);
  }, skip: Platform.isWindows ? 'Requires symbolic-link privileges.' : false);

  test('rejects nested links without producing partial exports', () async {
    await Link(paths.join(source.path, 'alias.md')).create('SKILL.md');
    fingerprint = (await realInspector.observe(
      path: source.path,
      cancellationToken: CancellationToken.none(),
    )).fingerprint!;
    final result = await export();
    expect(result.failureOrNull?.context['reason'], 'exportNotAllowed');
    expect(await destination.list().isEmpty, isTrue);
  }, skip: Platform.isWindows ? 'Requires symbolic-link privileges.' : false);

  test('changed source before capture is stale', () async {
    await File(paths.join(source.path, 'SKILL.md')).writeAsString('changed');
    final result = await export();
    expect(result.failureOrNull?.code, DriftFailureCode.staleDriftReview);
    expect(result.failureOrNull?.context['reason'], 'artifactChanged');
    expect(await destination.list().isEmpty, isTrue);
  });

  test(
    'changed source after capture is stale and staging is removed',
    () async {
      final inspector = DriftExportInspector(
        delegate: realInspector,
        onObserve: (path, call) async {
          if (call == 3) {
            await File(
              paths.join(source.path, 'SKILL.md'),
            ).writeAsString('changed');
          }
        },
      );
      final result = await export(inspector: inspector);
      expect(result.failureOrNull?.code, DriftFailureCode.staleDriftReview);
      expect(await destination.list().isEmpty, isTrue);
    },
  );

  test(
    'a captured fingerprint mismatch is stale and staging is removed',
    () async {
      final inspector = DriftExportInspector(
        delegate: realInspector,
        onObserve: (path, call) async {
          if (call == 2) {
            await File(paths.join(path, 'SKILL.md')).writeAsString('tampered');
          }
        },
      );
      final result = await export(inspector: inspector);
      expect(result.failureOrNull?.code, DriftFailureCode.staleDriftReview);
      expect(await destination.list().isEmpty, isTrue);
    },
  );

  test('cancellation after capture removes unpublished staging', () async {
    final cancellation = CancellationSource();
    final inspector = DriftExportInspector(
      delegate: realInspector,
      onObserve: (path, call) async {
        if (call == 2) await cancellation.cancel();
      },
    );
    final result = await export(
      inspector: inspector,
      token: cancellation.token,
    );
    expect(result.failureOrNull?.code, DriftFailureCode.operationCancelled);
    expect(await destination.list().isEmpty, isTrue);
  });

  test('cancelled export never creates output', () async {
    final cancellation = CancellationSource();
    await cancellation.cancel();
    final result = await export(token: cancellation.token);
    expect(result.failureOrNull?.code, DriftFailureCode.operationCancelled);
    expect(await destination.list().isEmpty, isTrue);
  });

  test('capture enforces file-count limit even if inspection raced', () async {
    for (var index = 0; index < maximumNormalizedSkillFileCount; index++) {
      await File(paths.join(source.path, '$index.txt')).writeAsString('');
    }
    final result = await export(
      inspector: DriftExportInspector(
        delegate: realInspector,
        fixed: PublishedArtifactInspection(
          state: PublishedArtifactState.mismatching,
          fingerprint: fingerprint,
        ),
      ),
    );
    expect(
      result.failureOrNull?.code,
      DriftFailureCode.skillContentLimitExceeded,
    );
    expect(await destination.list().isEmpty, isTrue);
  });

  test('capture enforces byte limit even if inspection raced', () async {
    final large = File(paths.join(source.path, 'large.bin'));
    final handle = await large.open(mode: FileMode.write);
    await handle.truncate(maximumNormalizedSkillByteSize + 1);
    await handle.close();
    final result = await export(
      inspector: DriftExportInspector(
        delegate: realInspector,
        fixed: PublishedArtifactInspection(
          state: PublishedArtifactState.mismatching,
          fingerprint: fingerprint,
        ),
      ),
    );
    expect(
      result.failureOrNull?.code,
      DriftFailureCode.skillContentLimitExceeded,
    );
    expect(await destination.list().isEmpty, isTrue);
  });

  test('missing destination is an expected export rejection', () async {
    final result = await export(
      destinationPath: paths.join(temp.path, 'not-created'),
    );
    expect(result.failureOrNull?.context['reason'], 'exportNotAllowed');
  });

  test('preserves nested files and empty directories', () async {
    final nested = await Directory(paths.join(source.path, 'nested')).create();
    await Directory(paths.join(nested.path, 'empty')).create();
    await File(paths.join(nested.path, 'notes.md')).writeAsString('notes');
    fingerprint = (await realInspector.observe(
      path: source.path,
      cancellationToken: CancellationToken.none(),
    )).fingerprint!;
    final result = await export();
    expect(result, isA<DriftSuccess<String>>());
    expect(
      await File(
        paths.join(result.valueOrNull!, 'nested', 'notes.md'),
      ).readAsString(),
      'notes',
    );
    expect(
      await Directory(
        paths.join(result.valueOrNull!, 'nested', 'empty'),
      ).exists(),
      isTrue,
    );
  });

  test('unsafe source takes priority over stale fingerprint', () async {
    final result = await export(
      inspector: DriftExportInspector(
        delegate: realInspector,
        fixed: const PublishedArtifactInspection(
          state: PublishedArtifactState.unsafe,
        ),
      ),
    );
    expect(
      result.failureOrNull?.code,
      DriftFailureCode.driftResolutionUnavailable,
    );
    expect(result.failureOrNull?.context['reason'], 'exportNotAllowed');
  });

  test(
    'unsafe source after capture takes priority and removes staging',
    () async {
      final result = await export(
        inspector: DriftExportInspector(
          delegate: realInspector,
          onObserve: (inspectedPath, call) async {
            if (call == 3) {
              await Directory(paths.join(inspectedPath, '.git')).create();
            }
          },
        ),
      );
      expect(
        result.failureOrNull?.code,
        DriftFailureCode.driftResolutionUnavailable,
      );
      expect(result.failureOrNull?.context['reason'], 'exportNotAllowed');
      expect(await destination.list().toList(), isEmpty);
    },
  );

  test('disappeared source after review is stale', () async {
    await source.delete(recursive: true);
    final result = await export();
    expect(result.failureOrNull?.code, DriftFailureCode.staleDriftReview);
    expect(await destination.list().isEmpty, isTrue);
  });

  test('IO failure during staged verification cleans staging', () async {
    final result = await export(
      inspector: DriftExportInspector(
        delegate: realInspector,
        onObserve: (path, call) async {
          if (call == 2) throw const FileSystemException('Injected IO fault.');
        },
      ),
    );
    expect(result.failureOrNull?.code, DriftFailureCode.ioFailure);
    expect(await destination.list().isEmpty, isTrue);
  });

  test('collision created during capture uses the next suffix', () async {
    final occupied = paths.join(
      destination.path,
      'sample-external-20261014010203',
    );
    final result = await export(
      inspector: DriftExportInspector(
        delegate: realInspector,
        onObserve: (path, call) async {
          if (call == 2) await File(occupied).writeAsString('existing');
        },
      ),
    );
    expect(result, isA<DriftSuccess<String>>());
    expect(
      paths.basename(result.valueOrNull!),
      'sample-external-20261014010203-2',
    );
    expect(await File(occupied).readAsString(), 'existing');
  });
}
