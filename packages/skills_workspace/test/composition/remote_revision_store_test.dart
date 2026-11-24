import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/composition/remote_revision_store.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:test/test.dart';

void main() {
  late String candidate;
  late String live;

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('remote-store-delta-');
    addTearDown(() => root.delete(recursive: true));
    candidate = path.join(root.path, 'candidate.git');
    live = path.join(root.path, 'live.git');
    for (final store in [candidate, live]) {
      await Directory(path.join(store, 'objects')).create(recursive: true);
    }
  });

  Future<List<RemoteStoreAddition>> additions() => readRemoteStoreAdditions(
    candidateStore: candidate,
    liveStore: live,
    cancellationToken: CancellationToken.none(),
  );

  test(
    'promotes only new object paths and puts pack data before its index',
    () async {
      final existing = path.join('objects', '01', 'a' * 38);
      final loose = path.join('objects', '01', 'b' * 38);
      final newDirectory = path.join('objects', '02');
      final pack = path.join('objects', 'pack', 'pack-${'c' * 40}.pack');
      final index = path.setExtension(pack, '.idx');
      await _file(live, existing);
      await Directory(path.join(live, 'objects', 'pack')).create();
      for (final relative in [
        existing,
        loose,
        path.join(newDirectory, 'd' * 38),
        index,
        pack,
        path.join('objects', 'info', 'alternates'),
        path.join('refs', 'heads', 'main'),
      ]) {
        await _file(candidate, relative);
      }

      expect(await additions(), [
        (
          source: path.join(candidate, loose),
          target: path.join(live, loose),
          isDirectory: false,
        ),
        (
          source: path.join(candidate, newDirectory),
          target: path.join(live, newDirectory),
          isDirectory: true,
        ),
        (
          source: path.join(candidate, pack),
          target: path.join(live, pack),
          isDirectory: false,
        ),
        (
          source: path.join(candidate, index),
          target: path.join(live, index),
          isDirectory: false,
        ),
      ]);
      expect(await File(path.join(live, loose)).exists(), isFalse);
      expect(await File(path.join(candidate, pack)).exists(), isTrue);
    },
  );

  test('rejects a new index without its matching object pack', () async {
    await _file(
      candidate,
      path.join('objects', 'pack', 'pack-${'e' * 40}.idx'),
    );
    await expectLater(additions(), throwsA(isA<RevisionEngineException>()));
  });

  test('rejects an object path occupied by a directory', () async {
    final occupied = path.join('objects', '01', 'f' * 38);
    await Directory(path.join(live, occupied)).create(recursive: true);
    await _file(candidate, occupied);
    await expectLater(additions(), throwsA(isA<RevisionEngineException>()));
  });
}

Future<void> _file(String root, String relative) async {
  final file = File(path.join(root, relative));
  await file.create(recursive: true);
  await file.writeAsString('object fixture');
}
