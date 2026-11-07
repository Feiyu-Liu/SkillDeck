// #52: source acquisition can exceed the default 30 seconds on the self-hosted
// Windows runner. Keep all assertions and coverage, with a bounded timeout.
@OnPlatform({'windows': Timeout(Duration(minutes: 2))})
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:skills_workspace/src/application/source/source_acquisition_models.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:skills_workspace/src/infrastructure/source/git_application_source_adapter.dart';
import 'package:test/test.dart';

import '../../support/content/revision_content_worker_fake.dart';

void main() {
  test('three metadata files use one batch before selected content', () async {
    final transport = _metadataTransport();
    final result = await _acquire(
      transport,
      source: GitSourceDescriptor(
        locator: 'owner/repo',
        skillPath: 'skills/skill-0',
      ),
    );
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.skills.single.slotKey, 'skill-0');
    expect(transport.streamRequests, [
      [for (var i = 0; i < 3; i++) 'skills/skill-$i/SKILL.md'],
      ['skills/skill-0/SKILL.md'],
    ]);
  });

  test('metadata batches contain at most 1000 requests', () async {
    final transport = _metadataTransport(count: 1001);
    final result = await _acquire(
      transport,
      source: GitSourceDescriptor(
        locator: 'owner/repo',
        skillPath: 'skills/skill-0',
      ),
    );
    expect(result.failureOrNull, isNull);
    expect(transport.streamRequests.map((requests) => requests.length), [
      1000,
      1,
      1,
    ]);
    expect(transport.streamRequests[1], ['skills/skill-1000/SKILL.md']);
    expect(transport.streamRequests.last, ['skills/skill-0/SKILL.md']);
  });

  test(
    'aggregate metadata byte limit retries the chunk entry by entry',
    () async {
      final transport = _metadataTransport(
        maximumBatchByteSize: _skillBytes('skill-0').length * 2 - 1,
      );
      final result = await _acquire(
        transport,
        source: GitSourceDescriptor(
          locator: 'owner/repo',
          skillPath: 'skills/skill-0',
        ),
      );
      expect(result.failureOrNull, isNull);
      expect(result.valueOrNull!.skills.single.slotKey, 'skill-0');
      expect(transport.streamRequests, [
        [for (var i = 0; i < 3; i++) 'skills/skill-$i/SKILL.md'],
        for (var i = 0; i < 3; i++) ['skills/skill-$i/SKILL.md'],
        ['skills/skill-0/SKILL.md'],
      ]);
    },
  );

  test(
    'an individually oversized metadata entry keeps its typed failure',
    () async {
      final transport = _metadataTransport(
        maximumBatchByteSize: _skillBytes('skill-0').length - 1,
      );
      final result = await _acquire(transport);
      expect(
        result.failureOrNull?.code,
        SourceAcquisitionFailureCode.skillContentLimitExceeded,
      );
      expect(result.failureOrNull?.context['limit'], 'byteSize');
      expect(transport.streamRequests.map((requests) => requests.length), [
        3,
        1,
      ]);
    },
  );

  test(
    'metadata errors other than aggregate byte limits are not retried',
    () async {
      final transport = _metadataTransport(
        streamFailure: GitTransportFailure<void>(
          code: GitTransportFailureCode.commandFailed,
          context: const {'reason': 'network'},
        ),
      );
      final result = await _acquire(transport);
      expect(
        result.failureOrNull?.code,
        SourceAcquisitionFailureCode.gitFailed,
      );
      expect(result.failureOrNull?.context['reason'], 'network');
      expect(transport.streamRequests.map((requests) => requests.length), [3]);
    },
  );

  test('cyclic metadata directory aliases terminate discovery', () async {
    final transport = _FakeGitTransport(
      entries: [_link('SKILL.md', '1'), _link('alias', '2')],
      blobs: {
        'SKILL.md': _bytes('alias/metadata'),
        'alias': _bytes('alias/nested'),
      },
    );
    final result = await _acquire(transport);
    expect(
      result.failureOrNull?.code,
      SourceAcquisitionFailureCode.skillNotFound,
    );
  });

  test(
    'discovery follows metadata link chains through directory aliases',
    () async {
      final transport = _FakeGitTransport(
        entries: [
          _link('SKILL.md', '1'),
          _link('first', '2'),
          _link('alias', '3'),
          _entry('real/metadata', '4'),
        ],
        blobs: {
          'SKILL.md': _bytes('first'),
          'first': _bytes('alias/metadata'),
          'alias': _bytes('real'),
          'real/metadata': _skillBytes('demo'),
        },
      );
      final result = await _acquire(transport);
      expect(result.failureOrNull, isNull);
      expect(result.valueOrNull!.skills.single.slotKey, 'demo');
      expect(
        result.valueOrNull!.skills.single.tree.files.map(
          (file) => file.relativePath,
        ),
        ['SKILL.md', 'alias/metadata', 'first', 'real/metadata'],
      );
    },
  );

  test(
    'repository over 1000 files ignores unrelated data links and submodules',
    () async {
      final transport = _FakeGitTransport(
        entries: [
          _entry('skills/demo/SKILL.md', '1'),
          _entry('skills/other/SKILL.md', '2'),
          for (var i = 0; i < 1100; i++) _entry('unrelated/file$i', '3'),
          GitTreeEntry(
            relativePath: 'vendor/module',
            objectId: _objectId('4'),
            kind: GitTreeEntryKind.gitlink,
            executable: false,
          ),
          _link('unrelated/dangling', '5'),
          _link('unrelated/unsafe', '6'),
          _link('unrelated/file-link', '7'),
          _entry('unrelated/data', '8'),
        ],
        blobs: {
          'skills/demo/SKILL.md': _skillBytes('demo'),
          'skills/other/SKILL.md': _skillBytes('other'),
          'unrelated/dangling': _bytes('missing'),
          'unrelated/unsafe': _bytes('/outside'),
          'unrelated/file-link': _bytes('data'),
        },
      );
      final result = await _acquire(transport);
      expect(result.failureOrNull, isNull);
      expect(result.valueOrNull!.skills.map((s) => s.slotKey), [
        'demo',
        'other',
      ]);
      expect(
        transport.requestedPaths.any(
          (p) => RegExp(r'^unrelated/file[0-9]+$').hasMatch(p),
        ),
        isFalse,
      );
      expect(transport.requestedPaths, isNot(contains('vendor/module')));
      expect(transport.requestedPaths, isNot(contains('unrelated/data')));
    },
  );
  test(
    'only selected roots acquire content and reject an oversized Skill',
    () async {
      final transport = _FakeGitTransport(
        entries: [
          _entry('skills/small/SKILL.md', '1'),
          _entry('skills/large/SKILL.md', '2'),
          for (var i = 0; i < 1000; i++) _entry('skills/large/f$i', '3'),
        ],
        blobs: {
          'skills/small/SKILL.md': _skillBytes('small'),
          'skills/large/SKILL.md': _skillBytes('large'),
        },
      );
      final small = await _acquire(
        transport,
        source: GitSourceDescriptor(locator: 'owner/repo@small'),
      );
      expect(small.failureOrNull, isNull);
      expect(small.valueOrNull!.skills.single.slotKey, 'small');
      expect(
        transport.requestedPaths.any((p) => p.startsWith('skills/large/f')),
        isFalse,
      );
      final large = await _acquire(
        transport,
        source: GitSourceDescriptor(locator: 'owner/repo@large'),
      );
      expect(
        large.failureOrNull?.code,
        SourceAcquisitionFailureCode.skillContentLimitExceeded,
      );
      expect(large.failureOrNull?.context, containsPair('limit', 'fileCount'));
      expect(large.failureOrNull?.context, containsPair('actual', 1001));
      expect(
        large.failureOrNull?.context,
        containsPair('maximumFileCount', 1000),
      );
      expect(
        large.failureOrNull?.context,
        containsPair('maximumByteSize', 50 * 1024 * 1024),
      );
    },
  );
  test('submodules inside a selected Skill fail validation', () async {
    final transport = _FakeGitTransport(
      entries: [
        _entry('skills/demo/SKILL.md', '1'),
        GitTreeEntry(
          relativePath: 'skills/demo/module',
          objectId: _objectId('2'),
          kind: GitTreeEntryKind.gitlink,
          executable: false,
        ),
      ],
      blobs: {'skills/demo/SKILL.md': _skillBytes('demo')},
    );
    final result = await _acquire(transport);
    expect(
      result.failureOrNull?.code,
      SourceAcquisitionFailureCode.invalidSkill,
    );
    expect(result.failureOrNull?.context['reason'], 'gitlinkNotAllowed');
  });
  test('plugin directory aliases identify one canonical Skill', () async {
    final transport = _FakeGitTransport(
      entries: [
        _entry('.claude-plugin/marketplace.json', '1'),
        _entry('skills/demo/SKILL.md', '2'),
        _link('plugins/building/skills/demo', '3'),
      ],
      blobs: {
        '.claude-plugin/marketplace.json': Uint8List.fromList(
          '{"plugins":[{"name":"building","source":"./plugins/building",'
                  '"skills":["./skills/demo"]}]}'
              .codeUnits,
        ),
        'skills/demo/SKILL.md': _skillBytes('demo'),
        'plugins/building/skills/demo': Uint8List.fromList(
          '../../../skills/demo'.codeUnits,
        ),
      },
    );
    final result = await GitApplicationSourceAdapter(transport: transport)
        .acquireGit(
          GitSourceDescriptor(locator: 'https://example.test/source.git'),
          selectedSkillNames: const {},
          options: const SourceAcquisitionOptions(),
          cancellationToken: CancellationToken.none(),
        );
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.skills, hasLength(1));
    expect(result.valueOrNull!.skills.single.skillPath, 'skills/demo');
    expect(result.valueOrNull!.skills.single.pluginName, 'building');
  });

  test('counts each repository entry once against Source limits', () async {
    // 600 files exceed the limit once per alias, but not per repository.
    final files = [for (var index = 0; index < 600; index += 1) 'f$index.txt'];
    final transport = _FakeGitTransport(
      entries: [
        _entry('skills/big/SKILL.md', '1'),
        for (final file in files) _entry('skills/big/$file', '2'),
        _link('plugins/a/skills/big', '3'),
        _link('plugins/b/skills/big', '3'),
      ],
      blobs: {
        'skills/big/SKILL.md': _skillBytes('big'),
        for (final file in files) 'skills/big/$file': Uint8List(1),
        'plugins/a/skills/big': _bytes('../../../skills/big'),
        'plugins/b/skills/big': _bytes('../../../skills/big'),
      },
    );
    final result = await _acquire(transport);
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.skills.single.skillPath, 'skills/big');
  });

  test('many aliases do not multiply candidate content budgets', () async {
    final files = [for (var index = 0; index < 600; index += 1) 'f$index.txt'];
    final links = [for (var index = 0; index < 20; index += 1) 'alias$index'];
    final transport = _FakeGitTransport(
      entries: [
        _entry('skills/big/SKILL.md', '1'),
        for (final file in files) _entry('skills/big/$file', '2'),
        for (final link in links) _link('plugins/$link', '3'),
      ],
      blobs: {
        'skills/big/SKILL.md': _skillBytes('big'),
        for (final file in files) 'skills/big/$file': Uint8List(1),
        for (final link in links) 'plugins/$link': _bytes('../skills/big'),
      },
    );
    final result = await _acquire(transport);
    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.skills.single.tree.files, hasLength(601));
  });

  test('a missing subpath never lists the repository root', () async {
    final transport = _FakeGitTransport(
      entries: [
        _entry('skills/demo/SKILL.md', '1'),
        _entry('other/SKILL.md', '2'),
      ],
      blobs: {
        'skills/demo/SKILL.md': _skillBytes('demo'),
        'other/SKILL.md': _skillBytes('other'),
      },
    );
    final result = await _acquire(
      transport,
      source: GitSourceDescriptor(
        locator: 'https://example.test/source.git',
        repositorySubpath: 'skills/dmeo/nested',
      ),
    );
    expect(result.failureOrNull, isNotNull);
    expect(transport.listedSubpaths, [
      'skills/dmeo/nested',
      'skills/dmeo',
      'skills',
    ]);
  });

  test(
    'exports a selected Git Skill without checkout and preserves mode',
    () async {
      final temporaryRoot = await Directory.systemTemp.createTemp(
        'git-source-application-test-',
      );
      addTearDown(() async => temporaryRoot.delete(recursive: true));
      String? operationPath;
      final transport = _FakeGitTransport(
        entries: [
          _entry('skills/one/SKILL.md', '1'),
          _entry('skills/one/script.sh', '2', executable: true),
          _entry('skills/two/SKILL.md', '3'),
        ],
        blobs: {
          'skills/one/SKILL.md': _skillBytes('One'),
          'skills/one/script.sh': Uint8List.fromList('#!/bin/sh\n'.codeUnits),
          'skills/two/SKILL.md': _skillBytes('Two'),
        },
      );
      final contentWorker = RecordingRevisionContentWorker();
      final adapter = GitApplicationSourceAdapter(
        transport: transport,
        contentWorker: contentWorker,
        temporaryDirectoryFactory: () async {
          final created = await temporaryRoot.createTemp('operation-');
          operationPath = created.path;
          return created;
        },
      );

      final result = await adapter.acquireGit(
        GitSourceDescriptor(
          locator: 'https://example.test/source.git',
          ref: 'main',
        ),
        selectedSkillNames: const {'one'},
        options: const SourceAcquisitionOptions(),
        cancellationToken: CancellationToken.none(),
      );

      final acquired = result.valueOrNull!;
      expect(acquired.resolvedSourceRevision, _objectId('f'));
      expect(acquired.skills, hasLength(1));
      final skill = acquired.skills.single;
      expect(skill.slotKey, 'one');
      expect(skill.skillPath, 'skills/one');
      expect((skill.provenance as GitSourceDescriptor).skillPath, 'skills/one');
      expect(
        skill.tree.files
            .singleWhere((file) => file.relativePath == 'script.sh')
            .isExecutable,
        isTrue,
      );
      expect(transport.disposed, 1);
      expect(await Directory(operationPath!).exists(), isFalse);
      expect(contentWorker.normalizationCalls, 1);
      expect(contentWorker.filesystemReadCalls, 0);
    },
  );

  test('normalizes a GitHub repository URL before acquisition', () async {
    final transport = _FakeGitTransport(
      entries: [_entry('SKILL.md', '1')],
      blobs: {'SKILL.md': _skillBytes('Root')},
    );
    final adapter = GitApplicationSourceAdapter(transport: transport);

    final result = await adapter.acquireGit(
      GitSourceDescriptor(locator: 'https://github.com/vercel-labs/skills'),
      selectedSkillNames: const {},
      options: const SourceAcquisitionOptions(),
      cancellationToken: CancellationToken.none(),
    );

    expect(
      transport.fetchedSource?.locator,
      'https://github.com/vercel-labs/skills.git',
    );
    expect(
      result.valueOrNull?.canonicalSource,
      GitSourceDescriptor(locator: 'https://github.com/vercel-labs/skills.git'),
    );
  });

  test(
    'batch acquisition fetches one locator and ref once across selections',
    () async {
      final transport = _FakeGitTransport(
        entries: [
          _entry('skills/one/SKILL.md', '1'),
          _entry('skills/two/SKILL.md', '2'),
        ],
        blobs: {
          'skills/one/SKILL.md': _skillBytes('One'),
          'skills/two/SKILL.md': _skillBytes('Two'),
        },
      );
      final adapter = GitApplicationSourceAdapter(transport: transport);

      final results = await adapter.acquireGitBatch([
        SourceAcquisitionRequest(
          source: GitSourceDescriptor(
            locator: 'https://example.test/source.git',
            ref: 'main',
            skillPath: 'skills/one',
          ),
        ),
        SourceAcquisitionRequest(
          source: GitSourceDescriptor(
            locator: 'https://example.test/source.git',
            ref: 'main',
            skillPath: 'skills/two',
          ),
        ),
      ], cancellationToken: CancellationToken.none());

      expect(
        results.map((result) => result.valueOrNull?.skills.single.slotKey),
        ['one', 'two'],
      );
      expect(transport.fetchCalls, 1);
      expect(transport.listCalls, 4);
      expect(transport.streamCalls, 4);
      expect(transport.disposed, 1);
    },
  );

  test(
    'one selection staging failure leaves the rest of the fetch usable',
    () async {
      final temporaryRoot = await Directory.systemTemp.createTemp(
        'git-source-application-test-',
      );
      addTearDown(() async => temporaryRoot.delete(recursive: true));
      final transport = _FakeGitTransport(
        entries: [
          _entry('skills/one/SKILL.md', '1'),
          _entry('skills/two/SKILL.md', '2'),
          _entry('skills/three/SKILL.md', '3'),
        ],
        blobs: {
          'skills/one/SKILL.md': _skillBytes('One'),
          'skills/two/SKILL.md': _skillBytes('Two'),
          'skills/three/SKILL.md': _skillBytes('Three'),
        },
      );
      final adapter = GitApplicationSourceAdapter(
        transport: transport,
        temporaryDirectoryFactory: () async {
          final created = await temporaryRoot.createTemp('operation-');
          // A file where the second selection stages its projection makes
          // only that selection's directory creation fail.
          await File('${created.path}/selection-1').writeAsString('');
          return created;
        },
      );

      final results = await adapter.acquireGitBatch([
        for (final name in ['one', 'two', 'three'])
          SourceAcquisitionRequest(
            source: GitSourceDescriptor(
              locator: 'https://example.test/source.git',
              ref: 'main',
              skillPath: 'skills/$name',
            ),
          ),
      ], cancellationToken: CancellationToken.none());

      expect(results[0].valueOrNull?.skills.single.slotKey, 'one');
      expect(
        results[1].failureOrNull?.code,
        SourceAcquisitionFailureCode.ioFailure,
      );
      expect(results[2].valueOrNull?.skills.single.slotKey, 'three');
      expect(transport.fetchCalls, 1);
      expect(transport.disposed, 1);
    },
  );

  test('batch acquisition keeps different refs in separate fetches', () async {
    final transport = _FakeGitTransport(
      entries: [_entry('SKILL.md', '1')],
      blobs: {'SKILL.md': _skillBytes('Root')},
    );
    final adapter = GitApplicationSourceAdapter(transport: transport);

    await adapter.acquireGitBatch([
      SourceAcquisitionRequest(
        source: GitSourceDescriptor(
          locator: 'https://example.test/source.git',
          ref: 'main',
        ),
      ),
      SourceAcquisitionRequest(
        source: GitSourceDescriptor(
          locator: 'https://example.test/source.git',
          ref: 'next',
        ),
      ),
    ], cancellationToken: CancellationToken.none());

    expect(transport.fetchCalls, 2);
  });

  test('one shared fetch timeout settles every matching selection', () async {
    final transport = _FakeGitTransport(
      fetchFailure: GitTransportFailure<GitBareSource>(
        code: GitTransportFailureCode.timedOut,
      ),
    );
    final adapter = GitApplicationSourceAdapter(transport: transport);

    final results = await adapter.acquireGitBatch([
      SourceAcquisitionRequest(
        source: GitSourceDescriptor(
          locator: 'https://example.test/source.git',
          skillPath: 'one',
        ),
      ),
      SourceAcquisitionRequest(
        source: GitSourceDescriptor(
          locator: 'https://example.test/source.git',
          skillPath: 'two',
        ),
      ),
    ], cancellationToken: CancellationToken.none());

    expect(transport.fetchCalls, 1);
    expect(
      results.map((result) => result.failureOrNull?.code),
      everyElement(SourceAcquisitionFailureCode.gitTimedOut),
    );
  });

  test('a pre-cancelled batch starts no Git fetch', () async {
    final cancellation = CancellationSource();
    await cancellation.cancel();
    final transport = _FakeGitTransport();
    final adapter = GitApplicationSourceAdapter(transport: transport);

    final results = await adapter.acquireGitBatch([
      SourceAcquisitionRequest(
        source: GitSourceDescriptor(locator: 'https://example.test/source.git'),
      ),
    ], cancellationToken: cancellation.token);

    expect(transport.fetchCalls, 0);
    expect(
      results.single.failureOrNull?.code,
      SourceAcquisitionFailureCode.operationCancelled,
    );
  });

  test('missing system Git maps without listing or materializing', () async {
    final transport = _FakeGitTransport(
      fetchFailure: GitTransportFailure<GitBareSource>(
        code: GitTransportFailureCode.unavailable,
      ),
    );
    final adapter = GitApplicationSourceAdapter(transport: transport);

    final result = await adapter.acquireGit(
      GitSourceDescriptor(locator: 'https://example.test/source.git'),
      selectedSkillNames: const {},
      options: const SourceAcquisitionOptions(),
      cancellationToken: CancellationToken.none(),
    );

    expect(
      result.failureOrNull?.code,
      SourceAcquisitionFailureCode.gitUnavailable,
    );
    expect(transport.listCalls, 0);
    expect(transport.streamCalls, 0);
  });

  test(
    'pre-cancelled Git acquisition creates no temporary directory',
    () async {
      final cancellation = CancellationSource();
      await cancellation.cancel();
      var temporaryCalls = 0;
      final adapter = GitApplicationSourceAdapter(
        transport: _FakeGitTransport(),
        temporaryDirectoryFactory: () async {
          temporaryCalls += 1;
          return Directory.systemTemp.createTemp('must-not-run-');
        },
      );

      final result = await adapter.acquireGit(
        GitSourceDescriptor(locator: 'https://example.test/source.git'),
        selectedSkillNames: const {},
        options: const SourceAcquisitionOptions(),
        cancellationToken: cancellation.token,
      );

      expect(
        result.failureOrNull?.code,
        SourceAcquisitionFailureCode.operationCancelled,
      );
      expect(temporaryCalls, 0);
    },
  );

  test('dereferences Git file and directory links before discovery', () async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'git-source-link-test-',
    );
    addTearDown(() async => temporaryRoot.delete(recursive: true));
    final transport = _FakeGitTransport(
      entries: [
        _entry('metadata.md', '1'),
        _entry('assets/run.sh', '2', executable: true),
        _link('SKILL.md', '3'),
        _link('bin', '4'),
      ],
      blobs: {
        'metadata.md': _skillBytes('Root'),
        'assets/run.sh': Uint8List.fromList('#!/bin/sh\n'.codeUnits),
        'SKILL.md': Uint8List.fromList('metadata.md'.codeUnits),
        'bin': Uint8List.fromList('assets'.codeUnits),
      },
    );
    final adapter = GitApplicationSourceAdapter(
      transport: transport,
      temporaryDirectoryFactory: () => temporaryRoot.createTemp('operation-'),
    );

    final result = await adapter.acquireGit(
      GitSourceDescriptor(locator: 'https://example.test/source.git'),
      selectedSkillNames: const {},
      options: const SourceAcquisitionOptions(),
      cancellationToken: CancellationToken.none(),
    );

    final files = result.valueOrNull!.skills.single.tree.files;
    expect(files.map((file) => file.relativePath), [
      'SKILL.md',
      'assets/run.sh',
      'bin/run.sh',
      'metadata.md',
    ]);
    expect(
      files
          .singleWhere((file) => file.relativePath == 'bin/run.sh')
          .isExecutable,
      isTrue,
    );
  });

  test('invalid Git link content fails the complete source tree', () async {
    final temporaryRoot = await Directory.systemTemp.createTemp(
      'git-source-invalid-link-test-',
    );
    addTearDown(() async => temporaryRoot.delete(recursive: true));
    final adapter = GitApplicationSourceAdapter(
      transport: _FakeGitTransport(
        entries: [_entry('SKILL.md', '1'), _link('alias', '2')],
        blobs: {
          'SKILL.md': _skillBytes('Root'),
          'alias': Uint8List.fromList('../outside'.codeUnits),
        },
      ),
      temporaryDirectoryFactory: () => temporaryRoot.createTemp('operation-'),
    );

    final result = await adapter.acquireGit(
      GitSourceDescriptor(locator: 'https://example.test/source.git'),
      selectedSkillNames: const {},
      options: const SourceAcquisitionOptions(),
      cancellationToken: CancellationToken.none(),
    );

    expect(
      result.failureOrNull?.code,
      SourceAcquisitionFailureCode.invalidSkill,
    );
    expect(
      result.failureOrNull?.context['reason'],
      'symbolicLinkEscapesSource',
    );
  });

  test(
    'credential-bearing locator is rejected before temporary work',
    () async {
      var temporaryCalls = 0;
      final adapter = GitApplicationSourceAdapter(
        transport: _FakeGitTransport(),
        temporaryDirectoryFactory: () async {
          temporaryCalls += 1;
          return Directory.systemTemp.createTemp('must-not-run-');
        },
      );

      final result = await adapter.acquireGit(
        GitSourceDescriptor(
          locator: 'https://user:secret@example.test/source.git',
        ),
        selectedSkillNames: const {},
        options: const SourceAcquisitionOptions(),
        cancellationToken: CancellationToken.none(),
      );

      expect(
        result.failureOrNull?.code,
        SourceAcquisitionFailureCode.transportRejected,
      );
      expect(temporaryCalls, 0);
    },
  );
}

