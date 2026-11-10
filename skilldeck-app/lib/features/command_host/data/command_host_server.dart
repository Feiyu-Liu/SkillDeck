import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import 'command_host_dispatcher.dart';
import 'command_cancellation.dart';

enum CommandHostStartFailureCode { alreadyRunning, startFailed }

final class CommandHostStartFailure implements Exception {
  const CommandHostStartFailure(this.code);
  final CommandHostStartFailureCode code;
}

final class CommandHostServer {
  CommandHostServer({
    required this.runDirectory,
    required this.isWindows,
    required this.appVersion,
    required this.dispatcher,
    required this.diagnostics,
    this.executablePath,
    this.bundleIdentifier,
    this.handshakeTimeout = const Duration(seconds: 5),
  });
  final String runDirectory;
  final bool isWindows;
  final Future<String> Function() appVersion;
  final CommandHostDispatcher dispatcher;
  final AppDiagnostics diagnostics;
  final Duration handshakeTimeout;
  final String? executablePath;
  final String? bundleIdentifier;
  final Set<Socket> _connections = {};
  final Map<Socket, CommandCancellation> _commands = {};
  final Set<Future<void>> _serving = {};
  ServerSocket? _listener;
  Future<void>? _starting;
  Future<void>? _stopping;
  bool _ownsSocket = false;
  bool _ownsDiscovery = false;
  String? _secret;
  String? _version;

  String get _socketPath => p.join(runDirectory, commandHostSocketFileName);
  String get _discoveryPath =>
      p.join(runDirectory, commandHostDiscoveryFileName);

  Future<void> start() {
    if (_stopping != null) {
      return Future.error(
        const CommandHostStartFailure(CommandHostStartFailureCode.startFailed),
      );
    }
    return _starting ??= _start();
  }

  Future<void> _start() async {
    try {
      await ensurePrivateDirectory(runDirectory);
      if (!isWindows) await _removeStaleSocket();
      _listener = isWindows
          ? await ServerSocket.bind(InternetAddress.loopbackIPv4, 0)
          : await ServerSocket.bind(
              InternetAddress(_socketPath, type: InternetAddressType.unix),
              0,
            );
      _ownsSocket = !isWindows;
      _version = await appVersion();
      final random = Random.secure();
      _secret = base64Url.encode(List.generate(32, (_) => random.nextInt(256)));
      final discovery = CommandHostDiscovery(
        protocolVersion: commandHostProtocolVersion,
        appVersion: _version!,
        pid: pid,
        secret: _secret!,
        endpoint: isWindows
            ? CommandHostEndpoint.loopbackTcp(_listener!.port)
            : CommandHostEndpoint.unixSocket(_socketPath),
      );
      await writePrivateFileAtomically(
        _discoveryPath,
        utf8.encode(jsonEncode(discovery.toJson())),
      );
      _ownsDiscovery = true;
      // Durable launch hint: cleanup removes endpoint files, never this file.
      await writePrivateFileAtomically(
        p.join(runDirectory, appLocationFileName),
        utf8.encode(
          jsonEncode(
            AppLocation(
              executablePath: executablePath ?? Platform.resolvedExecutable,
              bundleIdentifier: bundleIdentifier,
              appVersion: _version!,
            ).toJson(),
          ),
        ),
      );
      _listener!.listen(
        (socket) {
          _connections.add(socket);
          final serving = _serve(socket);
          _serving.add(serving);
          unawaited(serving.whenComplete(() => _serving.remove(serving)));
        },
        onError: (Object _) {
          diagnostics.info(
            'commandHost.rejected',
            context: {'code': 'transportError'},
          );
        },
      );
      diagnostics.info('commandHost.started');
    } on Object catch (error) {
      await _cleanup();
      final failure = error is CommandHostStartFailure
          ? error
          : const CommandHostStartFailure(
              CommandHostStartFailureCode.startFailed,
            );
      diagnostics.info(
        'commandHost.rejected',
        context: {'code': failure.code.name},
      );
      throw failure;
    }
  }

