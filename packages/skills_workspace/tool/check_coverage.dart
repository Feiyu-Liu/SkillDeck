import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: check_coverage <lcov-path> <minimum-percent>');
    exitCode = 64;
    return;
  }
  final minimum = double.tryParse(arguments[1]);
  if (minimum == null || minimum < 0 || minimum > 100) {
    stderr.writeln('minimum-percent must be between 0 and 100');
    exitCode = 64;
    return;
  }
  final file = File(arguments[0]);
  if (!await file.exists()) {
    stderr.writeln('LCOV file does not exist: ${file.path}');
    exitCode = 66;
    return;
  }

  var found = 0;
  var hit = 0;
  await for (final line
      in file
          .openRead()
          .transform(const SystemEncoding().decoder)
          .transform(const LineSplitter())) {
    if (line.startsWith('LF:')) {
      found += int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      hit += int.parse(line.substring(3));
    }
  }
  if (found == 0) {
    stderr.writeln('LCOV report contains no executable lines.');
    exitCode = 65;
    return;
  }
  final percentage = hit * 100 / found;
  stdout.writeln(
    'Package line coverage: ${percentage.toStringAsFixed(2)}% '
    '($hit/$found; minimum ${minimum.toStringAsFixed(2)}%)',
  );
  if (percentage < minimum) {
    exitCode = 1;
  }
}
