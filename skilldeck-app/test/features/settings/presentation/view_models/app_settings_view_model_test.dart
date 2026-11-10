import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/data/app_settings_coordinator.dart';
import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/presentation/view_models/app_settings_view_model.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_finalization_coordinator.dart';

import '../../../../support/fake_skills_workspace_repository.dart';

void main() {
  test(
    'does not publish pending settings when catalog reconfiguration fails',
    () async {
      const previous = AppSettings(localePreference: AppLocalePreference.en);
      final store = _MemoryAppSettingsStore(previous);
      final runtime = _FailingRuntime();
      final container = _container(store: store, runtime: runtime);
      addTearDown(container.dispose);
      final published = <AppSettingsState>[];
      final subscription = container.listen(appSettingsViewModelProvider, (
        _,
        next,
      ) {
        published.add(next);
      }, fireImmediately: true);
      addTearDown(subscription.close);

      await _ready(container);
      final saved = await container
          .read(appSettingsViewModelProvider.notifier)
          .saveCustomAgent(_pendingAgent);

      expect(saved, isFalse);
      expect(
        container.read(appSettingsViewModelProvider).status,
        AppSettingsStatus.failure,
      );
      expect(
        container.read(appSettingsViewModelProvider).errorCode,
        'settings_agent_id_conflict',
      );
      expect(
        container.read(appSettingsViewModelProvider).settings.toJson(),
        previous.toJson(),
      );
      expect(store.value?.toJson(), previous.toJson());
      expect(runtime.requests.single.customAgents.single.id, _pendingAgent.id);
      expect(
        published.every((state) => state.settings.customAgents.isEmpty),
        isTrue,
      );
    },
  );

  test(
    'provider forwards committed Settings reconfiguration to root recovery',
    () async {
      const previous = AppSettings(localePreference: AppLocalePreference.en);
      final store = _MemoryAppSettingsStore(previous);
      final runtime = _PendingRuntime();
      final workspace = FakeSkillsWorkspaceRepository(
        snapshot: SkillsWorkspaceSnapshot(
          revision: 5,
          projectRoots: const [],
          skills: const [],
        ),
      );
      final container = ProviderContainer(
        overrides: [
          appSettingsStoreProvider.overrideWithValue(store),
          appSettingsRuntimeProvider.overrideWithValue(runtime),
          skillsWorkspaceRepositoryProvider.overrideWithValue(workspace),
        ],
      );
      addTearDown(container.dispose);
      container.read(appSettingsViewModelProvider);
      await _ready(container);

      final saved = await container
          .read(appSettingsViewModelProvider.notifier)
          .saveCustomAgent(_pendingAgent);

      expect(saved, isTrue);
      expect(store.value?.customAgents.single.id, _pendingAgent.id);
      expect(
        container
            .read(appSettingsViewModelProvider)
            .settings
            .customAgents
            .single
            .id,
        _pendingAgent.id,
      );
      // `finalizationRecoveryCalls` increments synchronously at the start of
      // the coordinator's recovery attempt, before the awaited completion
      // clears the pending id and republishes state - polling on the call
      // count races ahead of that publish. Poll the actual observable
      // outcome instead.
      await _eventually(
        () => container
            .read(workspaceFinalizationCoordinatorProvider)
            .pendingOperationIds
            .isEmpty,
      );
      expect(workspace.finalizationRecoveryCalls, 1);
    },
  );

  test(
    'publishes pending settings only after reconfiguration completes',
    () async {
      const previous = AppSettings(localePreference: AppLocalePreference.en);
      final store = _MemoryAppSettingsStore(previous);
      final runtime = _BlockingRuntime();
      addTearDown(() {
        if (!runtime.allow.isCompleted) runtime.allow.complete();
      });
      final container = _container(store: store, runtime: runtime);
      addTearDown(container.dispose);
      container.read(appSettingsViewModelProvider);
      await _ready(container);

      final save = container
          .read(appSettingsViewModelProvider.notifier)
          .saveCustomAgent(_pendingAgent);
      await runtime.started.future;

      expect(
        container.read(appSettingsViewModelProvider).status,
        AppSettingsStatus.saving,
      );
      expect(
        container.read(appSettingsViewModelProvider).settings.toJson(),
        previous.toJson(),
      );
      expect(store.value?.customAgents.single.id, _pendingAgent.id);

      runtime.allow.complete();
      expect(await save, isTrue);
      expect(
        container
            .read(appSettingsViewModelProvider)
            .settings
            .customAgents
            .single
            .id,
        _pendingAgent.id,
      );
    },
  );

  test(
    'persists a locale-only preference without reconfiguring Workspace',
    () async {
      const previous = AppSettings(localePreference: AppLocalePreference.en);
      final store = _MemoryAppSettingsStore(previous);
      final runtime = _FailingRuntime();
      final container = _container(store: store, runtime: runtime);
      addTearDown(container.dispose);
      container.read(appSettingsViewModelProvider);
      await _ready(container);

      final saved = await container
          .read(appSettingsViewModelProvider.notifier)
          .setLocalePreference(AppLocalePreference.zh);

      expect(saved, isTrue);
      expect(runtime.requests, isEmpty);
      expect(store.value?.localePreference, AppLocalePreference.zh);
      expect(
        container.read(appSettingsViewModelProvider).settings.localePreference,
        AppLocalePreference.zh,
      );
    },
  );

  test('persists the duplicate activation confirmation preference', () async {
    final store = _MemoryAppSettingsStore(const AppSettings());
    final container = _container(store: store, runtime: _FailingRuntime());
    addTearDown(container.dispose);
    container.read(appSettingsViewModelProvider);
    await _ready(container);

    final saved = await container
        .read(appSettingsViewModelProvider.notifier)
        .setSuppressDuplicateActivationConfirmation(true);

    expect(saved, isTrue);
    expect(store.value?.suppressDuplicateActivationConfirmation, isTrue);
    expect(
      container
          .read(appSettingsViewModelProvider)
          .settings
          .suppressDuplicateActivationConfirmation,
      isTrue,
    );
  });

  test('persists the sidebar collapsed preference', () async {
    final store = _MemoryAppSettingsStore(const AppSettings());
    final container = _container(store: store, runtime: _FailingRuntime());
    addTearDown(container.dispose);
    container.read(appSettingsViewModelProvider);
    await _ready(container);

    final saved = await container
        .read(appSettingsViewModelProvider.notifier)
        .setSidebarCollapsed(true);

    expect(saved, isTrue);
    expect(store.value?.sidebarCollapsed, isTrue);
    expect(
      container.read(appSettingsViewModelProvider).settings.sidebarCollapsed,
      isTrue,
    );
  });

  test('persists the global activation method', () async {
    final store = _MemoryAppSettingsStore(const AppSettings());
    final container = _container(store: store, runtime: _FailingRuntime());
    addTearDown(container.dispose);
    container.read(appSettingsViewModelProvider);
    await _ready(container);

    final saved = await container
        .read(appSettingsViewModelProvider.notifier)
        .setGlobalActivationMethod(WorkspaceActivationMethod.copy);

    expect(saved, isTrue);
    expect(store.value?.globalActivationMethod, WorkspaceActivationMethod.copy);
    expect(
      container.read(globalActivationMethodProvider),
      WorkspaceActivationMethod.copy,
    );
  });
}

