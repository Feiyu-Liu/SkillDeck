import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/revision_content.dart';

const List<int> _hashDomain = <int>[
  0x73,
  0x6b,
  0x69,
  0x6c,
  0x6c,
  0x73,
  0x2d,
  0x77,
  0x6f,
  0x72,
  0x6b,
  0x73,
  0x70,
  0x61,
  0x63,
  0x65,
  0x2d,
  0x74,
  0x72,
  0x65,
  0x65,
  0x00,
  0x01,
];

/// Computes the framed, source-independent hash of an already normalized tree.
///
/// Keeping this utility above both source normalization and the native
/// Revision adapter prevents Store reads from inventing a second content-hash
/// format.
String computeNormalizedSkillTreeHash(List<NormalizedSkillFile> files) {
  final digestSink = _SingleDigestSink();
  final input = sha256.startChunkedConversion(digestSink);
  input.add(_hashDomain);
  _addUint64(input, files.length);
  for (final file in files) {
    _addFrame(input, utf8.encode(file.relativePath));
    input.add(<int>[file.isExecutable ? 1 : 0]);
    _addFrame(input, file.bytes);
  }
  input.close();
  return digestSink.value.toString();
}

void _addFrame(ByteConversionSink sink, List<int> bytes) {
  _addUint64(sink, bytes.length);
  sink.add(bytes);
}

void _addUint64(ByteConversionSink sink, int value) {
  final frame = ByteData(8)..setUint64(0, value, Endian.big);
  sink.add(frame.buffer.asUint8List());
}

final class _SingleDigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value => _digest ?? (throw StateError('Digest was not produced.'));

  @override
  void add(Digest data) => _digest = data;

  @override
  void close() {}
}
