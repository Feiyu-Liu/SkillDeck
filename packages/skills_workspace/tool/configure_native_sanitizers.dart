import 'dart:io';

import 'native_build_policy.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) _usage();
  final NativeSanitizerConfiguration configuration;
  try {
    configuration = NativeSanitizerConfiguration.parse(arguments.single);
  } on ArgumentError {
    _usage();
  }
  await _write(configuration.serialized);
}

Future<void> _write(String value) async {
  final packageRoot = File.fromUri(Platform.script).parent.parent;
  final configuration = File(
    '${packageRoot.path}${Platform.pathSeparator}native'
    '${Platform.pathSeparator}sanitizers.config',
  );
  await configuration.writeAsString('$value\n', flush: true);
  stdout.writeln('Native sanitizer configuration: $value');
}

Never _usage() {
  stderr.writeln(
    'usage: dart run tool/configure_native_sanitizers.dart '
    '<none|address[,undefined]>',
  );
  exit(64);
}
