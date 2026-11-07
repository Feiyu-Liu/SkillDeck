import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/application/activation/activation_target_resolver.dart';
import 'package:skills_workspace/src/application/agents/agent_catalog.dart';
import 'package:skills_workspace/src/domain/activation_selection.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  test('none resolves no targets without warnings', () async {
    final resolver = _resolver(<AgentDefinition>[]);

    final result = await resolver.resolve(
      selection: const ActivationSelection.none(),
      requestedMode: RequestedActivationMode.automatic,
      snapshot: RepositorySnapshot.empty(),
    );

    expect(result.valueOrNull!.targets, isEmpty);
    expect(result.valueOrNull!.warnings, isEmpty);
  });

  test(
    'automatic resolves detected agents and skips unsupported scope',
    () async {
      final detectedIds = <String>{'supported', 'project-only'};
      final resolver = _resolver(<AgentDefinition>[
        _definition('supported', '/shared/skills'),
        _definition('project-only', null, projectSkillsPath: '.agents/skills'),
      ], detectedIds: detectedIds);

      final result = await resolver.resolve(
        selection: const ActivationSelection.automatic(),
        requestedMode: RequestedActivationMode.copy,
        snapshot: RepositorySnapshot.empty(),
      );

      expect(result.valueOrNull!.targets.single.agentIds, <String>[
        'supported',
      ]);
      expect(
        result.valueOrNull!.warnings.single.code,
        ActivationWarningCode.activationTargetSkipped,
      );
    },
  );

  test('explicit selection supports configured but undetected Agent', () async {
    final resolver = _resolver(<AgentDefinition>[
      _definition('undetected', '/undetected/skills'),
    ]);

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'undetected', scope: ActivationScope.global),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot.empty(),
    );

    expect(
      result.valueOrNull!.targets.single.location,
      _platformLocation('/undetected/skills'),
    );
  });

  test('groups Agents whose roots are lexically equivalent', () async {
    final resolver = _resolver(<AgentDefinition>[
      _definition('z-agent', '/shared/skills'),
      _definition('a-agent', '/shared/skills/../skills'),
    ]);

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'z-agent', scope: ActivationScope.global),
        ActivationTarget(agentId: 'a-agent', scope: ActivationScope.global),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot.empty(),
    );

    expect(result.valueOrNull!.targets, hasLength(1));
    expect(result.valueOrNull!.targets.single.agentIds, <String>[
      'a-agent',
      'z-agent',
    ]);
    expect(result.valueOrNull!.warnings, isEmpty);
  });

  test('groups Agents whose roots resolve to one directory', () async {
    // ~/.agents/skills is a dotfiles link to ~/.claude/skills.
    final resolver = _resolver(
      <AgentDefinition>[
        _definition('universal', '/home/.agents/skills'),
        _definition('claude-code', '/home/.claude/skills'),
      ],
      identity: PosixActivationLocationIdentity(
        resolvedDirectories: <String, String>{
          _platformLocation('/home/.agents/skills'): _platformLocation(
            '/home/.claude/skills',
          ),
        },
      ),
    );

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'universal', scope: ActivationScope.global),
        ActivationTarget(agentId: 'claude-code', scope: ActivationScope.global),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot.empty(),
    );

    final target = result.valueOrNull!.targets.single;
    expect(target.location, _platformLocation('/home/.claude/skills'));
    expect(target.agentIds, <String>['claude-code', 'universal']);
    final warning = result.valueOrNull!.warnings.single;
    expect(warning.code, ActivationWarningCode.sharedActivationLocation);
    expect(warning.context, <String, Object?>{
      'location': _platformLocation('/home/.claude/skills'),
      'locations': <String>[
        _platformLocation('/home/.agents/skills'),
        _platformLocation('/home/.claude/skills'),
      ],
      'agentIds': <String>['claude-code', 'universal'],
    });
  });

  test('records the lexically first root when every root is a link', () async {
    final resolver = _resolver(
      <AgentDefinition>[
        _definition('claude-code', '/home/.claude/skills'),
        _definition('universal', '/home/.agents/skills'),
      ],
      identity: PosixActivationLocationIdentity(
        resolvedDirectories: <String, String>{
          _platformLocation('/home/.agents/skills'): _platformLocation(
            '/home/dotfiles/skills',
          ),
          _platformLocation('/home/.claude/skills'): _platformLocation(
            '/home/dotfiles/skills',
          ),
        },
      ),
    );

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'claude-code', scope: ActivationScope.global),
        ActivationTarget(agentId: 'universal', scope: ActivationScope.global),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot.empty(),
    );

    final target = result.valueOrNull!.targets.single;
    expect(target.location, _platformLocation('/home/.agents/skills'));
    expect(target.agentIds, <String>['claude-code', 'universal']);
  });

  test('a root that does not exist yet keeps its own group', () async {
    final resolver = _resolver(
      <AgentDefinition>[
        _definition('universal', '/home/.agents/skills'),
        _definition('claude-code', '/home/.claude/skills'),
      ],
      identity: PosixActivationLocationIdentity(
        missingDirectories: <String>{_platformLocation('/home/.agents/skills')},
      ),
    );

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'universal', scope: ActivationScope.global),
        ActivationTarget(agentId: 'claude-code', scope: ActivationScope.global),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot.empty(),
    );

    expect(
      result.valueOrNull!.targets.map((target) => target.location),
      <String>[
        _platformLocation('/home/.agents/skills'),
        _platformLocation('/home/.claude/skills'),
      ],
    );
    expect(result.valueOrNull!.warnings, isEmpty);
  });

  test('provenance must agree across a physically shared root', () async {
    final project = ProjectRoot(id: 'project', path: _platformLocation('/p'));
    final resolver = _resolver(
      <AgentDefinition>[
        _definition('global-agent', '/home/.agents/skills'),
        _definition('project-agent', null, projectSkillsPath: 'skills'),
      ],
      identity: PosixActivationLocationIdentity(
        resolvedDirectories: <String, String>{
          _platformLocation('/home/.agents/skills'): _platformLocation(
            '/p/skills',
          ),
        },
      ),
    );

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(
          agentId: 'global-agent',
          scope: ActivationScope.global,
        ),
        ActivationTarget(
          agentId: 'project-agent',
          scope: ActivationScope.project,
          projectRootId: project.id,
        ),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[project],
      ),
    );

    expect(
      result.failureOrNull!.code,
      ActivationFailureCode.activationUnsupported,
    );
    expect(
      result.failureOrNull!.context['reason'],
      'conflictingLocationProvenance',
    );
  });

  test('project automatic defaults to copy without probing links', () async {
    final project = ProjectRoot(
      id: 'project',
      path: _platformLocation('/project'),
    );
    final capability = FakeSymbolicLinkCapability(defaultResult: true);
    final resolver = _resolver(
      <AgentDefinition>[
        _definition('agent', '/global', projectSkillsPath: '.agents/skills'),
      ],
      detectedIds: <String>{'agent'},
      capability: capability,
    );

    final result = await resolver.resolve(
      selection: const ActivationSelection.automatic(
        scope: ActivationScope.project,
      ),
      requestedMode: RequestedActivationMode.automatic,
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[project],
      ),
    );

    expect(result.valueOrNull!.targets.single.mode, ActivationMode.copy);
    expect(capability.inspectedLocations, isEmpty);
  });

  test(
    'global automatic falls back to copy when links are unavailable',
    () async {
      final resolver = _resolver(
        <AgentDefinition>[_definition('agent', '/global')],
        detectedIds: <String>{'agent'},
      );

      final result = await resolver.resolve(
        selection: const ActivationSelection.automatic(),
        requestedMode: RequestedActivationMode.automatic,
        snapshot: RepositorySnapshot.empty(),
      );

      expect(result.valueOrNull!.targets.single.mode, ActivationMode.copy);
    },
  );

  test('explicit unavailable symbolic link is a strict failure', () async {
    final resolver = _resolver(<AgentDefinition>[
      _definition('agent', '/global'),
    ]);

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
      ]),
      requestedMode: RequestedActivationMode.symbolicLink,
      snapshot: RepositorySnapshot.empty(),
    );

    expect(
      result.failureOrNull?.code,
      ActivationFailureCode.activationUnsupported,
    );
    expect(result.failureOrNull?.context['reason'], 'symbolicLinkUnavailable');
  });

  test('explicit project symbolic link retains provenance and warns', () async {
    final project = ProjectRoot(
      id: 'project',
      path: _platformLocation('/project'),
    );
    final resolver = _resolver(<AgentDefinition>[
      _definition('agent', '/global', projectSkillsPath: '.agents/skills'),
    ], capability: FakeSymbolicLinkCapability(defaultResult: true));

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(
          agentId: 'agent',
          scope: ActivationScope.project,
          projectRootId: project.id,
        ),
      ]),
      requestedMode: RequestedActivationMode.symbolicLink,
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[project],
      ),
    );

    final target = result.valueOrNull!.targets.single;
    expect(target.mode, ActivationMode.symbolicLink);
    expect(target.projectRootId, project.id);
    expect(target.projectRootPath, project.path);
    expect(
      result.valueOrNull!.warnings.single.code,
      ActivationWarningCode.projectSymbolicLinkPortability,
    );
  });

  test('global and project targets warn about duplicate exposure', () async {
    final project = ProjectRoot(
      id: 'project',
      path: _platformLocation('/project'),
    );
    final resolver = _resolver(<AgentDefinition>[
      _definition('agent', '/global', projectSkillsPath: '.agents/skills'),
    ]);

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ActivationTarget(
          agentId: 'agent',
          scope: ActivationScope.project,
          projectRootId: project.id,
        ),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[project],
      ),
    );

    expect(result.valueOrNull!.targets, hasLength(2));
    expect(
      result.valueOrNull!.warnings.single.code,
      ActivationWarningCode.duplicateExposure,
    );
  });

  test('one location cannot carry conflicting scope provenance', () async {
    final project = ProjectRoot(
      id: 'project',
      path: _platformLocation('/project'),
    );
    final resolver = _resolver(<AgentDefinition>[
      _definition(
        'agent',
        path.join(project.path, 'skills'),
        projectSkillsPath: 'skills',
      ),
    ]);

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'agent', scope: ActivationScope.global),
        ActivationTarget(
          agentId: 'agent',
          scope: ActivationScope.project,
          projectRootId: project.id,
        ),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot(
        revision: RepositoryRevision.initial(),
        projectRoots: <ProjectRoot>[project],
      ),
    );

    expect(
      result.failureOrNull?.code,
      ActivationFailureCode.activationUnsupported,
    );
    expect(
      result.failureOrNull?.context['reason'],
      'conflictingLocationProvenance',
    );
  });

  test('targets and Agent IDs are sorted and immutable', () async {
    final resolver = _resolver(<AgentDefinition>[
      _definition('z', '/z'),
      _definition('b', '/a'),
      _definition('a', '/a'),
    ]);

    final result = await resolver.resolve(
      selection: ActivationSelection.explicit(<ActivationTarget>[
        ActivationTarget(agentId: 'z', scope: ActivationScope.global),
        ActivationTarget(agentId: 'b', scope: ActivationScope.global),
        ActivationTarget(agentId: 'a', scope: ActivationScope.global),
      ]),
      requestedMode: RequestedActivationMode.copy,
      snapshot: RepositorySnapshot.empty(),
    );

    expect(
      result.valueOrNull!.targets.map((target) => target.location),
      <String>[_platformLocation('/a'), _platformLocation('/z')],
    );
    expect(result.valueOrNull!.targets.first.agentIds, <String>['a', 'b']);
    expect(
      () => result.valueOrNull!.targets.add(result.valueOrNull!.targets.first),
      throwsUnsupportedError,
    );
    expect(
      () => result.valueOrNull!.targets.first.agentIds.add('other'),
      throwsUnsupportedError,
    );
  });

  test('Windows location identity normalizes separators and case', () {
    const identity = WindowsActivationLocationIdentity();

    expect(
      identity.key(r'C:/Users/A/.agents/skills/../skills'),
      identity.key(r'c:\users\a\.agents\skills'),
    );
  });
}

