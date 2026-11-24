import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

import '../support/drift_facade_fixture.dart';

void main() {
  test('RevisionId is a validated opaque value', () {
    const value = '0123456789abcdef0123456789abcdef01234567';
    final revision = RevisionId(value);
    expect(revision.value, value);
    expect(revision.toString(), value);
    expect(revision, RevisionId(value));
    expect(revision.hashCode, RevisionId(value).hashCode);
    expect(revision, isNot(RevisionId('0' * 40)));
    for (final invalid in [
      '',
      'a' * 39,
      'z' * 40,
      'a' * 64,
      value.toUpperCase(),
      '$value\n',
    ]) {
      expect(() => RevisionId(invalid), throwsArgumentError);
    }
  });

  test(
    'exports complete published history of both heads to one pack',
    () async {
      final fixture = await DriftFacadeFixture.create(activate: false);
      final repository = fixture.repository;
      final id = fixture.managedSkillId;
      await fixture.changeNotes(fixture.sourcePath, 'from the upstream\n');
      await driftSuccess(
        repository.update(UpdateRequest(managedSkillIds: {id})),
      );
      for (final notes in ['first publication\n', 'latest publication\n']) {
        final draft = await driftSuccess(
          repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
        );
        await fixture.changeNotes(draft.path, notes);
        await driftSuccess(
          repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
        );
      }

      final workspaceRevision = repository.snapshot.revision;
      final database = File(
        path.join(fixture.workspacePath, 'workspace.sqlite'),
      );
      final databaseBefore = await database.readAsBytes();
      final stores = Directory(
        path.join(fixture.workspacePath, 'revision-stores'),
      );
      final storeBefore = await _readFiles(stores);
      final historyBefore = await driftSuccess(
        repository.inspectOperationHistory(
          OperationHistoryRequest(managedSkillId: id),
        ),
      );
      final destination = path.join(fixture.exportDirectory, 'heads.pack');
      final result =
          await repository
                  .exportRevisionPack(
                    ExportRevisionPackRequest(
                      managedSkillId: id,
                      destinationPath: destination,
                    ),
                  )
                  .completed
              as SkillsSuccess<RevisionPackExport>;
      final heads = result.value;
      expect(result.changed, isFalse);
      expect(heads.upstream, isNotNull);
      expect(heads.effective, isNot(heads.upstream));
      expect(
        await Directory(
          fixture.exportDirectory,
        ).list().map((entity) => path.basename(entity.path)).toList(),
        ['heads.pack'],
      );

      final fresh = path.join(fixture.temporaryRoot.path, 'import.git');
      await _git(['init', '--bare', '--object-format=sha1', fresh]);
      final copiedPack = path.join(
        fresh,
        'objects',
        'pack',
        'pack-export.pack',
      );
      await File(destination).copy(copiedPack);
      await _git(['-C', fresh, 'index-pack', '--strict', copiedPack]);
      await _git([
        '-C',
        fresh,
        'fsck',
        '--full',
        '--no-reflogs',
        '--no-dangling',
        heads.effective.value,
        heads.upstream!.value,
      ]);
      expect(
        await _git(['-C', fresh, 'show', '${heads.upstream!.value}:notes.md']),
        'from the upstream\n',
      );
      expect(
        await _git(['-C', fresh, 'show', '${heads.effective.value}:notes.md']),
        'latest publication\n',
      );
      final traversed = await _git([
        '-C',
        fresh,
        'rev-list',
        heads.effective.value,
        heads.upstream!.value,
      ]);
      expect(traversed.trim().split('\n'), hasLength(greaterThanOrEqualTo(4)));

      final historyAfter = await driftSuccess(
        repository.inspectOperationHistory(
          OperationHistoryRequest(managedSkillId: id),
        ),
      );
      expect(
        historyAfter.entries.map((entry) => entry.operationId),
        historyBefore.entries.map((entry) => entry.operationId),
      );
      expect(repository.snapshot.revision, workspaceRevision);
      expect(await database.readAsBytes(), databaseBefore);
      expect(await _readFiles(stores), storeBefore);
    },
  );

  test('reports a missing ancestor as Store corruption', () async {
    final fixture = await DriftFacadeFixture.create(activate: false);
    final repository = fixture.repository;
    final id = fixture.managedSkillId;
    for (final notes in ['first publication\n', 'latest publication\n']) {
      final draft = await driftSuccess(
        repository.ensureDraft(EnsureDraftRequest(managedSkillId: id)),
      );
      await fixture.changeNotes(draft.path, notes);
      await driftSuccess(
        repository.publishDraft(PublishDraftRequest(managedSkillId: id)),
      );
    }
    final stores = path.join(fixture.workspacePath, 'revision-stores');
    final store = path.join(stores, '${id.value}.git');
    final request = ExportRevisionPackRequest(
      managedSkillId: id,
      destinationPath: path.join(fixture.exportDirectory, 'heads.pack'),
    );
    final heads = await driftSuccess(repository.exportRevisionPack(request));
    final ancestor = (await _git([
      '-C',
      store,
      'rev-parse',
      '${heads.effective.value}^',
    ])).trim();
    expect(ancestor, isNot(heads.upstream?.value));
    await File(
      path.join(
        store,
        'objects',
        ancestor.substring(0, 2),
        ancestor.substring(2),
      ),
    ).delete();
    await File(request.destinationPath).delete();

    await driftFailure(
      repository.exportRevisionPack(request),
      SkillsErrorCode.revisionStoreCorrupt,
    );
    expect(await File(request.destinationPath).exists(), isFalse);
    expect(
      await Directory(
        stores,
      ).list().any((entry) => path.basename(entry.path).startsWith('.pack-')),
      isFalse,
    );
  });

  test(
    'returns typed failures for an unknown Skill and unusable destinations',
    () async {
      final fixture = await DriftFacadeFixture.create(activate: false);
      final repository = fixture.repository;
      final existingFile = File(
        path.join(fixture.exportDirectory, 'existing.pack'),
      );
      await existingFile.writeAsString('keep this');
      for (final destination in [
        existingFile.path,
        fixture.exportDirectory,
        path.join(fixture.exportDirectory, 'missing', 'pack'),
        path.join(fixture.workspacePath, 'unsafe.pack'),
      ]) {
        await driftFailure(
          repository.exportRevisionPack(
            ExportRevisionPackRequest(
              managedSkillId: fixture.managedSkillId,
              destinationPath: destination,
            ),
          ),
          SkillsErrorCode.ioFailure,
          reason: 'destinationUnavailable',
        );
      }
      expect(await existingFile.readAsString(), 'keep this');
      final target = File(path.join(fixture.exportDirectory, 'unknown.pack'));
      await driftFailure(
        repository.exportRevisionPack(
          ExportRevisionPackRequest(
            managedSkillId: ManagedSkillId(
              '123e4567-e89b-42d3-a456-426614174321',
            ),
            destinationPath: target.path,
          ),
        ),
        SkillsErrorCode.skillNotFound,
      );
      expect(await target.exists(), isFalse);
    },
  );

  test(
    'cancellation after pack preparation starts leaves no destination',
    () async {
      final fixture = await DriftFacadeFixture.create(activate: false);
      final target = File(path.join(fixture.exportDirectory, 'cancelled.pack'));
      final operation = fixture.repository.exportRevisionPack(
        ExportRevisionPackRequest(
          managedSkillId: fixture.managedSkillId,
          destinationPath: target.path,
        ),
      );
      await operation.progress.firstWhere(
        (progress) => progress.phase == OperationProgressPhase.preparing,
      );
      final stores = Directory(
        path.join(fixture.workspacePath, 'revision-stores'),
      );
      expect(
        await stores.list().any(
          (entry) => path.basename(entry.path).startsWith('.pack-'),
        ),
        isTrue,
      );
      await operation.cancel();
      await driftFailure(operation, SkillsErrorCode.operationCancelled);
      expect(await target.exists(), isFalse);
    },
  );

  test('concurrent exports to the same path allow only one writer', () async {
    final fixture = await DriftFacadeFixture.create(activate: false);
    final request = ExportRevisionPackRequest(
      managedSkillId: fixture.managedSkillId,
      destinationPath: path.join(fixture.exportDirectory, 'race.pack'),
    );
    final results = await Future.wait([
      fixture.repository.exportRevisionPack(request).completed,
      fixture.repository.exportRevisionPack(request).completed,
    ]);
    expect(results.where((result) => result.isSuccess), hasLength(1));
    expect(
      results.singleWhere((result) => result.isFailure).failureOrNull?.context,
      {'reason': 'destinationUnavailable'},
    );
    expect(
      await File(request.destinationPath).openRead(0, 4).first,
      'PACK'.codeUnits,
    );
  });
}

Future<String> _git(List<String> arguments) async {
  final result = await Process.run('git', arguments);
  expect(result.exitCode, 0, reason: 'Git ${arguments.first} failed');
  return result.stdout as String;
}

Future<Map<String, List<int>>> _readFiles(Directory root) async => {
  await for (final entity in root.list(recursive: true, followLinks: false))
    if (entity is File)
      path.relative(entity.path, from: root.path): await entity.readAsBytes(),
};
