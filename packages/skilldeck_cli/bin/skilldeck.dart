import 'dart:io';

import 'package:skilldeck_cli/src/cli/runner.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runSkilldeck(
    arguments,
    environment: Platform.environment,
    isWindows: Platform.isWindows,
    out: stdout,
    err: stderr,
  );
  if (exitCode == 130) {
    await stdout.flush();
    await stderr.flush();
    // Do not keep a cancelled process alive for an outstanding launch/handshake.
    exit(130);
  }
}
