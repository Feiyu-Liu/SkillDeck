import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/application/discovery/external_discovery_models.dart';
import 'package:skills_workspace/src/application/discovery/external_skill_scanner.dart';
import 'package:skills_workspace/src/domain/activation_selection.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';
import '../../support/discovery/discovery_fakes.dart';

void main() {
  late FakeExternalSkillLocationPort locationPort;

  setUp(() {
    locationPort = FakeExternalSkillLocationPort();
  });

  test('preserves exact Local source selection for later Adoption', () async {
    final location = _platformLocation('/agents/skills');
    final scanned = _scanned(
      location: path.join(location, 'group', 'review'),
      locator: location,
      skillPath: 'group/review',
      slotKey: 'review',
      hash: 'a' * 64,
    );
    locationPort.results[location] =
        ExternalDiscoverySuccess<List<ScannedExternalSkill>>(
          value: <ScannedExternalSkill>[scanned],
        );
    final scanner = _scanner(locationPort, <AgentDefinition>[
      _definition('agent', location),
    ]);

    final result = await scanner.scanSelection(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
      ]),
      snapshot: RepositorySnapshot.empty(),
      includeInternal: false,
    );

    final occurrence = result.valueOrNull!.occurrencesBySlot['review']!.single;
    expect(occurrence.skillLocation, path.join(location, 'group', 'review'));
    expect(occurrence.source.locator, location);
    expect(occurrence.source.skillPath, 'group/review');
  });

  test('same Slot and hash aggregate locations and Agent IDs', () async {
    final a = _platformLocation('/a');
    final b = _platformLocation('/b');
    final aSkill = path.join(a, 'review');
    final bSkill = path.join(b, 'review');
    locationPort.results[a] = _success(<ScannedExternalSkill>[
      _scanned(location: aSkill, slotKey: 'review', hash: 'a' * 64),
    ]);
    locationPort.results[b] = _success(<ScannedExternalSkill>[
      _scanned(location: bSkill, slotKey: 'review', hash: 'a' * 64),
    ]);
    final scanner = _scanner(locationPort, <AgentDefinition>[
      _definition('z-agent', b),
      _definition('a-agent', a),
    ]);

    final resolved = scanner.resolveAllLocations(RepositorySnapshot.empty());
    final result = await scanner.scanTargets(
      resolved.valueOrNull!,
      snapshot: RepositorySnapshot.empty(),
      includeInternal: false,
    );

    final candidate = result.valueOrNull!.discovery.candidates.single;
    expect(candidate.locations, <String>[aSkill, bSkill]);
    expect(candidate.agentIds, <String>['a-agent', 'z-agent']);
    expect(result.valueOrNull!.discovery.conflicts, isEmpty);
    expect(locationPort.scannedLocations, <String>[a, b]);
  });

  test('targeted scan filters every known location by selected Slot', () async {
    final a = _platformLocation('/a');
    final b = _platformLocation('/b');
    locationPort.results[a] = _success(<ScannedExternalSkill>[
      _scanned(
        location: path.join(a, 'selected'),
        slotKey: 'selected',
        hash: 'a' * 64,
      ),
      _scanned(
        location: path.join(a, 'unrelated'),
        slotKey: 'unrelated',
        hash: 'b' * 64,
      ),
    ]);
    locationPort.results[b] = _success(<ScannedExternalSkill>[
      _scanned(
        location: path.join(b, 'selected'),
        slotKey: 'selected',
        hash: 'a' * 64,
      ),
    ]);
    final scanner = _scanner(locationPort, <AgentDefinition>[
      _definition('a', a),
      _definition('b', b),
    ]);

    final result = await scanner.scanTargets(
      scanner.resolveAllLocations(RepositorySnapshot.empty()).valueOrNull!,
      snapshot: RepositorySnapshot.empty(),
      includeInternal: false,
      selectedSlotKeys: const <String>{'selected'},
    );

    expect(result.valueOrNull!.occurrencesBySlot.keys, <String>['selected']);
    expect(locationPort.scannedLocations, <String>[a, b]);
    expect(locationPort.selectedSlotKeyRequests, <Set<String>?>[
      const <String>{'selected'},
      const <String>{'selected'},
    ]);
  });

  test('compatibility discovery reports only canonical destinations', () async {
    final canonical = _platformLocation('/canonical');
    final legacy = _platformLocation('/legacy');
    final legacySkill = path.join(legacy, 'review');
    locationPort.results[canonical] = _success(const <ScannedExternalSkill>[]);
    locationPort.results[legacy] = _success(<ScannedExternalSkill>[
      _scanned(location: legacySkill, slotKey: 'review', hash: 'a' * 64),
    ]);
    final scanner = _scanner(locationPort, <AgentDefinition>[
      _definition('agent', canonical, globalDiscoveryPaths: <String>[legacy]),
    ]);

    final result = await scanner.scanTargets(
      scanner.resolveAllLocations(RepositorySnapshot.empty()).valueOrNull!,
      snapshot: RepositorySnapshot.empty(),
      includeInternal: false,
    );

    final candidate = result.valueOrNull!.discovery.candidates.single;
    expect(candidate.locations, <String>[legacySkill]);
    expect(candidate.destinationLocations, <String>[
      path.join(canonical, 'review'),
    ]);
  });

  test(
    'one shared compatibility path retains every canonical target',
    () async {
      final sharedLegacy = _platformLocation('/shared-legacy');
      final firstCanonical = _platformLocation('/canonical-a');
      final secondCanonical = _platformLocation('/canonical-b');
      final legacySkill = path.join(sharedLegacy, 'review');
      locationPort.results[firstCanonical] = _success(
        const <ScannedExternalSkill>[],
      );
      locationPort.results[secondCanonical] = _success(
        const <ScannedExternalSkill>[],
      );
      locationPort.results[sharedLegacy] = _success(<ScannedExternalSkill>[
        _scanned(location: legacySkill, slotKey: 'review', hash: 'a' * 64),
      ]);
      final scanner = _scanner(locationPort, <AgentDefinition>[
        _definition(
          'agent-a',
          firstCanonical,
          globalDiscoveryPaths: <String>[sharedLegacy],
        ),
        _definition(
          'agent-b',
          secondCanonical,
          globalDiscoveryPaths: <String>[sharedLegacy],
        ),
      ]);

      final result = await scanner.scanTargets(
        scanner.resolveAllLocations(RepositorySnapshot.empty()).valueOrNull!,
        snapshot: RepositorySnapshot.empty(),
        includeInternal: false,
      );

      final candidate = result.valueOrNull!.discovery.candidates.single;
      expect(candidate.agentIds, <String>['agent-a', 'agent-b']);
      expect(candidate.destinationLocations, <String>[
        path.join(firstCanonical, 'review'),
        path.join(secondCanonical, 'review'),
      ]);
      expect(
        locationPort.scannedLocations.where((path) => path == sharedLegacy),
        hasLength(1),
      );
    },
  );

  test('same Slot with divergent content is one explicit conflict', () async {
    final a = _platformLocation('/a');
    final b = _platformLocation('/b');
    final aSkill = path.join(a, 'review');
    final bSkill = path.join(b, 'review');
    locationPort.results[a] = _success(<ScannedExternalSkill>[
      _scanned(location: aSkill, slotKey: 'review', hash: 'a' * 64),
    ]);
    locationPort.results[b] = _success(<ScannedExternalSkill>[
      _scanned(location: bSkill, slotKey: 'review', hash: 'b' * 64),
    ]);
    final scanner = _scanner(locationPort, <AgentDefinition>[
      _definition('a', a),
      _definition('b', b),
    ]);

    final result = await scanner.scanTargets(
      scanner.resolveAllLocations(RepositorySnapshot.empty()).valueOrNull!,
      snapshot: RepositorySnapshot.empty(),
      includeInternal: false,
    );

    expect(result.valueOrNull!.discovery.candidates, isEmpty);
    expect(result.valueOrNull!.discovery.conflicts, hasLength(1));
    expect(
      result.valueOrNull!.discovery.conflicts.single.contentHashByLocation,
      <String, String>{aSkill: 'a' * 64, bSkill: 'b' * 64},
    );
    // Each copy names the Agent whose folder holds it, so a reviewer can
    // choose by Agent.
    expect(
      result.valueOrNull!.discovery.conflicts.single.agentIdsByLocation,
      <String, List<String>>{
        aSkill: <String>['a'],
        bSkill: <String>['b'],
      },
    );
  });

  test(
    'managed Slots and managed Activation paths are not rediscovered',
    () async {
      final location = _platformLocation('/agents');
      locationPort.results[location] = _success(<ScannedExternalSkill>[
        _scanned(
          location: path.join(location, 'managed-slot'),
          slotKey: 'managed-slot',
          hash: 'a' * 64,
        ),
        _scanned(
          location: path.join(location, 'managed-path'),
          slotKey: 'other-slot',
          hash: 'b' * 64,
        ),
        _scanned(
          location: path.join(location, 'external'),
          slotKey: 'external',
          hash: 'c' * 64,
        ),
      ]);
      final managedSlot = _managedSkill(
        id: '00000000-0000-4000-8000-000000000001',
        slotKey: 'managed-slot',
      );
      final managedPath = _managedSkill(
        id: '00000000-0000-4000-8000-000000000002',
        slotKey: 'managed-path',
        activationLocation: location,
      );
      final scanner = _scanner(locationPort, <AgentDefinition>[
        _definition('agent', location),
      ]);

      final result = await scanner.scanSelection(
        selection: ActivationSelection.explicit(<ActivationTarget>[
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
        snapshot: RepositorySnapshot(
          revision: RepositoryRevision.initial(),
          managedSkills: <ManagedSkill>[managedSlot, managedPath],
        ),
        includeInternal: false,
      );

      expect(
        result.valueOrNull!.discovery.candidates.map((item) => item.slotKey),
        <String>['external'],
      );
    },
  );

  test(
    'all-known resolution uses registered roots only and groups locations',
    () {
      final scanner = _scanner(locationPort, <AgentDefinition>[
        _definition(
          'shared-a',
          _platformLocation('/shared'),
          projectPath: '.agents/skills',
        ),
        _definition('shared-b', _platformLocation('/shared')),
      ]);
      final registered = _platformLocation('/registered');
      final snapshot = RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[
          ProjectRoot(id: 'registered', path: registered),
        ],
      );

      final result = scanner.resolveAllLocations(snapshot);

      expect(result.valueOrNull, hasLength(2));
      expect(
        result.valueOrNull!.first.location,
        path.join(registered, '.agents', 'skills'),
      );
      expect(result.valueOrNull!.last.location, _platformLocation('/shared'));
      expect(result.valueOrNull!.last.agentIds, <String>[
        'shared-a',
        'shared-b',
      ]);
      expect(
        result.valueOrNull!.any(
          (target) => target.location.contains('unknown'),
        ),
        isFalse,
      );
    },
  );

  test('conflicting provenance at one location fails before scanning', () {
    final scanner = _scanner(locationPort, <AgentDefinition>[
      _definition(
        'agent',
        path.join(_platformLocation('/project'), 'skills'),
        projectPath: 'skills',
      ),
    ]);
    final snapshot = RepositorySnapshot(
      revision: RepositoryRevision.initial(),
      projectRoots: <ProjectRoot>[
        ProjectRoot(id: 'project', path: _platformLocation('/project')),
      ],
    );

    final result = scanner.resolveAllLocations(snapshot);

    expect(
      result.failureOrNull?.code,
      ExternalDiscoveryFailureCode.activationUnsupported,
    );
    expect(
      result.failureOrNull?.context['reason'],
      'conflictingLocationProvenance',
    );
    expect(locationPort.scannedLocations, isEmpty);
  });

  test('pre-cancelled discovery never invokes the location adapter', () async {
    final scanner = _scanner(locationPort, <AgentDefinition>[
      _definition('agent', '/agents'),
    ]);
    final cancellation = CancellationSource();
    await cancellation.cancel();

    final result = await scanner.scanTargets(
      scanner.resolveAllLocations(RepositorySnapshot.empty()).valueOrNull!,
      snapshot: RepositorySnapshot.empty(),
      includeInternal: false,
      cancellationToken: cancellation.token,
    );

    expect(
      result.failureOrNull?.code,
      ExternalDiscoveryFailureCode.operationCancelled,
    );
    expect(locationPort.scannedLocations, isEmpty);
  });
}