final class _FakeGitTransport implements GitSourceTransport {
  _FakeGitTransport({
    this.entries = const [],
    this.blobs = const {},
    this.fetchFailure,
    this.maximumBatchByteSize,
    this.streamFailure,
  });

  final List<GitTreeEntry> entries;
  final Map<String, Uint8List> blobs;
  final GitTransportFailure<GitBareSource>? fetchFailure;
  final int? maximumBatchByteSize;
  final GitTransportFailure<void>? streamFailure;
  final streamRequests = <List<String>>[];
  GitSourceDescriptor? fetchedSource;
  var fetchCalls = 0;
  var listCalls = 0;
  final listedSubpaths = <String>[];
  var streamCalls = 0;
  final requestedPaths = <String>[];
  var disposed = 0;

  @override
  Future<GitTransportResult<GitBareSource>> fetchBare(
    GitSourceDescriptor source, {
    required String repositoryPath,
    required String disabledHooksPath,
    required GitCancellationSignal cancellation,
  }) async {
    fetchCalls += 1;
    fetchedSource = source;
    return fetchFailure ??
        GitTransportSuccess<GitBareSource>(
          GitBareSource(
            repositoryPath: repositoryPath,
            resolvedRevision: _objectId('f'),
            disabledHooksPath: disabledHooksPath,
          ),
        );
  }

