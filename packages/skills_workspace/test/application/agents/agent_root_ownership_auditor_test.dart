import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/agents/agent_catalog_controller.dart';
import 'package:skills_workspace/src/application/agents/agent_root_ownership_auditor.dart';
import 'package:skills_workspace/src/application/ports/agent_root_ownership_ports.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:test/test.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  final home = Platform.isWindows ? r'C:\Users\tester' : '/Users/tester';

  test('returns unsupported without inspecting paths', () async {
    final inspection = _FakeInspection(supported: false);
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[
          _agent('agent', globalPath: path.join(home, '.agent', 'skills')),
        ],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.supported, isFalse);
    expect(result.currentUserId, isNull);
    expect(result.examinedRootCount, 0);
    expect(result.issues, isEmpty);
    expect(inspection.inspected, isEmpty);
  });

  test('ignores missing roots and Project paths', () async {
    final inspection = _FakeInspection()..physicalPaths[home] = home;
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[
          _agent(
            'agent',
            globalPath: path.join(home, '.agent', 'skills'),
            projectPath: path.join('.agent', 'skills'),
          ),
        ],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.isClean, isTrue);
    expect(result.examinedRootCount, 0);
    expect(inspection.inspected, <String>[path.join(home, '.agent', 'skills')]);
  });

  test(
    'collapses a mismatched descendant to one shared physical root',
    () async {
      final canonical = path.join(home, '.agent', 'skills');
      final compatibility = path.join(home, '.agent', 'legacy-skills');
      final physical = path.join(home, '.shared', 'skills');
      final child = path.join(physical, 'example', 'SKILL.md');
      final inspection = _FakeInspection()
        ..physicalPaths.addAll(<String, String>{
          home: home,
          canonical: physical,
          compatibility: physical,
        })
        ..metadata.addAll(<String, AgentRootEntryMetadata>{
          canonical: _directory(501),
          compatibility: _directory(501),
          child: _file(0),
        })
        ..children[physical] = <String>[child];
      final auditor = AgentRootOwnershipAuditor(
        catalogs: _catalog(
          builtIns: <AgentDefinition>[
            _agent(
              'built-in',
              globalPath: canonical,
              compatibilityPaths: <String>[compatibility],
            ),
          ],
          additional: <AgentDefinition>[
            _agent('custom', globalPath: canonical),
          ],
        ),
        inspection: inspection,
        userHomePath: home,
      );

      final result = await auditor.inspect();

      expect(result.examinedRootCount, 1);
      expect(result.issues, hasLength(1));
      final issue = result.issues.single;
      expect(issue.rootPath, physical);
      expect(issue.reason, AgentRootOwnershipIssueReason.ownerMismatch);
      expect(issue.repairable, isTrue);
      expect(issue.agentIds, <String>{'built-in', 'custom'});
      expect(issue.customAgentIds, <String>{'custom'});
      expect(issue.roles, <AgentSkillRootRole>{
        AgentSkillRootRole.canonicalActivation,
        AgentSkillRootRole.compatibilityDiscovery,
      });
    },
  );

  test('does not follow symbolic-link descendants', () async {
    final root = path.join(home, '.agent', 'skills');
    final link = path.join(root, 'external');
    final inspection = _FakeInspection()
      ..physicalPaths.addAll(<String, String>{home: home, root: root})
      ..metadata.addAll(<String, AgentRootEntryMetadata>{
        root: _directory(501),
        link: _link(0),
      })
      ..children[root] = <String>[link];
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[_agent('agent', globalPath: root)],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.isClean, isTrue);
    expect(result.examinedRootCount, 1);
  });

  test('resolves a compatibility symbolic-link root inside Home', () async {
    final canonical = path.join(home, '.agents', 'skills');
    final compatibility = path.join(home, '.gemini', 'antigravity', 'skills');
    final physical = path.join(home, '.gemini', 'config', 'skills');
    final inspection = _FakeInspection()
      ..physicalPaths.addAll(<String, String>{
        home: home,
        compatibility: physical,
      })
      ..metadata.addAll(<String, AgentRootEntryMetadata>{
        compatibility: _link(501),
        physical: _directory(501),
      });
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[
          _agent(
            'antigravity',
            globalPath: canonical,
            compatibilityPaths: <String>[compatibility],
          ),
        ],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.isClean, isTrue);
    expect(result.examinedRootCount, 1);
    expect(inspection.inspected, <String>[canonical, compatibility, physical]);
  });

  test(
    'repairs and deduplicates the physical target of a compatibility link',
    () async {
      final compatibility = path.join(home, '.gemini', 'antigravity', 'skills');
      final physical = path.join(home, '.gemini', 'config', 'skills');
      final inspection = _FakeInspection()
        ..physicalPaths.addAll(<String, String>{
          home: home,
          compatibility: physical,
          physical: physical,
        })
        ..metadata.addAll(<String, AgentRootEntryMetadata>{
          compatibility: _link(501),
          physical: _directory(0),
        });
      final auditor = AgentRootOwnershipAuditor(
        catalogs: _catalog(
          builtIns: <AgentDefinition>[
            _agent(
              'antigravity',
              globalPath: path.join(home, '.agents', 'skills'),
              compatibilityPaths: <String>[compatibility],
            ),
            _agent('gemini', globalPath: physical),
          ],
        ),
        inspection: inspection,
        userHomePath: home,
      );

      final result = await auditor.inspect();

      expect(result.examinedRootCount, 1);
      expect(result.repairableIssues, hasLength(1));
      final issue = result.repairableIssues.single;
      expect(issue.rootPath, physical);
      expect(issue.reason, AgentRootOwnershipIssueReason.ownerMismatch);
      expect(issue.agentIds, <String>{'antigravity', 'gemini'});
      expect(issue.roles, <AgentSkillRootRole>{
        AgentSkillRootRole.canonicalActivation,
        AgentSkillRootRole.compatibilityDiscovery,
      });
    },
  );

  test('audits a linked canonical root at the folder it resolves to', () async {
    final linkedRoot = path.join(home, '.agent', 'skills');
    final physical = path.join(home, 'dotfiles', 'skills');
    final child = path.join(physical, 'example', 'SKILL.md');
    final inspection = _FakeInspection()
      ..physicalPaths.addAll(<String, String>{home: home, linkedRoot: physical})
      ..metadata.addAll(<String, AgentRootEntryMetadata>{
        linkedRoot: _link(501),
        physical: _directory(501),
        child: _file(0),
      })
      ..children[physical] = <String>[child];
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[
          _agent('canonical', globalPath: linkedRoot),
          _agent(
            'compatibility',
            globalPath: path.join(home, '.agents', 'skills'),
            compatibilityPaths: <String>[linkedRoot],
          ),
        ],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.blockedIssues, isEmpty);
    final issue = result.repairableIssues.single;
    expect(issue.rootPath, physical);
    expect(issue.reason, AgentRootOwnershipIssueReason.ownerMismatch);
    expect(issue.agentIds, <String>{'canonical', 'compatibility'});
    expect(issue.roles, <AgentSkillRootRole>{
      AgentSkillRootRole.canonicalActivation,
      AgentSkillRootRole.compatibilityDiscovery,
    });
  });

  test(
    'allows a linked canonical root but blocks a root outside Home',
    () async {
      final linkedRoot = path.join(home, '.agent', 'skills');
      final physical = path.join(home, 'dotfiles', 'skills');
      final outsideRoot = path.join(
        Platform.isWindows ? r'C:\' : '/',
        'opt',
        'agent',
        'skills',
      );
      final inspection = _FakeInspection()
        ..physicalPaths.addAll(<String, String>{
          home: home,
          linkedRoot: physical,
          outsideRoot: outsideRoot,
        })
        ..metadata.addAll(<String, AgentRootEntryMetadata>{
          linkedRoot: _link(501),
          physical: _directory(501),
          outsideRoot: _directory(0),
        });
      final auditor = AgentRootOwnershipAuditor(
        catalogs: _catalog(
          builtIns: <AgentDefinition>[
            _agent('linked', globalPath: linkedRoot),
            _agent('outside', globalPath: outsideRoot),
          ],
        ),
        inspection: inspection,
        userHomePath: home,
      );

      final result = await auditor.inspect();

      expect(result.examinedRootCount, 2);
      expect(result.blockedIssues, hasLength(1));
      expect(result.blockedIssues.single.rootPath, outsideRoot);
      expect(
        result.blockedIssues.single.reason,
        AgentRootOwnershipIssueReason.outsideUserHome,
      );
    },
  );

  test('blocks a compatibility link whose target is outside Home', () async {
    final compatibility = path.join(home, '.agent', 'legacy-skills');
    final physical = path.join(
      Platform.isWindows ? r'C:\' : '/',
      'opt',
      'agent',
      'skills',
    );
    final inspection = _FakeInspection()
      ..physicalPaths.addAll(<String, String>{
        home: home,
        compatibility: physical,
      })
      ..metadata[compatibility] = _link(501);
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[
          _agent(
            'agent',
            globalPath: path.join(home, '.agents', 'skills'),
            compatibilityPaths: <String>[compatibility],
          ),
        ],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.blockedIssues, hasLength(1));
    expect(result.blockedIssues.single.rootPath, physical);
    expect(
      result.blockedIssues.single.reason,
      AgentRootOwnershipIssueReason.outsideUserHome,
    );
  });

  test('blocks a compatibility link whose target is not a directory', () async {
    final compatibility = path.join(home, '.agent', 'legacy-skills');
    final physical = path.join(home, '.agent', 'skills.txt');
    final inspection = _FakeInspection()
      ..physicalPaths.addAll(<String, String>{
        home: home,
        compatibility: physical,
      })
      ..metadata.addAll(<String, AgentRootEntryMetadata>{
        compatibility: _link(501),
        physical: _file(501),
      });
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[
          _agent(
            'agent',
            globalPath: path.join(home, '.agents', 'skills'),
            compatibilityPaths: <String>[compatibility],
          ),
        ],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.blockedIssues, hasLength(1));
    expect(result.blockedIssues.single.rootPath, physical);
    expect(
      result.blockedIssues.single.reason,
      AgentRootOwnershipIssueReason.notDirectory,
    );
  });

  test('blocks a compatibility link that cannot be resolved', () async {
    final compatibility = path.join(home, '.agent', 'legacy-skills');
    final inspection = _FakeInspection()
      ..physicalPaths[home] = home
      ..metadata[compatibility] = _link(501)
      ..physicalPathFailures.add(compatibility);
    final auditor = AgentRootOwnershipAuditor(
      catalogs: _catalog(
        builtIns: <AgentDefinition>[
          _agent(
            'agent',
            globalPath: path.join(home, '.agents', 'skills'),
            compatibilityPaths: <String>[compatibility],
          ),
        ],
      ),
      inspection: inspection,
      userHomePath: home,
    );

    final result = await auditor.inspect();

    expect(result.blockedIssues, hasLength(1));
    expect(result.blockedIssues.single.rootPath, compatibility);
    expect(
      result.blockedIssues.single.reason,
      AgentRootOwnershipIssueReason.inspectionFailed,
    );
  });
}