ActivationTargetResolver _resolver(
  List<AgentDefinition> definitions, {
  Set<String> detectedIds = const <String>{},
  FakeSymbolicLinkCapability? capability,
  PosixActivationLocationIdentity identity =
      const PosixActivationLocationIdentity(),
}) {
  final detection = FakeAgentDetectionPort(
    matches: (rule, _) =>
        detectedIds.any((agentId) => rule.path == '/detect/$agentId'),
  );
  final adjusted = <AgentDefinition>[
    for (final definition in definitions)
      definition.onPlatform(DesktopPlatform.macos)!.detectionPaths.isNotEmpty
          ? definition
          : AgentDefinition(
              id: definition.id,
              displayName: definition.displayName,
              platforms: <DesktopPlatform, AgentPlatformDefinition>{
                DesktopPlatform.macos: AgentPlatformDefinition(
                  globalSkillsPath: definition
                      .onPlatform(DesktopPlatform.macos)!
                      .globalSkillsPath,
                  projectSkillsPath: definition
                      .onPlatform(DesktopPlatform.macos)!
                      .projectSkillsPath,
                  detectionPaths: <AgentDetectionPath>[
                    AgentDetectionPath.absolute('/detect/${definition.id}'),
                  ],
                ),
              },
            ),
  ];
  final catalog = AgentCatalog.create(
    platform: DesktopPlatform.macos,
    detectionPort: detection,
    builtIns: adjusted,
  ).valueOrNull!;
  return ActivationTargetResolver(
    catalog: catalog,
    symbolicLinkCapability: capability ?? FakeSymbolicLinkCapability(),
    locationIdentity: identity,
  );
}

AgentDefinition _definition(
  String id,
  String? globalSkillsPath, {
  String? projectSkillsPath,
}) => AgentDefinition(
  id: id,
  displayName: id,
  platforms: <DesktopPlatform, AgentPlatformDefinition>{
    DesktopPlatform.macos: AgentPlatformDefinition(
      globalSkillsPath: globalSkillsPath,
      projectSkillsPath: projectSkillsPath,
    ),
  },
);

String _platformLocation(String value) => path.normalize(path.absolute(value));