  Future<void> _removeStaleSocket() async {
    if (await FileSystemEntity.type(_socketPath, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return;
    }
    Socket? probe;
    try {
      probe = await Socket.connect(
        InternetAddress(_socketPath, type: InternetAddressType.unix),
        0,
        timeout: handshakeTimeout,
      );
    } on SocketException catch (error) {
      // Only a refused/missing endpoint proves staleness. Permission errors
      // and timeouts must never delete another live host's socket.
      if (error.osError?.errorCode != 61 &&
          error.osError?.errorCode != 111 &&
          error.osError?.errorCode != 2) {
        throw const CommandHostStartFailure(
          CommandHostStartFailureCode.startFailed,
        );
      }
      await File(_socketPath).delete();
      return;
    } on TimeoutException {
      throw const CommandHostStartFailure(
        CommandHostStartFailureCode.alreadyRunning,
      );
    } finally {
      probe?.destroy();
    }
    throw const CommandHostStartFailure(
      CommandHostStartFailureCode.alreadyRunning,
    );
  }

  Future<void> _serve(Socket socket) async {
    final messages = StreamIterator(
      socket.cast<List<int>>().transform(const CommandHostDecoder()),
    );
    try {
      final hello = await _next(messages).timeout(handshakeTimeout);
      if (hello is! ClientHello) {
        throw const ClientFailure(ClientFailureCode.protocolViolation);
      }
      final rejection = !secretsMatch(hello.secret, _secret!)
          ? HostRejectCode.unauthorized
          : hello.protocolVersion != commandHostProtocolVersion
          ? HostRejectCode.protocolMismatch
          : null;
      if (rejection != null) {
        socket.add(encodeLine(HostReject(rejection)));
        await socket.flush();
        diagnostics.info(
          'commandHost.rejected',
          context: {'code': rejection.name},
        );
        return;
      }
      socket.add(
        encodeLine(
          HostHello(
            protocolVersion: commandHostProtocolVersion,
            appVersion: _version!,
          ),
        ),
      );
      final request = await _next(messages).timeout(handshakeTimeout);
      if (request is! CommandRequest) {
        throw const ClientFailure(ClientFailureCode.protocolViolation);
      }
      late final CommandCancellation cancellation;
      cancellation = CommandCancellation(
        onProgress: (progress) {
          if (cancellation.isCancelled) return;
          try {
            socket.add(
              encodeLine(
                OperationProgress(
                  data: {
                    'operationId': progress.operationId,
                    'kind': progress.kind.name,
                    'phase': progress.phase.name,
                    'completed': progress.completed,
                    if (progress.total != null) 'total': progress.total,
                  },
                ),
              ),
            );
          } on Object {
            unawaited(cancellation.cancel().catchError((Object _) {}));
          }
        },
      );
      _commands[socket] = cancellation;
      // Continue reading while the handler runs, so EOF cancels in-flight work.
      unawaited(() async {
        try {
          await messages.moveNext();
        } on Object {
          // Malformed trailing input also closes this one-command connection.
        }
        try {
          await cancellation.cancel();
        } on Object {
          // A broken task cancellation must not leak an unhandled error.
        }
      }());
      final result = await dispatcher.dispatch(
        request,
        cancellation: cancellation,
      );
      if (!cancellation.isCancelled) {
        socket.add(encodeLine(result));
        await socket.flush();
      }
      diagnostics.info(
        'commandHost.command',
        context: {
          // Unknown names are untrusted input and can contain locators/content.
          'command': dispatcher.recognizes(request.command)
              ? request.command
              : 'unknown',
          'outcome': result.ok ? 'success' : 'failed',
          for (final outcome in [
            'succeeded',
            'unchanged',
            'committedFinalizationPending',
            'failed',
            'notAttempted',
            'cancelled',
            'wouldSucceed',
          ])
            outcome: result.results
                .whereType<Map>()
                .where((item) => item['outcome'] == outcome)
                .length,
        },
      );
    } on Object {
      diagnostics.info(
        'commandHost.rejected',
        context: {'code': 'protocolViolation'},
      );
    } finally {
      _commands.remove(socket);
      socket.destroy();
      await messages.cancel();
      _connections.remove(socket);
    }
  }

  Future<WireMessage> _next(
    StreamIterator<Map<String, Object?>> messages,
  ) async {
    if (!await messages.moveNext()) {
      throw const ClientFailure(ClientFailureCode.protocolViolation);
    }
    return WireMessage.fromJson(messages.current);
  }

  Future<void> stop() => _stopping ??= _stop();
  Future<void> _stop() async {
    try {
      await _starting;
    } on Object {
      // A failed start has already released only the resources it acquired.
    }
    await _cleanup();
    diagnostics.info('commandHost.stopped');
  }

  Future<void> _cleanup() async {
    await _listener?.close();
    _listener = null;
    for (final socket in _connections.toList()) {
      await _commands[socket]?.cancel();
      socket.destroy();
    }
    await Future.wait(_serving.toList());
    if (_ownsDiscovery) {
      await _deleteIfPresent(_discoveryPath);
      _ownsDiscovery = false;
    }
    if (_ownsSocket) {
      await _deleteIfPresent(_socketPath);
      _ownsSocket = false;
    }
    _secret = null;
  }

  Future<void> _deleteIfPresent(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        rethrow;
      }
    }
  }
}
