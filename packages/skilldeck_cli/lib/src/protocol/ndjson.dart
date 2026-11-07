import 'dart:async';
import 'dart:convert';

import 'failure.dart';
import 'messages.dart';

const maximumCommandHostLineBytes = 1024 * 1024;

List<int> encodeLine(WireMessage message) {
  final bytes = utf8.encode(jsonEncode(message.toJson()));
  if (bytes.length > maximumCommandHostLineBytes) {
    throw const ClientFailure(ClientFailureCode.protocolViolation);
  }
  return [...bytes, 10];
}

/// Buffers at most one bounded UTF-8 line, even when the peer never sends LF.
final class CommandHostDecoder
    extends StreamTransformerBase<List<int>, Map<String, Object?>> {
  const CommandHostDecoder();

  @override
  Stream<Map<String, Object?>> bind(Stream<List<int>> stream) async* {
    var line = <int>[];
    await for (final chunk in stream) {
      for (final byte in chunk) {
        if (byte == 10) {
          final message = parseProtocol(() {
            final value = jsonDecode(utf8.decode(line));
            if (value is! Map<String, Object?>) throw const FormatException();
            return value;
          });
          line = <int>[];
          yield message;
        } else {
          if (line.length == maximumCommandHostLineBytes) {
            throw const ClientFailure(ClientFailureCode.protocolViolation);
          }
          line.add(byte);
        }
      }
    }
    if (line.isNotEmpty) {
      throw const ClientFailure(ClientFailureCode.protocolViolation);
    }
  }
}

bool secretsMatch(String a, String b) {
  final left = utf8.encode(a);
  final right = utf8.encode(b);
  var difference = left.length ^ right.length;
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    difference |=
        (i < left.length ? left[i] : 0) ^ (i < right.length ? right[i] : 0);
  }
  return difference == 0;
}
