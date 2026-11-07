import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

const _nfdFileName = 'café.md';
const _nfcFileName = 'café.md';

void main() {
  test('adopts under a custom Agent added after repository creation', () async {
    final fixture = await _ExternalAdoptionFixture.create();
    addTearDown(fixture.dispose);
    final repository = fixture.createRepository(includeCustomAgents: false);
    await _expectSuccess(repository.open());
    await _expectSuccess(
      repository.reconfigureAgentCatalog(
        ReconfigureAgentCatalogRequest(agents: fixture.agentDefinitions),
      ),
    );
    final discovery = await _expectSuccess(
      repository.discoverExternalSkills(
        const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
      ),
    );
    final adoption = await _expectSuccess(
      repository.adopt(
        AdoptRequest(
          selection: ExternalAdoptionSelection.fromConflict(
            discovery.conflicts.single,
            fixture.skillPath('a'),
          ),
        ),
      ),
    );
    expect(
      adoption.snapshot
          .findSkill(adoption.affectedSkillIds.single)!
          .activations,
      hasLength(2),
    );
    await _expectVoidSuccess(repository.close());
  });
  test(
    'adopts a Skill whose folder name differs from its slot key by case',
    () async {
      final fixture = await _ExternalAdoptionFixture.create();
      addTearDown(fixture.dispose);
      await fixture._writeSkill(
        'a',
        folderName: 'UpperCase',
        declaredName: 'uppercase',
      );
      final repository = fixture.createRepository();
      await _expectSuccess(repository.open());
      final discovery = await _expectSuccess(
        repository.discoverExternalSkills(
          const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
        ),
      );
      final candidate = discovery.candidates.singleWhere(
        (candidate) => candidate.slotKey == 'uppercase',
      );
      expect(
        candidate.locations.single,
        path.join(fixture.firstSkillsRoot.path, 'UpperCase'),
      );

      final adoption = await _expectSuccess(
        repository.adopt(
          AdoptRequest(
            selection: ExternalAdoptionSelection.fromCandidate(
              candidate,
              candidate.locations.single,
            ),
          ),
        ),
      );

      final managed = adoption.snapshot.findSkill(
        adoption.affectedSkillIds.single,
      )!;
      expect(managed.slotKey, 'uppercase');
      expect(managed.activations, hasLength(1));
      expect(
        await File(
          path.join(fixture.firstSkillsRoot.path, 'uppercase', 'body.md'),
        ).readAsString(),
        'body a\n',
      );
      await _expectVoidSuccess(repository.close());
    },
  );

  for (final authority in <String>['a', 'b']) {
    test(
      'public facade adopts divergent external Skill using $authority as authority',
      () async {
        final fixture = await _ExternalAdoptionFixture.create();
        addTearDown(fixture.dispose);

        var repository = fixture.createRepository();
        await _expectSuccess(repository.open());
        final discovery = await _expectSuccess(
          repository.discoverExternalSkills(
            const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
          ),
        );
        expect(discovery.candidates, isEmpty);
        final conflict = discovery.conflicts.single;
        final authorityPath = fixture.skillPath(authority);
        final authorityHash = conflict.contentHashByLocation[authorityPath]!;

        final adoption = await _expectSuccess(
          repository.adopt(
            AdoptRequest(
              selection: ExternalAdoptionSelection.fromConflict(
                conflict,
                authorityPath,
              ),
            ),
          ),
        );

        final managedSkillId = adoption.affectedSkillIds.single;
        final managed = adoption.snapshot.findSkill(managedSkillId)!;
        final source = managed.source as AdoptedSnapshotSourceDescriptor;
        expect(source.authoritativeLocation, path.normalize(authorityPath));
        expect(source.contentHash, authorityHash);
        expect(managed.activations, hasLength(2));
        await fixture.expectMaterializations(authority);

        await _expectVoidSuccess(repository.close());
        repository = fixture.createRepository();
        final reopened = await _expectSuccess(repository.open());
        final reopenedSkill = reopened.findSkill(managedSkillId)!;
        final reopenedSource =
            reopenedSkill.source as AdoptedSnapshotSourceDescriptor;
        expect(
          reopenedSource.authoritativeLocation,
          path.normalize(authorityPath),
        );
        expect(reopenedSource.contentHash, authorityHash);
        await fixture.expectMaterializations(authority);
        await _expectVoidSuccess(repository.close());
      },
      timeout: Platform.isWindows
          ? const Timeout(Duration(minutes: 4))
          : const Timeout(Duration(minutes: 2)),
    );
  }

  test(
    'adopts an external Skill with contained links and an NFD file name',
    () async {
      final fixture = await _ExternalAdoptionFixture.create(
        linksAndNfdName: true,
      );
      addTearDown(fixture.dispose);
      final repository = fixture.createRepository();
      await _expectSuccess(repository.open());
      final discovery = await _expectSuccess(
        repository.discoverExternalSkills(
          const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
        ),
      );
      final conflict = discovery.conflicts.single;

      final adoption = await _expectSuccess(
        repository.adopt(
          AdoptRequest(
            selection: ExternalAdoptionSelection.fromConflict(
              conflict,
              fixture.skillPath('a'),
            ),
          ),
        ),
      );

      final managed = adoption.snapshot.findSkill(
        adoption.affectedSkillIds.single,
      )!;
      expect(managed.activations, hasLength(2));
      await fixture.expectMaterializations('a');
      // Managed copies are plain: links are dereferenced into files and
      // names are stored in NFC.
      for (final root in <String>[
        path.join(fixture.workspaceRoot.path, 'repository-copies', _slotKey),
        fixture.skillPath('a'),
        fixture.skillPath('b'),
      ]) {
        final entries = await Directory(
          root,
        ).list(recursive: true, followLinks: false).toList();
        for (final entity in entries) {
          expect(
            await FileSystemEntity.type(entity.path, followLinks: false),
            isNot(FileSystemEntityType.link),
            reason: entity.path,
          );
        }
        final names = entries.map((entity) => path.basename(entity.path));
        expect(names, contains(_nfcFileName));
        expect(names, isNot(contains(_nfdFileName)));
        if (!Platform.isWindows) {
          expect(
            await File(path.join(root, 'CLAUDE.md')).readAsString(),
            'agents a\n',
          );
          expect(
            await File(path.join(root, 'docs-link', 'guide.md')).readAsString(),
            'guide a\n',
          );
        }
      }
      await _expectVoidSuccess(repository.close());
    },
    timeout: Platform.isWindows
        ? const Timeout(Duration(minutes: 4))
        : const Timeout(Duration(minutes: 2)),
  );

  test(
    'adopts from a linked compatibility root into the canonical root',
    () async {
      final fixture = await _CanonicalMigrationFixture.create();
      addTearDown(fixture.dispose);
      final repository = fixture.createRepository();

      await _expectSuccess(repository.open());
      final discovery = await _expectSuccess(
        repository.discoverExternalSkills(
          const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
        ),
      );
      final candidate = discovery.candidates.singleWhere(
        (candidate) => candidate.slotKey == _canonicalMigrationSlot,
      );
      expect(candidate.locations, <String>[fixture.legacySkillPath]);
      expect(candidate.destinationLocations, <String>[
        fixture.canonicalSkillPath,
      ]);

      final adoption = await _expectSuccess(
        repository.adopt(
          AdoptRequest(
            selection: ExternalAdoptionSelection.fromCandidate(
              candidate,
              fixture.legacySkillPath,
            ),
          ),
        ),
      );

      final managed = adoption.snapshot.findSkill(
        adoption.affectedSkillIds.single,
      )!;
      expect(managed.activations, hasLength(1));
      expect(managed.activations.single.location, fixture.canonicalSkillsRoot);
      expect(
        await File(
          path.join(fixture.canonicalSkillPath, 'body.md'),
        ).readAsString(),
        'legacy body\n',
      );
      expect(
        await Directory(fixture.physicalLegacySkillPath).exists(),
        isFalse,
      );
      expect(
        path.equals(
          await Directory(
            fixture.linkedLegacySkillsRoot,
          ).resolveSymbolicLinks(),
          await Directory(
            fixture.physicalLegacySkillsRoot,
          ).resolveSymbolicLinks(),
        ),
        isTrue,
      );
      await _expectVoidSuccess(repository.close());
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final target in <String>['its own folder', 'the compatibility root']) {
    test(
      'adopts and reactivates through a canonical root linked to $target',
      () async {
        final fixture = await _LinkedCanonicalFixture.create(
          sharesCompatibilityRoot: target == 'the compatibility root',
        );
        addTearDown(fixture.dispose);
        final repository = fixture.createRepository();
        await _expectSuccess(repository.open());

        final discovery = await _expectSuccess(
          repository.discoverExternalSkills(
            const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
          ),
        );
        final candidate = discovery.candidates.singleWhere(
          (candidate) => candidate.slotKey == _linkedCanonicalSlot,
        );
        final adoption = await _expectSuccess(
          repository.adopt(
            AdoptRequest(
              selection: ExternalAdoptionSelection.fromCandidate(
                candidate,
                fixture.compatibilitySkillPath,
              ),
            ),
          ),
        );
        final managedSkillId = adoption.affectedSkillIds.single;
        await fixture.expectActivated(isTrue);

        await _expectSuccess(
          repository.deactivate(
            DeactivateRequest(managedSkillIds: {managedSkillId}),
          ),
        );
        await fixture.expectActivated(isFalse);

        await _expectSuccess(
          repository.activate(
            ActivateRequest(
              managedSkillIds: {managedSkillId},
              selection: ActivationSelection.explicit(<ActivationTarget>[
                ActivationTarget(
                  agentId: _linkedCanonicalAgentId,
                  scope: ActivationScope.global,
                ),
              ]),
            ),
          ),
        );
        await fixture.expectActivated(isTrue);
        await _expectVoidSuccess(repository.close());
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  for (final layout in _SharedRootLayout.values) {
    test('adopts, deactivates and reactivates through two Agent roots that are '
        'one folder (${layout.name})', () async {
      final fixture = await _SharedRootFixture.create(layout);
      addTearDown(fixture.dispose);
      final repository = fixture.createRepository();
      await _expectSuccess(repository.open());

      final discovery = await _expectSuccess(
        repository.discoverExternalSkills(
          const DiscoverExternalSkillsRequest(scanAllKnownLocations: true),
        ),
      );
      expect(discovery.conflicts, isEmpty);
      expect(
        discovery.candidates,
        hasLength(_SharedRootFixture.slotKeys.length),
      );

      final managedSkillIds = <ManagedSkillId>{};
      for (final candidate in discovery.candidates) {
        final result = await repository
            .adopt(
              AdoptRequest(
                selection: ExternalAdoptionSelection.fromCandidate(
                  candidate,
                  candidate.locations.first,
                ),
              ),
            )
            .completed;
        final adoption = result.valueOrNull;
        expect(
          adoption,
          isNotNull,
          reason:
              '${candidate.slotKey}: ${result.failureOrNull?.code} '
              '${result.failureOrNull?.context}',
        );
        expect(
          result.warnings.map((warning) => warning.code),
          contains(SkillsWarningCode.sharedActivationLocation),
        );
        final managedSkillId = adoption!.affectedSkillIds.single;
        managedSkillIds.add(managedSkillId);
        final activation = adoption.snapshot
            .findSkill(managedSkillId)!
            .activations
            .single;
        expect(
          activation.agentIds,
          containsAll(<String>['claude-code', 'cursor']),
        );
        expect(
          await fixture.isPhysicalRoot(activation.location),
          isTrue,
          reason: 'the Activation is recorded at ${activation.location}',
        );
      }
      await fixture.expectLinksIntact();
      await fixture.expectActivated(isTrue);

      await _expectSuccess(
        repository.deactivate(
          DeactivateRequest(managedSkillIds: managedSkillIds),
        ),
      );
      await fixture.expectActivated(isFalse);

      await _expectSuccess(
        repository.activate(
          ActivateRequest(
            managedSkillIds: managedSkillIds,
            selection: ActivationSelection.explicit(<ActivationTarget>[
              ActivationTarget(
                agentId: 'claude-code',
                scope: ActivationScope.global,
              ),
              ActivationTarget(
                agentId: 'cursor',
                scope: ActivationScope.global,
              ),
            ]),
          ),
        ),
      );
      await fixture.expectActivated(isTrue);
      await fixture.expectLinksIntact();
      await _expectVoidSuccess(repository.close());
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}

const _slotKey = 'external-review';
const _firstAgentId = 'external-adoption-a';
const _secondAgentId = 'external-adoption-b';
const _canonicalMigrationSlot = 'agent-browser';
const _canonicalMigrationAgentId = 'custom-canonical-migration';

final class _CanonicalMigrationFixture {
  _CanonicalMigrationFixture._({
    required this.temporaryRoot,
    required this.workspaceRoot,
    required this.agentHome,
    required this.canonicalSkillsRoot,
    required this.physicalLegacySkillsRoot,
    required this.linkedLegacySkillsRoot,
  });

  final Directory temporaryRoot;
  final Directory workspaceRoot;
  final Directory agentHome;
  final String canonicalSkillsRoot;
  final String physicalLegacySkillsRoot;
  final String linkedLegacySkillsRoot;
  SkillsRepository? _repository;

  String get canonicalSkillPath =>
      path.join(canonicalSkillsRoot, _canonicalMigrationSlot);

  String get legacySkillPath =>
      path.join(linkedLegacySkillsRoot, _canonicalMigrationSlot);

  String get physicalLegacySkillPath =>
      path.join(physicalLegacySkillsRoot, _canonicalMigrationSlot);

  static Future<_CanonicalMigrationFixture> create() async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'skills-workspace-canonical-migration-e2e-',
    );
    final agentHome = Directory(path.join(temporaryRoot.path, 'home'));
    final canonicalSkillsRoot = path.join(agentHome.path, '.agents', 'skills');
    final physicalLegacySkillsRoot = path.join(
      agentHome.path,
      '.gemini',
      'config',
      'skills',
    );
    final linkedLegacySkillsRoot = path.join(
      agentHome.path,
      '.gemini',
      'antigravity',
      'skills',
    );
    final fixture = _CanonicalMigrationFixture._(
      temporaryRoot: temporaryRoot,
      workspaceRoot: Directory(path.join(temporaryRoot.path, 'workspace')),
      agentHome: agentHome,
      canonicalSkillsRoot: canonicalSkillsRoot,
      physicalLegacySkillsRoot: physicalLegacySkillsRoot,
      linkedLegacySkillsRoot: linkedLegacySkillsRoot,
    );
    await Directory(fixture.physicalLegacySkillPath).create(recursive: true);
    await Directory(
      path.dirname(linkedLegacySkillsRoot),
    ).create(recursive: true);
    await _createDirectoryAlias(
      linkedLegacySkillsRoot,
      physicalLegacySkillsRoot,
    );
    await File(
      path.join(fixture.physicalLegacySkillPath, 'SKILL.md'),
    ).writeAsString(
      '---\n'
      'name: $_canonicalMigrationSlot\n'
      'description: Linked compatibility fixture\n'
      '---\n'
      '# Agent Browser\n',
      flush: true,
    );
    await File(
      path.join(fixture.physicalLegacySkillPath, 'body.md'),
    ).writeAsString('legacy body\n', flush: true);
    return fixture;
  }

  SkillsRepository createRepository() {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: workspaceRoot.absolute.path,
        agentHomePath: agentHome.absolute.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
        additionalAgents: <AgentDefinition>[
          AgentDefinition(
            id: _canonicalMigrationAgentId,
            displayName: 'Canonical Migration',
            platforms: <DesktopPlatform, AgentPlatformDefinition>{
              _platform(): AgentPlatformDefinition(
                globalSkillsPath: canonicalSkillsRoot,
                globalDiscoverySkillsPaths: <String>[linkedLegacySkillsRoot],
              ),
            },
          ),
        ],
      ),
    );
    _repository = repository;
    return repository;
  }

  Future<void> dispose() async {
    final repository = _repository;
    if (repository != null && repository.isOpen) {
      try {
        await repository.close().completed;
      } on Object {
        // Preserve the original test failure while continuing cleanup.
      }
    }
    if (!await temporaryRoot.exists()) return;
    try {
      await temporaryRoot.delete(recursive: true);
    } on FileSystemException {
      await _makeWritable(temporaryRoot.path);
      await temporaryRoot.delete(recursive: true);
    }
  }
}

const _linkedCanonicalSlot = 'linked-canonical';
const _linkedCanonicalAgentId = 'custom-linked-canonical';

/// A Home whose canonical `.agents/skills` is a link, as dotfiles setups
/// make it, to its own folder or to the Agent's compatibility root.
final class _LinkedCanonicalFixture {
  _LinkedCanonicalFixture._({
    required this.temporaryRoot,
    required this.agentHome,
    required this.canonicalSkillsRoot,
    required this.linkTarget,
    required this.compatibilitySkillsRoot,
  });

  final Directory temporaryRoot;
  final Directory agentHome;
  final String canonicalSkillsRoot;
  final String linkTarget;
  final String compatibilitySkillsRoot;
  SkillsRepository? _repository;

  String get compatibilitySkillPath =>
      path.join(compatibilitySkillsRoot, _linkedCanonicalSlot);

  static Future<_LinkedCanonicalFixture> create({
    required bool sharesCompatibilityRoot,
  }) async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'skills-workspace-linked-canonical-e2e-',
    );
    final agentHome = Directory(path.join(temporaryRoot.path, 'home'));
    final compatibilitySkillsRoot = path.join(
      agentHome.path,
      '.legacy',
      'skills',
    );
    final fixture = _LinkedCanonicalFixture._(
      temporaryRoot: temporaryRoot,
      agentHome: agentHome,
      canonicalSkillsRoot: path.join(agentHome.path, '.agents', 'skills'),
      linkTarget: sharesCompatibilityRoot
          ? compatibilitySkillsRoot
          : path.join(agentHome.path, 'dotfiles', 'skills'),
      compatibilitySkillsRoot: compatibilitySkillsRoot,
    );
    await Directory(fixture.linkTarget).create(recursive: true);
    await Directory(
      path.dirname(fixture.canonicalSkillsRoot),
    ).create(recursive: true);
    await _createDirectoryAlias(
      fixture.canonicalSkillsRoot,
      fixture.linkTarget,
    );
    await Directory(fixture.compatibilitySkillPath).create(recursive: true);
    await File(
      path.join(fixture.compatibilitySkillPath, 'SKILL.md'),
    ).writeAsString(
      '---\n'
      'name: $_linkedCanonicalSlot\n'
      'description: Linked canonical fixture\n'
      '---\n'
      '# Linked canonical\n',
      flush: true,
    );
    return fixture;
  }

  SkillsRepository createRepository() {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: path.join(temporaryRoot.absolute.path, 'workspace'),
        agentHomePath: agentHome.absolute.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
        additionalAgents: <AgentDefinition>[
          AgentDefinition(
            id: _linkedCanonicalAgentId,
            displayName: 'Linked Canonical',
            platforms: <DesktopPlatform, AgentPlatformDefinition>{
              _platform(): AgentPlatformDefinition(
                globalSkillsPath: canonicalSkillsRoot,
                globalDiscoverySkillsPaths: <String>[compatibilitySkillsRoot],
              ),
            },
          ),
        ],
      ),
    );
    _repository = repository;
    return repository;
  }

  /// The Activation lands in the link's target, and the link itself stays.
  Future<void> expectActivated(Matcher matcher) async {
    expect(
      await File(
        path.join(linkTarget, _linkedCanonicalSlot, 'SKILL.md'),
      ).exists(),
      matcher,
    );
    expect(
      path.equals(
        await Directory(canonicalSkillsRoot).resolveSymbolicLinks(),
        await Directory(linkTarget).resolveSymbolicLinks(),
      ),
      isTrue,
    );
    if (linkTarget != compatibilitySkillsRoot) {
      expect(await Directory(compatibilitySkillPath).exists(), isFalse);
    }
  }

  Future<void> dispose() async {
    final repository = _repository;
    if (repository != null && repository.isOpen) {
      try {
        await repository.close().completed;
      } on Object {
        // Preserve the original test failure while continuing cleanup.
      }
    }
    if (!await temporaryRoot.exists()) return;
    try {
      await temporaryRoot.delete(recursive: true);
    } on FileSystemException {
      await _makeWritable(temporaryRoot.path);
      await temporaryRoot.delete(recursive: true);
    }
  }
}

