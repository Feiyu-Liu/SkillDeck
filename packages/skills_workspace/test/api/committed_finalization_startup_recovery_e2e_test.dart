import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  test(
    'first reopen resumes a real committed finalization before publishing',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      var repository = fixture.createRepository();
      await _expectSuccess(repository.open(), label: 'initial open');
      final installed =
          (await _expectSuccess(
                    repository.install(
                      InstallRequest(
                        source: LocalSourceDescriptor(
                          locator: fixture.source.path,
                        ),
                        activationSelection: const ActivationSelection.none(),
                      ),
                    ),
                    label: 'install',
                  )
                  as InstallCompleted)
              .report;
      final managedSkillId = installed.affectedSkillIds.single;

      final blocker = await fixture.blockBackupPublication();
      final result = await repository
          .setFavorite(
            SetFavoriteRequest(
              managedSkillId: managedSkillId,
              isFavorite: true,
            ),
          )
          .completed;
      await blocker.restore();
      final pending = result.finalizationPendingOrNull;
      expect(
        pending,
        isNotNull,
        reason: 'the real finalization fault must occur after business commit',
      );
      expect(
        repository.snapshot.findSkill(managedSkillId)?.favorite.isFavorite,
        isTrue,
      );

      await _expectSuccess(repository.close(), label: 'close pending facade');
      repository = fixture.createRepository();

      final reopened = await _expectSuccess(
        repository.open(),
        label: 'first reopen recovery',
      );
      expect(
        reopened.revision.value,
        greaterThanOrEqualTo(pending!.committedRepositoryRevision.value),
      );
      expect(reopened.findSkill(managedSkillId)?.favorite.isFavorite, isTrue);

      await _expectSuccess(
        repository.resumeFinalizationRecovery(),
        label: 'idempotent explicit recovery',
      );
      await _expectSuccess(repository.close(), label: 'final close');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

final class _Fixture {
  _Fixture._({
    required this.root,
    required this.workspace,
    required this.agentHome,
    required this.source,
  });

  final Directory root;
  final Directory workspace;
  final Directory agentHome;
  final Directory source;
  final List<SkillsRepository> _repositories = [];

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp(
      'skills-workspace-finalization-startup-e2e-',
    );
    final workspace = Directory(path.join(root.path, 'workspace'));
    final agentHome = Directory(path.join(root.path, 'agent-home'));
    final source = Directory(path.join(root.path, 'source'));
    await agentHome.create(recursive: true);
    await source.create(recursive: true);
    await File(path.join(source.path, 'SKILL.md')).writeAsString(
      '---\n'
      'name: finalization-startup-e2e\n'
      'description: Startup finalization recovery fixture.\n'
      '---\n'
      '# Finalization startup recovery\n',
      flush: true,
    );
    return _Fixture._(
      root: root,
      workspace: workspace,
      agentHome: agentHome,
      source: source,
    );
  }

  SkillsRepository createRepository() {
    final repository = createSkillsRepository(
      SkillsRepositoryConfiguration(
        rootPath: workspace.absolute.path,
        agentHomePath: agentHome.absolute.path,
        defaultLockWaitPolicy: LockWaitPolicy.wait(
          timeout: const Duration(seconds: 10),
        ),
      ),
    );
    _repositories.add(repository);
    return repository;
  }

  Future<_BackupPublicationBlocker> blockBackupPublication() async {
    final active = Directory(
      path.join(workspace.path, 'control-plane-backups', '0'),
    );
    final parked = Directory('${active.path}.parked');
    expect(await active.exists(), isTrue);
    await active.rename(parked.path);
    final blocker = File(active.path);
    await blocker.writeAsString('finalization fault fixture', flush: true);
    return _BackupPublicationBlocker(
      blocker: blocker,
      parked: parked,
      active: active,
    );
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
    if (!await root.exists()) return;
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      await _makeTreeWritable(root.path);
      await root.delete(recursive: true);
    }
  }
}

final class _BackupPublicationBlocker {
  _BackupPublicationBlocker({
    required this.blocker,
    required this.parked,
    required this.active,
  });

  final File blocker;
  final Directory parked;
  final Directory active;
  bool _restored = false;

  Future<void> restore() async {
    if (_restored) return;
    _restored = true;
    if (await blocker.exists()) await blocker.delete();
    if (await parked.exists()) await parked.rename(active.path);
  }
}

Future<T> _expectSuccess<T>(
  SkillsOperation<T> operation, {
  required String label,
}) async {
  final result = await operation.completed;
  expect(result, isA<SkillsSuccess<T>>(), reason: '$label: $result');
  return result.valueOrNull as T;
}

Future<void> _makeTreeWritable(String rootPath) async {
  final ProcessResult result;
  if (Platform.isWindows) {
    final rootResult = await Process.run('attrib', ['-R', rootPath]);
    if (rootResult.exitCode != 0) {
      throw FileSystemException('Failed to make test root writable.', rootPath);
    }
    result = await Process.run('attrib', [
      '-R',
      path.join(rootPath, '*'),
      '/S',
      '/D',
    ]);
  } else {
    result = await Process.run('chmod', ['-R', 'u+w', rootPath]);
  }
  if (result.exitCode != 0) {
    throw FileSystemException('Failed to make test tree writable.', rootPath);
  }
}
