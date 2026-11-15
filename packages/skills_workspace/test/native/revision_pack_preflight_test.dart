import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:test/test.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';

void main() {
  late Directory scratch;
  late RevisionNativeEngine engine;
  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('pack-preflight-');
    engine = RevisionNativeEngine.open();
  });
  tearDown(() async {
    engine.close();
    await scratch.delete(recursive: true);
  });

  void restore(
    List<int> pack,
    List<int> index, {
    RevisionObjectImportLimits limits = const RevisionObjectImportLimits(),
    String? root,
  }) {
    final packFile = File(path.join(scratch.path, 'input.pack'))
      ..writeAsBytesSync(pack);
    final indexFile = File(path.join(scratch.path, 'input.idx'))
      ..writeAsBytesSync(index);
    engine.restoreRecoveryPack(
      stagedRepositoryPath: path.join(scratch.path, 'staged.git'),
      packPath: packFile.path,
      indexPath: indexFile.path,
      retainedRoots: [RevisionObjectId(root ?? '1' * 40)],
      limits: limits,
    );
  }

  for (final type in [3, 7]) {
    test(
      'tiny compressed input rejects giant ${type == 3 ? 'declared object' : 'delta result'} before index/object allocation',
      () {
        final body = type == 3
            ? const <int>[]
            : [..._varint(1), ..._varint(1 << 40)];
        final object = [
          ..._objectHeader(type, type == 3 ? 1 << 40 : body.length),
          if (type == 7) ...List.filled(20, 0),
          ...zlib.encode(body),
        ];
        final pack = _pack([object]);
        expect(pack.length, lessThan(128));
        // The deliberately invalid empty index would yield bundleFailure if a
        // library/index reader ran first. limitExceeded proves the earlier gate.
        expect(
          () => restore(
            pack,
            [],
            limits: const RevisionObjectImportLimits(
              maximumObjectBytes: 1024,
              maximumTotalBytes: 1024 * 1024,
            ),
          ),
          throwsA(_code(RevisionNativeFailureCode.limitExceeded)),
        );
        expect(
          Directory(
            path.join(scratch.path, 'staged.git', 'objects', 'pack'),
          ).existsSync(),
          isTrue,
        );
      },
    );
  }

  test('streaming actual inflate output cannot exceed the selected budget', () {
    final encoded = zlib.encode(Uint8List(8 * 1024 * 1024));
    expect(encoded.length, lessThan(16384));
    final pack = _pack([
      [..._objectHeader(3, 1), ...encoded],
    ]);
    expect(
      () => restore(
        pack,
        [],
        limits: const RevisionObjectImportLimits(
          maximumObjectBytes: 1024,
          maximumTotalBytes: 1024 * 1024,
        ),
      ),
      throwsA(_code(RevisionNativeFailureCode.limitExceeded)),
    );
  });

  for (final ofs in [false, true]) {
    test(
      'valid ${ofs ? 'OFS' : 'REF'} delta is bounded before exact staged recovery',
      () {
        final fixture = _deltaFixture(ofs: ofs);
        restore(fixture.pack, fixture.index, root: fixture.root);
        final recovered = engine.readTree(
          path.join(scratch.path, 'staged.git'),
          RevisionObjectId(fixture.root),
        );
        expect(recovered.files.single.bytes, ascii.encode('ab'));
      },
    );
  }

  test('delta depth limit is distinct from malformed pack data', () {
    final fixture = _deltaFixture();
    expect(
      () => restore(
        fixture.pack,
        fixture.index,
        root: fixture.root,
        limits: const RevisionObjectImportLimits(maximumDeltaDepth: 0),
      ),
      throwsA(_code(RevisionNativeFailureCode.limitExceeded)),
    );
  });

  for (final depth in [16, 65]) {
    test(
      'raw REF delta chain depth $depth is bounded before library indexing',
      () {
        final raw = File(path.join(scratch.path, 'chain.pack'))
          ..writeAsBytesSync(_refChain(depth));
        final indexed = Directory(path.join(scratch.path, 'indexed'))
          ..createSync();
        if (depth > 64) {
          expect(
            () => engine.createPackIndex(
              packPath: raw.path,
              stagingDirectory: indexed.path,
            ),
            throwsA(_code(RevisionNativeFailureCode.limitExceeded)),
          );
          expect(indexed.listSync(), isEmpty);
        } else {
          engine.createPackIndex(
            packPath: raw.path,
            stagingDirectory: indexed.path,
          );
          expect(
            File(path.join(indexed.path, 'objects.idx')).lengthSync(),
            greaterThan(0),
          );
        }
      },
    );
  }
  test(
    'worker cancellation interrupts fixed-buffer preflight inflation',
    () async {
      final object = [
        ..._objectHeader(3, 64 * 1024 * 1024),
        ...zlib.encode(Uint8List(64 * 1024 * 1024)),
      ];
      final raw = File(path.join(scratch.path, 'inflate.pack'))
        ..writeAsBytesSync(_pack([object]));
      final indexed = Directory(path.join(scratch.path, 'cancelled'))
        ..createSync();
      final worker = await RevisionWorker.start();
      final cancellation = CancellationSource();
      final future = worker.createPackIndex(
        packPath: raw.path,
        stagingDirectory: indexed.path,
        limits: const RevisionObjectImportLimits(
          maximumObjectBytes: 128 * 1024 * 1024,
        ),
        cancellationToken: cancellation.token,
      );
      final timer = Timer(
        const Duration(milliseconds: 2),
        () => unawaited(cancellation.cancel()),
      );
      try {
        await expectLater(
          future,
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
        await worker.close();
      }
    },
  );

  test(
    'a missing REF delta base fails before any dependency pointer is followed',
    () {
      final fixture = _deltaFixture(missingBase: true);
      expect(
        () => restore(fixture.pack, fixture.index, root: fixture.root),
        throwsA(_code(RevisionNativeFailureCode.bundleFailure)),
      );
    },
  );

  test(
    'self-referential REF delta is rejected before a library follows the cycle',
    () {
      final fixture = _deltaFixture(cycle: true);
      expect(
        () => restore(fixture.pack, fixture.index, root: fixture.root),
        throwsA(_code(RevisionNativeFailureCode.bundleFailure)),
      );
    },
  );
}