Future<void> _createDirectoryAlias(String alias, String target) async {
  if (!Platform.isWindows) {
    await Link(alias).create(target);
    return;
  }
  final result = await Process.run('cmd.exe', <String>[
    '/d',
    '/c',
    'mklink',
    '/J',
    alias,
    target,
  ], runInShell: false);
  if (result.exitCode != 0) {
    throw FileSystemException(
      'Unable to create the Windows compatibility junction.',
      alias,
    );
  }
}

final class _ExternalAdoptionFixture {
  _ExternalAdoptionFixture._({
    required this.temporaryRoot,
    required this.workspaceRoot,
    required this.agentHome,
    required this.firstSkillsRoot,
    required this.secondSkillsRoot,
  });

  final Directory temporaryRoot;
  final Directory workspaceRoot;
  final Directory agentHome;
  final Directory firstSkillsRoot;
  final Directory secondSkillsRoot;
  final List<SkillsRepository> _repositories = <SkillsRepository>[];

  static Future<_ExternalAdoptionFixture> create({
    bool linksAndNfdName = false,
  }) async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'skills-workspace-external-adoption-e2e-',
    );
    final fixture = _ExternalAdoptionFixture._(
      temporaryRoot: temporaryRoot,
      workspaceRoot: Directory(path.join(temporaryRoot.path, 'workspace')),
      agentHome: Directory(path.join(temporaryRoot.path, 'agent-home')),
      firstSkillsRoot: Directory(
        path.join(temporaryRoot.path, 'agent-a-skills'),
      ),
      secondSkillsRoot: Directory(
        path.join(temporaryRoot.path, 'agent-b-skills'),
      ),
    );
    await fixture.agentHome.create(recursive: true);
    await fixture._writeSkill('a', linksAndNfdName: linksAndNfdName);
    await fixture._writeSkill('b', linksAndNfdName: linksAndNfdName);
    return fixture;
  }

  List<AgentDefinition> get agentDefinitions => <AgentDefinition>[
    AgentDefinition(
      id: _firstAgentId,
      displayName: 'External Adoption A',
      platforms: <DesktopPlatform, AgentPlatformDefinition>{
        _platform(): AgentPlatformDefinition(
          globalSkillsPath: firstSkillsRoot.absolute.path,
        ),
      },
    ),
    AgentDefinition(
      id: _secondAgentId,
      displayName: 'External Adoption B',
      platforms: <DesktopPlatform, AgentPlatformDefinition>{
        _platform(): AgentPlatformDefinition(
          globalSkillsPath: secondSkillsRoot.absolute.path,
        ),
      },
    ),
  ];

  SkillsRepository createRepository({bool includeCustomAgents = true}) {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: workspaceRoot.absolute.path,
        agentHomePath: agentHome.absolute.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
        additionalAgents: includeCustomAgents ? agentDefinitions : const [],
      ),
    );
    _repositories.add(repository);
    return repository;
  }

  String skillPath(String authority) => path.join(
    authority == 'a' ? firstSkillsRoot.path : secondSkillsRoot.path,
    _slotKey,
  );

  Future<void> expectMaterializations(String authority) async {
    final expected = 'body $authority\n';
    for (final root in <String>[
      path.join(workspaceRoot.path, 'repository-copies', _slotKey),
      skillPath('a'),
      skillPath('b'),
    ]) {
      expect(await File(path.join(root, 'body.md')).readAsString(), expected);
    }
    expect(
      await Directory(
        path.join(workspaceRoot.path, 'repository-copies', _slotKey, '.git'),
      ).exists(),
      isFalse,
    );
  }

  Future<void> _writeSkill(
    String authority, {
    String folderName = _slotKey,
    String declaredName = _slotKey,
    bool linksAndNfdName = false,
  }) async {
    final root = path.join(
      authority == 'a' ? firstSkillsRoot.path : secondSkillsRoot.path,
      folderName,
    );
    await Directory(root).create(recursive: true);
    await File(path.join(root, 'SKILL.md')).writeAsString(
      '---\n'
      'name: $declaredName\n'
      'description: External adoption $authority\n'
      '---\n'
      '# External adoption\n',
      flush: true,
    );
    await File(
      path.join(root, 'body.md'),
    ).writeAsString('body $authority\n', flush: true);
    await Directory(path.join(root, '.git')).create();
    await File(
      path.join(root, '.git', 'config'),
    ).writeAsString('external metadata $authority\n', flush: true);
    if (!linksAndNfdName) return;
    // The shapes real users have: links that stay inside the Skill (as
    // `npx skills` and agent templates create them) and a decomposed name.
    await File(
      path.join(root, 'AGENTS.md'),
    ).writeAsString('agents $authority\n', flush: true);
    await Directory(path.join(root, 'docs')).create();
    await File(
      path.join(root, 'docs', 'guide.md'),
    ).writeAsString('guide $authority\n', flush: true);
    await File(
      path.join(root, _nfdFileName),
    ).writeAsString('nfd $authority\n', flush: true);
    if (!Platform.isWindows) {
      await Link(path.join(root, 'CLAUDE.md')).create('AGENTS.md');
      await Link(path.join(root, 'docs-link')).create('docs');
    }
  }

  Future<void> dispose() async {
    for (final repository in _repositories.reversed) {
      if (!repository.isOpen) continue;
      try {
        await repository.close().completed;
      } on Object {
        // Preserve the original test failure while continuing cleanup.
      }
    }
    if (!await temporaryRoot.exists()) return;
    try {
      await temporaryRoot.delete(recursive: true);
    } on FileSystemException {
      await _makeWritable(temporaryRoot.path);
      await temporaryRoot.delete(recursive: true);
    }
  }
}

