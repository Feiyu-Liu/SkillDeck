import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/revision_content_worker_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/discovery/file_system_external_skill_location.dart';
import 'package:skills_workspace/src/infrastructure/source/local_source.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporaryDirectory;
  late FileSystemExternalSkillLocation adapter;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-external-location-',
    );
    adapter = FileSystemExternalSkillLocation();
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('discovers nested Skills with exact source continuity', () async {
    final location = Directory(path.join(temporaryDirectory.path, 'skills'));
    await _writeSkill(
      path.join(location.path, 'group', 'review'),
      name: 'review',
      body: 'review body',
    );

    final result = await adapter.scanLocation(
      location: location.path,
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );

    final skill = result.valueOrNull!.single;
    expect(skill.slotKey, 'review');
    expect(skill.skillLocation, path.join(location.path, 'group', 'review'));
    expect(skill.source.locator, location.path);
    expect(skill.source.skillPath, 'group/review');
    expect(skill.contentHash, hasLength(64));
  });

  test('discovers a Skill stored as a Git working tree', () async {
    final location = Directory(path.join(temporaryDirectory.path, 'skills'));
    final skill = await _writeSkill(
      path.join(location.path, 'git-backed'),
      name: 'git-backed',
      body: 'working tree body',
    );
    await Directory(path.join(skill.path, '.git')).create();
    await File(
      path.join(skill.path, '.git', 'config'),
    ).writeAsString('private metadata');

    final result = await adapter.scanLocation(
      location: location.path,
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );

    expect(result.failureOrNull, isNull);
    expect(result.warnings, isEmpty);
    expect(result.valueOrNull!.single.slotKey, 'git-backed');
  });

  test('skips one invalid candidate and keeps valid Skills', () async {
    final location = Directory(path.join(temporaryDirectory.path, 'skills'));
    await _writeSkill(
      path.join(location.path, 'invalid'),
      name: 'invalid',
      body: 'invalid body',
    );
    await _writeSkill(
      path.join(location.path, 'valid'),
      name: 'valid',
      body: 'valid body',
    );
    final adapter = FileSystemExternalSkillLocation(
      localSource: LocalSourceAdapter(
        contentWorker: const _RejectingRevisionContentWorker('invalid'),
      ),
    );

    final result = await adapter.scanLocation(
      location: location.path,
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );

    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.map((skill) => skill.slotKey), <String>[
      'valid',
    ]);
    expect(result.warnings, hasLength(1));
    expect(result.warnings.single.code.name, 'sourceEntrySkipped');
    expect(result.warnings.single.context['skillPath'], 'invalid');
    expect(result.warnings.single.context['reason'], 'testInvalidCandidate');
  });

  test('all invalid candidates produce an empty successful scan', () async {
    final location = Directory(path.join(temporaryDirectory.path, 'skills'));
    await _writeSkill(
      path.join(location.path, 'invalid'),
      name: 'invalid',
      body: 'invalid body',
    );
    final adapter = FileSystemExternalSkillLocation(
      localSource: LocalSourceAdapter(
        contentWorker: const _RejectingRevisionContentWorker('invalid'),
      ),
    );

    final result = await adapter.scanLocation(
      location: location.path,
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );

    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull, isEmpty);
    expect(result.warnings, hasLength(1));
  });

  test(
    'discovers a top-level Skill symbolic link at its visible location',
    () async {
      if (Platform.isWindows) {
        return;
      }
      final location = Directory(path.join(temporaryDirectory.path, 'skills'));
      final external = await _writeSkill(
        path.join(temporaryDirectory.path, 'external'),
        name: 'linked',
        body: 'linked body',
      );
      await location.create();
      final linked = path.join(location.path, 'linked');
      await Link(linked).create(external.path);

      final result = await adapter.scanLocation(
        location: location.path,
        includeInternal: false,
        cancellationToken: CancellationToken.none(),
      );

      final skill = result.valueOrNull!.single;
      expect(skill.skillLocation, linked);
      expect(skill.source.locator, linked);
      expect(skill.source.skillPath, isEmpty);
    },
  );

  test(
    'uses a physical mutation path beneath a linked discovery root',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('Covered by the Windows junction validation probe.');
        return;
      }
      final physicalLocation = Directory(
        path.join(temporaryDirectory.path, 'physical-skills'),
      );
      final skill = await _writeSkill(
        path.join(physicalLocation.path, 'review'),
        name: 'review',
        body: 'review body',
      );
      final linkedLocation = path.join(
        temporaryDirectory.path,
        'legacy-skills',
      );
      await Link(linkedLocation).create(physicalLocation.path);

      final result = await adapter.scanLocation(
        location: linkedLocation,
        includeInternal: false,
        cancellationToken: CancellationToken.none(),
      );

      final scanned = result.valueOrNull!.single;
      final resolvedSkillPath = await skill.resolveSymbolicLinks();
      expect(scanned.skillLocation, path.join(linkedLocation, 'review'));
      expect(scanned.mutationPath, resolvedSkillPath);
      expect(scanned.contentIdentityPath, resolvedSkillPath);
    },
  );

  test('missing location is an empty successful scan', () async {
    final result = await adapter.scanLocation(
      location: path.join(temporaryDirectory.path, 'missing'),
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );

    expect(result.valueOrNull, isEmpty);
  });

  test('internal Skills follow the explicit includeInternal option', () async {
    final location = Directory(path.join(temporaryDirectory.path, 'skills'));
    await _writeSkill(
      path.join(location.path, 'internal'),
      name: 'internal',
      body: 'internal body',
      internal: true,
    );

    final excluded = await adapter.scanLocation(
      location: location.path,
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );
    final included = await adapter.scanLocation(
      location: location.path,
      includeInternal: true,
      cancellationToken: CancellationToken.none(),
    );

    expect(excluded.valueOrNull, isEmpty);
    expect(included.valueOrNull!.single.slotKey, 'internal');
  });

  test('scan is read-only and preserves every source byte', () async {
    final location = Directory(path.join(temporaryDirectory.path, 'skills'));
    final skill = await _writeSkill(
      path.join(location.path, 'review'),
      name: 'review',
      body: 'preserve me',
    );
    final skillFile = File(path.join(skill.path, 'SKILL.md'));
    final beforeBytes = await skillFile.readAsBytes();
    final beforeEntries = await _relativeEntries(location);

    final result = await adapter.scanLocation(
      location: location.path,
      includeInternal: false,
      cancellationToken: CancellationToken.none(),
    );

    expect(result.valueOrNull, hasLength(1));
    expect(await skillFile.readAsBytes(), beforeBytes);
    expect(await _relativeEntries(location), beforeEntries);
  });

  test(
    'targeted scan reads complete content only for matching Slots',
    () async {
      final location = Directory(path.join(temporaryDirectory.path, 'skills'));
      await _writeSkill(
        path.join(location.path, 'selected'),
        name: 'selected',
        body: 'selected body',
      );
      await _writeSkill(
        path.join(location.path, 'unrelated'),
        name: 'unrelated',
        body: 'unrelated body',
      );
      final worker = _CountingRevisionContentWorker();
      final targetedAdapter = FileSystemExternalSkillLocation(
        localSource: LocalSourceAdapter(contentWorker: worker),
      );

      final result = await targetedAdapter.scanLocation(
        location: location.path,
        selectedSlotKeys: const <String>{'selected'},
        includeInternal: false,
        cancellationToken: CancellationToken.none(),
      );

      expect(result.valueOrNull!.map((skill) => skill.slotKey), <String>[
        'selected',
      ]);
      expect(worker.readBasenames, <String>['selected']);
    },
  );

  test('pre-cancelled scan performs no discovery', () async {
    final cancellation = CancellationSource();
    await cancellation.cancel();

    final result = await adapter.scanLocation(
      location: temporaryDirectory.path,
      includeInternal: false,
      cancellationToken: cancellation.token,
    );

    expect(result.failureOrNull?.code.name, 'operationCancelled');
  });
}

