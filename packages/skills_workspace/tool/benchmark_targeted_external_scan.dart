import 'dart:convert';
import 'dart:io';

import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/infrastructure/discovery/file_system_external_skill_location.dart';
import 'package:skills_workspace/src/infrastructure/source/local_source.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_runtime.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final worker = RevisionWorkerRuntime(
    taskExecutor: executeComposedRevisionWorkerTask,
  );
  await worker.start();
  final scanner = FileSystemExternalSkillLocation(
    localSource: LocalSourceAdapter(contentWorker: worker),
  );
  try {
    await _scan(scanner, options);
    final runs = <_Run>[];
    for (var index = 0; index < options.runs; index += 1) {
      final stopwatch = Stopwatch()..start();
      final skillCount = await _scan(scanner, options);
      stopwatch.stop();
      runs.add(_Run(elapsed: stopwatch.elapsed, skillCount: skillCount));
    }
    final micros = [for (final run in runs) run.elapsed.inMicroseconds]..sort();
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'schemaVersion': 1,
        'slotKey': options.slotKey,
        'locationCount': options.locations.length,
        'steadyStateRuns': options.runs,
        'medianMicros': micros[micros.length ~/ 2],
        'slowestMicros': micros.last,
        'runsMicros': [for (final run in runs) run.elapsed.inMicroseconds],
        'matchingOccurrences': runs.last.skillCount,
      }),
    );
  } finally {
    await worker.close();
  }
}

Future<int> _scan(
  FileSystemExternalSkillLocation scanner,
  _Options options,
) async {
  var skillCount = 0;
  for (final location in options.locations) {
    final result = await scanner.scanLocation(
      location: location,
      selectedSlotKeys: <String>{options.slotKey},
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );
    final skills = result.valueOrNull;
    if (skills == null) {
      _fail('Targeted External Skill scan failed.', 1);
    }
    skillCount += skills.length;
  }
  return skillCount;
}

final class _Run {
  const _Run({required this.elapsed, required this.skillCount});

  final Duration elapsed;
  final int skillCount;
}

final class _Options {
  const _Options({
    required this.locations,
    required this.slotKey,
    required this.runs,
  });

  final List<String> locations;
  final String slotKey;
  final int runs;

  static _Options parse(List<String> arguments) {
    final locations = <String>[];
    String? slotKey;
    var runs = 5;
    for (var index = 0; index < arguments.length; index += 1) {
      final name = arguments[index];
      if (index + 1 >= arguments.length) _usage();
      final value = arguments[++index];
      switch (name) {
        case '--location':
          locations.add(value);
        case '--slot':
          slotKey = value;
        case '--runs':
          runs = int.tryParse(value) ?? _usage();
        default:
          _usage();
      }
    }
    if (locations.isEmpty || slotKey == null || slotKey.isEmpty || runs < 1) {
      _usage();
    }
    return _Options(
      locations: List.unmodifiable(locations),
      slotKey: slotKey,
      runs: runs,
    );
  }

  static Never _usage() => _fail(
    'usage: dart run tool/benchmark_targeted_external_scan.dart '
    '--location <path> [--location <path>...] --slot <slot-key> '
    '[--runs <count>]',
    64,
  );
}

Never _fail(String message, int code) {
  stderr.writeln(message);
  exit(code);
}
