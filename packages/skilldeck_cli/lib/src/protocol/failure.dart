enum ClientFailureCode {
  appUnavailable,
  appNotInstalled,
  appLaunchTimeout,
  protocolMismatch,
  unauthorized,
  insecureDiscovery,
  protocolViolation,
  timeout,
  missingHome,
}

final class ClientFailure implements Exception {
  const ClientFailure(this.code);
  final ClientFailureCode code;

  String get message => switch (code) {
    ClientFailureCode.appUnavailable => 'Open SkillDeck and try again.',
    ClientFailureCode.appNotInstalled =>
      'Install SkillDeck and open it once, then try again.',
    ClientFailureCode.appLaunchTimeout =>
      'SkillDeck did not start in time. Open SkillDeck and try again.',
    ClientFailureCode.protocolMismatch =>
      'Update SkillDeck and the CLI to compatible versions.',
    ClientFailureCode.unauthorized => 'Command Host authentication failed.',
    ClientFailureCode.insecureDiscovery =>
      'Command Host discovery is not private.',
    ClientFailureCode.protocolViolation => 'Invalid Command Host response.',
    ClientFailureCode.timeout => 'The Command Host did not answer in time.',
    ClientFailureCode.missingHome => 'The user home directory is unavailable.',
  };

  @override
  String toString() => 'ClientFailure(${code.name})';
}

T parseProtocol<T>(T Function() parse) {
  try {
    return parse();
  } on Object {
    throw const ClientFailure(ClientFailureCode.protocolViolation);
  }
}
