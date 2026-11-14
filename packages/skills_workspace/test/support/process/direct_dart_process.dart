import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Builds raw-VM arguments without running another set of Native Assets hooks.
///
/// Dart 3.14 uses temporary native libraries for each dartdev invocation. A
/// later invocation can overwrite the package's shared native_assets.yaml and
/// delete its libraries before a crash-test child starts. Give children an
/// immutable package configuration pointing at their parent's live libraries.
List<String> directDartScriptArguments(
  String scriptPath, [
  Iterable<String> arguments = const <String>[],
]) => <String>[
  '--disable-dart-dev',
  '--packages=${_helperPackageConfig.path}',
  scriptPath,
  ...arguments,
];

final File _helperPackageConfig = _createHelperPackageConfig();

File _createHelperPackageConfig() {
  final packageConfig = File(
    path.join(Directory.current.path, '.dart_tool', 'package_config.json'),
  ).absolute;
  if (!packageConfig.existsSync()) {
    throw StateError('The test package configuration is missing.');
  }
  const prefix = '--delete_temp_dir_on_shutdown=';
  final nativeRootArguments = Platform.executableArguments.where(
    (argument) => argument.startsWith(prefix),
  );
  if (nativeRootArguments.isEmpty) return packageConfig;
  final nativeRoot = Directory(
    nativeRootArguments.first.substring(prefix.length),
  );
  final assets = File(
    path.join(packageConfig.parent.path, 'native_assets.yaml'),
  );
  if (!assets.existsSync()) return packageConfig;
  final mapping =
      jsonDecode(
            assets
                .readAsLinesSync()
                .where((line) => !line.startsWith('#'))
                .join('\n'),
          )
          as Map<String, Object?>;
  final targets = mapping['native-assets'] as Map<String, Object?>;
  for (final value in targets.values) {
    final entries = value as Map<String, Object?>;
    for (final asset in entries.values) {
      final location = asset as List<Object?>;
      if (location.length != 2 || location[0] != 'absolute') continue;
      final library = File(
        path.join(
          nativeRoot.path,
          'lib',
          path.basename(location[1]! as String),
        ),
      );
      if (!library.existsSync()) {
        throw StateError(
          'The parent Native Asset required by a test helper is missing.',
        );
      }
      location[1] = library.absolute.path;
    }
  }
  final config =
      jsonDecode(packageConfig.readAsStringSync()) as Map<String, Object?>;
  for (final entry in config['packages']! as List<Object?>) {
    final package = entry! as Map<String, Object?>;
    package['rootUri'] = packageConfig.uri
        .resolve(package['rootUri']! as String)
        .toString();
  }
  final runtime = Directory(
    path.join(packageConfig.parent.path, 'test-helpers'),
  )..createSync(recursive: true);
  final directory = runtime.createTempSync('runtime-');
  File(
    path.join(directory.path, 'native_assets.yaml'),
  ).writeAsStringSync(jsonEncode(mapping));
  return File(path.join(directory.path, 'package_config.json'))
    ..writeAsStringSync(jsonEncode(config));
}