const _pendingAgent = CustomAgentSettings(
  id: 'custom-reviewer-1234',
  displayName: 'Reviewer',
  iconName: 'bot',
  platforms: {
    AppDesktopPlatform.linux: CustomAgentPlatformSettings(
      globalSkillsPath: '/tmp/reviewer/skills',
    ),
  },
);

ProviderContainer _container({
  required _MemoryAppSettingsStore store,
  required AppSettingsRuntime runtime,
}) => ProviderContainer(
  overrides: [
    appSettingsStoreProvider.overrideWithValue(store),
    appSettingsCoordinatorProvider.overrideWithValue(
      AppSettingsCoordinator(store: store, runtime: runtime),
    ),
  ],
);

Future<void> _ready(ProviderContainer container) => _eventually(
  () =>
      container.read(appSettingsViewModelProvider).status ==
      AppSettingsStatus.ready,
);

Future<void> _eventually(bool Function() predicate) async {
  for (var index = 0; index < 30; index++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Condition did not become true.');
}

final class _MemoryAppSettingsStore implements AppSettingsStore {
  _MemoryAppSettingsStore(this.value);

  AppSettings? value;

  @override
  Future<AppSettingsStoreSnapshot> captureSnapshot() async => value == null
      ? const AppSettingsStoreSnapshot.missing()
      : AppSettingsStoreSnapshot.withValue(jsonEncode(value!.toJson()));

  @override
  Future<AppSettings?> read() async => value;

  @override
  Future<void> restore(AppSettingsStoreSnapshot snapshot) async {
    value = snapshot.isMissing ? null : AppSettings.decode(snapshot.rawValue!);
  }

  @override
  Future<void> write(AppSettings settings) async {
    value = settings;
  }
}

final class _FailingRuntime implements AppSettingsRuntime {
  final requests = <AppSettings>[];

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> reconfigureAgentCatalog(
    AppSettings nextSettings,
  ) async {
    requests.add(nextSettings);
    return WorkspaceFailed(
      failure: WorkspaceFailure(
        code: WorkspaceErrorCode.duplicateAgentId,
        operation: WorkspaceOperationKind.reconfigureAgentCatalog,
      ),
    );
  }
}

final class _BlockingRuntime implements AppSettingsRuntime {
  final started = Completer<void>();
  final allow = Completer<void>();

  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> reconfigureAgentCatalog(
    AppSettings nextSettings,
  ) async {
    started.complete();
    await allow.future;
    return WorkspaceCompleted(value: SkillsWorkspaceSnapshot.empty());
  }
}

final class _PendingRuntime implements AppSettingsRuntime {
  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> reconfigureAgentCatalog(
    AppSettings nextSettings,
  ) async => WorkspaceCommittedPending(
    operationId: 'settings-provider-pending',
    committedRevision: 5,
  );
}
