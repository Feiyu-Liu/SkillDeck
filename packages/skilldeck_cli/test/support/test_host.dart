import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';

/// A real local peer, independent of the App implementation.
final class TestHost {
  TestHost(
    this.runDirectory, {
    this.reject,
    this.silent = false,
    this.malformed = false,
  });
  final String runDirectory;
  final HostRejectCode? reject;
  final bool silent;
  final bool malformed;
  ServerSocket? listener;
  final Set<Socket> sockets = {};
  final secret = base64Url.encode(List.filled(32, 7));

  Future<void> start() async {
    await ensurePrivateDirectory(runDirectory);
    listener = Platform.isWindows
        ? await ServerSocket.bind(InternetAddress.loopbackIPv4, 0)
        : await ServerSocket.bind(
            InternetAddress(
              p.join(runDirectory, 'host.sock'),
              type: InternetAddressType.unix,
            ),
            0,
          );
    final discovery = CommandHostDiscovery(
      protocolVersion: 1,
      appVersion: '2.0.0',
      pid: pid,
      secret: secret,
      endpoint: Platform.isWindows
          ? CommandHostEndpoint.loopbackTcp(listener!.port)
          : CommandHostEndpoint.unixSocket(p.join(runDirectory, 'host.sock')),
    );
    await writePrivateFileAtomically(
      p.join(runDirectory, commandHostDiscoveryFileName),
      utf8.encode(jsonEncode(discovery.toJson())),
    );
    listener!.listen((socket) {
      sockets.add(socket);
      unawaited(serve(socket));
    });
  }

  Future<void> serve(Socket socket) async {
    final input = StreamIterator(
      socket.cast<List<int>>().transform(const CommandHostDecoder()),
    );
    try {
      if (!await input.moveNext()) return;
      final hello = ClientHello.fromJson(input.current);
      if (silent) {
        await input.moveNext();
        return;
      }
      if (malformed) {
        socket.add(utf8.encode('[]\n'));
        await socket.flush();
        return;
      }
      final rejection =
          reject ??
          (!secretsMatch(hello.secret, secret)
              ? HostRejectCode.unauthorized
              : hello.protocolVersion != 1
              ? HostRejectCode.protocolMismatch
              : null);
      socket.add(
        encodeLine(
          rejection == null
              ? const HostHello(protocolVersion: 1, appVersion: '2.0.0')
              : HostReject(rejection),
        ),
      );
      if (rejection != null) {
        await socket.flush();
        return;
      }
      if (!await input.moveNext()) return;
      final request = CommandRequest.fromJson(input.current);
      socket.add(
        encodeLine(
          CommandResult(
            ok: true,
            command: request.command,
            data: {
              'appVersion': '2.0.0',
              'protocolVersion': 1,
              'workspace': {
                'state': 'ready',
                'skillCount': 2,
                'projectRootCount': 1,
              },
            },
          ),
        ),
      );
      await socket.flush();
    } finally {
      socket.destroy();
      await input.cancel();
      sockets.remove(socket);
    }
  }

  Future<void> close() async {
    await listener?.close();
    for (final socket in sockets.toList()) {
      socket.destroy();
    }
  }
}
