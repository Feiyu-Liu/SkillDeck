import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/models/activation_location_group.dart';
import 'package:skills_manager/features/skills/models/installed_skill.dart';
import 'package:skills_manager/features/skills/models/skill_acquisition.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/presentation/view_models/skill_acquisition_view_model.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';

import '../../../support/fake_skill_acquisition_repository.dart';
import '../../../support/fake_skill_browser_repository.dart';

void main() {
  test('overlapping catalog refreshes retain the selected locations', () async {
    const agents = [
      AgentOption(id: 'codex', displayName: 'Codex', location: '/shared'),
      AgentOption(id: 'claude', displayName: 'Claude', location: '/claude'),
    ];
    final repo = FakeSkillAcquisitionRepository(agents: agents);
    final container = ProviderContainer(
      overrides: [
        skillAcquisitionRepositoryProvider.overrideWithValue(repo),
        deviceAgentMembersProvider.overrideWithValue(
          const AsyncData({'codex', 'claude'}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(skillAcquisitionViewModelProvider.notifier);
    await vm.loadTargets(scope: SkillActivationScope.global);
    vm.toggleLocation(
      vm.locationGroups.firstWhere((g) => g.location == '/claude').key,
      false,
    );
    final first = Completer<WorkspaceCompletion<List<AgentOption>>>();
    final second = Completer<WorkspaceCompletion<List<AgentOption>>>();
    var calls = 0;
    repo.targetInspectionHandler = (_, _) =>
        calls++ == 0 ? first.future : second.future;
    final loading = vm.loadTargets(scope: SkillActivationScope.global);
    final reloading = vm.loadTargets(scope: SkillActivationScope.global);
    second.complete(WorkspaceCompleted(value: agents));
    await reloading;
    first.complete(WorkspaceCompleted(value: agents));
    await loading;
    expect(vm.selectedLocations.map((key) => key.location), ['/shared']);
  });

  WorkspaceActivationTarget target(
    String id, {
    bool detected = true,
    WorkspaceScope scope = WorkspaceScope.global,
    String? root,
    String location = '/home/test/.agents/skills',
  }) => WorkspaceActivationTarget(
    agentId: id,
    displayName: id,
    detected: detected,
    scope: scope,
    projectRootId: root,
    location: location,
  );

  test('one shared directory, detected request IDs only', () {
    final groups = groupActivationLocations([
      target('codex'),
      target('opencode'),
      target('universal', detected: false),
    ]);
    expect(groups, hasLength(1));
    expect(groups.single.shared, isTrue);
    expect(groups.single.requestAgentIds, {'codex', 'opencode'});
    expect(groups.single.visibleAgents.map((t) => t.agentId), [
      'codex',
      'opencode',
    ]);
  });

  test('scope and project identity are never collapsed by path alone', () {
    expect(
      groupActivationLocations([
        target('codex'),
        target('codex', scope: WorkspaceScope.project, root: 'a'),
        target('codex', scope: WorkspaceScope.project, root: 'b'),
        target('claude', location: '/home/test/.claude/skills'),
      ]),
      hasLength(4),
    );
  });

  test('explicit undetected group uses stable valid representative', () {
    final g = groupActivationLocations([
      target('zed', detected: false),
      target('codex', detected: false),
    ]).single;
    expect(g.requestAgentIds, {'codex'});
    expect(g.detected, isFalse);
  });

  test('acquisition resolves selected locations and rejects stale keys', () {
    const state = SkillAcquisitionState(
      agents: [
        AgentOption(id: 'codex', displayName: 'Codex', location: '/shared'),
        AgentOption(
          id: 'opencode',
          displayName: 'OpenCode',
          location: '/shared',
        ),
        AgentOption(
          id: 'universal',
          displayName: 'Universal',
          location: '/shared',
          detected: false,
        ),
      ],
    );
    final key = state.locationGroups.single.key;
    expect(state.copyWith(selectedLocations: {key}).selectedAgentIds, {
      'codex',
      'opencode',
    });
    expect(
      state
          .copyWith(agents: const [], selectedLocations: {key})
          .selectedAgentIds,
      isEmpty,
    );
  });

  SkillActivationLocation activation({
    required String location,
    WorkspaceScope scope = WorkspaceScope.global,
    String? root,
    List<String> agentIds = const ['claude'],
  }) => SkillActivationLocation(
    location: location,
    scope: scope,
    projectRootId: root,
    projectRootPath: root == null ? null : '/$root',
    mode: WorkspaceActivationMode.copy,
    agentIds: agentIds,
  );

  test(
    'old shared activation does not enable corrected Antigravity location',
    () {
      final groups = groupActivationLocations([
        target('antigravity', location: '/home/test/.gemini/config/skills'),
        target('antigravity-cli', location: '/home/test/.gemini/config/skills'),
        target('codex'),
      ]);
      final skill = testSkill(
        slotKey: 'legacy',
        displayName: 'Legacy',
        activations: [
          activation(
            location: '/home/test/.agents/skills',
            agentIds: ['antigravity', 'codex'],
          ),
        ],
      );
      final active = activeGroupsInScope(
        skill,
        groups: groups,
        scope: InstalledScopeFilter.global,
      );
      expect(active.single.targets.single.agentId, 'codex');
      expect(skill.activations.single.agentIds, ['antigravity', 'codex']);
    },
  );

  test('Scope buckets an installed Skill by the reach of its Activations', () {
    final never = testSkill(slotKey: 'never', displayName: 'Never activated');
    final globalOnly = testSkill(
      slotKey: 'global',
      displayName: 'Global only',
      activations: [activation(location: '/global/skills')],
    );
    final projectAOnly = testSkill(
      slotKey: 'project-a',
      displayName: 'Project A only',
      activations: [
        activation(
          location: '/a/.agents/skills',
          scope: WorkspaceScope.project,
          root: 'a',
        ),
      ],
    );
    final both = testSkill(
      slotKey: 'both',
      displayName: 'Global and Project A',
      activations: [
        activation(location: '/global/skills'),
        activation(
          location: '/a/.agents/skills',
          scope: WorkspaceScope.project,
          root: 'a',
        ),
      ],
    );

    bool inBucket(
      InstalledSkill skill,
      InstalledScopeFilter scope, [
      String? root,
    ]) => matchesInstalledSelection(
      skill,
      scope: scope,
      projectRootId: root,
      filter: const InstalledLocationFilter.all(),
    );

    // Global bucket: reaches every Agent everywhere.
    expect(inBucket(never, InstalledScopeFilter.global), isFalse);
    expect(inBucket(globalOnly, InstalledScopeFilter.global), isTrue);
    expect(inBucket(projectAOnly, InstalledScopeFilter.global), isFalse);
    expect(inBucket(both, InstalledScopeFilter.global), isTrue);

    // Project A bucket: reaches only Agents working in Project A.
    expect(inBucket(never, InstalledScopeFilter.project, 'a'), isFalse);
    expect(inBucket(globalOnly, InstalledScopeFilter.project, 'a'), isFalse);
    expect(inBucket(projectAOnly, InstalledScopeFilter.project, 'a'), isTrue);
    expect(inBucket(both, InstalledScopeFilter.project, 'a'), isTrue);

    // Project B bucket: an Activation in another Project does not reach it.
    expect(inBucket(projectAOnly, InstalledScopeFilter.project, 'b'), isFalse);
    expect(inBucket(both, InstalledScopeFilter.project, 'b'), isFalse);

    // Inactive bucket: exactly the Skills no Agent can reach, in any Scope.
    expect(inBucket(never, InstalledScopeFilter.inactive), isTrue);
    expect(inBucket(globalOnly, InstalledScopeFilter.inactive), isFalse);
    expect(inBucket(projectAOnly, InstalledScopeFilter.inactive), isFalse);
    expect(inBucket(both, InstalledScopeFilter.inactive), isFalse);

    // The inactive bucket ignores the remembered Project Root.
    expect(
      matchesInstalledSelection(
        never,
        scope: InstalledScopeFilter.inactive,
        projectRootId: 'a',
        filter: const InstalledLocationFilter.all(),
      ),
      isTrue,
    );
  });

  test('scope state keeps Global and Project Activations independent', () {
    final skill = testSkill(
      slotKey: 'coexisting',
      displayName: 'Coexisting',
      activations: [
        activation(location: '/global'),
        activation(
          location: '/project-a',
          scope: WorkspaceScope.project,
          root: 'a',
        ),
      ],
    );

    final projectState = skillScopeState(skill, projectRootId: 'a');
    expect(projectState.hasGlobalActivation, isTrue);
    expect(projectState.hasProjectActivation, isTrue);
    final otherProjectState = skillScopeState(skill, projectRootId: 'b');
    expect(otherProjectState.hasGlobalActivation, isTrue);
    expect(otherProjectState.hasProjectActivation, isFalse);
  });

  test('inactive is device-wide and does not depend on project selection', () {
    final skill = testSkill(
      slotKey: 'global-only',
      displayName: 'Global only',
      activations: [activation(location: '/global')],
    );

    expect(
      skillScopeState(skill, projectRootId: 'project-a').isInactive,
      isFalse,
    );
    expect(
      matchesInstalledSelection(
        skill,
        scope: InstalledScopeFilter.inactive,
        projectRootId: 'project-a',
        filter: const InstalledLocationFilter.all(),
      ),
      isFalse,
    );
  });

  test('detects Global activation overlap by Agent or shared group', () {
    final skill = testSkill(
      slotKey: 'overlap',
      displayName: 'Overlap',
      activations: [
        activation(location: '/global/claude', agentIds: const ['claude']),
        activation(
          location: '/global/shared',
          agentIds: const [universalAgentId],
        ),
      ],
    );
    final projectClaude = ActivationLocationGroup([
      target(
        'claude',
        scope: WorkspaceScope.project,
        root: 'project',
        location: '/project/claude',
      ),
    ]);
    final projectShared = ActivationLocationGroup([
      target(
        universalAgentId,
        scope: WorkspaceScope.project,
        root: 'project',
        location: '/project/shared',
      ),
      target(
        'codex',
        scope: WorkspaceScope.project,
        root: 'project',
        location: '/project/shared',
      ),
    ]);
    final projectCodex = ActivationLocationGroup([
      target(
        'codex',
        scope: WorkspaceScope.project,
        root: 'project',
        location: '/project/codex',
      ),
    ]);

    expect(
      hasGlobalActivationOverlap(skill: skill, projectGroup: projectClaude),
      isTrue,
    );
    expect(
      hasGlobalActivationOverlap(skill: skill, projectGroup: projectShared),
      isTrue,
    );
    expect(
      hasGlobalActivationOverlap(skill: skill, projectGroup: projectCodex),
      isFalse,
    );
  });

  test('a Global Agent can manage other Agents Global Skills', () {
    final filter = InstalledLocationFilter.location(
      activationLocationKey(WorkspaceScope.global, null, '/selected'),
    );
    final cases = [
      (locations: [activation(location: '/selected')], visible: true),
      (locations: [activation(location: '/other')], visible: true),
      (locations: <SkillActivationLocation>[], visible: true),
      (
        locations: [
          activation(
            location: '/project',
            scope: WorkspaceScope.project,
            root: 'a',
          ),
        ],
        visible: false,
      ),
      (
        locations: [
          activation(location: '/other'),
          activation(
            location: '/project',
            scope: WorkspaceScope.project,
            root: 'a',
          ),
        ],
        visible: true,
      ),
    ];
    for (final (index, scenario) in cases.indexed) {
      expect(
        matchesInstalledSelection(
          testSkill(
            slotKey: 'case-$index',
            displayName: 'Case $index',
            activations: scenario.locations,
          ),
          scope: InstalledScopeFilter.global,
          filter: filter,
        ),
        scenario.visible,
        reason: 'Global Agent candidate case $index',
      );
    }
    expect(
      matchesInstalledSelection(
        testSkill(slotKey: 'inactive', displayName: 'Inactive'),
        scope: InstalledScopeFilter.global,
        filter: const InstalledLocationFilter.location(null),
      ),
      isFalse,
    );
  });

  test('selecting a Project Agent still excludes other Project Agents', () {
    expect(
      matchesInstalledSelection(
        testSkill(
          slotKey: 'other',
          displayName: 'Other Agent',
          activations: [
            activation(
              location: '/project/other',
              scope: WorkspaceScope.project,
              root: 'a',
            ),
          ],
        ),
        scope: InstalledScopeFilter.project,
        projectRootId: 'a',
        filter: InstalledLocationFilter.location(
          activationLocationKey(
            WorkspaceScope.project,
            'a',
            '/project/selected',
          ),
        ),
      ),
      isFalse,
    );
  });

  test('selecting one Agent keeps candidates within the current Scope', () {
    final active = testSkill(
      slotKey: 'alpha',
      displayName: 'Alpha',
      activations: [activation(location: '/shared')],
    );
    final inactive = testSkill(slotKey: 'beta', displayName: 'Beta');
    final key = activationLocationKey(WorkspaceScope.global, null, '/shared');

    expect(
      matchesInstalledSelection(
        active,
        scope: InstalledScopeFilter.global,
        filter: InstalledLocationFilter.location(key),
      ),
      isTrue,
    );
    expect(
      matchesInstalledSelection(
        inactive,
        scope: InstalledScopeFilter.global,
        filter: InstalledLocationFilter.location(key),
      ),
      isTrue,
    );

    final globalOnly = active;
    final projectOnly = testSkill(
      slotKey: 'project',
      displayName: 'Project',
      activations: [
        activation(
          location: '/project/shared',
          scope: WorkspaceScope.project,
          root: 'project-a',
        ),
      ],
    );
    final projectKey = activationLocationKey(
      WorkspaceScope.project,
      'project-a',
      '/project/shared',
    );
    expect(
      matchesInstalledSelection(
        globalOnly,
        scope: InstalledScopeFilter.project,
        projectRootId: 'project-a',
        filter: InstalledLocationFilter.location(projectKey),
      ),
      isFalse,
    );
    expect(
      matchesInstalledSelection(
        projectOnly,
        scope: InstalledScopeFilter.project,
        projectRootId: 'project-a',
        filter: InstalledLocationFilter.location(projectKey),
      ),
      isTrue,
    );

    // Inactive stays the reach bucket, so an Agent selection cannot pull an
    // activated Skill into it.
    expect(
      matchesInstalledSelection(
        active,
        scope: InstalledScopeFilter.inactive,
        filter: InstalledLocationFilter.location(key),
      ),
      isFalse,
    );
    expect(
      matchesInstalledSelection(
        inactive,
        scope: InstalledScopeFilter.inactive,
        filter: InstalledLocationFilter.location(key),
      ),
      isTrue,
    );
  });

  test('the badge counts Activation Locations, not recorded Agent IDs', () {
    WorkspaceActivationTarget target(
      String agentId,
      String location, {
      bool detected = true,
      WorkspaceScope scope = WorkspaceScope.global,
      String? root,
    }) => WorkspaceActivationTarget(
      agentId: agentId,
      displayName: agentId,
      detected: detected,
      location: location,
      scope: scope,
      projectRootId: root,
    );

    const shared = '/home/test/.agents/skills';
    const claude = '/home/test/.claude/skills';
    const kiro = '/home/test/.kiro/skills';
    // The record lists every Agent convention mapped to the directory. Eight of
    // them share it, so counting IDs would report eight switches where the
    // Scope offers one.
    final sharedSkill = testSkill(
      slotKey: 'shared',
      displayName: 'Shared',
      activations: [
        activation(
          location: shared,
          agentIds: const ['codex', 'opencode', 'universal', 'aider', 'cline'],
        ),
      ],
    );
    final groups = groupActivationLocations([
      target('codex', shared),
      target('opencode', shared),
      target('universal', shared, detected: false),
      target('claude-code', claude),
      target('kiro-cli', kiro),
    ]);
    expect(groups, hasLength(3));

    final sharedReach = activationReachInScope(
      sharedSkill,
      groups: groups,
      scope: InstalledScopeFilter.global,
    );
    expect(sharedReach.enabled, 1);
    expect(sharedReach.total, 3);
    expect(
      activationReachInScope(
        sharedSkill,
        groups: groups.where((g) => g.location != shared),
        scope: InstalledScopeFilter.global,
      ),
      (enabled: 0, total: 2),
    );
    expect(
      matchesInstalledSelection(
        sharedSkill,
        scope: InstalledScopeFilter.inactive,
        filter: const InstalledLocationFilter.all(),
      ),
      isFalse,
    );

    // The same Agent reached globally and inside a Project is two locations,
    // and each Scope only counts what it can reach.
    final everywhere = testSkill(
      slotKey: 'both',
      displayName: 'Both',
      activations: [
        activation(location: claude),
        activation(
          location: '/a/.claude/skills',
          scope: WorkspaceScope.project,
          root: 'a',
        ),
      ],
    );
    expect(
      activationReachInScope(
        everywhere,
        groups: groups,
        scope: InstalledScopeFilter.global,
      ),
      (enabled: 1, total: 3),
    );
    expect(
      activationReachInScope(
        everywhere,
        groups: const [],
        scope: InstalledScopeFilter.project,
        projectRootId: 'a',
      ),
      // Persisted Activations cannot add roster groups back to the count.
      (enabled: 0, total: 0),
    );
    expect(
      activationReachInScope(
        everywhere,
        groups: groups,
        scope: InstalledScopeFilter.project,
        projectRootId: 'b',
      ),
      (enabled: 0, total: 3),
    );
    expect(
      activationReachInScope(
        testSkill(slotKey: 'never', displayName: 'Never'),
        groups: groups,
        scope: InstalledScopeFilter.global,
      ),
      (enabled: 0, total: 3),
    );
    expect(
      activationReachInScope(
        everywhere,
        groups: groups,
        scope: InstalledScopeFilter.inactive,
      ),
      (enabled: 0, total: 0),
    );
  });

  test('late target inspection cannot overwrite the new scope', () async {
    final first = Completer<WorkspaceCompletion<List<AgentOption>>>();
    final repo = FakeSkillAcquisitionRepository()
      ..targetInspectionHandler = (scope, _) =>
          scope == SkillActivationScope.global
          ? first.future
          : Future.value(
              WorkspaceCompleted(
                value: const [
                  AgentOption(
                    id: 'codex',
                    displayName: 'Codex',
                    location: '/project/.agents/skills',
                  ),
                ],
              ),
            );
    final container = ProviderContainer(
      overrides: [
        skillAcquisitionRepositoryProvider.overrideWithValue(repo),
        deviceAgentMembersProvider.overrideWithValue(
          const AsyncData({'codex'}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(skillAcquisitionViewModelProvider.notifier);
    final pending = vm.loadTargets(scope: SkillActivationScope.global);
    expect(vm.loadingTargets, isTrue);
    expect(vm.canInstall, isFalse);
    await vm.loadTargets(
      scope: SkillActivationScope.project,
      projectRootId: 'p',
    );
    first.complete(WorkspaceCompleted(value: repo.agents));
    await pending;
    expect(vm.locationGroups.single.location, '/project/.agents/skills');
    expect(vm.selectedLocations.single.projectRootId, 'p');
    expect(vm.loadingTargets, isFalse);
  });

  test('membership changes and refresh preserve selection intent', () async {
    var agents = const [
      AgentOption(id: 'codex', displayName: 'Codex', location: '/shared'),
      AgentOption(
        id: 'custom',
        displayName: 'Custom',
        location: '/custom',
        detected: false,
      ),
    ];
    final repo = FakeSkillAcquisitionRepository()
      ..targetInspectionHandler = (_, _) async =>
          WorkspaceCompleted(value: agents);
    final container = ProviderContainer(
      overrides: [
        skillAcquisitionRepositoryProvider.overrideWithValue(repo),
        deviceAgentMembersProvider.overrideWithValue(
          const AsyncData({'codex', 'custom'}),
        ),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(skillAcquisitionViewModelProvider.notifier);
    await vm.loadTargets(scope: SkillActivationScope.global);
    expect(vm.visibleLocations, hasLength(2));
    vm.selectAllLocations(true);
    expect(vm.selectedLocations, hasLength(2));
    vm.toggleLocation(
      vm.locationGroups.firstWhere((g) => g.detected).key,
      false,
    );
    expect(vm.selectedLocations.single.location, '/custom');
    agents = const [
      AgentOption(id: 'codex', displayName: 'Codex', location: '/shared'),
    ];
    await vm.loadTargets(scope: SkillActivationScope.global);
    expect(vm.selectedLocations, isEmpty);
  });
}
