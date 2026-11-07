import 'dart:io';

import 'package:path/path.dart' as path;

/// Builds raw-VM arguments for a test helper without entering dartdev.
///
/// A helper started through dartdev may run Native Assets hooks and replace a
/// shared `.dart_tool/lib` artifact while its parent is resolving FFI symbols.
List<String> directDartScriptArguments(
  String scriptPath, [
  Iterable<String> arguments = const <String>[],
]) {
  final packageConfig = File(
    path.join(Directory.current.path, '.dart_tool', 'package_config.json'),
  ).absolute;
  if (!packageConfig.existsSync()) {
    throw StateError('The test package configuration is missing.');
  }
  return <String>[
    '--disable-dart-dev',
    '--packages=${packageConfig.path}',
    scriptPath,
    ...arguments,
  ];
}
