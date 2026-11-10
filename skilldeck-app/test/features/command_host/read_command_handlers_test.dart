import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:skilldeck_cli/skilldeck_cli.dart';
import 'package:skilldeck_cli/skilldeck_protocol.dart';
import 'package:skilldeck_cli/src/cli/runner.dart';
import 'package:skills_manager/features/command_host/data/command_host_dispatcher.dart';
import 'package:skills_manager/features/command_host/data/read_command_handlers.dart';
import 'package:skills_manager/features/command_host/presentation/command_host_providers.dart';
import 'package:skills_manager/features/settings/data/skills_manager_runtime.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/features/settings/settings_providers.dart';
import 'package:skills_manager/features/skills/activation_location_providers.dart';
import 'package:skills_manager/features/skills/data/repositories/skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/data/repositories/diagnostic_skills_workspace_repository.dart';
import 'package:skills_manager/features/skills/device_agents_providers.dart';
import 'package:skills_manager/features/skills/models/skill_document.dart';
import 'package:skills_manager/features/skills/models/skills_workspace.dart';
import 'package:skills_manager/features/skills/skills_providers.dart';
import 'package:skills_manager/features/skills/workspace_snapshot_providers.dart';
import 'package:skills_manager/features/updates/skill_update_status_coordinator.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';
import 'package:skills_manager/shared/failures/app_failure_reporter.dart';

import '../../support/recording_app_diagnostic_sink.dart';
import 'support/read_fixtures.dart';

