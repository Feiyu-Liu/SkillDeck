import 'dart:typed_data';

import 'package:skills_workspace/src/api/composite_command_dispatcher.dart';
import 'package:skills_workspace/src/api/requests.dart';
import 'package:skills_workspace/src/api/result.dart';
import 'package:skills_workspace/src/application/ports/revision_store_access_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/composition/effective_revision_content_command_handlers.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

const _hashA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _hashB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');

void main() {
  late _SnapshotReader snapshotReader;
  late WorkspaceSnapshotPublisher snapshots;
  late _ContentPort content;
  late CompositeSkillsRepositoryCommandDispatcher dispatcher;

  setUp(() async {
    snapshotReader = _SnapshotReader(_snapshot(contentHash: _hashA));
    snapshots = WorkspaceSnapshotPublisher(reader: snapshotReader);
    await snapshots.publishInitial(
      await snapshots.readInitial(integrity: WorkspaceIntegrity()),
    );
    content = _ContentPort(_tree(_hashA));
    dispatcher = CompositeSkillsRepositoryCommandDispatcher(
      buildEffectiveRevisionContentCommandHandlers(
        snapshots: snapshots,
        content: content,
      ),
    );
  });

  tearDown(() => snapshots.close());

  test(
    'lists metadata and reads an executable binary file as a defensive copy',
    () async {
      final manifest = await _success(
        dispatcher.execute<EffectiveSkillFileManifest>(
          operationId: _operationId(),
          kind: WorkspaceOperationKind.listEffectiveFiles,
          request: ListEffectiveFilesRequest(managedSkillId: _skillId),
          cancellationToken: CancellationToken.none(),
          markBusinessCommitted: () {},
          reportProgress: _ignoreProgress,
        ),
      );

      expect(manifest.managedSkillId, _skillId);
      expect(manifest.contentHash, _hashA);
      expect(manifest.files, <EffectiveSkillFileEntry>[
        const EffectiveSkillFileEntry(
          relativePath: 'SKILL.md',
          byteSize: 6,
          isExecutable: false,
        ),
        const EffectiveSkillFileEntry(
          relativePath: 'bin/run',
          byteSize: 3,
          isExecutable: true,
        ),
      ]);

      final file = await _success(
        dispatcher.execute<EffectiveSkillFileContent>(
          operationId: _operationId(),
          kind: WorkspaceOperationKind.readEffectiveFile,
          request: ReadEffectiveFileRequest(
            managedSkillId: _skillId,
            expectedContentHash: manifest.contentHash,
            relativePath: 'bin/run',
          ),
          cancellationToken: CancellationToken.none(),
          markBusinessCommitted: () {},
          reportProgress: _ignoreProgress,
        ),
      );

      expect(file.bytes, Uint8List.fromList(<int>[0, 1, 2]));
      file.bytes[0] = 255;
      expect(content.tree.files.last.bytes, <int>[0, 1, 2]);
    },
  );

  test('rejects unsafe paths without reading the Revision Store', () async {
    for (final relativePath in const <String>[
      '',
      '/SKILL.md',
      r'\\server\share',
      r'C:\Skill.md',
      '../SKILL.md',
      'docs//SKILL.md',
      r'docs\SKILL.md',
      'SKILL.md\u0000',
    ]) {
      final result = await dispatcher.execute<EffectiveSkillFileContent>(
        operationId: _operationId(),
        kind: WorkspaceOperationKind.readEffectiveFile,
        request: ReadEffectiveFileRequest(
          managedSkillId: _skillId,
          expectedContentHash: _hashA,
          relativePath: relativePath == r'SKILL.md\u0000'
              ? 'SKILL.md\u0000'.replaceAll(r'\u0000', '\u0000')
              : relativePath,
        ),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: _ignoreProgress,
      );

      expect(
        result.failureOrNull?.code,
        SkillsErrorCode.invalidEffectiveFilePath,
      );
    }
    expect(content.readCount, 0);
  });

  test(
    'returns stale Snapshot when the requested hash no longer matches',
    () async {
      final result = await dispatcher.execute<EffectiveSkillFileContent>(
        operationId: _operationId(),
        kind: WorkspaceOperationKind.readEffectiveFile,
        request: ReadEffectiveFileRequest(
          managedSkillId: _skillId,
          expectedContentHash: _hashB,
          relativePath: 'SKILL.md',
        ),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: _ignoreProgress,
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
      expect(content.readCount, 0);
    },
  );

  test(
    'returns stale Snapshot when a revalidated Pointer selects later bytes',
    () async {
      content.tree = _tree(_hashB);

      final result = await dispatcher.execute<EffectiveSkillFileContent>(
        operationId: _operationId(),
        kind: WorkspaceOperationKind.readEffectiveFile,
        request: ReadEffectiveFileRequest(
          managedSkillId: _skillId,
          expectedContentHash: _hashA,
          relativePath: 'SKILL.md',
        ),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: _ignoreProgress,
      );

      expect(result.failureOrNull?.code, SkillsErrorCode.staleSnapshot);
    },
  );

  test(
    'returns typed failures for missing Skill, file, corruption, and cancellation',
    () async {
      final unknownSkill = ManagedSkillId(
        '123e4567-e89b-42d3-a456-426614174001',
      );
      final missingSkill = await dispatcher.execute<EffectiveSkillFileManifest>(
        operationId: _operationId(),
        kind: WorkspaceOperationKind.listEffectiveFiles,
        request: ListEffectiveFilesRequest(managedSkillId: unknownSkill),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: _ignoreProgress,
      );
      expect(missingSkill.failureOrNull?.code, SkillsErrorCode.skillNotFound);

      final missingFile = await dispatcher.execute<EffectiveSkillFileContent>(
        operationId: _operationId(),
        kind: WorkspaceOperationKind.readEffectiveFile,
        request: ReadEffectiveFileRequest(
          managedSkillId: _skillId,
          expectedContentHash: _hashA,
          relativePath: 'missing.md',
        ),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: _ignoreProgress,
      );
      expect(
        missingFile.failureOrNull?.code,
        SkillsErrorCode.effectiveFileNotFound,
      );

      content.failure = StateError('corrupt store');
      final corrupt = await dispatcher.execute<EffectiveSkillFileManifest>(
        operationId: _operationId(),
        kind: WorkspaceOperationKind.listEffectiveFiles,
        request: ListEffectiveFilesRequest(managedSkillId: _skillId),
        cancellationToken: CancellationToken.none(),
        markBusinessCommitted: () {},
        reportProgress: _ignoreProgress,
      );
      expect(corrupt.failureOrNull?.code, SkillsErrorCode.ioFailure);
      content.failure = null;

      final source = CancellationSource();
      await source.cancel();
      final cancelled = await dispatcher.execute<EffectiveSkillFileManifest>(
        operationId: _operationId(),
        kind: WorkspaceOperationKind.listEffectiveFiles,
        request: ListEffectiveFilesRequest(managedSkillId: _skillId),
        cancellationToken: source.token,
        markBusinessCommitted: () {},
        reportProgress: _ignoreProgress,
      );
      expect(cancelled.failureOrNull?.code, SkillsErrorCode.operationCancelled);
    },
  );
}

Future<T> _success<T>(Future<SkillsResult<T>> result) async {
  final completed = await result;
  expect(completed, isA<SkillsSuccess<T>>(), reason: '$completed');
  return completed.valueOrNull as T;
}

RepositorySnapshot _snapshot({required String contentHash}) =>
    RepositorySnapshot(
      revision: RepositoryRevision.initial(),
      managedSkills: <ManagedSkill>[
        ManagedSkill(
          id: _skillId,
          slotKey: 'example',
          declaredName: 'example',
          displayName: 'Example',
          description: 'Example skill',
          source: LocalSourceDescriptor(locator: '/tmp/example'),
          currentRevision: ManagedSkillRevisionSummary(
            contentHash: contentHash,
            fileCount: 2,
            byteSize: 9,
            publishedAt: DateTime.utc(2026),
          ),
        ),
      ],
    );

NormalizedSkillTree _tree(String hash) => NormalizedSkillTree(
  contentHash: hash,
  byteSize: 9,
  files: <NormalizedSkillFile>[
    NormalizedSkillFile(
      relativePath: 'SKILL.md',
      bytes: 'skill\n'.codeUnits,
      isExecutable: false,
    ),
    NormalizedSkillFile(
      relativePath: 'bin/run',
      bytes: const <int>[0, 1, 2],
      isExecutable: true,
    ),
  ],
);

final class _SnapshotReader implements WorkspaceSnapshotReaderPort {
  _SnapshotReader(this.snapshot);

  final RepositorySnapshot snapshot;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      snapshot;
}

final class _ContentPort implements CurrentEffectiveRevisionContentPort {
  _ContentPort(this.tree);

  NormalizedSkillTree tree;
  Object? failure;
  var readCount = 0;

  @override
  Future<NormalizedSkillTree> readCurrentEffective(
    ManagedSkillId managedSkillId, {
    CancellationToken? cancellationToken,
  }) async {
    readCount += 1;
    final error = failure;
    if (error != null) throw error;
    return tree;
  }
}

OperationId _operationId() =>
    OperationId('123e4567-e89b-42d3-a456-426614174099');

void _ignoreProgress(
  OperationProgressPhase phase, {
  String? currentItem,
  int completed = 0,
  int? total,
}) {}
