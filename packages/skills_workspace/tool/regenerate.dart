import 'dart:io';

Future<void> main() async {
  const commands = <(String, List<String>)>[
    ('dart', <String>['run', 'build_runner', 'build']),
    (
      'dart',
      <String>[
        'run',
        'drift_dev',
        'schema',
        'dump',
        'lib/src/infrastructure/database/workspace_database.dart',
        'drift_schemas/drift_schema_v3.json',
      ],
    ),
    (
      'dart',
      <String>[
        'run',
        'drift_dev',
        'schema',
        'generate',
        'drift_schemas',
        'test/infrastructure/database/generated',
      ],
    ),
    ('dart', <String>['run', 'ffigen', '--config', 'ffigen.yaml']),
  ];

  for (final (executable, arguments) in commands) {
    stdout.writeln('> $executable ${arguments.join(' ')}');
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.inheritStdio,
    );
    final result = await process.exitCode;
    if (result != 0) {
      stderr.writeln('Generation failed with exit code $result.');
      exit(result);
    }
  }
}
