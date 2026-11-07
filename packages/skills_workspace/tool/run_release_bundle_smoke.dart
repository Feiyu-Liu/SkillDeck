import 'dart:async';
import 'dart:io';

import 'release_bundle_smoke.dart';

Future<void> main(List<String> arguments) async {
  final ReleaseBundleSmokeOptions options;
  try {
    options = ReleaseBundleSmokeOptions.parse(arguments);
  } on FormatException catch (error) {
    _fail('${error.message}\n${_usage()}', 64);
  }
  final bundle = Directory(options.bundlePath).absolute;
  final executable = releaseBundleExecutable(bundle, _hostPlatform());
  if (!await executable.exists()) {
    _fail('Release executable does not exist: ${executable.path}', 66);
  }

  final process = await Process.start(
    executable.path,
    const <String>[],
    environment: <String, String>{
      ...Platform.environment,
      'SKILLS_WORKSPACE_RELEASE_SMOKE': '1',
    },
  );
  final stdoutFuture = process.stdout.transform(systemEncoding.decoder).join();
  final stderrFuture = process.stderr.transform(systemEncoding.decoder).join();
  final exitCode = await process.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      process.kill();
      return 124;
    },
  );
  final output = await stdoutFuture;
  final diagnostic = await stderrFuture;
  try {
    validateReleaseBundleSmokeResult(
      exitCode: exitCode,
      output: output,
      diagnostic: diagnostic,
    );
  } on StateError catch (error) {
    _fail(error.message, exitCode == 0 ? 1 : exitCode);
  }
  stdout.writeln(expectedReleaseBundleSmokeOutput);
}

ReleaseBundlePlatform _hostPlatform() {
  if (Platform.isMacOS) {
    return ReleaseBundlePlatform.macOS;
  }
  if (Platform.isWindows) {
    return ReleaseBundlePlatform.windows;
  }
  if (Platform.isLinux) {
    return ReleaseBundlePlatform.linux;
  }
  throw UnsupportedError('Release smoke supports desktop hosts only.');
}

String _usage() =>
    'usage: dart run tool/run_release_bundle_smoke.dart --bundle <path>';

Never _fail(String message, int code) {
  stderr.writeln(message);
  exit(code);
}
