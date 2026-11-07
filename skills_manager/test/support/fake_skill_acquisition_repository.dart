import 'dart:async';

import 'package:skills_manager/features/skills/data/repositories/skill_acquisition_repository.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';

final class FakeSkillAcquisitionRepository
    implements SkillAcquisitionRepository {
  FakeSkillAcquisitionRepository({
    this.agents = const [
      AgentOption(
        id: 'codex',
        displayName: 'Codex',
        location: '/global/codex/skills',
      ),
    ],
  });

  @override
  final List<AgentOption> agents;

  @override
  Future<WorkspaceCompletion<List<AgentOption>>> inspectTargets({
    required SkillActivationScope scope,
    String? projectRootId,
  }) async {
    targetInspections.add((scope: scope, projectRootId: projectRootId));
    if (targetInspectionHandler case final handler?) {
      return handler(scope, projectRootId);
    }
    final error = inspectTargetsError;
    if (error != null) return WorkspaceFailed(failure: error);
    final pending = inspectTargetsPending;
    if (pending != null) return pending;
    return WorkspaceCompleted(value: agents, warnings: inspectTargetsWarnings);
  }

  SkillSourceInspection? inspection;
  Future<WorkspaceCompletion<List<AgentOption>>> Function(
    SkillActivationScope,
    String?,
  )?
  targetInspectionHandler;
  InstallReceipt? receipt;
  AcquisitionInstallAttempt? installAttempt;
  Object? inspectError;
  Object? installError;
  WorkspaceFailure? inspectTargetsError;
  WorkspaceCommittedPending<List<AgentOption>>? inspectTargetsPending;
  List<WorkspaceWarning> inspectTargetsWarnings = const [];
  AcquisitionTask<SkillSourceInspection> Function(SkillSourceDraft draft)?
  inspectHandler;
  AcquisitionTask<AcquisitionInstallAttempt> Function(
    InstallSelection selection,
  )?
  installHandler;
  AcquisitionTask<InstallReceipt> Function(WorkspaceInstallTakeoverDraft draft)?
  confirmInstallTakeoverHandler;
  final List<WorkspaceInstallTakeoverDraft> confirmedInstallTakeovers = [];
  SkillSourceDraft? inspectedDraft;
  InstallSelection? installSelection;
  void Function(InstallSelection selection)? onInstall;
  int cancelCalls = 0;
  final List<({SkillActivationScope scope, String? projectRootId})>
  targetInspections = [];

  @override
  AcquisitionTask<SkillSourceInspection> inspect(SkillSourceDraft draft) {
    inspectedDraft = draft;
    final handler = inspectHandler;
    if (handler != null) return handler(draft);
    return _task(
      value: inspection,
      error: inspectError,
      phase: AcquisitionPhase.inspecting,
    );
  }

  @override
  AcquisitionTask<AcquisitionInstallAttempt> install(
    InstallSelection selection,
  ) {
    installSelection = selection;
    onInstall?.call(selection);
    final handler = installHandler;
    if (handler != null) return handler(selection);
    return _task(
      value:
          installAttempt ??
          (receipt == null ? null : AcquisitionInstallCompleted(receipt!)),
      error: installError,
      phase: AcquisitionPhase.applying,
    );
  }

  @override
  AcquisitionTask<InstallReceipt> confirmInstallTakeover(
    WorkspaceInstallTakeoverDraft draft,
  ) {
    confirmedInstallTakeovers.add(draft);
    final handler = confirmInstallTakeoverHandler;
    if (handler != null) return handler(draft);
    return _task(
      value: receipt,
      error: installError,
      phase: AcquisitionPhase.applying,
    );
  }

  AcquisitionTask<T> _task<T>({
    required T? value,
    required Object? error,
    required AcquisitionPhase phase,
  }) => AcquisitionTask<T>(
    current: AcquisitionProgress(phase: phase),
    states: const Stream.empty(),
    completed: error == null
        ? Future<WorkspaceCompletion<T>>.value(
            WorkspaceCompleted(value: value as T),
          )
        : error is WorkspaceFailure
        ? Future<WorkspaceCompletion<T>>.value(WorkspaceFailed(failure: error))
        : Future<WorkspaceCompletion<T>>.error(error),
    cancel: () async {
      cancelCalls += 1;
    },
  );
}