ExternalSkillScanner _scanner(
  FakeExternalSkillLocationPort port,
  List<AgentDefinition> definitions,
) {
  final catalog = AgentCatalog.create(
    platform: DesktopPlatform.macos,
    detectionPort: FakeAgentDetectionPort(),
    builtIns: definitions,
  ).valueOrNull!;
  const identity = PosixActivationLocationIdentity();
  return ExternalSkillScanner(
    catalog: catalog,
    activationTargetResolver: ActivationTargetResolver(
      catalog: catalog,
      symbolicLinkCapability: FakeSymbolicLinkCapability(),
      locationIdentity: identity,
    ),
    locationIdentity: identity,
    locationPort: port,
  );
}

AgentDefinition _definition(
  String id,
  String globalPath, {
  String? projectPath,
  List<String> globalDiscoveryPaths = const <String>[],
  List<String> projectDiscoveryPaths = const <String>[],
}) => AgentDefinition(
  id: id,
  displayName: id,
  platforms: <DesktopPlatform, AgentPlatformDefinition>{
    DesktopPlatform.macos: AgentPlatformDefinition(
      globalSkillsPath: globalPath,
      projectSkillsPath: projectPath,
      globalDiscoverySkillsPaths: globalDiscoveryPaths,
      projectDiscoverySkillsPaths: projectDiscoveryPaths,
    ),
  },
);

