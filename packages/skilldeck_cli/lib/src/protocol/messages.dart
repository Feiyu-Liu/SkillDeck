import 'failure.dart';

const commandHostProtocolVersion = 1;
const cliOutputSchemaVersion = 1;

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, _freeze(value))),
  ),
  List<Object?>() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
Map<String, Object?> _map(Map<String, Object?> value) =>
    _freeze(value) as Map<String, Object?>;

sealed class WireMessage {
  const WireMessage();
  Map<String, Object?> toJson();

  factory WireMessage.fromJson(Map<String, Object?> json) => parseProtocol(
    () => switch (json['type']) {
      'clientHello' => ClientHello.fromJson(json),
      'hostHello' => HostHello.fromJson(json),
      'hostReject' => HostReject.fromJson(json),
      'commandRequest' => CommandRequest.fromJson(json),
      'commandResult' => CommandResult.fromJson(json),
      'operationProgress' => OperationProgress.fromJson(json),
      _ => throw const ClientFailure(ClientFailureCode.protocolViolation),
    },
  );
}

final class ClientHello extends WireMessage {
  const ClientHello({
    required this.protocolVersion,
    required this.cliVersion,
    required this.secret,
  });
  final int protocolVersion;
  final String cliVersion;
  final String secret;
  factory ClientHello.fromJson(Map<String, Object?> json) => parseProtocol(() {
    if (json['type'] != 'clientHello') throw const FormatException();
    return ClientHello(
      protocolVersion: json['protocolVersion'] as int,
      cliVersion: json['cliVersion'] as String,
      secret: json['secret'] as String,
    );
  });
  @override
  Map<String, Object?> toJson() => {
    'type': 'clientHello',
    'protocolVersion': protocolVersion,
    'cliVersion': cliVersion,
    'secret': secret,
  };
}

final class HostHello extends WireMessage {
  const HostHello({required this.protocolVersion, required this.appVersion});
  final int protocolVersion;
  final String appVersion;
  factory HostHello.fromJson(Map<String, Object?> json) => parseProtocol(() {
    if (json['type'] != 'hostHello') throw const FormatException();
    return HostHello(
      protocolVersion: json['protocolVersion'] as int,
      appVersion: json['appVersion'] as String,
    );
  });
  @override
  Map<String, Object?> toJson() => {
    'type': 'hostHello',
    'protocolVersion': protocolVersion,
    'appVersion': appVersion,
  };
}

enum HostRejectCode { unauthorized, protocolMismatch }

final class HostReject extends WireMessage {
  const HostReject(this.code);
  final HostRejectCode code;
  factory HostReject.fromJson(Map<String, Object?> json) => parseProtocol(() {
    if (json['type'] != 'hostReject') throw const FormatException();
    return HostReject(HostRejectCode.values.byName(json['code'] as String));
  });
  @override
  Map<String, Object?> toJson() => {'type': 'hostReject', 'code': code.name};
}

final class CommandRequest extends WireMessage {
  CommandRequest({
    required this.command,
    Map<String, Object?> arguments = const {},
  }) : arguments = _map(arguments);
  final String command;
  final Map<String, Object?> arguments;
  factory CommandRequest.fromJson(Map<String, Object?> json) =>
      parseProtocol(() {
        if (json['type'] != 'commandRequest') throw const FormatException();
        return CommandRequest(
          command: json['command'] as String,
          arguments: json['arguments'] as Map<String, Object?>,
        );
      });
  @override
  Map<String, Object?> toJson() => {
    'type': 'commandRequest',
    'command': command,
    'arguments': arguments,
  };
}

final class CommandError {
  CommandError({
    required this.code,
    required this.message,
    Map<String, Object?> details = const {},
  }) : details = _map(details);
  final String code;
  final String message;
  final Map<String, Object?> details;
  factory CommandError.fromJson(Map<String, Object?> json) => parseProtocol(
    () => CommandError(
      code: json['code'] as String,
      message: json['message'] as String,
      details: json['details'] as Map<String, Object?>,
    ),
  );
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'details': details,
  };
}

final class CommandResult extends WireMessage {
  CommandResult({
    this.schemaVersion = cliOutputSchemaVersion,
    required this.ok,
    required this.command,
    List<Object?> results = const [],
    Map<String, Object?> data = const {},
    this.error,
  }) : results = _freeze(results) as List<Object?>,
       data = _map(data);
  factory CommandResult.failure(String command, String code, String message) =>
      CommandResult(
        ok: false,
        command: command,
        error: CommandError(code: code, message: message),
      );
  final int schemaVersion;
  final bool ok;
  final String command;
  final List<Object?> results;
  final Map<String, Object?> data;
  final CommandError? error;
  factory CommandResult.fromJson(Map<String, Object?> json) =>
      parseProtocol(() {
        if (json['type'] != 'commandResult' ||
            json['schemaVersion'] != cliOutputSchemaVersion) {
          throw const FormatException();
        }
        final result = CommandResult(
          schemaVersion: json['schemaVersion'] as int,
          ok: json['ok'] as bool,
          command: json['command'] as String,
          results: json['results'] as List<Object?>,
          data: json['data'] as Map<String, Object?>,
          error: json['error'] == null
              ? null
              : CommandError.fromJson(json['error'] as Map<String, Object?>),
        );
        if (result.ok != (result.error == null)) throw const FormatException();
        return result;
      });
  Map<String, Object?> toOutputJson() => {
    'schemaVersion': schemaVersion,
    'ok': ok,
    'command': command,
    'results': results,
    'data': data,
    'error': error?.toJson(),
  };
  @override
  Map<String, Object?> toJson() => {'type': 'commandResult', ...toOutputJson()};
}

final class OperationProgress extends WireMessage {
  OperationProgress({Map<String, Object?> data = const {}}) : data = _map(data);
  final Map<String, Object?> data;
  factory OperationProgress.fromJson(Map<String, Object?> json) =>
      parseProtocol(() {
        if (json['type'] != 'operationProgress') throw const FormatException();
        return OperationProgress(data: json['data'] as Map<String, Object?>);
      });
  @override
  Map<String, Object?> toJson() => {'type': 'operationProgress', 'data': data};
}
