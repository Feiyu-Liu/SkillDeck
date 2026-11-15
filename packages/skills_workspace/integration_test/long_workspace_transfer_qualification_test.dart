// Explicit qualification beyond the supported ordinary Workspace path gate.
// On Windows, current pre-existing fresh-start/Control Plane IO blocks this
// scenario before transfer. Keep the failure visible; this test is not skipped.
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:skills_workspace/skills_workspace.dart';
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:test/test.dart';
import '../test/support/git_transport/git_http_backend_server.dart';

void main() {
  final priorWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = priorWarning,
  );
  late Directory root;
  late SkillsRepository a;
  late ManagedSkillId aId;
  Future<T> success<T>(SkillsOperation<T> operation) async {
    final result = await operation.completed;
    expect(result, isA<SkillsSuccess<T>>(), reason: '$result');
    return result.valueOrNull as T;
  }

  Future<CommittedRevisionBatch> capture(
    SkillsRepository repo,
    ManagedSkillId id,
  ) => success(
    repo.exportCommittedRevision(
      ExportCommittedRevisionRequest(
        managedSkillId: id,
        expectedRevision: repo.snapshot.revision,
      ),
    ),
  );
  String workspace(String name) => path.join(root.path, name);
  SkillsRepository create(String name) => createSkillsRepository(
    SkillsRepositoryConfiguration(
      rootPath: workspace(name),
      agentHomePath: workspace('agent-home'),
      defaultLockWaitPolicy: LockWaitPolicy.wait(
        timeout: const Duration(seconds: 10),
      ),
    ),
  );
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'long-workspace-qualification-',
    );
    final source = await Directory(workspace('source')).create();
    await File(path.join(source.path, 'SKILL.md')).writeAsString(
      '---\nname: long-path-fixture\ndescription: Disposable qualification\n---\n# Fixture\n',
    );
    a = create('a');
    await success(a.open());
    final installed =
        await success(
              a.install(
                InstallRequest(
                  source: LocalSourceDescriptor(locator: source.path),
                  activationSelection: const ActivationSelection.none(),
                ),
              ),
            )
            as InstallCompleted;
    aId = installed.report.affectedSkillIds.single;
  });
  tearDown(() async {
    if (a.isOpen) await a.close().completed;
    await PlatformDurableWorkspaceFilesystem().removeOwnedPath(
      targetPath: root.path,
      ownerRoot: root.parent.path,
    );
  });
  test(
    'public transfers round trip under a long Unicode canonical Workspace',
    () async {
      final longName = path.joinAll([
        'long-workspace',
        for (var i = 0; i < 6; i++) '路径-😀-${'segment' * 5}-$i',
      ]);
      final remotePath = path.join(root.path, 'long-remote.git');
      expect(
        (await Process.run('git', ['init', '--bare', remotePath])).exitCode,
        0,
      );
      expect(
        (await Process.run('git', [
          'config',
          'http.receivepack',
          'true',
        ], workingDirectory: remotePath)).exitCode,
        0,
      );
      final server = await GitHttpBackendServer.start(
        projectRoot: root.path,
        bearerToken: 'disposable-long-path-token',
      );
      final receiver = create(longName);
      try {
        await success(receiver.open());
        final initial = await success(
          receiver.captureAuthoritativeState(
            const CaptureAuthoritativeStateRequest(),
          ),
        );
        final batch = await capture(a, aId);
        final incoming = await success(
          receiver.prepareIncomingRevision(
            PrepareIncomingRevisionRequest(
              expectedIdentity: initial.identity,
              expectedRevision: receiver.snapshot.revision,
              contentManifest: batch.wireManifest,
              packBytes: batch.packBytes,
            ),
          ),
        );
        final installed =
            await success(
                  receiver.installIncomingRevision(
                    InstallIncomingRevisionRequest(
                      expectedIdentity: initial.identity,
                      expectedRevision: receiver.snapshot.revision,
                      incoming: incoming,
                    ),
                  ),
                )
                as IncomingRevisionInstalled;
        final id = installed.managedSkillId;
        expect(
          path
              .join(workspace(longName), 'revision-stores', '${id.value}.git')
              .length,
          greaterThan(320),
        );
        final exported = await capture(receiver, id);
        expect(exported.currentEffective, batch.currentEffective);
        final remote = RevisionTransferRemote.loopbackForTesting(
          url: server.locatorFor('long-remote.git'),
          ephemeralHeaders: () async => [
            'Authorization: Bearer disposable-long-path-token',
          ],
        );
        await success(
          receiver.pushCommittedRevision(
            PushCommittedRevisionRequest(
              managedSkillId: id,
              expectedIdentity: initial.identity,
              expectedRevision: receiver.snapshot.revision,
              batch: exported,
              remote: remote,
            ),
          ),
        );
        final fetched = await success(
          receiver.fetchIncomingRevision(
            FetchIncomingRevisionRequest(
              managedSkillId: id,
              expectedIdentity: initial.identity,
              expectedRevision: receiver.snapshot.revision,
              contentManifest: exported.wireManifest,
              remote: remote,
            ),
          ),
        );
        expect(fetched.currentEffective, exported.currentEffective);
        expect(
          (await success(
            receiver.captureAuthoritativeState(
              const CaptureAuthoritativeStateRequest(),
            ),
          )).isComplete,
          isTrue,
        );
        await success(
          receiver.remove(
            RemoveRequest(
              managedSkillIds: {id},
              intent: DestructiveIntent(
                reviewedRevision: receiver.snapshot.revision,
              ),
            ),
          ),
        );
        final removed = await success(
          receiver.captureAuthoritativeState(
            const CaptureAuthoritativeStateRequest(),
          ),
        );
        expect(removed.isComplete, isTrue);
        expect(removed.snapshot.managedSkills, isEmpty);
      } finally {
        if (receiver.isOpen) await receiver.close().completed;
        await server.close();
      }
    },
  );
}
