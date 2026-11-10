import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skills_manager/features/command_host/data/approval_command_handlers.dart';
import 'package:skills_manager/features/command_host/data/command_approval.dart';
import 'package:skills_manager/features/command_host/data/command_approval_registry.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/data/command_host_server.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import '../../support/recording_app_diagnostic_sink.dart';
import 'support/approval_presenter.dart';
import 'support/read_fixtures.dart';
import 'support/write_repository.dart';

void main() {
  late Directory temp;
  late CommandHostServer server;
  late RecordingAppDiagnosticSink sink;
  SkillsWorkspaceSnapshot? snapshot;
  late WriteRepository repository;
  late ApprovalPresenter presenter;
  late CommandApprovalRegistry approvals;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-host-');
    sink = RecordingAppDiagnosticSink();
    snapshot = SkillsWorkspaceSnapshot.empty();
    repository = WriteRepository();
    presenter = ApprovalPresenter();
    approvals = CommandApprovalRegistry(
      presenter: presenter,
      repository: () => repository,
    );
    server = CommandHostServer(
      runDirectory: temp.path,
      isWindows: Platform.isWindows,
      appVersion: () async => '3.2.1',
      executablePath: p.join(temp.path, 'SkillDeck'),
      bundleIdentifier: 'test.skilldeck',
      diagnostics: AppDiagnostics(sink: sink),
      dispatcher: CommandHostDispatcher({
        'status': statusCommandHandler(
          appVersion: '3.2.1',
          snapshot: () => snapshot,
        ),
        ...approvalCommandHandlers(
          skillsLock: () => null,
          registry: approvals,
          repository: () => repository,
          snapshot: () => repository.current,
          updates: testUpdates,
          agents: () async => [testAgent()],
        ),
        'broken': (_) => throw StateError('sensitive content'),
      }),
    );
    await server.start();
  });
  tearDown(() async {
    await approvals.close();
    await repository.publications.close();
    await server.stop();
    await temp.delete(recursive: true);
  });
  Future<CommandResult> command(String command) =>
      CommandHostClient(runDirectory: temp.path)
          .execute(CommandRequest(command: command));
  Future<Socket> connect() async {
    final discovery = await readDiscovery(temp.path);
    return switch (discovery.endpoint) {
      UnixSocketEndpoint(:final path) => Socket.connect(
        InternetAddress(path, type: InternetAddressType.unix),
        0,
      ),
      LoopbackTcpEndpoint(:final port) => Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      ),
    };
  }

  Future<WireMessage> hello({String? secret, int version = 1}) async {
    final discovery = await readDiscovery(temp.path);
    final socket = await connect();
    final messages = StreamIterator(
      socket.cast<List<int>>().transform(const CommandHostDecoder()),
    );
    try {
      socket.add(
        encodeLine(
          ClientHello(
            protocolVersion: version,
            cliVersion: '0.1.0',
            secret: secret ?? discovery.secret,
          ),
        ),
      );
      expect(await messages.moveNext(), isTrue);
      return WireMessage.fromJson(messages.current);
    } finally {
      socket.destroy();
      await messages.cancel();
    }
  }

  test(
    'remove waits for App approval over a real Command Host connection',
    () async {
      var finished = false;
      final running = CommandHostClient(runDirectory: temp.path)
          .execute(
            CommandRequest(
              command: 'remove',
              arguments: {'selection': SkillSelection(all: true).toJson()},
            ),
          )
          .then((value) {
            finished = true;
            return value;
          });
      await presenter.presented.future;
      expect(finished, false);
      expect(repository.calls, isEmpty);
      presenter.decide(const CommandApprovalApproved(reviewedRevision: 37));
      final result = await running;
      expect(result.ok, true);
      expect(result.results, hasLength(3));
      expect(repository.calls, ['remove']);
      expect(repository.reviewedRevisions, [37]);
    },
  );

  test(
    'source replace waits for App approval and returns per-item mappings',
    () async {
      repository.candidates = [
        for (final s in repository.current.skills)
          WriteRepository.candidate(s.slotKey),
      ];
      var finished = false;
      final running = CommandHostClient(runDirectory: temp.path)
          .execute(
            CommandRequest(
              command: 'source replace',
              arguments: {
                'selection': SkillSelection(all: true).toJson(),
                'to': 'new/repo',
              },
            ),
          )
          .then((value) {
            finished = true;
            return value;
          });
      await presenter.presented.future;
      expect(finished, false);
      expect(repository.replaceSourceRequests, isEmpty);
      presenter.decide(const CommandApprovalApproved(reviewedRevision: 7));
      final result = await running;
      expect(result.ok, true);
      expect(result.results, hasLength(3));
      for (final row in result.results.cast<Map>()) {
        expect(row['outcome'], 'succeeded');
        expect((row['to'] as Map)['locator'], 'new/repo');
        expect((row['from'] as Map)['locator'], 'https://example.test/repo');
      }
      expect(repository.replaceSourceRequests.map((r) => r.expectedRevision), [
        7,
        8,
        9,
      ]);
      expect(jsonEncode(result.toJson()), isNot(contains('user:password')));
    },
  );

  test('disconnect leaves the request available to a new client', () async {
    final client = CommandHostClient(runDirectory: temp.path);
    final connection = await client.connect();
    final disconnected = connection.execute(
      CommandRequest(
        command: 'remove',
        arguments: {'selection': SkillSelection(all: true).toJson()},
      ),
    );
    final closedResult = expectLater(
      disconnected,
      throwsA(isA<ClientFailure>()),
    );
    await presenter.presented.future;
    final id = presenter.requests.single.id;
    await connection.close();
    await closedResult;
    final pending = await client.execute(
      CommandRequest(command: 'approvals status', arguments: {'id': id}),
    );
    expect(pending.data['state'], 'pending');
    expect(presenter.withdrawn, isEmpty);
    presenter.decide(const CommandApprovalApproved(reviewedRevision: 7));
    final result = await client.execute(
      CommandRequest(command: 'approvals wait', arguments: {'id': id}),
    );
    expect(result.ok, true);
    expect(result.command, 'approvals wait');
    expect((result.data['result'] as Map)['command'], 'remove');
    expect(repository.calls, ['remove']);
    expect(repository.taskCancelled, false);
  });

  test(
    'real client status round trip uses current snapshot and version',
    () async {
      final result = await command('status');
      expect(result.ok, isTrue);
      expect(result.results, isEmpty);
      expect(result.data, {
        'appVersion': '3.2.1',
        'protocolVersion': 1,
        'projectRoots': [],
        'workspace': {'state': 'ready', 'skillCount': 0, 'projectRootCount': 0},
      });
      snapshot = SkillsWorkspaceSnapshot(
        revision: 2,
        projectRoots: [
          SkillProjectRoot(id: 'project', path: p.join(temp.path, 'project')),
        ],
        skills: const [],
      );
      expect((await command('status')).data['workspace'], {
        'state': 'ready',
        'skillCount': 0,
        'projectRootCount': 1,
      });
      snapshot = null;
      expect(
        ((await command('status')).data['workspace'] as Map)['state'],
        'unavailable',
      );
    },
  );
  test('handshake accepts compatible authenticated peer', () async {
    expect(await hello(), isA<HostHello>());
  });
  test('handshake rejects incorrect secret and protocol', () async {
    expect(
      (await hello(secret: 'wrong') as HostReject).code,
      HostRejectCode.unauthorized,
    );
    expect(
      (await hello(version: 2) as HostReject).code,
      HostRejectCode.protocolMismatch,
    );
    final discovery = (await readDiscovery(temp.path)).toJson()
      ..['secret'] = base64Url.encode(List.filled(32, 0));
    await writePrivateFileAtomically(
      p.join(temp.path, commandHostDiscoveryFileName),
      utf8.encode(jsonEncode(discovery)),
    );
    await expectLater(
      command('status'),
      throwsA(
        isA<ClientFailure>().having(
          (e) => e.code,
          'code',
          ClientFailureCode.unauthorized,
        ),
      ),
    );
  });
  test(
    'unknown command and unexpected handler failure have stable errors',
    () async {
      expect((await command('unknown')).error?.code, 'unknownCommand');
      final broken = await command('broken');
      expect(broken.error?.code, 'internalError');
      expect(jsonEncode(broken.toJson()), isNot(contains('sensitive content')));
    },
  );
  test(
    'stop is idempotent, closes connections, and removes endpoint files',
    () async {
      final socket = await connect();
      final closed = socket.drain<void>();
      await server.stop();
      await server.stop();
      await closed.timeout(const Duration(seconds: 2));
      socket.destroy();
      expect(
        await File(p.join(temp.path, commandHostDiscoveryFileName)).exists(),
        isFalse,
      );
      expect(
        await File(p.join(temp.path, appLocationFileName)).exists(),
        isTrue,
      );
      expect(
        await FileSystemEntity.type(
          p.join(temp.path, commandHostSocketFileName),
        ),
        FileSystemEntityType.notFound,
      );
    },
  );
  test(
    'start records its launch target, and stop keeps it unchanged',
    () async {
      final location = await readAppLocation(temp.path);
      expect(location.toJson(), {
        'executablePath': p.join(temp.path, 'SkillDeck'),
        'bundleIdentifier': 'test.skilldeck',
        'appVersion': '3.2.1',
      });
      await server.stop();
      expect((await readAppLocation(temp.path)).toJson(), location.toJson());
      expect(
        await File(p.join(temp.path, commandHostDiscoveryFileName)).exists(),
        isFalse,
      );
    },
  );
  test('private discovery and run directory permissions', () async {
    expect(
      (await File(p.join(temp.path, appLocationFileName)).stat()).mode & 511,
      384,
    );
    expect((await Directory(temp.path).stat()).mode & 511, 448);
    expect(
      (await File(
            p.join(temp.path, commandHostDiscoveryFileName),
          ).stat()).mode &
          511,
      384,
    );
  }, skip: Platform.isWindows);
  test(
    'second host refuses live Unix socket without deleting discovery',
    () async {
      final discovery = await readDiscovery(temp.path);
      final second = CommandHostServer(
        runDirectory: temp.path,
        isWindows: false,
        appVersion: () async => 'other',
        dispatcher: CommandHostDispatcher({}),
        diagnostics: AppDiagnostics.disabled(),
      );
      await expectLater(
        second.start(),
        throwsA(
          isA<CommandHostStartFailure>().having(
            (e) => e.code,
            'code',
            CommandHostStartFailureCode.alreadyRunning,
          ),
        ),
      );
      await second.stop();
      expect((await readDiscovery(temp.path)).toJson(), discovery.toJson());
      expect((await command('status')).ok, isTrue);
    },
    skip: Platform.isWindows,
  );
  test('restart replaces stale socket and rotates per-launch secret', () async {
    final previous = await readDiscovery(temp.path);
    await server.stop();
    if (!Platform.isWindows) {
      final original = p.join(temp.path, 'crashed.sock');
      final stale = await ServerSocket.bind(
        InternetAddress(original, type: InternetAddressType.unix),
        0,
      );
      await File(original).rename(p.join(temp.path, commandHostSocketFileName));
      await stale.close();
    }
    final next = CommandHostServer(
      runDirectory: temp.path,
      isWindows: Platform.isWindows,
      appVersion: () async => '3.2.1',
      dispatcher: CommandHostDispatcher({}),
      diagnostics: AppDiagnostics.disabled(),
    );
    try {
      await next.start();
      expect((await readDiscovery(temp.path)).secret, isNot(previous.secret));
      expect(
        (await readAppLocation(temp.path)).executablePath,
        Platform.resolvedExecutable,
      );
      expect((await readAppLocation(temp.path)).bundleIdentifier, isNull);
    } finally {
      await next.stop();
    }
  });
  test('invalid JSON and oversize requests close the connection', () async {
    for (final bytes in [
      utf8.encode('not-json\n'),
      List.filled(maximumCommandHostLineBytes + 1, 32),
    ]) {
      final socket = await connect();
      final done = socket.drain<void>();
      socket.add(bytes);
      await done.timeout(const Duration(seconds: 2));
      socket.destroy();
    }
  });
  test(
    'diagnostics contain events and no credentials, arguments or unknown input',
    () async {
      final discovery = await readDiscovery(temp.path);
      const sensitive = 'https://user:secret@example.test/private-content';
      final socket = await connect();
      final messages = StreamIterator(
        socket.cast<List<int>>().transform(const CommandHostDecoder()),
      );
      socket.add(
        encodeLine(
          ClientHello(
            protocolVersion: 1,
            cliVersion: 'test',
            secret: discovery.secret,
          ),
        ),
      );
      expect(await messages.moveNext(), isTrue);
      socket.add(
        encodeLine(
          CommandRequest(
            command: sensitive,
            arguments: {'secret': sensitive, 'HOME': sensitive},
          ),
        ),
      );
      expect(await messages.moveNext(), isTrue);
      socket.destroy();
      await messages.cancel();
      await server.stop();
      final logs = jsonEncode(sink.events.map((e) => e.toJson()).toList());
      expect(logs, contains('commandHost.started'));
      expect(logs, contains('commandHost.command'));
      expect(logs, contains('commandHost.stopped'));
      expect(logs, isNot(contains(discovery.secret)));
      expect(logs, isNot(contains(sensitive)));
    },
  );
  test('loopback TCP fallback works with the real client', () async {
    final run = p.join(temp.path, 'tcp');
    final tcp = CommandHostServer(
      runDirectory: run,
      isWindows: true,
      appVersion: () async => '3.2.1',
      diagnostics: AppDiagnostics.disabled(),
      dispatcher: CommandHostDispatcher({
        'status': statusCommandHandler(
          appVersion: '3.2.1',
          snapshot: () => snapshot,
        ),
      }),
    );
    try {
      await tcp.start();
      expect((await readDiscovery(run)).endpoint, isA<LoopbackTcpEndpoint>());
      final result = await CommandHostClient(runDirectory: run)
          .execute(CommandRequest(command: 'status'));
      expect(result.ok, isTrue);
    } finally {
      await tcp.stop();
    }
  });
  test(
    'failed start releases the bound endpoint and stop stays idempotent',
    () async {
      final run = p.join(temp.path, 'failed');
      final failing = CommandHostServer(
        runDirectory: run,
        isWindows: Platform.isWindows,
        appVersion: () async => throw StateError('private exception'),
        diagnostics: AppDiagnostics.disabled(),
        dispatcher: CommandHostDispatcher({}),
      );
      await expectLater(
        failing.start(),
        throwsA(isA<CommandHostStartFailure>()),
      );
      await failing.stop();
      await failing.stop();
      expect(
        await File(p.join(run, commandHostDiscoveryFileName)).exists(),
        isFalse,
      );
      expect(
        await FileSystemEntity.type(p.join(run, commandHostSocketFileName)),
        FileSystemEntityType.notFound,
      );
    },
  );
  test(
    'stop waits for pending start and cannot publish a late endpoint',
    () async {
      final run = p.join(temp.path, 'pending');
      final version = Completer<String>();
      final enteredVersion = Completer<void>();
      final pending = CommandHostServer(
        runDirectory: run,
        isWindows: Platform.isWindows,
        appVersion: () {
          enteredVersion.complete();
          return version.future;
        },
        diagnostics: AppDiagnostics.disabled(),
        dispatcher: CommandHostDispatcher({}),
      );
      final starting = pending.start();
      await enteredVersion.future;
      final stopping = pending.stop();
      version.complete('3.2.1');
      await starting;
      await stopping;
      expect(
        await File(p.join(run, commandHostDiscoveryFileName)).exists(),
        isFalse,
      );
      await expectLater(
        pending.start(),
        throwsA(isA<CommandHostStartFailure>()),
      );
    },
  );
}
