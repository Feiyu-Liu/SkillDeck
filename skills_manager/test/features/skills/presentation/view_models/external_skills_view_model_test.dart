import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/external_skills.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/external_skills_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';

import '../../../../support/fake_skills_workspace_repository.dart';
import '../../../../support/recording_app_analytics.dart';

void main() {
  test('scan selects candidates with a stable first authority', () async {
    final repository = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _discovery(),
    );
    final context = _context(repository);
    addTearDown(context.dispose);

    await context.notifier.scan();

    final state = context.container.read(externalSkillsViewModelProvider);
    expect(state.status, ExternalSkillsStatus.ready);
    expect(state.selectedSlotKeys, {'alpha'});
    expect(state.authoritativeLocations['alpha'], '/agents/a/alpha');
    expect(state.authoritativeLocations.containsKey('beta'), isFalse);
    expect(state.unmanagedSlotCount, 2);
  });

  test('conflict requires an explicit authoritative location', () async {
    final repository = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: ExternalSkillsDiscovery(
        candidates: const [],
        conflicts: [
          ExternalSkillConflict(
            slotKey: 'beta',
            contentHashByLocation: const {
              '/agents/a/beta': 'hash-a',
              '/agents/b/beta': 'hash-b',
            },
          ),
        ],
      ),
    );
    final context = _context(repository);
    addTearDown(context.dispose);
    await context.notifier.scan();

    expect(
      context.container.read(externalSkillsViewModelProvider).canConfirm,
      isFalse,
    );

    context.notifier.selectAuthority('beta', '/agents/b/beta');
    context.notifier.reviewConfirmation();

    final state = context.container.read(externalSkillsViewModelProvider);
    expect(state.canConfirm, isTrue);
    expect(state.status, ExternalSkillsStatus.confirming);
    expect(state.selectedSlotKeys, {'beta'});
  });

  test(
    'conflict adoption sends every reviewed location hash unchanged',
    () async {
      const reviewedHashes = <String, String>{
        '/agents/a/beta': 'hash-a',
        '/agents/b/beta': 'hash-b',
      };
      final repository = FakeSkillsWorkspaceRepository(
        externalSkillsDiscovery: ExternalSkillsDiscovery(
          candidates: const [],
          conflicts: [
            ExternalSkillConflict(
              slotKey: 'beta',
              contentHashByLocation: reviewedHashes,
            ),
          ],
        ),
      );
      final context = _context(repository);
      addTearDown(context.dispose);
      await context.notifier.scan();
      context.notifier.selectAuthority('beta', '/agents/b/beta');
      context.notifier.reviewConfirmation();

      await context.notifier.adoptSelected();

      expect(repository.adoptionRequests, hasLength(1));
      final request = repository.adoptionRequests.single;
      expect(request.slotKey, 'beta');
      expect(request.authoritativeLocation, '/agents/b/beta');
      expect(request.reviewedContentHashByLocation, reviewedHashes);
    },
  );

  test(
    'a rescan keeps choices made while it runs and selects new Skills',
    () async {
      final repository = FakeSkillsWorkspaceRepository(
        externalSkillsDiscovery: _twoCandidates(),
      );
      final context = _context(repository);
      addTearDown(context.dispose);
      await context.notifier.scan();

      final completer =
          Completer<WorkspaceCompletion<ExternalSkillsDiscovery>>();
      repository.discoverExternalSkillsTask = WorkspaceTask(
        current: _progress(WorkspaceOperationPhase.inspecting),
        states: const Stream.empty(),
        completed: completer.future,
        cancel: () async {},
      );
      final rescan = context.notifier.scan();
      // The review stays usable while the scan runs.
      context.notifier.setSelected('zeta', selected: false);
      var state = context.container.read(externalSkillsViewModelProvider);
      expect(state.scanning, isTrue);
      expect(state.selectedSlotKeys, {'alpha'});
      // Adoption waits for the latest content.
      await context.notifier.adoptSelected();
      expect(repository.adoptionRequests, isEmpty);

      completer.complete(
        WorkspaceCompleted(
          value: ExternalSkillsDiscovery(
            candidates: [
              ..._twoCandidates().candidates,
              ExternalSkillCandidate(
                slotKey: 'omega',
                declaredName: 'Omega',
                description: '',
                contentHash: 'hash-omega',
                locations: const ['/agents/omega'],
                agentIds: const ['agent'],
              ),
            ],
            conflicts: const [],
          ),
        ),
      );
      await rescan;

      state = context.container.read(externalSkillsViewModelProvider);
      expect(state.status, ExternalSkillsStatus.ready);
      expect(state.selectedSlotKeys, {'alpha', 'omega'});
    },
  );

  test('scan is single-flight', () async {
    final completer = Completer<WorkspaceCompletion<ExternalSkillsDiscovery>>();
    final repository = FakeSkillsWorkspaceRepository()
      ..discoverExternalSkillsTask = WorkspaceTask(
        current: _progress(WorkspaceOperationPhase.inspecting),
        states: const Stream.empty(),
        completed: completer.future,
        cancel: () async {},
      );
    final context = _context(repository);
    addTearDown(context.dispose);

    final first = context.notifier.scan();
    final second = context.notifier.scan();
    expect(repository.discoverExternalSkillsCalls, 1);

    completer.complete(
      WorkspaceCompleted(value: ExternalSkillsDiscovery.empty()),
    );
    await Future.wait([first, second]);
    expect(repository.discoverExternalSkillsCalls, 1);
  });

  test(
    'adoption is sorted without imperatively synchronizing catalog state',
    () async {
      final repository = FakeSkillsWorkspaceRepository(
        externalSkillsDiscovery: _twoCandidates(),
      );
      final analytics = RecordingAppAnalytics();
      final context = _context(repository, analytics: analytics);
      addTearDown(context.dispose);
      await context.notifier.scan();
      context.notifier.reviewConfirmation();

      await context.notifier.adoptSelected();

      final state = context.container.read(externalSkillsViewModelProvider);
      expect(repository.adoptionRequests.map((request) => request.slotKey), [
        'alpha',
        'zeta',
      ]);
      expect(state.status, ExternalSkillsStatus.success);
      expect(state.completedSlotKeys, ['alpha', 'zeta']);
      expect(repository.refreshCalls, 0);
      expect(repository.discoverExternalSkillsCalls, 1);
      expect(state.discovery?.isEmpty, isTrue);
      expect(state.selectedSlotKeys, isEmpty);
      expect(
        context.container
            .read(appNotificationControllerProvider)!
            .notification
            .message,
        AppNotificationMessage.externalSkillsAdopted,
      );
      expect(analytics.events.single.action, 'external_adoption');
      expect(analytics.events.single.name, 'success');
      expect(analytics.events.single.itemCount, 2);
    },
  );

  test('a failing Skill does not stop the rest of the batch', () async {
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.externalConflict,
      operation: WorkspaceOperationKind.adopt,
    );
    final repository =
        FakeSkillsWorkspaceRepository(externalSkillsDiscovery: _twoCandidates())
          ..adoptTaskBuilder = (_) => failedWorkspaceTask(
            kind: WorkspaceOperationKind.adopt,
            error: failure,
          );
    final context = _context(repository);
    addTearDown(context.dispose);
    await context.notifier.scan();

    await context.notifier.adoptSelected();

    final state = context.container.read(externalSkillsViewModelProvider);
    expect(repository.adoptionRequests.map((request) => request.slotKey), [
      'alpha',
      'zeta',
    ]);
    expect(state.status, ExternalSkillsStatus.failure);
    expect(state.completedSlotKeys, isEmpty);
    expect(state.failure, same(failure));
    expect(state.failedAdoptions.map((failed) => failed.name), [
      'Alpha',
      'Zeta',
    ]);
    expect(state.selectedSlotKeys, {'alpha', 'zeta'});
  });

  test('adopts the Skills around one that fails and reports partial', () async {
    final analytics = RecordingAppAnalytics();
    final failure = WorkspaceException(
      code: WorkspaceErrorCode.activationUnavailable,
      operation: WorkspaceOperationKind.adopt,
      context: const {'reason': 'adoptionTargetOccupied'},
    );
    final repository = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _threeCandidates(),
    );
    repository.adoptTaskBuilder = (request) {
      if (request.slotKey == 'beta') {
        return failedWorkspaceTask(
          kind: WorkspaceOperationKind.adopt,
          error: failure,
        );
      }
      return completedWorkspaceTask(
        kind: WorkspaceOperationKind.adopt,
        value: WorkspaceMutationReceipt(
          snapshot: repository.current,
          affectedSkillIds: const {},
        ),
      );
    };
    final context = _context(repository, analytics: analytics);
    addTearDown(context.dispose);
    await context.notifier.scan();

    await context.notifier.adoptSelected();

    final state = context.container.read(externalSkillsViewModelProvider);
    expect(repository.adoptionRequests.map((request) => request.slotKey), [
      'alpha',
      'beta',
      'gamma',
    ]);
    expect(state.status, ExternalSkillsStatus.partial);
    expect(state.completedSlotKeys, ['alpha', 'gamma']);
    expect(state.failure, same(failure));
    final failed = state.failedAdoptions.single;
    expect(failed.slotKey, 'beta');
    expect(failed.name, 'Beta');
    expect(failed.failure, same(failure));
    expect(state.discovery!.candidates.map((candidate) => candidate.slotKey), [
      'beta',
    ]);
    expect(state.selectedSlotKeys, {'beta'});
    final event = analytics.events.single;
    expect(event.name, 'partial');
    expect(event.errorCode, 'activationUnavailable:adoptionTargetOccupied');
    expect(
      event.dimensions(platform: 'macos', appVersion: '1'),
      allOf(
        containsPair('dimension5', '2_5'),
        containsPair('dimension6', '2_5'),
      ),
    );
    expect(
      context.container
          .read(appNotificationControllerProvider)!
          .notification
          .message,
      AppNotificationMessage.externalSkillsPartiallyAdopted,
    );
  });

  test('a repository-wide failure stops the batch', () async {
    final repository =
        FakeSkillsWorkspaceRepository(externalSkillsDiscovery: _twoCandidates())
          ..adoptTaskBuilder = (_) => failedWorkspaceTask(
            kind: WorkspaceOperationKind.adopt,
            error: WorkspaceException(
              code: WorkspaceErrorCode.repositoryBusy,
              operation: WorkspaceOperationKind.adopt,
            ),
          );
    final context = _context(repository);
    addTearDown(context.dispose);
    await context.notifier.scan();

    await context.notifier.adoptSelected();

    final state = context.container.read(externalSkillsViewModelProvider);
    expect(repository.adoptionRequests.map((request) => request.slotKey), [
      'alpha',
    ]);
    expect(state.status, ExternalSkillsStatus.failure);
    expect(state.failedAdoptions.map((failed) => failed.slotKey), ['alpha']);
  });

  test(
    'partial completion preserves committed slots without rescanning',
    () async {
      final failure = WorkspaceException(
        code: WorkspaceErrorCode.ioFailure,
        operation: WorkspaceOperationKind.adopt,
      );
      final repository = FakeSkillsWorkspaceRepository(
        externalSkillsDiscovery: _twoCandidates(),
      );
      repository.adoptTaskBuilder = (request) {
        if (request.slotKey == 'zeta') {
          return failedWorkspaceTask(
            kind: WorkspaceOperationKind.adopt,
            error: failure,
          );
        }
        return completedWorkspaceTask(
          kind: WorkspaceOperationKind.adopt,
          value: WorkspaceMutationReceipt(
            snapshot: repository.current,
            affectedSkillIds: const {},
          ),
        );
      };
      final context = _context(repository);
      addTearDown(context.dispose);
      await context.notifier.scan();

      await context.notifier.adoptSelected();

      final state = context.container.read(externalSkillsViewModelProvider);
      expect(state.status, ExternalSkillsStatus.partial);
      expect(state.completedSlotKeys, ['alpha']);
      expect(repository.refreshCalls, 0);
      expect(repository.discoverExternalSkillsCalls, 1);
      expect(state.discovery?.uniqueSlotCount, 1);
      expect(state.selectedSlotKeys, <String>{'zeta'});
      expect(state.authoritativeLocations.keys, <String>{'zeta'});
    },
  );

  test('cancellation is terminal without an inline failure', () async {
    final repository =
        FakeSkillsWorkspaceRepository(externalSkillsDiscovery: _twoCandidates())
          ..adoptError = WorkspaceException(
            code: WorkspaceErrorCode.operationCancelled,
            operation: WorkspaceOperationKind.adopt,
          );
    final context = _context(repository);
    addTearDown(context.dispose);
    await context.notifier.scan();

    await context.notifier.adoptSelected();

    final state = context.container.read(externalSkillsViewModelProvider);
    expect(state.status, ExternalSkillsStatus.cancelled);
    expect(state.failure, isNull);
    expect(
      context.container
          .read(appNotificationControllerProvider)!
          .notification
          .message,
      AppNotificationMessage.operationCancelled,
    );
  });

  test('failed background scan keeps the previous discovery', () async {
    final repository = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _discovery(),
    );
    final context = _context(repository);
    addTearDown(context.dispose);
    await context.notifier.scan();
    final previous = context.container
        .read(externalSkillsViewModelProvider)
        .discovery;
    repository.discoverExternalSkillsError = WorkspaceException(
      code: WorkspaceErrorCode.ioFailure,
      operation: WorkspaceOperationKind.discoverExternalSkills,
    );

    await context.notifier.scan();

    final state = context.container.read(externalSkillsViewModelProvider);
    expect(state.status, ExternalSkillsStatus.failure);
    expect(state.discovery, same(previous));
    expect(context.container.read(appNotificationControllerProvider), isNull);
  });

  test(
    'a stale adoption rescans, keeps the review, and asks to confirm again',
    () async {
      final analytics = RecordingAppAnalytics();
      final repository = FakeSkillsWorkspaceRepository(
        externalSkillsDiscovery: _twoCandidates(),
      );
      repository.adoptTaskBuilder = (_) {
        // An Agent rewrote the Skill after the scan.
        repository.externalSkillsDiscovery = ExternalSkillsDiscovery(
          candidates: [
            ExternalSkillCandidate(
              slotKey: 'alpha',
              declaredName: 'Alpha',
              description: '',
              contentHash: 'hash-alpha-2',
              locations: const ['/agents/alpha'],
              agentIds: const ['agent'],
            ),
            ..._twoCandidates().candidates.where((c) => c.slotKey == 'zeta'),
          ],
          conflicts: const [],
        );
        return failedWorkspaceTask(
          kind: WorkspaceOperationKind.adopt,
          error: WorkspaceException(
            code: WorkspaceErrorCode.staleSnapshot,
            operation: WorkspaceOperationKind.adopt,
          ),
        );
      };
      final context = _context(repository, analytics: analytics);
      addTearDown(context.dispose);
      await context.notifier.scan();
      context.notifier.setSelected('zeta', selected: false);

      await context.notifier.adoptSelected();

      final state = context.container.read(externalSkillsViewModelProvider);
      expect(repository.discoverExternalSkillsCalls, 2);
      expect(state.status, ExternalSkillsStatus.ready);
      expect(state.failure, isNull);
      expect(state.rescannedAfterChange, isTrue);
      expect(state.selectedSlotKeys, {'alpha'});
      expect(
        state.discovery!.candidates
            .singleWhere((candidate) => candidate.slotKey == 'alpha')
            .contentHash,
        'hash-alpha-2',
      );
      expect(context.container.read(appNotificationControllerProvider), isNull);
      expect(analytics.events.single.name, 'failed');

      context.notifier.reviewConfirmation();
      expect(
        context.container
            .read(externalSkillsViewModelProvider)
            .rescannedAfterChange,
        isFalse,
      );
    },
  );

  test('adoption failure analytics reports an allowlisted reason', () async {
    final analytics = RecordingAppAnalytics();
    final repository = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _twoCandidates(),
    );
    repository.adoptTaskBuilder = (_) => failedWorkspaceTask(
      kind: WorkspaceOperationKind.adopt,
      error: WorkspaceException(
        code: WorkspaceErrorCode.operationFailed,
        operation: WorkspaceOperationKind.adopt,
        context: const {'reason': 'businessCommitFailed'},
      ),
    );
    final context = _context(repository, analytics: analytics);
    addTearDown(context.dispose);
    await context.notifier.scan();
    context.notifier.setSelected('zeta', selected: false);

    await context.notifier.adoptSelected();

    final event = analytics.events.single;
    expect(event.action, 'external_adoption');
    expect(event.name, 'failed');
    expect(event.errorCode, 'operationFailed:businessCommitFailed');
    expect(
      event.dimensions(platform: 'macos', appVersion: '1'),
      containsPair('dimension6', '0'),
    );
  });

  test(
    'a committed adoption awaiting finalization leaves the review',
    () async {
      final repository = FakeSkillsWorkspaceRepository(
        externalSkillsDiscovery: _twoCandidates(),
      );
      repository.adoptTaskBuilder = (_) => WorkspaceTask(
        current: WorkspaceOperationProgress(
          operationId: 'adopt',
          kind: WorkspaceOperationKind.adopt,
          phase: WorkspaceOperationPhase.applying,
        ),
        states: const Stream.empty(),
        completed: Future.value(
          WorkspaceCommittedPending<WorkspaceMutationReceipt>(
            operationId: 'adopt',
            committedRevision: 2,
          ),
        ),
        cancel: () async {},
      );
      final context = _context(repository);
      addTearDown(context.dispose);
      await context.notifier.scan();

      await context.notifier.adoptSelected();

      final state = context.container.read(externalSkillsViewModelProvider);
      expect(state.completedSlotKeys, ['alpha']);
      expect(state.selectedSlotKeys, {'zeta'});
      expect(
        state.discovery!.candidates.map((candidate) => candidate.slotKey),
        ['zeta'],
      );
    },
  );

  test('an Agent catalog change rescans a finished review', () async {
    final repository = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _discovery(),
    );
    final context = _context(repository);
    addTearDown(context.dispose);
    await context.notifier.scan();

    context.notifier.agentCatalogChanged();
    await Future<void>.delayed(Duration.zero);

    expect(repository.discoverExternalSkillsCalls, 2);
  });

  test('an Agent catalog change never triggers the first scan', () async {
    final repository = FakeSkillsWorkspaceRepository(
      externalSkillsDiscovery: _discovery(),
    );
    final context = _context(repository);
    addTearDown(context.dispose);

    context.notifier.agentCatalogChanged();
    await Future<void>.delayed(Duration.zero);

    expect(repository.discoverExternalSkillsCalls, 0);
  });
}

