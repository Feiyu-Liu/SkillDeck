import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'failure.dart';

const commandHostDiscoveryFileName = 'command-host.json';
const commandHostSocketFileName = 'host.sock';

String commandHostRunDirectory({
  required Map<String, String> environment,
  required bool isWindows,
}) {
  final home = environment[isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null || home.trim().isEmpty) {
    throw const ClientFailure(ClientFailureCode.missingHome);
  }
  final context = p.Context(style: isWindows ? p.Style.windows : p.Style.posix);
  return context.join(home, '.skilldeck', 'run');
}

sealed class CommandHostEndpoint {
  const CommandHostEndpoint();
  const factory CommandHostEndpoint.unixSocket(String path) =
      UnixSocketEndpoint;
  const factory CommandHostEndpoint.loopbackTcp(int port) = LoopbackTcpEndpoint;
  Map<String, Object?> toJson();
  factory CommandHostEndpoint.fromJson(Map<String, Object?> json) =>
      parseProtocol(() {
        switch (json['type']) {
          case 'unixSocket':
            final path = json['path'] as String;
            if (path.isEmpty) throw const FormatException();
            return UnixSocketEndpoint(path);
          case 'loopbackTcp':
            final port = json['port'] as int;
            if (port < 1 || port > 65535) throw const FormatException();
            return LoopbackTcpEndpoint(port);
          default:
            throw const FormatException();
        }
      });
}

final class UnixSocketEndpoint extends CommandHostEndpoint {
  const UnixSocketEndpoint(this.path);
  final String path;
  @override
  Map<String, Object?> toJson() => {'type': 'unixSocket', 'path': path};
}

final class LoopbackTcpEndpoint extends CommandHostEndpoint {
  const LoopbackTcpEndpoint(this.port);
  final int port;
  @override
  Map<String, Object?> toJson() => {'type': 'loopbackTcp', 'port': port};
}

final class CommandHostDiscovery {
  const CommandHostDiscovery({
    required this.protocolVersion,
    required this.appVersion,
    required this.pid,
    required this.endpoint,
    required this.secret,
  });
  final int protocolVersion;
  final String appVersion;
  final int pid;
  final CommandHostEndpoint endpoint;
  final String secret;
  factory CommandHostDiscovery.fromJson(Map<String, Object?> json) =>
      parseProtocol(() {
        final secret = json['secret'] as String;
        if (base64Url.decode(base64Url.normalize(secret)).length != 32) {
          throw const FormatException();
        }
        return CommandHostDiscovery(
          protocolVersion: json['protocolVersion'] as int,
          appVersion: json['appVersion'] as String,
          pid: json['pid'] as int,
          endpoint: CommandHostEndpoint.fromJson(
            json['endpoint'] as Map<String, Object?>,
          ),
          secret: secret,
        );
      });
  Map<String, Object?> toJson() => {
    'protocolVersion': protocolVersion,
    'appVersion': appVersion,
    'pid': pid,
    'endpoint': endpoint.toJson(),
    'secret': secret,
  };
}

Future<CommandHostDiscovery> readDiscovery(String runDirectory) async {
  final file = File(p.join(runDirectory, commandHostDiscoveryFileName));
  try {
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const ClientFailure(ClientFailureCode.appUnavailable);
    }
    final stat = await file.stat();
    if (!Platform.isWindows && stat.mode & 63 != 0) {
      throw const ClientFailure(ClientFailureCode.insecureDiscovery);
    }
    // Bound discovery too; it contains only a small endpoint and credentials.
    if (stat.size > 1024 * 1024) {
      throw const ClientFailure(ClientFailureCode.protocolViolation);
    }
    final content = await file.readAsString();
    return parseProtocol<CommandHostDiscovery>(
      () => CommandHostDiscovery.fromJson(
        jsonDecode(content) as Map<String, Object?>,
      ),
    );
  } on FileSystemException {
    throw const ClientFailure(ClientFailureCode.appUnavailable);
  }
}
