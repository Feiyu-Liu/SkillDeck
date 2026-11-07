import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/composition/materialization_inspection_worker_pool.dart';
import 'package:skills_workspace/src/composition/revision_worker_task_executor.dart';
import 'package:skills_workspace/src/composition/workspace_materialization_reconciler.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'package:skills_workspace/src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'package:skills_workspace/src/infrastructure/database/workspace_database.dart';
import 'package:skills_workspace/src/infrastructure/workspace_layout.dart';
import 'package:skills_workspace/src/native/revision_worker/revision_worker_runtime.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  final workspaceRoot = Directory(options.workspacePath).absolute;
  final databaseFile = File(path.join(workspaceRoot.path, 'workspace.sqlite'));
  if (!await databaseFile.exists()) {
    _fail('Workspace database does not exist.', 66);
  }

  final inspectionRuns = await _measureInspection(
    workspaceRoot.path,
    options.runs,
  );
  final openRuns = await _measureOpen(workspaceRoot.path, options.runs);
  final report = <String, Object>{
    'schemaVersion': 1,
    'workspacePath': workspaceRoot.path,
    'steadyStateRuns': options.runs,
    'inspection': _summarizeInspection(inspectionRuns),
    'open': _summarizeDurations(openRuns),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
}

Future<List<_InspectionRun>> _measureInspection(
  String workspacePath,
  int runs,
) async {
  final layout = WorkspaceLayout(workspacePath);
  final database = WorkspaceDatabase.forFile(File(layout.databasePath));
  final worker = RevisionWorkerRuntime(
    taskExecutor: executeComposedRevisionWorkerTask,
  );
  final inspectionWorkers = MaterializationInspectionWorkerPool();
  await Future.wait(<Future<void>>[worker.start(), inspectionWorkers.start()]);
  final reconciler = DriftWorkspaceMaterializationReconciler(
    database: database,
    layout: layout,
    revisionEngine: worker,
    filesystem: PlatformDurableWorkspaceFilesystem(),
    artifactInspector: FileSystemPublishedArtifactInspector(
      metadataObserver: const FileSystemPublishedArtifactMetadataObserver(),
      contentWorker: inspectionWorkers,
    ),
    accessGate: ManagedSkillRevisionAccessGate(),
  );
  try {
    await reconciler.reconcileMaterializations(isolatedSkillIds: const {});
    final results = <_InspectionRun>[];
    for (var index = 0; index < runs; index += 1) {
      final stopwatch = Stopwatch()..start();
      final report = await reconciler.reconcileMaterializations(
        isolatedSkillIds: const {},
      );
      stopwatch.stop();
      results.add(_InspectionRun(stopwatch.elapsed, report));
    }
    return results;
  } finally {
    await Future.wait(<Future<void>>[
      inspectionWorkers.close(),
      worker.close(),
    ]);
    await database.close();
  }
}

Future<List<Duration>> _measureOpen(String workspacePath, int runs) async {
  Future<Duration> openOnce() async {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: workspacePath,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 30),
        ),
      ),
    );
    final stopwatch = Stopwatch()..start();
    final opened = await repository.open().completed;
    stopwatch.stop();
    if (!opened.isSuccess) {
      _fail('Workspace open failed during the benchmark.', 1);
    }
    final closed = await repository.close().completed;
    if (!closed.isSuccess) {
      _fail('Workspace close failed during the benchmark.', 1);
    }
    return stopwatch.elapsed;
  }

  await openOnce();
  return <Duration>[
    for (var index = 0; index < runs; index += 1) await openOnce(),
  ];
}

Map<String, Object> _summarizeInspection(List<_InspectionRun> runs) {
  final elapsed = [for (final run in runs) run.elapsed];
  final latest = runs.last.report;
  return <String, Object>{
    ..._summarizeDurations(elapsed),
    'phaseMedianMicros': _median([
      for (final run in runs) run.report.inspectionElapsed.inMicroseconds,
    ]),
    'phaseSlowestMicros': runs
        .map((run) => run.report.inspectionElapsed.inMicroseconds)
        .reduce((left, right) => left > right ? left : right),
    'inspectedArtifacts': latest.inspectedArtifactCount,
    'inspectedFiles': latest.inspectedFileCount,
    'inspectedBytes': latest.inspectedByteCount,
    'repairedArtifacts': latest.repairedArtifactCount,
  };
}

Map<String, Object> _summarizeDurations(List<Duration> values) {
  final micros = [for (final value in values) value.inMicroseconds];
  return <String, Object>{
    'medianMicros': _median(micros),
    'slowestMicros': micros.reduce(
      (left, right) => left > right ? left : right,
    ),
    'runsMicros': micros,
  };
}

int _median(List<int> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) ~/ 2;
}

final class _InspectionRun {
  const _InspectionRun(this.elapsed, this.report);

  final Duration elapsed;
  final WorkspaceMaterializationReconciliationReport report;
}

final class _Options {
  const _Options({required this.workspacePath, required this.runs});

  final String workspacePath;
  final int runs;

  static _Options parse(List<String> arguments) {
    String? workspacePath;
    var runs = 5;
    for (var index = 0; index < arguments.length; index += 1) {
      final name = arguments[index];
      if (index + 1 >= arguments.length) _usage();
      final value = arguments[++index];
      switch (name) {
        case '--workspace':
          workspacePath = value;
        case '--runs':
          runs = int.tryParse(value) ?? _usage();
        default:
          _usage();
      }
    }
    if (workspacePath == null || workspacePath.trim().isEmpty || runs < 1) {
      _usage();
    }
    return _Options(workspacePath: workspacePath, runs: runs);
  }

  static Never _usage() => _fail(
    'usage: dart run tool/benchmark_workspace_open.dart '
    '--workspace <copied-workspace-path> [--runs <count>]',
    64,
  );
}

Never _fail(String message, int code) {
  stderr.writeln(message);
  exit(code);
}
