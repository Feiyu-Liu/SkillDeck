import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/data/repositories/diagnostic_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/recording_app_diagnostic_sink.dart';

void main() {
  test('traces successful typed completion and task operations', () async {
    final fixture = _fixture();

    expect(
      await fixture.repository.open(),
      isA<WorkspaceCompleted<SkillsWorkspaceSnapshot>>(),
    );
    final installCompletion = await fixture.repository
        .install(
          WorkspaceInstallRequest(
            source: const SkillSourceInput(
              kind: WorkspaceSourceKind.local,
              locator: '/source',
            ),
            scope: WorkspaceScope.global,
            agentIds: {},
          ),
        )
        .completed;
    expect(
      installCompletion,
      isA<WorkspaceCompleted<WorkspaceInstallAttempt>>(),
    );

    expect(fixture.sink.events.map((event) => event.event), [
      'operation.started',
      'operation.succeeded',
      'operation.started',
      'operation.succeeded',
    ]);
    expect(fixture.sink.events[0].operationKey, 'open');
    expect(fixture.sink.events[1].context['revision'], 0);
    expect(fixture.sink.events[2].operationKey, 'install');
    expect(fixture.sink.events[2].operationId, 'fake-install');
    expect(fixture.sink.events[3].context['takeoverRequired'], isFalse);
  });

  test(
    'logs a typed repository failure without an unexpected exception',
    () async {
      final fixture = _fixture();
      final failure = WorkspaceException(
        code: WorkspaceErrorCode.gitFailed,
        operation: WorkspaceOperationKind.refresh,
        diagnostic: 'The sanitized Git clone failed.',
      );
      fixture.delegate.refreshError = failure;

      final completion = await fixture.repository.refresh();

      expect(completion, isA<WorkspaceFailed<SkillsWorkspaceSnapshot>>());
      expect(
        (completion as WorkspaceFailed<SkillsWorkspaceSnapshot>).failure,
        same(failure),
      );
      expect(fixture.sink.events.map((event) => event.event), [
        'operation.started',
        'operation.failed',
      ]);
      expect(fixture.sink.events.last.codeKey, 'gitFailed');
      expect(
        fixture.sink.events.last.diagnostic,
        'The sanitized Git clone failed.',
      );

      expect(fixture.sink.events, hasLength(2));
    },
  );

  test('traces cancellation request and terminal cancellation', () async {
    final fixture = _fixture();
    final completer =
        Completer<WorkspaceCompletion<WorkspaceMutationReceipt>>();
    final cancellation = WorkspaceException(
      code: WorkspaceErrorCode.operationCancelled,
      operation: WorkspaceOperationKind.update,
    );
    fixture.delegate.updateTask = WorkspaceTask(
      current: WorkspaceOperationProgress(
        operationId: 'operation-update',
        kind: WorkspaceOperationKind.update,
        phase: WorkspaceOperationPhase.applying,
      ),
      states: const Stream.empty(),
      completed: completer.future,
      cancel: () async {
        completer.complete(WorkspaceFailed(failure: cancellation));
      },
    );

    final task = fixture.repository.update(
      skillIds: {WorkspaceSkillId('alpha')},
    );
    final resultExpectation = expectLater(
      task.completed,
      completion(isA<WorkspaceFailed<WorkspaceMutationReceipt>>()),
    );
    await task.cancel();
    final outcome = await task.completed;
    expect(
      (outcome as WorkspaceFailed<WorkspaceMutationReceipt>).failure,
      same(cancellation),
    );
    await resultExpectation;

    expect(fixture.sink.events.map((event) => event.event), [
      'operation.started',
      'operation.cancel_requested',
      'operation.cancelled',
    ]);
    expect(fixture.sink.events.last.level, AppDiagnosticLevel.info);
    expect(fixture.sink.events.last.operationId, 'operation-update');
  });
  test(
    'drift commands preserve handles and trace bounded metadata only',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.delegate.dispose);
      final id = WorkspaceSkillId('drift-skill');
      final review =
          (await fixture.repository.inspectSkillDrift(id).completed
                  as WorkspaceCompleted<WorkspaceSkillDriftReview>)
              .value;
      await fixture.repository
          .exportSkillDriftArtifact(
            review: review,
            artifactId: 'repositoryCopy',
            destinationDirectory: '/private-export-path',
          )
          .completed;
      await fixture.repository
          .resolveSkillDrift(
            review: review,
            resolution: const WorkspaceDriftResolution.restoreManaged(),
          )
          .completed;
      expect(
        fixture.delegate.exportedSkillDriftArtifacts.single.review,
        same(review),
      );
      expect(fixture.delegate.resolvedSkillDrifts.single.review, same(review));
      expect(fixture.sink.events.map((event) => event.operationKey), [
        'inspectSkillDrift',
        'inspectSkillDrift',
        'exportSkillDriftArtifact',
        'exportSkillDriftArtifact',
        'resolveSkillDrift',
        'resolveSkillDrift',
      ]);
      expect(fixture.sink.events[1].context['artifactCount'], 0);
      expect(
        fixture.sink.events.every(
          (event) => !event.context.toString().contains('/private-export-path'),
        ),
        isTrue,
      );
    },
  );
  test('personal tag commands trace identities but never tag names', () async {
    final fixture = _fixture();
    addTearDown(fixture.delegate.dispose);
    final created =
        (await fixture.repository
                    .createPersonalTag(name: 'Secret Project', color: '#3E63DD')
                    .completed
                as WorkspaceCompleted<WorkspacePersonalTag>)
            .value;
    await fixture.repository
        .updatePersonalTag(tagId: created.id, name: 'Secret Renamed')
        .completed;
    await fixture.repository.deletePersonalTag(created.id).completed;

    expect(fixture.sink.events.map((event) => event.operationKey), [
      'createPersonalTag',
      'createPersonalTag',
      'updatePersonalTag',
      'updatePersonalTag',
      'deletePersonalTag',
      'deletePersonalTag',
    ]);
    expect(fixture.sink.events[1].context['tagId'], created.id);
    expect(
      fixture.sink.events.every(
        (event) => !event.context.toString().contains('Secret'),
      ),
      isTrue,
    );
  });
}

({
  FakeSkillsWorkspaceRepository delegate,
  DiagnosticSkillsWorkspaceRepository repository,
  RecordingAppDiagnosticSink sink,
  AppFailureReporter reporter,
})
_fixture() {
  final delegate = FakeSkillsWorkspaceRepository();
  final sink = RecordingAppDiagnosticSink();
  final diagnostics = AppDiagnostics(sink: sink);
  final reporter = AppFailureReporter(diagnostics);
  return (
    delegate: delegate,
    repository: DiagnosticSkillsWorkspaceRepository(
      delegate: delegate,
      diagnostics: diagnostics,
      failureReporter: reporter,
    ),
    sink: sink,
    reporter: reporter,
  );
}
