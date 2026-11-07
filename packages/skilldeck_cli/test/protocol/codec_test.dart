import 'dart:convert';

import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:test/test.dart';

void main() {
  test('every message round trips through fragmented NDJSON', () async {
    final messages = <WireMessage>[
      const ClientHello(
        protocolVersion: 1,
        cliVersion: '0.1.0',
        secret: 'test',
      ),
      const HostHello(protocolVersion: 1, appVersion: '1.0.0'),
      const HostReject(HostRejectCode.unauthorized),
      const HostReject(HostRejectCode.protocolMismatch),
      CommandRequest(command: 'status', arguments: {'unicode': '技能'}),
      CommandResult(
        ok: true,
        command: 'status',
        data: {
          'nested': [1],
        },
      ),
      CommandResult.failure('status', 'internalError', 'Failed.'),
      OperationProgress(data: {'state': 'reserved'}),
    ];
    final bytes = messages.expand(encodeLine).toList();
    final decoded = await Stream.fromIterable(bytes.map((b) => [b]))
        .transform(const CommandHostDecoder())
        .toList();
    expect(
      decoded.map((j) => WireMessage.fromJson(j).toJson()).toList(),
      messages.map((m) => m.toJson()).toList(),
    );
  });
  for (final invalid in ['{bad}\n', '[]\n', 'null\n', '{}', '\n']) {
    test('rejects malformed or unterminated input $invalid', () async {
      await expectLater(
        Stream<List<int>>.value(utf8.encode(invalid))
            .transform(const CommandHostDecoder())
            .toList(),
        throwsA(
          isA<ClientFailure>().having(
            (e) => e.code,
            'code',
            ClientFailureCode.protocolViolation,
          ),
        ),
      );
    });
  }
  test('rejects malformed UTF-8', () async {
    await expectLater(
      Stream.value([255, 10]).transform(const CommandHostDecoder()).toList(),
      throwsA(isA<ClientFailure>()),
    );
  });
  test('rejects oversized line before LF and across chunks', () async {
    await expectLater(
      Stream.fromIterable([
        List.filled(maximumCommandHostLineBytes, 32),
        [32],
      ]).transform(const CommandHostDecoder()).toList(),
      throwsA(isA<ClientFailure>()),
    );
    expect(
      () => encodeLine(
        CommandRequest(
          command: 'x',
          arguments: {'text': 'x' * maximumCommandHostLineBytes},
        ),
      ),
      throwsA(isA<ClientFailure>()),
    );
  });
  test('accepts a line at exactly the limit', () async {
    final bytes = utf8.encode(
      '{"x":"${'a' * (maximumCommandHostLineBytes - 8)}"}\n',
    );
    expect(bytes.length, maximumCommandHostLineBytes + 1);
    expect(
      await Stream<List<int>>.value(bytes)
          .transform(const CommandHostDecoder())
          .length,
      1,
    );
  });
  test('typed parsing rejects wrong field types and unknown messages', () {
    for (final json in <Map<String, Object?>>[
      {'type': 'other'},
      {'type': 'hostHello', 'protocolVersion': '1'},
      {'type': 'hostReject', 'code': 'other'},
      {'type': 'commandRequest', 'command': 'status', 'arguments': []},
    ]) {
      expect(() => WireMessage.fromJson(json), throwsA(isA<ClientFailure>()));
    }
  });
  test('messages defensively freeze nested input', () {
    final nested = [1];
    final request = CommandRequest(
      command: 'status',
      arguments: {'nested': nested},
    );
    nested.add(2);
    expect(request.arguments['nested'], [1]);
    expect(
      () => (request.arguments['nested'] as List).add(3),
      throwsUnsupportedError,
    );
  });
  test('secrets compare contents and lengths', () {
    expect(secretsMatch('abc', 'abc'), isTrue);
    expect(secretsMatch('abc', 'abd'), isFalse);
    expect(secretsMatch('abc', 'abc '), isFalse);
    expect(secretsMatch('abc', ''), isFalse);
  });
}