AgentCatalogController _catalog({
  required List<AgentDefinition> builtIns,
  List<AgentDefinition> additional = const <AgentDefinition>[],
}) => AgentCatalogController.create(
  platform: DesktopPlatform.macos,
  detectionPort: FakeAgentDetectionPort(),
  builtIns: builtIns,
  additional: additional,
).valueOrNull!;

AgentDefinition _agent(
  String id, {
  required String globalPath,
  String? projectPath,
  List<String> compatibilityPaths = const <String>[],
}) => AgentDefinition(
  id: id,
  displayName: id,
  platforms: <DesktopPlatform, AgentPlatformDefinition>{
    DesktopPlatform.macos: AgentPlatformDefinition(
      globalSkillsPath: globalPath,
      projectSkillsPath: projectPath,
      globalDiscoverySkillsPaths: compatibilityPaths,
    ),
  },
);

AgentRootEntryMetadata _directory(int ownerUserId) => AgentRootEntryMetadata(
  type: AgentRootEntryType.directory,
  ownerUserId: ownerUserId,
);

AgentRootEntryMetadata _file(int ownerUserId) => AgentRootEntryMetadata(
  type: AgentRootEntryType.file,
  ownerUserId: ownerUserId,
);

AgentRootEntryMetadata _link(int ownerUserId) => AgentRootEntryMetadata(
  type: AgentRootEntryType.symbolicLink,
  ownerUserId: ownerUserId,
);

final class _FakeInspection implements AgentRootOwnershipInspectionPort {
  _FakeInspection({this.supported = true});

  @override
  final bool supported;
  final Map<String, AgentRootEntryMetadata> metadata =
      <String, AgentRootEntryMetadata>{};
  final Map<String, String> physicalPaths = <String, String>{};
  final Set<String> physicalPathFailures = <String>{};
  final Map<String, List<String>> children = <String, List<String>>{};
  final List<String> inspected = <String>[];

  @override
  int currentUserId() => 501;

  @override
  Stream<String> descendants(String rootPath) =>
      Stream<String>.fromIterable(children[rootPath] ?? const <String>[]);

  @override
  Future<AgentRootEntryMetadata?> inspect(String value) async {
    inspected.add(value);
    return metadata[value];
  }

  @override
  Future<String> physicalDirectoryPath(String value) async {
    if (physicalPathFailures.contains(value)) {
      throw StateError('Unable to resolve $value');
    }
    return physicalPaths[value] ?? value;
  }
}
