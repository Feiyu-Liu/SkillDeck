import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

/// A real public-facade runtime with isolated Source and Agent directories.
final class DriftFacadeFixture {
  DriftFacadeFixture._(this.temporaryRoot);

  static const skillName = 'drift-skill';
  static const baseNotes = 'base notes\n';
  static const firstAgentId = 'drift-facade-agent-a';
  static const secondAgentId = 'drift-facade-agent-b';

  final Directory temporaryRoot;
  final List<SkillsRepository> _repositories = [];
  late final SkillsRepository repository;
  late final ManagedSkillId managedSkillId;

  String get workspacePath => path.join(temporaryRoot.path, 'workspace');
  String get sourcePath => path.join(temporaryRoot.path, 'source');
  String get agentHomePath => path.join(temporaryRoot.path, 'agent-home');
  String get repositoryCopyPath =>
      path.join(workspacePath, 'repository-copies', skillName);
  String get exportDirectory => path.join(temporaryRoot.path, 'exports');

  String activationRoot([String agentId = firstAgentId]) =>
      path.join(agentHomePath, agentId, 'skills');

  String activationPath([String agentId = firstAgentId]) =>
      path.join(activationRoot(agentId), skillName);

  static Future<DriftFacadeFixture> create({
    RequestedActivationMode mode = RequestedActivationMode.copy,
    bool twoActivations = false,
    bool activate = true,
  }) async {
    final fixture = DriftFacadeFixture._(
      await Directory.systemTemp.createTemp('skills-workspace-drift-facade-'),
    );
    addTearDown(fixture.dispose);
    await Directory(fixture.agentHomePath).create(recursive: true);
    await Directory(fixture.sourcePath).create(recursive: true);
    await Directory(fixture.exportDirectory).create();
    await fixture.writeSkillMarkdown(fixture.sourcePath);
    await File(
      path.join(fixture.sourcePath, 'notes.md'),
    ).writeAsString(baseNotes, flush: true);
    fixture.repository = fixture.createRepository();
    await driftSuccess(fixture.repository.open());
    final installed = await driftSuccess(
      fixture.repository.install(
        InstallRequest(
          source: LocalSourceDescriptor(locator: fixture.sourcePath),
          activationSelection: activate
              ? ActivationSelection.explicit([
                  ActivationTarget(
                    agentId: firstAgentId,
                    scope: ActivationScope.global,
                  ),
                  if (twoActivations)
                    ActivationTarget(
                      agentId: secondAgentId,
                      scope: ActivationScope.global,
                    ),
                ])
              : const ActivationSelection.none(),
          activationMode: mode,
        ),
      ),
    );
    fixture.managedSkillId =
        (installed as InstallCompleted).report.affectedSkillIds.single;
    return fixture;
  }

  SkillsRepository createRepository() {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: workspacePath,
        agentHomePath: agentHomePath,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
        additionalAgents: [
          for (final id in [firstAgentId, secondAgentId])
            AgentDefinition(
              id: id,
              displayName: id,
              platforms: {
                _platform: AgentPlatformDefinition(
                  globalSkillsPath: activationRoot(id),
                ),
              },
            ),
        ],
      ),
    );
    _repositories.add(repository);
    return repository;
  }

  Future<SkillDriftReview> inspect() => driftSuccess(
    repository.inspectSkillDrift(
      InspectSkillDriftRequest(managedSkillId: managedSkillId),
    ),
  );

  Future<MutationReport> resolve(
    SkillDriftReview review,
    SkillDriftResolution resolution,
  ) => driftSuccess(
    repository.resolveSkillDrift(
      ResolveSkillDriftRequest(review: review, resolution: resolution),
    ),
  );

  Future<PublishedHistoryPage> history() => driftSuccess(
    repository.inspectPublishedHistory(
      PublishedHistoryRequest(managedSkillId: managedSkillId),
    ),
  );

  Future<void> changeNotes(String root, String contents) async {
    await makeWritable(root);
    await File(
      path.join(root, 'notes.md'),
    ).writeAsString(contents, flush: true);
  }

  Future<void> deleteArtifact(String target) async {
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.link) {
      await Link(target).delete();
    } else if (type == FileSystemEntityType.directory) {
      await makeWritable(target);
      await Directory(target).delete(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      await makeWritable(target);
      await File(target).delete();
    }
  }

  Future<void> makeWritable(String target) async {
    final result = await Process.run(
      Platform.isWindows ? 'attrib' : 'chmod',
      Platform.isWindows ? ['-R', target] : ['-R', 'u+w', target],
    );
    if (result.exitCode != 0) {
      throw FileSystemException('Failed to make test artifact writable.');
    }
    if (Platform.isWindows && await Directory(target).exists()) {
      final nested = await Process.run('attrib', [
        '-R',
        path.join(target, '*'),
        '/S',
        '/D',
      ]);
      if (nested.exitCode != 0) {
        throw FileSystemException('Failed to make test artifact writable.');
      }
    }
  }

  Future<void> writeSkillMarkdown(String root, {String name = skillName}) =>
      File(path.join(root, 'SKILL.md')).writeAsString(
        '---\nname: $name\ndescription: Drift facade test\n---\n# Skill\n',
        flush: true,
      );

  Future<void> expectEffectiveNotes(String contents) async {
    final manifest = await driftSuccess(
      repository.listEffectiveFiles(
        ListEffectiveFilesRequest(managedSkillId: managedSkillId),
      ),
    );
    final file = await driftSuccess(
      repository.readEffectiveFile(
        ReadEffectiveFileRequest(
          managedSkillId: managedSkillId,
          expectedContentHash: manifest.contentHash,
          relativePath: 'notes.md',
        ),
      ),
    );
    expect(utf8.decode(file.bytes), contents);
  }

  Future<void> expectMaterializedNotes(
    String contents, {
    bool secondActivation = false,
  }) async {
    for (final root in [
      repositoryCopyPath,
      activationPath(),
      if (secondActivation) activationPath(secondAgentId),
    ]) {
      expect(await File(path.join(root, 'notes.md')).readAsString(), contents);
    }
  }

  Future<void> dispose() async {
    for (final repository in _repositories.reversed) {
      if (repository.isOpen) await repository.close().completed;
    }
    if (await temporaryRoot.exists()) {
      await makeWritable(temporaryRoot.path);
      await temporaryRoot.delete(recursive: true);
    }
  }
}

Future<T> driftSuccess<T>(SkillsOperation<T> operation) async {
  final result = await operation.completed;
  expect(result, isA<SkillsSuccess<T>>(), reason: '$result');
  return result.valueOrNull as T;
}

Future<void> driftFailure<T>(
  SkillsOperation<T> operation,
  SkillsErrorCode code, {
  String? reason,
}) async {
  final result = await operation.completed;
  expect(result, isA<SkillsFailure<T>>(), reason: '$result');
  expect(result.failureOrNull?.code, code);
  if (reason != null) expect(result.failureOrNull?.context['reason'], reason);
}

DesktopPlatform get _platform => Platform.isMacOS
    ? DesktopPlatform.macos
    : Platform.isWindows
    ? DesktopPlatform.windows
    : DesktopPlatform.linux;
