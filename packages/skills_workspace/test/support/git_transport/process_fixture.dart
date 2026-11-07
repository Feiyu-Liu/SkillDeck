import 'dart:io';

Future<void> main(List<String> arguments) async {
  switch (arguments.firstOrNull) {
    case '--print':
      stdout.write(Platform.environment['GIT_FIXTURE_VALUE'] ?? 'missing');
      stderr.write('diagnostic');
    case '--large-output':
      stdout.write(List.filled(1024, 'o').join());
      stderr.write(List.filled(1024, 'e').join());
    default:
      exitCode = 64;
  }
}