Future<Directory> _writeSkill(
  String directoryPath, {
  required String name,
  required String body,
  bool internal = false,
}) async {
  final directory = Directory(directoryPath);
  await directory.create(recursive: true);
  await File(path.join(directory.path, 'SKILL.md')).writeAsString('''
---
name: $name
description: Example Skill
${internal ? 'metadata:\n  internal: true' : ''}
---
$body
''');
  return directory;
}

Future<List<String>> _relativeEntries(Directory root) async {
  final entries = <String>[];
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    entries.add(path.relative(entity.path, from: root.path));
  }
  entries.sort();
  return entries;
}

final class _RejectingRevisionContentWorker
    implements RevisionContentWorkerPort {
  const _RejectingRevisionContentWorker(this.rejectedBasename);

  final String rejectedBasename;
  static const _delegate = DirectRevisionContentWorker();

  @override
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) => _delegate.normalizeContent(
    entries,
    maximumFileCount: maximumFileCount,
    maximumByteSize: maximumByteSize,
    isCancelled: isCancelled,
  );

  @override
  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) {
    if (path.basename(rootPath) == rejectedBasename) {
      return Future.value(
        SkillContentFailure<NormalizedSkillTree>(
          code: SkillContentFailureCode.invalidContent,
          context: const <String, Object?>{
            'reason': 'testInvalidCandidate',
            'path': 'unsupported-entry',
          },
        ),
      );
    }
    return _delegate.readFilesystemTree(
      rootPath,
      gitMetadataDisposition: gitMetadataDisposition,
      capturePosixExecutableIntent: capturePosixExecutableIntent,
      executableIntentOverrides: executableIntentOverrides,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    );
  }
}

final class _CountingRevisionContentWorker
    implements RevisionContentWorkerPort {
  static const _delegate = DirectRevisionContentWorker();
  final List<String> readBasenames = <String>[];

  @override
  Future<SkillContentResult<NormalizedSkillTree>> normalizeContent(
    List<SkillContentEntry> entries, {
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) => _delegate.normalizeContent(
    entries,
    maximumFileCount: maximumFileCount,
    maximumByteSize: maximumByteSize,
    isCancelled: isCancelled,
  );

  @override
  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) {
    readBasenames.add(path.basename(rootPath));
    return _delegate.readFilesystemTree(
      rootPath,
      gitMetadataDisposition: gitMetadataDisposition,
      capturePosixExecutableIntent: capturePosixExecutableIntent,
      executableIntentOverrides: executableIntentOverrides,
      maximumFileCount: maximumFileCount,
      maximumByteSize: maximumByteSize,
      isCancelled: isCancelled,
    );
  }
}
