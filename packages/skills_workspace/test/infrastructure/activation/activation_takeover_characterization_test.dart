import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_occupancy_inspector.dart';
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/domain/activation_selection.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/activation/file_system_activation_occupancy_probe.dart';
import 'package:skills_workspace/src/infrastructure/content/filesystem_skill_tree_reader.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory activationLocation;
  late ActivationOccupancyInspector inspector;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-takeover-',
    );
    activationLocation = Directory(
      path.join(temporaryDirectory.path, 'agent-skills'),
    );
    await activationLocation.create();
    final catalog = AgentCatalog.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(matches: (_, _) => true),
      builtIns: <AgentDefinition>[
        AgentDefinition(
          id: 'agent',
          displayName: 'Agent',
          platforms: <DesktopPlatform, AgentPlatformDefinition>{
            DesktopPlatform.macos: AgentPlatformDefinition(
              globalSkillsPath: activationLocation.path,
              detectionPaths: <AgentDetectionPath>[
                AgentDetectionPath.absolute(activationLocation.path),
              ],
            ),
          },
        ),
      ],
    ).valueOrNull!;
    final identity = const PosixActivationLocationIdentity();
    inspector = ActivationOccupancyInspector(
      targetResolver: ActivationTargetResolver(
        catalog: catalog,
        symbolicLinkCapability: FakeSymbolicLinkCapability(),
        locationIdentity: identity,
      ),
      locationIdentity: identity,
      occupancyProbe: FileSystemActivationOccupancyProbe(
        repositoryCopyPathForSkill: (skill) =>
            path.join(temporaryDirectory.path, 'repository', skill.slotKey),
        locationIdentity: identity,
      ),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'multi-Skill inspection reports only occupied targets and writes nothing',
    () async {
      final alphaSource = await _writeSkill(
        path.join(temporaryDirectory.path, 'sources', 'alpha'),
        name: 'alpha',
        body: 'alpha',
      );
      final betaSource = await _writeSkill(
        path.join(temporaryDirectory.path, 'sources', 'beta'),
        name: 'beta',
        body: 'managed beta',
      );
      final occupiedBeta = await _writeSkill(
        path.join(activationLocation.path, 'beta'),
        name: 'beta',
        body: 'external beta',
      );
      final alpha = await _skill(
        alphaSource,
        id: '00000000-0000-4000-8000-000000000001',
        slotKey: 'alpha',
      );
      final beta = await _skill(
        betaSource,
        id: '00000000-0000-4000-8000-000000000002',
        slotKey: 'beta',
      );
      final before = await File(
        path.join(occupiedBeta.path, 'SKILL.md'),
      ).readAsBytes();

      final result = await inspector.inspect(
        snapshot: RepositorySnapshot(
          revision: RepositoryRevision.initial(),
          managedSkills: <ManagedSkill>[beta, alpha],
        ),
        managedSkillIds: <ManagedSkillId>{alpha.id, beta.id},
        selection: ActivationSelection.explicit(<ActivationTarget>[
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
        mode: RequestedActivationMode.copy,
      );

      expect(result.valueOrNull!.occupancies, hasLength(1));
      expect(result.valueOrNull!.occupancies.single.slotKey, 'beta');
      expect(
        result.valueOrNull!.occupancies.single.contentRelation,
        InspectedActivationContentRelation.differsFromCurrentRevision,
      );
      expect(result.valueOrNull!.canReplace, isTrue);
      expect(result.valueOrNull!.allContentMatches, isFalse);
      expect(
        await Directory(path.join(activationLocation.path, 'alpha')).exists(),
        isFalse,
      );
      expect(
        await File(path.join(occupiedBeta.path, 'SKILL.md')).readAsBytes(),
        before,
      );
    },
  );

  test(
    'identical unmanaged content is explicitly recognizable for takeover',
    () async {
      final source = await _writeSkill(
        path.join(temporaryDirectory.path, 'source'),
        name: 'review',
        body: 'identical',
      );
      await _writeSkill(
        path.join(activationLocation.path, 'review'),
        name: 'review',
        body: 'identical',
      );
      final skill = await _skill(
        source,
        id: '00000000-0000-4000-8000-000000000001',
        slotKey: 'review',
      );

      final result = await inspector.inspect(
        snapshot: RepositorySnapshot(
          revision: RepositoryRevision.initial(),
          managedSkills: <ManagedSkill>[skill],
        ),
        managedSkillIds: <ManagedSkillId>{skill.id},
        selection: ActivationSelection.explicit(<ActivationTarget>[
          ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ]),
        mode: RequestedActivationMode.copy,
      );

      expect(result.valueOrNull!.occupancies, hasLength(1));
      expect(result.valueOrNull!.allContentMatches, isTrue);
      expect(result.valueOrNull!.canReplace, isTrue);
    },
  );
}

Future<Directory> _writeSkill(
  String directoryPath, {
  required String name,
  required String body,
}) async {
  final directory = Directory(directoryPath);
  await directory.create(recursive: true);
  await File(path.join(directory.path, 'SKILL.md')).writeAsString('''
---
name: $name
description: Example Skill
---
$body
''');
  return directory;
}

Future<ManagedSkill> _skill(
  Directory source, {
  required String id,
  required String slotKey,
}) async {
  final tree = (await const FilesystemSkillTreeReader().read(
    source.path,
  )).valueOrNull!;
  return ManagedSkill(
    id: ManagedSkillId(id),
    slotKey: slotKey,
    declaredName: slotKey,
    displayName: slotKey,
    description: '$slotKey Skill',
    source: LocalSourceDescriptor(locator: source.path),
    currentRevision: ManagedSkillRevisionSummary(
      contentHash: tree.contentHash,
      fileCount: tree.fileCount,
      byteSize: tree.byteSize,
      publishedAt: DateTime.utc(2026),
    ),
  );
}
