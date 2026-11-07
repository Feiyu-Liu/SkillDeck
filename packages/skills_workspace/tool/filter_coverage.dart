import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln('usage: filter_coverage <input-lcov> <output-lcov>');
    exit(64);
  }
  final input = File(arguments[0]);
  final output = File(arguments[1]);
  if (!await input.exists()) {
    stderr.writeln('LCOV input does not exist: ${input.path}');
    exit(66);
  }

  final retained = StringBuffer();
  var record = <String>[];
  var retainedRecords = 0;
  var excludedRecords = 0;
  void flush() {
    if (record.isEmpty) return;
    String? source;
    for (final line in record) {
      if (line.startsWith('SF:')) {
        source = line.substring(3).replaceAll('\\', '/');
        break;
      }
    }
    if (source == null || _isGenerated(source)) {
      excludedRecords += 1;
    } else {
      retained.writeln(record.join('\n'));
      retainedRecords += 1;
    }
    record = <String>[];
  }

  await for (final line
      in input
          .openRead()
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
    record.add(line);
    if (line == 'end_of_record') flush();
  }
  flush();
  if (retainedRecords == 0) {
    stderr.writeln('Coverage filter retained no production source records.');
    exit(65);
  }
  await output.parent.create(recursive: true);
  await output.writeAsString(retained.toString(), flush: true);
  stdout.writeln(
    'Coverage records: retained=$retainedRecords '
    'generated-excluded=$excludedRecords',
  );
}

bool _isGenerated(String source) {
  final name = source.split('/').last;
  return name.endsWith('.g.dart') || source.contains('/generated/');
}
