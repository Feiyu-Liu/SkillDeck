import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_acquisition_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';

import '../../support/memory_app_settings_store.dart';
import '../../support/fake_skill_acquisition_repository.dart';

WorkspaceAgentInfo agent(
  String id, {
  bool builtIn = true,
  bool detected = false,
  Set<String> projects = const {},
}) => WorkspaceAgentInfo(
  id: id,
  displayName: id,
  isBuiltIn: builtIn,
  supportedScopes: {WorkspaceScope.global, WorkspaceScope.project},
  detectedGlobally: detected,
  detectedProjectRootIds: projects,
);

class _Members extends Notifier<AsyncValue<Set<String>>> {
  @override
  AsyncValue<Set<String>> build() => const AsyncLoading();
  void replace(Set<String> ids) => state = AsyncData(ids);
}

final _members = NotifierProvider<_Members, AsyncValue<Set<String>>>(
  _Members.new,
);

void main() {
  test(
    'old settings and persistent inclusion/exclusion retain detection truth',
    () {
      final old = AppSettings.fromJson({
        'version': 1,
        'localePreference': 'en',
        'customAgents': [],
      });
      expect(old.builtInAgentVisibilityOverrides, isEmpty);
      final agents = [
        agent('codex', detected: true),
        agent('cursor'),
        agent('project', projects: {'p'}),
        agent('custom-a', builtIn: false),
      ];
      final settings = old.copyWith(
        builtInAgentVisibilityOverrides: {
          'codex': false,
          'cursor': true,
          'future': true,
        },
      );
      expect(deviceAgentMemberIds(agents, settings), {
        'cursor',
        'project',
        'custom-a',
      });
      expect(agents[1].detected, isFalse);
      expect(
        AppSettings.fromJson(settings.toJson()).builtInAgentVisibilityOverrides,
        settings.builtInAgentVisibilityOverrides,
      );
      expect(
        () => AppSettings.fromJson({
          ...old.toJson(),
          'builtInAgentVisibilityOverrides': {'codex': 'true'},
        }),
        throwsFormatException,
      );
      expect(
        () => const AppSettings(
          builtInAgentVisibilityOverrides: {'universal': true},
        ).validate(),
        throwsFormatException,
      );
    },
  );

  test('shared location keeps identity but only explicitly included IDs can activate', () {
    final targets = [
      for (final id in ['codex', 'cursor', 'universal'])
        WorkspaceActivationTarget(
          agentId: id,
          displayName: id,
          detected: id == 'codex',
          location: '/shared',
          scope: WorkspaceScope.global,
        ),
    ];
    final group = projectDeviceAgentGroups(targets, {'cursor'}).single;
    expect(group.shared, isTrue);
    expect(group.requestAgentIds, {'cursor'});
    expect(group.visibleAgents.single.agentId, 'cursor');
    expect(group.visibleAgents.single.detected, isFalse);
    final removed = projectDeviceAgentGroups(targets, {}).single;
    expect(removed.canActivate, isFalse);
    expect(removed.requestAgentIds, isEmpty);
    expect(removed.shared, isTrue);
    expect(deviceActivationGroups(targets, {}), isEmpty);
    expect(deviceActivationGroups(targets, {'cursor'}).single.shared, isTrue);
  });

  test('removed Agents disappear and rejoining restores the same location', () {
    final targets = [
      WorkspaceActivationTarget(
        agentId: 'codex',
        displayName: 'Codex',
        detected: true,
        location: '/codex',
        scope: WorkspaceScope.global,
      ),
    ];
    expect(deviceActivationGroups(targets, const {}), isEmpty);
    final restored = deviceActivationGroups(targets, {'codex'}).single;
    expect(restored.canActivate, isTrue);
    expect(restored.location, '/codex');
    expect(deviceActivationGroups(const [], {'deleted-custom'}), isEmpty);
  });

  test(
    'membership persists and failed writes retain the previous settings',
    () async {
      final store = MemoryAppSettingsStore(
        const AppSettings(localePreference: AppLocalePreference.zh),
      );
      final container = ProviderContainer(
        overrides: [appSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final vm = container.read(appSettingsViewModelProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      expect(await vm.setBuiltInAgentMembership('codex', false), isTrue);
      expect(store.value!.builtInAgentVisibilityOverrides, {'codex': false});
      store.failWrites = true;
      expect(await vm.setBuiltInAgentMembership('cursor', true), isFalse);
      expect(
        container
            .read(appSettingsViewModelProvider)
            .settings
            .builtInAgentVisibilityOverrides,
        {'codex': false},
      );
      expect(store.value!.localePreference, AppLocalePreference.zh);
      final restarted = ProviderContainer(
        overrides: [appSettingsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(restarted.dispose);
      restarted.read(appSettingsViewModelProvider);
      await Future<void>.delayed(Duration.zero);
      expect(
        restarted
            .read(appSettingsViewModelProvider)
            .settings
            .builtInAgentVisibilityOverrides,
        {'codex': false},
      );
    },
  );

  test('late roster initializes defaults; later changes preserve selection and remove stale IDs', () async {
    final repo = FakeSkillAcquisitionRepository(
      agents: const [
        AgentOption(id: 'codex', displayName: 'Codex', location: '/shared'),
        AgentOption(
          id: 'cursor',
          displayName: 'Cursor',
          location: '/shared',
          detected: false,
        ),
        AgentOption(id: 'claude', displayName: 'Claude', location: '/claude'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        skillAcquisitionRepositoryProvider.overrideWithValue(repo),
        deviceAgentMembersProvider.overrideWith((ref) => ref.watch(_members)),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(skillAcquisitionViewModelProvider.notifier);
    await vm.loadTargets(scope: SkillActivationScope.global);
    expect(vm.selectedLocations, isEmpty);
    container.read(_members.notifier).replace({'codex', 'claude'});
    await container.pump();
    expect(container.read(deviceAgentMembersProvider).value, {
      'codex',
      'claude',
    });
    vm.reconcileAgentMembership({'codex', 'claude'});
    expect(vm.selectedLocations, hasLength(2));
    vm.toggleLocation(
      vm.locationGroups.firstWhere((g) => g.location == '/claude').key,
      false,
    );
    container.read(_members.notifier).replace({'cursor', 'claude'});
    await container.pump();
    vm.reconcileAgentMembership({'cursor', 'claude'});
    expect(container.read(skillAcquisitionViewModelProvider).selectedAgentIds, {
      'cursor',
    });
    container.read(_members.notifier).replace({'claude'});
    await container.pump();
    vm.reconcileAgentMembership({'claude'});
    expect(vm.selectedLocations, isEmpty);
  });
}