Future<T> _expectSuccess<T>(SkillsOperation<T> operation) async {
  final result = await operation.completed;
  final value = result.valueOrNull;
  if (value == null) {
    fail('expected success, got ${result.failureOrNull?.code}');
  }
  return value;
}

Future<void> _expectVoidSuccess(SkillsOperation<void> operation) async {
  final result = await operation.completed;
  expect(
    result.isSuccess,
    isTrue,
    reason: 'expected success, got ${result.failureOrNull?.code}',
  );
}

Future<void> _makeWritable(String rootPath) async {
  final ProcessResult result;
  if (Platform.isWindows) {
    result = await Process.run('attrib', <String>[
      '-R',
      path.join(rootPath, '*'),
      '/S',
      '/D',
    ]);
  } else {
    result = await Process.run('chmod', <String>['-R', 'u+w', rootPath]);
  }
  if (result.exitCode != 0) {
    throw FileSystemException('Unable to make temporary test root writable.');
  }
}

DesktopPlatform _platform() => switch (Platform.operatingSystem) {
  'macos' => DesktopPlatform.macos,
  'windows' => DesktopPlatform.windows,
  _ => DesktopPlatform.linux,
};

/// How a dotfiles setup can make the universal root and Claude Code's root one
/// physical folder.
enum _SharedRootLayout {
  /// `~/.agents/skills -> ~/.claude/skills`.
  universalLinksToClaude,

