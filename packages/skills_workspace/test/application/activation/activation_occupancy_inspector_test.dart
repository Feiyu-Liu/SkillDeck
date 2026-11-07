import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_occupancy_inspector.dart';
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/domain/activation_selection.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  late RecordingActivationOccupancyProbe probe;
  late ActivationOccupancyInspector inspector;

  setUp(() {
    probe = RecordingActivationOccupancyProbe();
    final activationLocation = _platformLocation('/activation');
    final definition = AgentDefinition(
      id: 'agent',
      displayName: 'Agent',
      platforms: <DesktopPlatform, AgentPlatformDefinition>{
        DesktopPlatform.macos: AgentPlatformDefinition(
          globalSkillsPath: activationLocation,
          detectionPaths: <AgentDetectionPath>[
            AgentDetectionPath.absolute(_platformLocation('/detect/agent')),
          ],
        ),
      },
    );
    final catalog = AgentCatalog.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(matches: (_, _) => true),
      builtIns: <AgentDefinition>[definition],
    ).valueOrNull!;
    final resolver = ActivationTargetResolver(
      catalog: catalog,
      symbolicLinkCapability: FakeSymbolicLinkCapability(),
      locationIdentity: const PosixActivationLocationIdentity(),
    );
    inspector = ActivationOccupancyInspector(
      targetResolver: resolver,
      locationIdentity: const PosixActivationLocationIdentity(),
      occupancyProbe: probe,
    );
  });

  test('skips vacant and already managed target locations', () async {
    final alreadyManaged = _skill(
      id: '00000000-0000-4000-8000-000000000001',
      slotKey: 'managed',
      activations: <SkillActivation>[
        SkillActivation(
          location: _platformLocation('/activation'),
          scope: ActivationScope.global,
          mode: ActivationMode.copy,
          agentIds: const <String>['agent'],
        ),
      ],
    );
    final vacant = _skill(
      id: '00000000-0000-4000-8000-000000000002',
      slotKey: 'vacant',
    );

    final result = await inspector.inspect(
      snapshot: _snapshot(<ManagedSkill>[alreadyManaged, vacant]),
      managedSkillIds: <ManagedSkillId>{alreadyManaged.id, vacant.id},
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
      ]),
      mode: RequestedActivationMode.copy,
    );

    expect(result.valueOrNull!.occupancies, isEmpty);
    expect(probe.inspectedPaths, <String>[
      path.join(_platformLocation('/activation'), 'vacant'),
    ]);
  });

  test('aggregates occupied targets in stable managed-Skill order', () async {
    final later = _skill(
      id: '00000000-0000-4000-8000-000000000002',
      slotKey: 'later',
    );
    final earlier = _skill(
      id: '00000000-0000-4000-8000-000000000001',
      slotKey: 'earlier',
    );
    for (final skill in <ManagedSkill>[earlier, later]) {
      final targetPath = path.join(
        _platformLocation('/activation'),
        skill.slotKey,
      );
      probe.results[targetPath] = _occupancy(skill, targetPath);
    }

    final result = await inspector.inspect(
      snapshot: _snapshot(<ManagedSkill>[later, earlier]),
      managedSkillIds: <ManagedSkillId>{later.id, earlier.id},
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
      ]),
      mode: RequestedActivationMode.copy,
    );

    expect(
      result.valueOrNull!.occupancies.map((entry) => entry.slotKey),
      <String>['earlier', 'later'],
    );
    expect(result.valueOrNull!.canReplace, isTrue);
    expect(result.valueOrNull!.allContentMatches, isTrue);
  });

  test('missing managed Skill fails before probing', () async {
    final missing = ManagedSkillId('00000000-0000-4000-8000-000000000099');

    final result = await inspector.inspect(
      snapshot: RepositorySnapshot.empty(),
      managedSkillIds: <ManagedSkillId>{missing},
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
      ]),
      mode: RequestedActivationMode.copy,
    );

    expect(result.failureOrNull?.code, ActivationFailureCode.skillNotFound);
    expect(result.failureOrNull?.context['managedSkillId'], missing.value);
    expect(probe.inspectedPaths, isEmpty);
  });

  test('cancellation before resolution prevents probes', () async {
    final source = CancellationSource();
    await source.cancel();
    final skill = _skill(
      id: '00000000-0000-4000-8000-000000000001',
      slotKey: 'skill',
    );

    final result = await inspector.inspect(
      snapshot: _snapshot(<ManagedSkill>[skill]),
      managedSkillIds: <ManagedSkillId>{skill.id},
      selection: const ActivationSelection.automatic(),
      mode: RequestedActivationMode.copy,
      cancellationToken: source.token,
    );

    expect(
      result.failureOrNull?.code,
      ActivationFailureCode.operationCancelled,
    );
    expect(probe.inspectedPaths, isEmpty);
  });

  test(
    'probe failure stops aggregation without hiding resolver warnings',
    () async {
      final skill = _skill(
        id: '00000000-0000-4000-8000-000000000001',
        slotKey: 'skill',
      );
      probe.failures[path.join(
        _platformLocation('/activation'),
        'skill',
      )] = ActivationFailure<InspectedActivationOccupancy?>(
        code: ActivationFailureCode.activationUnavailable,
        context: const <String, Object?>{'reason': 'unreadable'},
      );

      final result = await inspector.inspect(
        snapshot: _snapshot(<ManagedSkill>[skill]),
        managedSkillIds: <ManagedSkillId>{skill.id},
        selection: ActivationSelection.explicit(<ActivationTarget>[
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
        mode: RequestedActivationMode.copy,
      );

      expect(
        result.failureOrNull?.code,
        ActivationFailureCode.activationUnavailable,
      );
      expect(result.failureOrNull?.context['reason'], 'unreadable');
    },
  );
}

RepositorySnapshot _snapshot(List<ManagedSkill> skills) => RepositorySnapshot(
  revision: RepositoryRevision.initial(),
  managedSkills: skills,
);

ManagedSkill _skill({
  required String id,
  required String slotKey,
  List<SkillActivation> activations = const <SkillActivation>[],
}) => ManagedSkill(
  id: ManagedSkillId(id),
  slotKey: slotKey,
  declaredName: slotKey,
  displayName: slotKey,
  description: '$slotKey Skill',
  source: LocalSourceDescriptor(locator: '/source/$slotKey'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash: 'a' * 64,
    fileCount: 1,
    byteSize: 1,
    publishedAt: DateTime.utc(2026),
  ),
  activations: activations,
);

InspectedActivationOccupancy _occupancy(
  ManagedSkill skill,
  String targetPath,
) => InspectedActivationOccupancy(
  managedSkillId: skill.id,
  slotKey: skill.slotKey,
  target: ResolvedActivationTarget(
    location: _platformLocation('/activation'),
    scope: ActivationScope.global,
    mode: ActivationMode.copy,
    agentIds: const <String>['agent'],
  ),
  targetPath: targetPath,
  kind: InspectedActivationOccupancyKind.skillDirectory,
  contentRelation: InspectedActivationContentRelation.matchesCurrentRevision,
  fingerprint: 'fingerprint:${skill.slotKey}',
  replaceable: true,
);

String _platformLocation(String value) => path.normalize(path.absolute(value));
