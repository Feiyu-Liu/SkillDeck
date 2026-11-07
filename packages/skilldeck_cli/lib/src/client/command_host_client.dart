import 'dart:async';
import 'dart:io';

import '../../skilldeck_protocol.dart';
import '../cli/version.dart';

/// A handshaken connection. Availability retries never send a command.
abstract interface class CommandHostConnection {
  Future<CommandResult> execute(CommandRequest request);
  Future<void> close();
}

final class CommandHostClient {
  const CommandHostClient({
    required this.runDirectory,
    this.connectTimeout = const Duration(seconds: 5),
    this.handshakeTimeout = const Duration(seconds: 5),
  });
  final String runDirectory;
  final Duration connectTimeout;
  final Duration handshakeTimeout;

  Future<CommandResult> execute(CommandRequest request) async {
    final connection = await connect();
    try {
      return await connection.execute(request);
    } finally {
      await connection.close();
    }
  }

  /// [timeout] caps discovery, connection and handshake together, with cleanup.
  Future<CommandHostConnection> connect({Duration? timeout}) async {
    Socket? socket;
    StreamIterator<Map<String, Object?>>? messages;
    final elapsed = Stopwatch()..start();
    Duration budget(Duration normal) {
      if (timeout == null) return normal;
      final remaining = timeout - elapsed.elapsed;
      if (remaining <= Duration.zero) throw TimeoutException('');
      return remaining < normal ? remaining : normal;
    }

    try {
      final discovery = await readDiscovery(runDirectory)
          .timeout(budget(connectTimeout));
      if (discovery.protocolVersion != commandHostProtocolVersion) {
        throw const ClientFailure(ClientFailureCode.protocolMismatch);
      }
      final (address, port) = switch (discovery.endpoint) {
        UnixSocketEndpoint(:final path) => (
          InternetAddress(path, type: InternetAddressType.unix),
          0,
        ),
        LoopbackTcpEndpoint(:final port) => (
          InternetAddress.loopbackIPv4,
          port,
        ),
      };
      final connecting = await Socket.startConnect(address, port);
      try {
        socket = await connecting.socket.timeout(budget(connectTimeout));
      } on Object {
        connecting.cancel();
        rethrow;
      }
      messages = StreamIterator(
        socket.cast<List<int>>().transform(const CommandHostDecoder()),
      );
      socket.add(
        encodeLine(
          ClientHello(
            protocolVersion: commandHostProtocolVersion,
            cliVersion: cliVersion,
            secret: discovery.secret,
          ),
        ),
      );
      final hello = await _next(messages).timeout(budget(handshakeTimeout));
      switch (hello) {
        case HostReject(:final code):
          throw ClientFailure(switch (code) {
            HostRejectCode.unauthorized => ClientFailureCode.unauthorized,
            HostRejectCode.protocolMismatch =>
              ClientFailureCode.protocolMismatch,
          });
        case HostHello(:final protocolVersion):
          if (protocolVersion != commandHostProtocolVersion) {
            throw const ClientFailure(ClientFailureCode.protocolMismatch);
          }
        default:
          throw const ClientFailure(ClientFailureCode.protocolViolation);
      }
      return _SocketConnection(socket, messages, handshakeTimeout);
    } on Object catch (error) {
      socket?.destroy();
      await messages?.cancel();
      throw _failure(error);
    }
  }
}

final class _SocketConnection implements CommandHostConnection {
  _SocketConnection(this.socket, this.messages, this.responseTimeout);
  final Socket socket;
  final StreamIterator<Map<String, Object?>> messages;
  final Duration responseTimeout;
  Future<void>? _closing;

  @override
  Future<CommandResult> execute(CommandRequest request) async {
    try {
      socket.add(encodeLine(request));
      WireMessage result;
      do {
        // The handshake timeout is not a write-operation deadline. EOF/SIGINT
        // closes the connection; long operations can legitimately exceed it.
        result = ['status', 'agents', 'list', 'show'].contains(request.command)
            ? await _next(messages).timeout(responseTimeout)
            : await _next(messages);
      } while (result is OperationProgress);
      if (result is! CommandResult || result.command != request.command) {
        throw const ClientFailure(ClientFailureCode.protocolViolation);
      }
      return result;
    } on Object catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    socket.destroy();
    await messages.cancel();
  }
}

ClientFailure _failure(Object error) => switch (error) {
  ClientFailure() => error,
  TimeoutException() => const ClientFailure(ClientFailureCode.timeout),
  IOException() => const ClientFailure(ClientFailureCode.appUnavailable),
  _ => const ClientFailure(ClientFailureCode.protocolViolation),
};

Future<WireMessage> _next(StreamIterator<Map<String, Object?>> messages) async {
  if (!await messages.moveNext()) {
    throw const ClientFailure(ClientFailureCode.protocolViolation);
  }
  return WireMessage.fromJson(messages.current);
}
