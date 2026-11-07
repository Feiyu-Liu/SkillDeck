import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('usage: reset_coverage <coverage-directory>');
    exitCode = 64;
    return;
  }
  final directory = Directory(arguments.single);
  if (await directory.exists()) {
    await directory.delete(recursive: true);
  }
}