ExternalSkillsDiscovery _discovery() => ExternalSkillsDiscovery(
  candidates: [
    ExternalSkillCandidate(
      slotKey: 'alpha',
      declaredName: 'Alpha',
      description: 'Alpha description',
      contentHash: 'hash-alpha',
      locations: const ['/agents/z/alpha', '/agents/a/alpha'],
      agentIds: const ['z-agent', 'a-agent'],
    ),
  ],
  conflicts: [
    ExternalSkillConflict(
      slotKey: 'beta',
      contentHashByLocation: const {
        '/agents/a/beta': 'hash-a',
        '/agents/b/beta': 'hash-b',
      },
    ),
  ],
);

ExternalSkillsDiscovery _twoCandidates() => ExternalSkillsDiscovery(
  candidates: [
    ExternalSkillCandidate(
      slotKey: 'zeta',
      declaredName: 'Zeta',
      description: '',
      contentHash: 'hash-zeta',
      locations: const ['/agents/zeta'],
      agentIds: const ['agent'],
    ),
    ExternalSkillCandidate(
      slotKey: 'alpha',
      declaredName: 'Alpha',
      description: '',
      contentHash: 'hash-alpha',
      locations: const ['/agents/alpha'],
      agentIds: const ['agent'],
    ),
  ],
  conflicts: const [],
);

