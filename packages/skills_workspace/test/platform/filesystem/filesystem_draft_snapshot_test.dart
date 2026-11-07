import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/drafts/draft_snapshot_coordinator.dart';
import 'package:skills_workspace/src/application/ports/draft_snapshot_ports.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/infrastructure/content/draft_content_adapter.dart';
import 'package:skills_workspace/src/platform/filesystem/filesystem_draft_snapshot.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late String draftPath;
  late String stagingDestinationPath;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-draft-snapshot-',
    );
    draftPath = path.join(temporary.path, 'draft');
    stagingDestinationPath = path.join(temporary.path, 'private', 'snapshot');
    await Directory(path.join(draftPath, 'notes')).create(recursive: true);
    await File(path.join(draftPath, 'SKILL.md')).writeAsString(_skillSource);
    await File(
      path.join(draftPath, 'notes', 'guide.md'),
    ).writeAsString('# Guide\n');
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'captures bytes, directory evidence, and a stable fingerprint',
    () async {
      final adapter = FilesystemDraftSnapshotAdapter();
      final request = _request(draftPath, stagingDestinationPath);

      final captureResult = await adapter.capture(request);
      final capture = captureResult.valueOrNull!;
      final current = await adapter.fingerprint(request);

      expect(current.valueOrNull, capture.fingerprint);
      expect(capture.files.map((file) => file.relativePath), [
        'SKILL.md',
        'notes/guide.md',
      ]);
      expect(capture.fingerprint.entries.map((entry) => entry.relativePath), [
        '',
        'SKILL.md',
        'notes',
        'notes/guide.md',
      ]);
      expect(
        await File(path.join(capture.stagingPath, 'SKILL.md')).readAsString(),
        _skillSource,
      );

      await adapter.discardStaging(capture);
      expect(await Directory(capture.stagingPath).exists(), isFalse);
    },
  );

  test('a write before capture becomes part of the stable snapshot', () async {
    var wroteBeforeCapture = false;
    final guide = File(path.join(draftPath, 'notes', 'guide.md'));
    final adapter = FilesystemDraftSnapshotAdapter(
      observer: (purpose, event, relativePath) async {
        if (!wroteBeforeCapture &&
            purpose == DraftFilesystemScanPurpose.capture &&
            event == DraftFilesystemCaptureEvent.beforeScan) {
          wroteBeforeCapture = true;
          await guide.writeAsString('# Saved before scan\n');
        }
      },
    );
    final coordinator = DraftSnapshotCoordinator(
      filesystem: adapter,
      content: const NormalizedDraftContentAdapter(),
    );

    final result = await coordinator.captureForDirectPublish(
      request: _request(draftPath, stagingDestinationPath),
      expectedDeclaredName: 'example-skill',
    );

    final capturedGuide = result.valueOrNull!.normalizedTree.files.singleWhere(
      (file) => file.relativePath == 'notes/guide.md',
    );
    expect(utf8.decode(capturedGuide.bytes), '# Saved before scan\n');
    await adapter.discardStaging(result.valueOrNull!.capture);
  });

  test('a write during capture retries and uses only later bytes', () async {
    var wroteDuringCapture = false;
    final guide = File(path.join(draftPath, 'notes', 'guide.md'));
    final adapter = FilesystemDraftSnapshotAdapter(
      observer: (purpose, event, relativePath) async {
        if (!wroteDuringCapture &&
            purpose == DraftFilesystemScanPurpose.capture &&
            event == DraftFilesystemCaptureEvent.afterFileRead &&
            relativePath == 'notes/guide.md') {
          wroteDuringCapture = true;
          await guide.writeAsString('# Saved during scan\n');
        }
      },
    );
    final coordinator = DraftSnapshotCoordinator(
      filesystem: adapter,
      content: const NormalizedDraftContentAdapter(),
    );

    final result = await coordinator.captureForDirectPublish(
      request: _request(draftPath, stagingDestinationPath),
      expectedDeclaredName: 'example-skill',
    );

    final capturedGuide = result.valueOrNull!.normalizedTree.files.singleWhere(
      (file) => file.relativePath == 'notes/guide.md',
    );
    expect(utf8.decode(capturedGuide.bytes), '# Saved during scan\n');
    await adapter.discardStaging(result.valueOrNull!.capture);
  });

  test(
    'three overlapping revalidation writes fail with the typed code',
    () async {
      var revalidationWrites = 0;
      final adapter = FilesystemDraftSnapshotAdapter(
        observer: (purpose, event, relativePath) async {
          if (purpose == DraftFilesystemScanPurpose.revalidation &&
              event == DraftFilesystemCaptureEvent.afterFileRead &&
              relativePath == 'SKILL.md') {
            revalidationWrites += 1;
            final file = File(path.join(draftPath, 'SKILL.md'));
            await file.writeAsString('${await file.readAsString()} ');
          }
        },
      );
      final coordinator = DraftSnapshotCoordinator(
        filesystem: adapter,
        content: const NormalizedDraftContentAdapter(),
      );

      final result = await coordinator.captureForDirectPublish(
        request: _request(draftPath, stagingDestinationPath),
        expectedDeclaredName: 'example-skill',
      );

      expect(
        result.failureOrNull!.code,
        DraftSnapshotFailureCode.draftChangedDuringPublish,
      );
      expect(revalidationWrites, 3);
      final stagingParent = Directory(path.dirname(stagingDestinationPath));
      final residue = await stagingParent
          .list(followLinks: false)
          .where(
            (entry) => path
                .basename(entry.path)
                .startsWith('.snapshot.draft-capture.'),
          )
          .toList();
      expect(residue, isEmpty);
    },
  );

  test('a save after capture selects preserve and re-anchor', () async {
    final adapter = FilesystemDraftSnapshotAdapter();
    final coordinator = DraftSnapshotCoordinator(
      filesystem: adapter,
      content: const NormalizedDraftContentAdapter(),
    );
    final request = _request(draftPath, stagingDestinationPath);
    final captured = await coordinator.captureForDirectPublish(
      request: request,
      expectedDeclaredName: 'example-skill',
    );
    await File(
      path.join(draftPath, 'notes', 'guide.md'),
    ).writeAsString('# Later save\n');

    final disposition = await coordinator.decidePublishedDraftDisposition(
      snapshot: captured.valueOrNull!,
      request: request,
    );

    expect(disposition, PublishedDraftDisposition.preserveAndReanchor);
    await adapter.discardStaging(captured.valueOrNull!.capture);
  });

  test('an unchanged Draft is eligible for compare-and-delete', () async {
    final adapter = FilesystemDraftSnapshotAdapter();
    final coordinator = DraftSnapshotCoordinator(
      filesystem: adapter,
      content: const NormalizedDraftContentAdapter(),
    );
    final request = _request(draftPath, stagingDestinationPath);
    final captured = await coordinator.captureForDirectPublish(
      request: request,
      expectedDeclaredName: 'example-skill',
    );

    final disposition = await coordinator.decidePublishedDraftDisposition(
      snapshot: captured.valueOrNull!,
      request: request,
    );

    expect(disposition, PublishedDraftDisposition.deleteUnchanged);
    await adapter.discardStaging(captured.valueOrNull!.capture);
  });

  test(
    'direct Publish name changes fail before a revision can be built',
    () async {
      final adapter = FilesystemDraftSnapshotAdapter();
      final coordinator = DraftSnapshotCoordinator(
        filesystem: adapter,
        content: const NormalizedDraftContentAdapter(),
      );

      final result = await coordinator.captureForDirectPublish(
        request: _request(draftPath, stagingDestinationPath),
        expectedDeclaredName: 'different-name',
      );

      expect(
        result.failureOrNull!.code,
        DraftSnapshotFailureCode.declaredNameChangeNotAllowed,
      );
    },
  );
}

DraftCaptureRequest _request(String draftPath, String stagingDestinationPath) =>
    DraftCaptureRequest(
      liveDraftPath: draftPath,
      stagingDestinationPath: stagingDestinationPath,
      capturePosixExecutableIntent: !Platform.isWindows,
    );

final String _skillSource = utf8.decode(<int>[
  ...utf8.encode('---\n'),
  ...utf8.encode('name: example-skill\n'),
  ...utf8.encode('description: Example\n'),
  ...utf8.encode('---\n'),
  ...utf8.encode('# Example\n'),
]);
