import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/application/agents/built_in_agent_definitions.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/infrastructure/agents/file_system_agent_detection.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-agent-catalog-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('built-in catalog preserves all 73 reference Agent IDs', () {
    final definitions = buildBuiltInAgentDefinitions(
      platform: DesktopPlatform.macos,
      environment: <String, String>{'HOME': temporaryDirectory.path},
    );

    expect(definitions, hasLength(73));
    expect(
      definitions.map((definition) => definition.id).toSet(),
      hasLength(73),
    );
    expect(
      definitions.map((definition) => definition.id),
      containsAll(<String>[
        'amp',
        'claude-code',
        'codex',
        'cursor',
        'gemini-cli',
        'opencode',
        'warp',
        'universal',
      ]),
    );
  });

  test('additional Agents cannot override a built-in ID', () {
    final custom = _definition(
      id: 'codex',
      globalPath: path.join(temporaryDirectory.path, 'skills'),
    );
    final result = AgentCatalog.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(),
      builtIns: <AgentDefinition>[custom],
      additional: <AgentDefinition>[custom],
    );

    expect(result.failureOrNull?.code, ActivationFailureCode.duplicateAgentId);
  });

  test('resolves global and registered Project Root locations', () {
    final catalog = AgentCatalog.create(
      platform: DesktopPlatform.linux,
      detectionPort: FakeAgentDetectionPort(),
      builtIns: <AgentDefinition>[
        _definition(
          id: 'test',
          globalPath: path.join(temporaryDirectory.path, 'global'),
          projectPath: '.agents/skills',
          platform: DesktopPlatform.linux,
        ),
      ],
    ).valueOrNull!;
    final projectRoot = ProjectRoot(
      id: 'project',
      path: path.join(temporaryDirectory.path, 'project'),
    );

    final global = catalog.resolve(
      agentId: 'test',
      scope: ActivationScope.global,
    );
    final project = catalog.resolve(
      agentId: 'test',
      scope: ActivationScope.project,
      projectRoot: projectRoot,
    );

    expect(
      global.valueOrNull!.location,
      path.join(temporaryDirectory.path, 'global'),
    );
    expect(
      project.valueOrNull!.location,
      path.join(projectRoot.path, '.agents', 'skills'),
    );
    expect(project.valueOrNull!.projectRootId, 'project');
    expect(project.valueOrNull!.projectRootPath, projectRoot.path);
  });

  test('resolves canonical and compatibility discovery paths separately', () {
    final canonicalGlobal = path.join(temporaryDirectory.path, 'canonical');
    final legacyGlobal = path.join(temporaryDirectory.path, 'legacy');
    final projectRoot = ProjectRoot(
      id: 'project',
      path: path.join(temporaryDirectory.path, 'project'),
    );
    final definition = AgentDefinition(
      id: 'test',
      displayName: 'Test',
      platforms: <DesktopPlatform, AgentPlatformDefinition>{
        DesktopPlatform.macos: AgentPlatformDefinition(
          globalSkillsPath: canonicalGlobal,
          projectSkillsPath: '.agents/skills',
          globalDiscoverySkillsPaths: <String>[legacyGlobal, canonicalGlobal],
          projectDiscoverySkillsPaths: const <String>[
            '.legacy/skills',
            '.agents/skills',
          ],
        ),
      },
    );
    final catalog = AgentCatalog.create(
      platform: DesktopPlatform.macos,
      detectionPort: FakeAgentDetectionPort(),
      builtIns: <AgentDefinition>[definition],
    ).valueOrNull!;

    final global = catalog
        .resolveDiscovery(agentId: 'test', scope: ActivationScope.global)
        .valueOrNull!;
    final project = catalog
        .resolveDiscovery(
          agentId: 'test',
          scope: ActivationScope.project,
          projectRoot: projectRoot,
        )
        .valueOrNull!;

    expect(global.map((target) => target.location), <String>[
      canonicalGlobal,
      legacyGlobal,
    ]);
    expect(
      global.map((target) => target.canonicalTarget.location).toSet(),
      <String>{canonicalGlobal},
    );
    expect(project.map((target) => target.location), <String>[
      path.join(projectRoot.path, '.agents', 'skills'),
      path.join(projectRoot.path, '.legacy', 'skills'),
    ]);
    expect(
      project.map((target) => target.canonicalTarget.location).toSet(),
      <String>{path.join(projectRoot.path, '.agents', 'skills')},
    );
  });

  test(
    'detection honors any-path and all-path rules through the port',
    () async {
      final any = _definition(
        id: 'any',
        globalPath: path.join(temporaryDirectory.path, 'any'),
        detections: <AgentDetectionPath>[
          AgentDetectionPath.absolute(
            path.join(temporaryDirectory.path, 'one'),
          ),
          AgentDetectionPath.absolute(
            path.join(temporaryDirectory.path, 'two'),
          ),
        ],
      );
      final all = _definition(
        id: 'all',
        globalPath: path.join(temporaryDirectory.path, 'all'),
        detections: <AgentDetectionPath>[
          AgentDetectionPath.absolute(
            path.join(temporaryDirectory.path, 'one'),
          ),
          AgentDetectionPath.absolute(
            path.join(temporaryDirectory.path, 'two'),
          ),
        ],
        requireAll: true,
      );
      final port = FakeAgentDetectionPort(
        matches: (detection, _) => detection.path.endsWith('one'),
      );
      final catalog = AgentCatalog.create(
        platform: DesktopPlatform.macos,
        detectionPort: port,
        builtIns: <AgentDefinition>[any, all],
      ).valueOrNull!;

      expect(await catalog.detect(), <String>{'any'});
    },
  );

  test('filesystem package detection tolerates malformed manifests', () async {
    final project = Directory(path.join(temporaryDirectory.path, 'project'));
    await project.create();
    final manifest = File(path.join(project.path, 'package.json'));
    final detection = AgentDetectionPath.projectPackageDependency('eve');
    const adapter = FileSystemAgentDetection();
    final root = ProjectRoot(id: 'project', path: project.path);

    await manifest.writeAsString('{not-json');
    expect(await adapter.matches(detection, projectRoot: root), isFalse);
    await manifest.writeAsString('{"devDependencies":{"eve":"1.0.0"}}');
    expect(await adapter.matches(detection, projectRoot: root), isTrue);
  });

  test('uses XDG config root consistently on every platform', () {
    final home = path.join(temporaryDirectory.path, 'home');
    final xdg = path.join(temporaryDirectory.path, 'xdg');
    const configRootAgents = <String>['devin', 'goose'];

    for (final platform in DesktopPlatform.values) {
      final definitions = buildBuiltInAgentDefinitions(
        platform: platform,
        environment: <String, String>{
          'HOME': home,
          'USERPROFILE': home,
          'XDG_CONFIG_HOME': xdg,
        },
      );
      for (final agentId in configRootAgents) {
        final globalPath = definitions
            .singleWhere((definition) => definition.id == agentId)
            .onPlatform(platform)!
            .globalSkillsPath!;
        expect(path.isWithin(xdg, globalPath), isTrue);
      }
      final universalAliases = <String, String>{
        'amp': path.join(xdg, 'agents', 'skills'),
        'opencode': path.join(xdg, 'opencode', 'skills'),
        'universal': path.join(xdg, 'agents', 'skills'),
      };
      for (final entry in universalAliases.entries) {
        final platformDefinition = definitions
            .singleWhere((definition) => definition.id == entry.key)
            .onPlatform(platform)!;
        expect(
          platformDefinition.globalSkillsPath,
          path.join(home, '.agents', 'skills'),
        );
        expect(
          // Built-in suffixes may contain '/', which is also a valid Windows
          // separator. Compare locations rather than their spelling.
          platformDefinition.globalDiscoverySkillsPaths.map(path.normalize),
          contains(path.normalize(entry.value)),
        );
      }
    }
  });

  test('OpenClaw location uses explicit existing-path input', () {
    final home = temporaryDirectory.path;
    final legacy = path.join(home, '.clawdbot');
    final definitions = buildBuiltInAgentDefinitions(
      platform: DesktopPlatform.macos,
      environment: <String, String>{'HOME': home},
      existingPaths: <String>{legacy},
    );

    expect(
      definitions
          .singleWhere((definition) => definition.id == 'openclaw')
          .onPlatform(DesktopPlatform.macos)!
          .globalSkillsPath,
      path.join(legacy, 'skills'),
    );
  });
}

AgentDefinition _definition({
  required String id,
  required String globalPath,
  String? projectPath,
  DesktopPlatform platform = DesktopPlatform.macos,
  List<AgentDetectionPath> detections = const <AgentDetectionPath>[],
  bool requireAll = false,
}) => AgentDefinition(
  id: id,
  displayName: id,
  platforms: <DesktopPlatform, AgentPlatformDefinition>{
    platform: AgentPlatformDefinition(
      globalSkillsPath: globalPath,
      projectSkillsPath: projectPath,
      detectionPaths: detections,
      requireAllDetectionPaths: requireAll,
    ),
  },
);