ExternalSkillsDiscovery _threeCandidates() => ExternalSkillsDiscovery(
  candidates: [
    for (final (slotKey, name) in [
      ('gamma', 'Gamma'),
      ('alpha', 'Alpha'),
      ('beta', 'Beta'),
    ])
      ExternalSkillCandidate(
        slotKey: slotKey,
        declaredName: name,
        description: '',
        contentHash: 'hash-$slotKey',
        locations: ['/agents/$slotKey'],
        agentIds: const ['agent'],
      ),
  ],
  conflicts: const [],
);

WorkspaceOperationProgress _progress(WorkspaceOperationPhase phase) =>
    WorkspaceOperationProgress(
      operationId: 'scan',
      kind: WorkspaceOperationKind.discoverExternalSkills,
      phase: phase,
    );

_TestContext _context(
  FakeSkillsWorkspaceRepository repository, {
  AppAnalytics analytics = const NoopAppAnalytics(),
}) {
  final container = ProviderContainer(
    overrides: [
      appAnalyticsProvider.overrideWithValue(analytics),
      skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
    ],
  );
  final subscription = container.listen(
    externalSkillsViewModelProvider,
    (_, _) {},
    fireImmediately: true,
  );
  return _TestContext(
    container: container,
    subscription: subscription,
    notifier: container.read(externalSkillsViewModelProvider.notifier),
  );
}

final class _TestContext {
  const _TestContext({
    required this.container,
    required this.subscription,
    required this.notifier,
  });

  final ProviderContainer container;
  final ProviderSubscription<ExternalSkillsState> subscription;
  final ExternalSkillsViewModel notifier;

  void dispose() {
    subscription.close();
    container.dispose();
  }
}