  @override
  Future<GitTransportResult<List<GitTreeEntry>>> listTree(
    GitBareSource source, {
    required String repositorySubpath,
    required GitCancellationSignal cancellation,
  }) async {
    listCalls += 1;
    listedSubpaths.add(repositorySubpath);
    return GitTransportSuccess<List<GitTreeEntry>>([
      for (final entry in entries)
        if (repositorySubpath.isEmpty ||
            entry.relativePath == repositorySubpath ||
            entry.relativePath.startsWith('$repositorySubpath/'))
          entry,
    ]);
  }

  @override
  Future<GitTransportResult<void>> streamBlobs(
    GitBareSource source, {
    required List<GitBlobRequest> requests,
    required GitBlobChunkConsumer onChunk,
    required GitCancellationSignal cancellation,
  }) async {
    streamCalls += 1;
    streamRequests.add([for (final request in requests) request.relativePath]);
    if (streamFailure != null) return streamFailure!;
    var byteCount = 0;
    for (final request in requests) {
      byteCount += blobs[request.relativePath]!.length;
      if (maximumBatchByteSize != null && byteCount > maximumBatchByteSize!) {
        return GitTransportFailure<void>(
          code: GitTransportFailureCode.invalidOutput,
          context: const {'reason': 'blobBytesExceededLimit'},
        );
      }
      requestedPaths.add(request.relativePath);
      await onChunk(
        GitBlobChunk(
          request: request,
          bytes: blobs[request.relativePath]!,
          isLast: true,
        ),
      );
    }
    return const GitTransportSuccess<void>(null);
  }