Matcher _code(RevisionNativeFailureCode code) =>
    isA<RevisionNativeException>().having((error) => error.code, 'code', code);
List<int> _varint(int value) {
  final bytes = <int>[];
  do {
    var byte = value & 127;
    value >>= 7;
    if (value > 0) byte |= 128;
    bytes.add(byte);
  } while (value > 0);
  return bytes;
}

List<int> _objectHeader(int type, int size) {
  var first = type << 4 | size & 15;
  size >>= 4;
  if (size > 0) first |= 128;
  return [first, if (size > 0) ..._varint(size)];
}

List<int> _u32(int value) => [
  value >> 24 & 255,
  value >> 16 & 255,
  value >> 8 & 255,
  value & 255,
];
String _oid(String type, List<int> bytes) => sha1.convert([
  ...ascii.encode('$type ${bytes.length}\u0000'),
  ...bytes,
]).toString();
List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
List<int> _pack(List<List<int>> objects) {
  final bytes = [
    ...ascii.encode('PACK'),
    ..._u32(2),
    ..._u32(objects.length),
    for (final object in objects) ...object,
  ];
  return [...bytes, ...sha1.convert(bytes).bytes];
}

int _crc(List<int> bytes) {
  var value = 0xffffffff;
  for (final byte in bytes) {
    value ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      value = value & 1 == 1 ? (value >> 1) ^ 0xedb88320 : value >> 1;
    }
  }
  return value ^ 0xffffffff;
}

({List<int> pack, List<int> index, String root}) _deltaFixture({
  bool cycle = false,
  bool ofs = false,
  bool missingBase = false,
}) {
  final base = ascii.encode('a'), result = ascii.encode('ab');
  final baseId = _oid('blob', base), resultId = _oid('blob', result);
  final delta = [1, 2, 0x90, 1, 1, 98];
  final baseObject = [..._objectHeader(3, 1), ...zlib.encode(base)];
  // Small fixture offset distance fits one OFS byte.
  final deltaObject = [
    ..._objectHeader(ofs ? 6 : 7, delta.length),
    if (ofs)
      baseObject.length
    else
      ..._hex(
        missingBase
            ? 'f' * 40
            : cycle
            ? resultId
            : baseId,
      ),
    ...zlib.encode(delta),
  ];
  final tree = [...ascii.encode('100644 file\u0000'), ..._hex(resultId)];
  final treeId = _oid('tree', tree);
  final commit = ascii.encode(
    'tree $treeId\nauthor Fixture <fixture@example.invalid> 1 +0000\ncommitter Fixture <fixture@example.invalid> 1 +0000\n\nfixture\n',
  );
  final root = _oid('commit', commit);
  final objects = [
    baseObject,
    deltaObject,
    [..._objectHeader(2, tree.length), ...zlib.encode(tree)],
    [..._objectHeader(1, commit.length), ...zlib.encode(commit)],
  ];
  final ids = [baseId, resultId, treeId, root];
  var offset = 12;
  final entries = <({String oid, int offset, int crc})>[];
  for (var i = 0; i < objects.length; i++) {
    entries.add((oid: ids[i], offset: offset, crc: _crc(objects[i])));
    offset += objects[i].length;
  }
  entries.sort((a, b) => a.oid.compareTo(b.oid));
  final pack = _pack(objects);
  final index = [
    0xff,
    0x74,
    0x4f,
    0x63,
    ..._u32(2),
    for (var i = 0; i < 256; i++)
      ..._u32(
        entries
            .where(
              (entry) => int.parse(entry.oid.substring(0, 2), radix: 16) <= i,
            )
            .length,
      ),
    for (final entry in entries) ..._hex(entry.oid),
    for (final entry in entries) ..._u32(entry.crc),
    for (final entry in entries) ..._u32(entry.offset),
    ...pack.sublist(pack.length - 20),
  ];
  return (
    pack: pack,
    index: [...index, ...sha1.convert(index).bytes],
    root: root,
  );
}

List<int> _refChain(int depth) {
  List<int> bytes = ascii.encode('a');
  var oid = _oid('blob', bytes);
  final objects = <List<int>>[
    [..._objectHeader(3, bytes.length), ...zlib.encode(bytes)],
  ];
  for (var i = 0; i < depth; i++) {
    final delta = [
      ..._varint(bytes.length),
      ..._varint(bytes.length + 1),
      0x90,
      bytes.length,
      1,
      120,
    ];
    objects.add([
      ..._objectHeader(7, delta.length),
      ..._hex(oid),
      ...zlib.encode(delta),
    ]);
    bytes = [...bytes, 120];
    oid = _oid('blob', bytes);
  }
  return _pack(objects);
}
