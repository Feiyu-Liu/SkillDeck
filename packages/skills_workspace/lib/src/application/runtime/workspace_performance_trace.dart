import 'dart:convert';
import 'dart:developer' as developer;

import 'package:logging/logging.dart';

/// Fixed event names keep content, paths, identities, and exceptions out of logs.
enum WorkspacePerformancePhase {
  writerLock,
  controlPlaneRecovery,
  controlPlaneOpen,
  revisionWorkerStartup,
  revisionMaintenance,
  journalRecovery,
  revisionReferenceReconciliation,
  snapshotRead,
  snapshotPublication,
  requestGateOpen,
  skillValidation,
  workspaceValidation,
}

/// Local performance diagnostics only; this does not send telemetry.
final class WorkspacePerformanceTrace {
  WorkspacePerformanceTrace(this.phase)
    : _stopwatch = Stopwatch()..start(),
      _task = developer.TimelineTask()
        ..start(
          phase == WorkspacePerformancePhase.skillValidation ||
                  phase == WorkspacePerformancePhase.workspaceValidation
              ? 'skills_workspace.validation.${phase.name}'
              : 'skills_workspace.open.${phase.name}',
        );

  static final _logger = Logger('skills_workspace.performance');

  final WorkspacePerformancePhase phase;
  final Stopwatch _stopwatch;
  final developer.TimelineTask _task;
  int inspectedArtifactCount = 0;
  int inspectedFileCount = 0;
  int inspectedByteCount = 0;
  int repairedArtifactCount = 0;

  void finish({
    required bool failed,
    bool cancelled = false,
    int? checkedSkillCount,
  }) {
    _stopwatch.stop();
    final event = <String, Object>{
      'phase': phase.name,
      'elapsedMicros': _stopwatch.elapsedMicroseconds,
      'failed': failed,
      'cancelled': cancelled,
      'checkedSkillCount': ?checkedSkillCount,
      if (phase == WorkspacePerformancePhase.skillValidation) ...{
        'inspectedArtifactCount': inspectedArtifactCount,
        'inspectedFileCount': inspectedFileCount,
        'inspectedByteCount': inspectedByteCount,
        'repairedArtifactCount': repairedArtifactCount,
      },
    };
    _task.finish(arguments: event);
    final message = jsonEncode(event);
    developer.log(message, name: _logger.name);
    _logger.info(message);
  }
}
