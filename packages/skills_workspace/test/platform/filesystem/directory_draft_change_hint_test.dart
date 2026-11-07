import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/draft_snapshot_ports.dart';
import 'package:skills_workspace/src/platform/filesystem/directory_draft_change_hint.dart';
import 'package:skills_workspace/src/platform/filesystem/filesystem_draft_snapshot.dart';
import 'package:test/test.dart';

void main() {
  test('all filesystem event details collapse to advisory tokens', () async {
    final controller = StreamController<FileSystemEvent>();
    addTearDown(controller.close);
    final adapter = DirectoryDraftChangeHintPort(
      directoryWatch: (_) => controller.stream,
    );
    final hints = adapter.watchDraft('/draft').take(3).toList();

    controller
      ..add(FileSystemCreateEvent('/draft/new.md', false))
      ..add(FileSystemModifyEvent('/draft/SKILL.md', false, true))
      ..add(FileSystemDeleteEvent('/draft/old.md', false));

    expect(await hints, hasLength(3));
  });

  test('real Directory.watch emits a hint for Draft activity', () async {
    if (!FileSystemEntity.isWatchSupported) return;
    final temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-draft-watch-',
    );
    addTearDown(() async {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });
    final adapter = DirectoryDraftChangeHintPort();
    final hint = adapter
        .watchDraft(temporary.path)
        .first
        .timeout(const Duration(seconds: 5));

    await File(path.join(temporary.path, 'SKILL.md')).writeAsString('# edit');

    await expectLater(hint, completes);
  });

  test(
    'a missed hint cannot hide a change from authoritative fingerprinting',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'skills-workspace-draft-watch-authority-',
      );
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final draft = Directory(path.join(temporary.path, 'draft'));
      await draft.create();
      final skill = File(path.join(draft.path, 'SKILL.md'));
      await skill.writeAsString('# before');
      final request = DraftCaptureRequest(
        liveDraftPath: draft.path,
        stagingDestinationPath: path.join(temporary.path, 'staging', 'draft'),
        capturePosixExecutableIntent: !Platform.isWindows,
      );
      final snapshots = FilesystemDraftSnapshotAdapter();
      final before = (await snapshots.fingerprint(request)).valueOrNull!;
      final missedHints = DirectoryDraftChangeHintPort(
        directoryWatch: (_) => const Stream<FileSystemEvent>.empty(),
      );

      await skill.writeAsString('# after');
      final after = (await snapshots.fingerprint(request)).valueOrNull!;

      expect(await missedHints.watchDraft(draft.path).toList(), isEmpty);
      expect(after, isNot(before));
    },
  );
}