  @override
  Future<void> dispose(GitBareSource source) async {
    disposed += 1;
  }
}

GitTreeEntry _entry(
  String relativePath,
  String objectCharacter, {
  bool executable = false,
}) => GitTreeEntry(
  relativePath: relativePath,
  objectId: _objectId(objectCharacter),
  kind: GitTreeEntryKind.blob,
  executable: executable,
);

Future<SourceAcquisitionResult<AcquiredSource>> _acquire(
  _FakeGitTransport transport, {
  GitSourceDescriptor? source,
}) => GitApplicationSourceAdapter(transport: transport).acquireGit(
  source ?? GitSourceDescriptor(locator: 'https://example.test/source.git'),
  selectedSkillNames: const {},
  options: const SourceAcquisitionOptions(),
  cancellationToken: CancellationToken.none(),
);

Uint8List _bytes(String value) => Uint8List.fromList(utf8.encode(value));

GitTreeEntry _link(String relativePath, String objectCharacter) => GitTreeEntry(
  relativePath: relativePath,
  objectId: _objectId(objectCharacter),
  kind: GitTreeEntryKind.symbolicLink,
  executable: false,
);

Uint8List _skillBytes(String name) => Uint8List.fromList(
  '---\nname: $name\ndescription: $name description\n---\n'.codeUnits,
);

String _objectId(String character) => List.filled(40, character).join();

_FakeGitTransport _metadataTransport({
  int count = 3,
  int? maximumBatchByteSize,
  GitTransportFailure<void>? streamFailure,
}) => _FakeGitTransport(
  entries: [
    for (var i = 0; i < count; i++) _entry('skills/skill-$i/SKILL.md', '1'),
  ],
  blobs: {
    for (var i = 0; i < count; i++)
      'skills/skill-$i/SKILL.md': _skillBytes('skill-$i'),
  },
  maximumBatchByteSize: maximumBatchByteSize,
  streamFailure: streamFailure,
);