void main() {
  late Directory temp;
  late _ReadRepository repository;
  late ProviderContainer container;
  late SkillsManagerRuntime runtime;
  late CommandHostDispatcher dispatcher;
  late RecordingAppDiagnosticSink sink;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('sd-read-');
    repository = _ReadRepository(testSnapshot());
    sink = RecordingAppDiagnosticSink();
    final diagnostics = AppDiagnostics(sink: sink);
    runtime = SkillsManagerRuntime(
      repositoryRoot: p.join(temp.path, 'workspace'),
      settings: const AppSettings(),
      diagnostics: diagnostics,
      failureReporter: AppFailureReporter(diagnostics),
      workspace: repository,
    );
    container = ProviderContainer(
      overrides: [
        skillsManagerRuntimeFactoryProvider.overrideWithValue(() => runtime),
        skillsWorkspaceRepositoryProvider.overrideWithValue(
          DiagnosticSkillsWorkspaceRepository(
            delegate: repository,
            diagnostics: diagnostics,
            failureReporter: AppFailureReporter(diagnostics),
          ),
        ),
        deviceAgentCatalogProvider.overrideWith(
          (ref) async => [testAgent(), testAgent(id: 'other', name: 'Other')],
        ),
        deviceAgentMembersProvider.overrideWithValue(
          const AsyncData({'codex'}),
        ),
        activationTargetsProvider.overrideWith(
          (ref, selection) async =>
              WorkspaceCompleted(value: [testGlobalTarget]),
        ),
        skillUpdateStatusProvider.overrideWithBuild(
          (ref, notifier) => testUpdates(),
        ),
        commandHostConfigurationProvider.overrideWithValue(
          CommandHostConfiguration(
            environment: {'HOME': temp.path, 'USERPROFILE': temp.path},
            isWindows: Platform.isWindows,
          ),
        ),
        commandHostAppVersionProvider.overrideWith((ref) async => '2.0.0'),
        appDiagnosticsProvider.overrideWithValue(diagnostics),
      ],
    );
    await container.read(workspaceSnapshotProvider.future);
    dispatcher = CommandHostDispatcher({
      'status': statusCommandHandler(
        appVersion: '2.0.0',
        snapshot: () => container.read(workspaceSnapshotProvider).asData?.value,
      ),
      ...readCommandHandlers(
        snapshot: () => container.read(workspaceSnapshotProvider).asData?.value,
        repository: () => container.read(skillsWorkspaceRepositoryProvider),
        updates: () => container.read(skillUpdateStatusProvider),
        agents: () => container.read(deviceAgentCatalogProvider.future),
        members: () async =>
            container.read(deviceAgentMembersProvider).requireValue,
        globalTargets: () async => readCommandValue(
          await container.read(
            activationTargetsProvider((
              scope: WorkspaceScope.global,
              projectRootId: null,
            )).future,
          ),
        ),
      ),
    });
  });
  tearDown(() async {
    await runtime.close();
    container.dispose();
    await temp.delete(recursive: true);
  });
  Future<CommandResult> dispatch(
    String command, {
    SkillSelection? selection,
    String? document,
  }) => dispatcher.dispatch(
    CommandRequest(
      command: command,
      arguments: {
        if (selection != null) 'selection': selection.toJson(),
        'document': ?document,
      },
    ),
  );

  test(
    'agents uses catalog, membership and global target provider overrides',
    () async {
      final result = await dispatch('agents');
      expect(result.ok, true);
      expect(result.data['agents'], [
        {
          'id': 'codex',
          'name': 'Codex',
          'enabled': true,
          'globalRoots': ['/agents/codex'],
        },
        {'id': 'other', 'name': 'Other', 'enabled': false, 'globalRoots': []},
      ]);
    },
  );
  test('status includes public project roots', () async {
    expect((await dispatch('status')).data['projectRoots'], [
      {'id': 'project-1', 'path': '/projects/demo'},
    ]);
  });
  test('list results and full skill projections use current snapshot and update provider', () async {
    final result = await dispatch('list', selection: SkillSelection(all: true));
    expect(result.ok, true);
    expect(result.results, [
      {'id': 'skill-1', 'slotKey': 'alpha', 'outcome': 'listed'},
      {'id': 'skill-2', 'slotKey': 'beta', 'outcome': 'listed'},
    ]);
    final skills = (result.data['skills'] as List).cast<Map>();
    expect(skills.first['update'], {'status': 'updateAvailable'});
    expect(skills.first['source'], {
      'kind': 'git',
      'locator': 'https://example.test/repo',
    });
    final filtered = await dispatch(
      'list',
      selection: SkillSelection(hasUpdate: true),
    );
    expect(filtered.results, [result.results.first]);
    expect(repository.listCalls, 0);
  });
  test('empty list matches succeed, while empty show matches fail', () async {
    final result = await dispatch(
      'list',
      selection: SkillSelection(tags: ['missing']),
    );
    expect(result.ok, true);
    expect(result.results, isEmpty);
    expect(result.data['skills'], isEmpty);
    expect(
      (await dispatch(
        'show',
        selection: SkillSelection(tags: ['missing']),
      )).error?.code,
      'skillNotFound',
    );
  });
  test('show lists documents without reading content', () async {
    final result = await dispatch(
      'show',
      selection: SkillSelection(refs: ['alpha']),
    );
    expect(result.ok, true);
    expect((result.data['skill'] as Map)['id'], 'skill-1');
    expect(result.data['documents'], ['SKILL.md', 'docs/guide.md']);
    expect(result.data.containsKey('document'), false);
    expect(repository.listCalls, 1);
    expect(repository.reads, isEmpty);
  });
  test('show document uses the manifest hash, not the snapshot hash', () async {
    final result = await dispatch(
      'show',
      selection: SkillSelection(refs: ['skill-1']),
      document: 'docs/guide.md',
    );
    expect(result.ok, true);
    expect(result.data['document'], {
      'path': 'docs/guide.md',
      'text': 'Guide 技能\n',
    });
    expect(repository.reads.single, (
      'skill-1',
      'docs/guide.md',
      'effective-document-hash',
    ));
  });
  test(
    'ambiguous selection fails before listing or reading documents',
    () async {
      expect(
        (await dispatch(
          'show',
          selection: SkillSelection(all: true),
        )).error?.code,
        'ambiguousSelection',
      );
      expect(repository.listCalls, 0);
      expect(repository.reads, isEmpty);
    },
  );
  test(
    'unlisted and traversal document paths fail before repository read',
    () async {
      for (final path in ['missing.md', '../SKILL.md', '/private/SKILL.md']) {
        expect(
          (await dispatch(
            'show',
            selection: SkillSelection(refs: ['alpha']),
            document: path,
          )).error?.code,
          'documentNotFound',
        );
      }
      expect(repository.reads, isEmpty);
    },
  );
  test(
    'document byte limit includes multibyte text, accepts exactly 512 KiB',
    () async {
      repository.documents['SKILL.md'] = 'x' * maximumCommandDocumentBytes;
      expect(
        (await dispatch(
          'show',
          selection: SkillSelection(refs: ['alpha']),
          document: 'SKILL.md',
        )).ok,
        true,
      );
      repository.documents['SKILL.md'] =
          '技' * (maximumCommandDocumentBytes ~/ 3 + 1);
      expect(
        (await dispatch(
          'show',
          selection: SkillSelection(refs: ['alpha']),
          document: 'SKILL.md',
        )).error?.code,
        'documentTooLarge',
      );
    },
  );
  test('JSON escaping expansion is bounded by the wire limit', () async {
    repository.documents['SKILL.md'] =
        '\u0000' * (maximumCommandHostLineBytes ~/ 6);
    final result = await dispatch(
      'show',
      selection: SkillSelection(refs: ['alpha']),
      document: 'SKILL.md',
    );
    expect(result.error?.code, 'documentTooLarge');
    expect(() => encodeLine(result), returnsNormally);
  });
  test(
    'unexpected and typed repository failures expose stable codes only',
    () async {
      repository.failure = WorkspaceErrorCode.staleSnapshot;
      final result = await dispatch(
        'show',
        selection: SkillSelection(refs: ['alpha']),
        document: 'SKILL.md',
      );
      expect(result.error?.code, 'staleSnapshot');
      expect(jsonEncode(result.toOutputJson()), isNot(contains('sensitive')));
      repository.failure = WorkspaceErrorCode.documentUnavailable;
      expect(
        (await dispatch(
          'show',
          selection: SkillSelection(refs: ['alpha']),
        )).error?.code,
        'documentNotFound',
      );
      repository.failure = null;
      repository.throwOnRead = true;
      expect(
        (await dispatch(
          'show',
          selection: SkillSelection(refs: ['alpha']),
          document: 'SKILL.md',
        )).error?.code,
        'internalError',
      );
    },
  );
  test(
    'missing, malformed, empty and unsupported arguments return usage',
    () async {
      for (final arguments in <Map<String, Object?>>[
        {},
        {'selection': 'invalid'},
        {
          'selection': {
            'refs': [1],
          },
        },
        {'selection': SkillSelection().toJson()},
        {'selection': SkillSelection(all: true).toJson(), 'unknown': 'secret'},
        {
          'selection': SkillSelection(all: true).toJson(),
          'document': 'SKILL.md',
        },
      ]) {
        expect(
          (await dispatcher.dispatch(
            CommandRequest(command: 'list', arguments: arguments),
          )).error?.code,
          'usage',
        );
      }
    },
  );
  test('real Command Host and CLI list --json end to end; read failures exit 1 or 2', () async {
    final server = await container.read(commandHostProvider.future);
    expect(server, isNotNull);
    final out = StringBuffer();
    final err = StringBuffer();
    Future<int> run(List<String> args) => runSkilldeck(
      args,
      environment: {'HOME': temp.path, 'USERPROFILE': temp.path},
      isWindows: Platform.isWindows,
      cwd: temp.path,
      out: out,
      err: err,
    );
    expect(await run(['list', '--all', '--json', '--no-launch']), 0);
    final json = jsonDecode(out.toString()) as Map;
    expect(json['schemaVersion'], 1);
    expect(json['ok'], true);
    expect((json['results'] as List), hasLength(2));
    expect((json['data'] as Map)['skills'], hasLength(2));
    expect(err.toString(), isEmpty);
    for (final (args, code, error) in <(List<String>, int, String)>[
      (['show', '--all'], 1, 'ambiguousSelection'),
      (['show', 'alpha', '--document', 'missing.md'], 1, 'documentNotFound'),
      (['show', 'unknown'], 1, 'skillNotFound'),
      (['list'], 2, 'usage'),
    ]) {
      out.clear();
      expect(await run([...args, '--json']), code);
      expect((jsonDecode(out.toString()) as Map)['error']['code'], error);
    }
    repository.documents['SKILL.md'] = 'x' * (maximumCommandDocumentBytes + 1);
    out.clear();
    expect(await run(['show', 'alpha', '--document', 'SKILL.md', '--json']), 1);
    expect(
      (jsonDecode(out.toString()) as Map)['error']['code'],
      'documentTooLarge',
    );
    // A document is written raw, without adding or removing its final newline.
    repository.documents['SKILL.md'] = 'raw text without newline';
    out.clear();
    expect(await run(['show', 'alpha', '--document', 'SKILL.md']), 0);
    expect(out.toString(), 'raw text without newline');
    await server!.stop();
    final logs = jsonEncode(sink.events.map((e) => e.toJson()).toList());
    for (final input in [
      'alpha',
      'unknown',
      'missing.md',
      'raw text without newline',
      temp.path,
    ]) {
      expect(logs, isNot(contains(input)));
    }
  });
  test('repository diagnostics omit details for success and failure only inside dispatch', () async {
    repository.failure = WorkspaceErrorCode.staleSnapshot;
    await dispatch('show', selection: SkillSelection(refs: ['alpha']));
    repository.failure = null;
    repository.throwOnRead = true;
    await dispatch(
      'show',
      selection: SkillSelection(refs: ['alpha']),
      document: 'SKILL.md',
    );
    final logs = jsonEncode(
      sink.events.map((event) => event.toJson()).toList(),
    );
    expect(logs, contains('operation.failed'));
    for (final input in [
      'skill-1',
      'SKILL.md',
      'sensitive',
      'effective-document-hash',
    ]) {
      expect(logs, isNot(contains(input)));
    }
    container
        .read(appDiagnosticsProvider)
        .info('outside', context: {'visible': 'outside scope'});
    expect(sink.events.last.context, {'visible': 'outside scope'});
  });
  test(
    'real client rejects oversized list response with structured error',
    () async {
      repository.publish(
        testSnapshot(
          skills: [testSkill(name: 'x' * maximumCommandHostLineBytes)],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final server = await container.read(commandHostProvider.future);
      expect(server, isNotNull);
      final result =
          await CommandHostClient(
            runDirectory: p.join(temp.path, '.skilldeck', 'run'),
          ).execute(
            CommandRequest(
              command: 'list',
              arguments: {'selection': SkillSelection(all: true).toJson()},
            ),
          );
      expect(result.error?.code, 'responseTooLarge');
    },
  );
}

/// Implements only the read seams this test exercises; no real filesystem use.
final class _ReadRepository implements SkillsWorkspaceRepository {
  _ReadRepository(this.snapshot);
  SkillsWorkspaceSnapshot snapshot;
  final _snapshots = StreamController<SkillsWorkspaceSnapshot>.broadcast();
  void publish(SkillsWorkspaceSnapshot next) {
    snapshot = SkillsWorkspaceSnapshot(
      revision: snapshot.revision + 1,
      projectRoots: next.projectRoots,
      skills: next.skills,
      personalTags: next.personalTags,
    );
    _snapshots.add(snapshot);
  }

  final documents = {'SKILL.md': '# Alpha\n', 'docs/guide.md': 'Guide 技能\n'};
  final reads = <(String, String, String)>[];
  int listCalls = 0;
  WorkspaceErrorCode? failure;
  bool throwOnRead = false;
  @override
  SkillsWorkspaceSnapshot get current => snapshot;
  @override
  Stream<SkillsWorkspaceSnapshot> get snapshots => _snapshots.stream;
  @override
  Future<WorkspaceCompletion<SkillsWorkspaceSnapshot>> open() async =>
      WorkspaceCompleted(value: snapshot);
  @override
  Future<void> close() => _snapshots.close();
  WorkspaceCompletion<T> completed<T>(T value) => failure == null
      ? WorkspaceCompleted(value: value)
      : WorkspaceFailed(
          failure: WorkspaceFailure(
            code: failure!,
            operation: WorkspaceOperationKind.readDocument,
            context: {'path': '/sensitive/path'},
            diagnostic: 'sensitive document',
          ),
        );
  @override
  Future<WorkspaceCompletion<List<SkillDocumentEntry>>> listSkillDocuments(
    WorkspaceSkillId id,
  ) async {
    listCalls++;
    return completed([
      for (final path in documents.keys)
        SkillDocumentEntry(
          relativePath: path,
          name: p.posix.basename(path),
          contentHash: 'effective-document-hash',
        ),
    ]);
  }

  @override
  Future<WorkspaceCompletion<String>> readSkillDocument(
    WorkspaceSkillId id,
    String path, {
    required String expectedContentHash,
  }) async {
    reads.add((id.value, path, expectedContentHash));
    if (throwOnRead) throw StateError('sensitive content');
    return completed(documents[path]!);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected repository call');
}