  /// `~/.claude/skills -> ~/.agents/skills`.
  claudeLinksToUniversal,

  /// Both roots link to `~/dotfiles/skills`, a Git checkout.
  bothLinkToDotfiles,
}

/// A Home whose built-in Claude Code root and universal `.agents/skills` root
/// resolve to one directory holding several external Skills.
final class _SharedRootFixture {
  _SharedRootFixture._({
    required this.temporaryRoot,
    required this.agentHome,
    required this.physicalRoot,
    required this.links,
  });

  static const slotKeys = <String>['plain', 'linked', 'checked-out', 'cased'];

  final Directory temporaryRoot;
  final Directory agentHome;
  final String physicalRoot;
  final List<String> links;
  SkillsRepository? _repository;

  static Future<_SharedRootFixture> create(_SharedRootLayout layout) async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'skills-workspace-shared-root-e2e-',
    );
    final agentHome = Directory(path.join(temporaryRoot.path, 'home'));
    final universalRoot = path.join(agentHome.path, '.agents', 'skills');
    final claudeRoot = path.join(agentHome.path, '.claude', 'skills');
    final (physicalRoot, links) = switch (layout) {
      _SharedRootLayout.universalLinksToClaude => (
        claudeRoot,
        <String>[universalRoot],
      ),
      _SharedRootLayout.claudeLinksToUniversal => (
        universalRoot,
        <String>[claudeRoot],
      ),
      _SharedRootLayout.bothLinkToDotfiles => (
        path.join(agentHome.path, 'dotfiles', 'skills'),
        <String>[universalRoot, claudeRoot],
      ),
    };
    final fixture = _SharedRootFixture._(
      temporaryRoot: temporaryRoot,
      agentHome: agentHome,
      physicalRoot: physicalRoot,
      links: links,
    );
    // Detect Cursor as a universal Agent; `.claude` detects Claude Code.
    await Directory(
      path.join(agentHome.path, '.cursor'),
    ).create(recursive: true);
    await Directory(physicalRoot).create(recursive: true);
    if (layout == _SharedRootLayout.bothLinkToDotfiles) {
      await Directory(
        path.join(agentHome.path, 'dotfiles', '.git'),
      ).create(recursive: true);
    }
    for (final link in links) {
      await Directory(path.dirname(link)).create(recursive: true);
      await _createDirectoryAlias(link, physicalRoot);
    }
    await fixture._writeSkills();
    return fixture;
  }

  Future<void> _writeSkills() async {
    for (final slotKey in slotKeys) {
      final folder = slotKey == 'cased' ? 'Cased' : slotKey;
      final root = path.join(physicalRoot, folder);
      await Directory(root).create();
      await File(path.join(root, 'SKILL.md')).writeAsString(
        '---\n'
        'name: $slotKey\n'
        'description: Shared root $slotKey\n'
        '---\n'
        '# $slotKey\n',
        flush: true,
      );
      await File(
        path.join(root, 'body.md'),
      ).writeAsString('body $slotKey\n', flush: true);
      switch (slotKey) {
        case 'linked':
          await File(
            path.join(root, 'AGENTS.md'),
          ).writeAsString('agents\n', flush: true);
          await Directory(path.join(root, 'docs')).create();
          await File(
            path.join(root, 'docs', 'guide.md'),
          ).writeAsString('guide\n', flush: true);
          await File(
            path.join(root, _nfdFileName),
          ).writeAsString('nfd\n', flush: true);
          if (!Platform.isWindows) {
            await Link(path.join(root, 'CLAUDE.md')).create('AGENTS.md');
            await Link(path.join(root, 'docs-link')).create('docs');
          }
        case 'checked-out':
          await Directory(path.join(root, '.git')).create();
          await File(
            path.join(root, '.git', 'config'),
          ).writeAsString('checkout\n', flush: true);
      }
    }
  }

  SkillsRepository createRepository() {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: path.join(temporaryRoot.absolute.path, 'workspace'),
        agentHomePath: agentHome.absolute.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
      ),
    );
    _repository = repository;
    return repository;
  }

  Future<bool> isPhysicalRoot(String location) async => path.equals(
    await Directory(location).resolveSymbolicLinks(),
    await Directory(physicalRoot).resolveSymbolicLinks(),
  );

  /// Every Skill is materialized once, in the physical folder.
  Future<void> expectActivated(Matcher matcher) async {
    for (final slotKey in slotKeys) {
      expect(
        await File(path.join(physicalRoot, slotKey, 'SKILL.md')).exists(),
        matcher,
        reason: slotKey,
      );
    }
  }

  /// The configured links survive every mutation and still point at the
  /// physical folder.
  Future<void> expectLinksIntact() async {
    for (final link in links) {
      expect(
        await FileSystemEntity.type(link, followLinks: false),
        Platform.isWindows
            ? isNot(FileSystemEntityType.notFound)
            : FileSystemEntityType.link,
        reason: link,
      );
      expect(await isPhysicalRoot(link), isTrue, reason: link);
    }
  }

  Future<void> dispose() async {
    final repository = _repository;
    if (repository != null && repository.isOpen) {
      try {
        await repository.close().completed;
      } on Object {
        // Preserve the original test failure while continuing cleanup.
      }
    }
    if (!await temporaryRoot.exists()) return;
    try {
      await temporaryRoot.delete(recursive: true);
    } on FileSystemException {
      await _makeWritable(temporaryRoot.path);
      await temporaryRoot.delete(recursive: true);
    }
  }
}
