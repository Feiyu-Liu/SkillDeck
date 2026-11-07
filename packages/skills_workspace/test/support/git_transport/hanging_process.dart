import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    exitCode = 64;
    return;
  }

  final mode = arguments[0];
  final heartbeatPath = arguments[1];
  final pidDirectory = arguments[2];
  final modeName = mode.startsWith('--') ? mode.substring(2) : mode;
  File('$pidDirectory/$modeName.pid').writeAsStringSync('$pid');
  if (mode == '--child') {
    final heartbeat = File(heartbeatPath);
    while (true) {
      heartbeat.writeAsStringSync(
        DateTime.now().microsecondsSinceEpoch.toString(),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  if (mode != '--parent' && mode != '--middle') {
    exitCode = 64;
    return;
  }

  final childMode = mode == '--parent' ? '--middle' : '--child';
  final child = await Process.start(Platform.resolvedExecutable, [
    '--disable-dart-dev',
    Platform.script.toFilePath(),
    childMode,
    heartbeatPath,
    pidDirectory,
  ], runInShell: false);
  await child.exitCode;
}
