import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skills_manager/features/command_host/data/command_line_distribution.dart';
import 'package:skills_manager/features/command_host/data/command_line_distribution_service.dart';
import 'package:skills_manager/features/command_host/data/skilldeck_agent_skill_service.dart';
import 'package:skills_manager/features/command_host/presentation/command_line_distribution_providers.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:yaml/yaml.dart';

import 'support/write_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late File bundled;
  late List<int> skillBytes;
  late List<String> diagnostics;

  CommandLineDistributionService distribution({
    Future<void> Function(File)? prepareExecutable,
    bool isWindows = false,
  }) => CommandLineDistributionService(
    rootDirectory: p.join(temp.path, '.skilldeck'),
    bundledExecutable: bundled.path,
    isWindows: isWindows,
    loadSkill: () async => skillBytes,
    diagnostics: AppDiagnostics.debug(writer: diagnostics.add),
    prepareExecutable: prepareExecutable,
  );

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-distribution-');
    bundled = File(p.join(temp.path, 'bundled'));
    skillBytes = utf8.encode('first asset');
    diagnostics = [];
  });
  tearDown(() async => temp.delete(recursive: true));

  group('stable tool', () {
    test(
      'copies a missing target, private directories and executable mode',
      () async {
        await bundled.writeAsString('binary');
        final service = distribution();
        final state = await service.ensureTool();
        expect(state.status, CommandLineToolStatus.ready);
        expect(state.path, service.toolPath);
        expect(await File(state.path).readAsString(), 'binary');
        if (!Platform.isWindows) {
          expect((await File(state.path).stat()).mode & 0x1ff, 0x1ed);
          expect(
            (await Directory(p.dirname(state.path)).stat()).mode & 0x1ff,
            0x1c0,
          );
        }
        expect(diagnostics.single, contains('"status":"ready"'));
        expect(diagnostics.single, isNot(contains(temp.path)));
      },
    );

    test(
      'skips identical bytes across launches and runs once per launch',
      () async {
        await bundled.writeAsString('same');
        final service = distribution();
        await service.ensureTool();
        final target = File(service.toolPath);
        final oldTime = DateTime.utc(2001);
        await target.setLastModified(oldTime);
        final next = distribution();
        final first = next.ensureTool();
        expect(identical(first, next.ensureTool()), isTrue);
        expect((await first).status, CommandLineToolStatus.ready);
        expect((await target.lastModified()).toUtc(), oldTime);
      },
    );

    test('replaces different bytes', () async {
      await bundled.writeAsString('first');
      final service = distribution();
      await service.ensureTool();
      await bundled.writeAsString('second');
      expect(
        (await distribution().ensureTool()).status,
        CommandLineToolStatus.ready,
      );
      expect(await File(service.toolPath).readAsString(), 'second');
      expect(await Directory(p.dirname(service.toolPath)).list().length, 1);
    });

    test('missing bundle preserves old copy and reports notBundled', () async {
      final service = distribution();
      await File(service.toolPath).create(recursive: true);
      await File(service.toolPath).writeAsString('old');
      expect(
        (await service.ensureTool()).status,
        CommandLineToolStatus.notBundled,
      );
      expect(await File(service.toolPath).readAsString(), 'old');
    });

    test('pre-rename write failure leaves the previous copy intact', () async {
      await bundled.writeAsString('new');
      final service = distribution(
        prepareExecutable: (_) async {
          throw const FileSystemException('private path or process output');
        },
      );
      final old = await File(service.toolPath).create(recursive: true);
      await old.writeAsString('old');
      expect((await service.ensureTool()).status, CommandLineToolStatus.failed);
      expect(await old.readAsString(), 'old');
      expect(await Directory(p.dirname(service.toolPath)).list().length, 1);
      expect(diagnostics.single, contains('"status":"failed"'));
      expect(diagnostics.single, isNot(contains('private path')));
    });

    test('directory creation error is failed', () async {
      await bundled.writeAsString('new');
      final service = distribution();
      await File(service.rootDirectory).writeAsString('obstruction');
      expect((await service.ensureTool()).status, CommandLineToolStatus.failed);
    });

    test('Windows uses skilldeck.exe', () async {
      expect(distribution(isWindows: true).toolPath, endsWith('skilldeck.exe'));
    });
  });

  group('maintained Agent Skill Source', () {
    test('writes the first tree and nothing else', () async {
      final service = distribution();
      expect(await service.ensureAgentSkillSource(), service.sourceDirectory);
      final entries = await Directory(service.sourceDirectory).list().toList();
      expect(entries.map((file) => p.basename(file.path)), ['SKILL.md']);
      expect(await File(entries.single.path).readAsBytes(), skillBytes);
      expect(
        await Directory(p.dirname(service.sourceDirectory)).list().length,
        1,
      );
    });

    test('skips unchanged bytes across launches', () async {
      final service = distribution();
      await service.ensureAgentSkillSource();
      final target = File(p.join(service.sourceDirectory, 'SKILL.md'));
      final oldTime = DateTime.utc(2001);
      await target.setLastModified(oldTime);
      await distribution().ensureAgentSkillSource();
      expect((await target.lastModified()).toUtc(), oldTime);
    });

    test('replaces changed tree and cleans staging', () async {
      final service = distribution();
      await service.ensureAgentSkillSource();
      skillBytes = utf8.encode('upgraded asset');
      await distribution().ensureAgentSkillSource();
      expect(
        await File(p.join(service.sourceDirectory, 'SKILL.md')).readAsBytes(),
        skillBytes,
      );
      expect(
        await Directory(p.dirname(service.sourceDirectory)).list().length,
        1,
      );
    });

    test('asset read failure preserves previous Source', () async {
      final service = distribution();
      await service.ensureAgentSkillSource();
      final failing = CommandLineDistributionService(
        rootDirectory: service.rootDirectory,
        bundledExecutable: bundled.path,
        isWindows: false,
        loadSkill: () async => throw StateError('unavailable'),
        diagnostics: AppDiagnostics.disabled(),
      );
      await expectLater(failing.ensureAgentSkillSource(), throwsStateError);
      expect(
        await File(p.join(service.sourceDirectory, 'SKILL.md')).readAsBytes(),
        skillBytes,
      );
    });
  });

  group('install', () {
    late WriteRepository repository;
    late LocalSkillDeckAgentSkillService service;
    setUp(() {
      repository = WriteRepository()
        ..candidates = [WriteRepository.candidate('skilldeck')];
      final files = distribution();
      service = LocalSkillDeckAgentSkillService(
        repository: () => repository,
        sourceDirectory: files.ensureAgentSkillSource,
      );
    });
    tearDown(() => repository.publications.close());

    for (final agents in [
      <String>{},
      {'codex', 'claude'},
    ]) {
      test('global install for $agents carries Source and name', () async {
        expect(await service.install(agentIds: agents), isNull);
        final request = repository.installRequests.single;
        expect(request.source.kind, WorkspaceSourceKind.local);
        expect(request.source.locator, distribution().sourceDirectory);
        expect(request.skillNames, {'skilldeck'});
        expect(request.scope, WorkspaceScope.global);
        expect(request.projectRootId, isNull);
        expect(request.agentIds, agents);
        expect(request.storeOnly, agents.isEmpty);
      });
    }

    test('takeover returns a stable failure without confirming', () async {
      repository.occupied = true;
      final failure = await service.install(agentIds: {'codex'});
      expect(failure?.codeKey, 'activationTargetOccupied');
      expect(repository.calls, ['install']);
    });

    test('Workspace failures pass through', () async {
      repository.failures[1] = WorkspaceErrorCode.ioFailure;
      expect((await service.install(agentIds: {}))?.codeKey, 'ioFailure');
    });

    test('committed pending is distinguished from success', () async {
      repository.pending.add(1);
      expect(
        (await service.install(agentIds: {}))?.codeKey,
        'committedFinalizationPending',
      );
    });
  });

  group('providers', () {
    test('unconfigured distribution never accesses home', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        (await container.read(commandLineToolProvider.future)).status,
        CommandLineToolStatus.notBundled,
      );
      expect(container.read(skillDeckAgentSkillProvider).installed, isFalse);
      expect(
        await container.read(skillDeckAgentSkillSourceProvider.future),
        isNull,
      );
      expect(
        (await container
                .read(skillDeckAgentSkillServiceProvider)
                .install(agentIds: {}))
            ?.codeKey,
        'sourceUnavailable',
      );
    });

    test(
      'installed identity and global Agents follow Snapshot publications',
      () async {
        final files = distribution();
        final repository = WriteRepository();
        final container = ProviderContainer(
          overrides: [
            commandLineDistributionServiceProvider.overrideWithValue(files),
            skillsWorkspaceRepositoryProvider.overrideWithValue(repository),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await repository.publications.close();
        });
        await container.read(workspaceSnapshotProvider.future);
        expect(container.read(skillDeckAgentSkillProvider).installed, isFalse);

        WorkspaceSkill skill({
          required String locator,
          WorkspaceSourceKind kind = WorkspaceSourceKind.local,
        }) => WorkspaceSkill(
          id: WorkspaceSkillId('managed-skilldeck'),
          slotKey: 'skilldeck',
          declaredName: 'skilldeck',
          displayName: 'skilldeck',
          description: 'CLI guidance',
          source: SkillSourceProvenance(kind: kind, locator: locator),
          currentRevision: SkillRevision(
            contentHash: 'hash',
            fileCount: 1,
            byteSize: 10,
            acquiredAt: DateTime.utc(2026),
          ),
          activations: [
            SkillActivationLocation(
              location: p.join(temp.path, 'global'),
              scope: WorkspaceScope.global,
              mode: WorkspaceActivationMode.copy,
              agentIds: ['codex', 'claude'],
            ),
            SkillActivationLocation(
              location: p.join(temp.path, 'project'),
              scope: WorkspaceScope.project,
              mode: WorkspaceActivationMode.copy,
              agentIds: ['cursor'],
            ),
          ],
        );
        var revision = 10;
        Future<void> publish(WorkspaceSkill next) async {
          repository.publications.add(
            SkillsWorkspaceSnapshot(
              revision: revision++,
              projectRoots: [],
              skills: [next],
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }

        await publish(skill(locator: files.sourceDirectory));
        final installed = container.read(skillDeckAgentSkillProvider);
        expect(installed.installed, isTrue);
        expect(installed.skillId, WorkspaceSkillId('managed-skilldeck'));
        expect(installed.activeAgentIds, {'codex', 'claude'});
        await publish(skill(locator: p.join(temp.path, 'user-skilldeck')));
        expect(container.read(skillDeckAgentSkillProvider).installed, isFalse);
        await publish(
          skill(locator: files.sourceDirectory, kind: WorkspaceSourceKind.git),
        );
        expect(container.read(skillDeckAgentSkillProvider).installed, isFalse);
      },
    );
  });

  test(
    'shipped asset has parseable frontmatter and required guidance',
    () async {
      final text = await rootBundle.loadString(skillDeckAgentSkillAsset);
      final parts = text.split('---');
      final frontmatter = loadYaml(parts[1]) as YamlMap;
      expect(frontmatter['name'], 'skilldeck');
      expect(frontmatter['description'], isA<String>());
      expect((frontmatter['description'] as String).trim(), isNotEmpty);
      final body = parts.skip(2).join('---');
      expect(body, contains('--json'));
      expect(body, contains('approvals wait'));
      expect(body, contains('| 5 |'));
      expect(text.split('\n').length, lessThanOrEqualTo(120));
    },
  );
}