ScannedExternalSkill _scanned({
  required String location,
  required String slotKey,
  required String hash,
  String? locator,
  String skillPath = '',
}) => ScannedExternalSkill(
  declaredName: slotKey,
  description: '$slotKey Skill',
  slotKey: slotKey,
  contentHash: hash,
  skillLocation: location,
  source: LocalSourceDescriptor(
    locator: locator ?? location,
    skillPath: skillPath,
  ),
);

ExternalDiscoverySuccess<List<ScannedExternalSkill>> _success(
  List<ScannedExternalSkill> skills,
) => ExternalDiscoverySuccess<List<ScannedExternalSkill>>(value: skills);

String _platformLocation(String value) => path.normalize(path.absolute(value));

ManagedSkill _managedSkill({
  required String id,
  required String slotKey,
  String? activationLocation,
}) => ManagedSkill(
  id: ManagedSkillId(id),
  slotKey: slotKey,
  declaredName: slotKey,
  displayName: slotKey,
  description: '$slotKey Skill',
  source: LocalSourceDescriptor(locator: '/source/$slotKey'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: 'f' * 64,
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026),
  ),
  activations: activationLocation == null
      ? const <SkillActivation>[]
      : <SkillActivation>[
          SkillActivation(
            location: activationLocation,
            scope: ActivationScope.global,
            mode: ActivationMode.copy,
            agentIds: const <String>['agent'],
          ),
        ],
);
