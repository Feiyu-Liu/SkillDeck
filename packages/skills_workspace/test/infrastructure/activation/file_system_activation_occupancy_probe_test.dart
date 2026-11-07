import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/activation/activation_models.dart';
import 'package:skills_workspace/src/application/activation/activation_result.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/content/filesystem_skill_tree_reader.dart';
import 'package:skills_workspace/src/infrastructure/activation/file_system_activation_occupancy_probe.dart';
import 'package:test/test.dart';
import 'package:skills_workspace/src/application/ports/revision_content_worker_ports.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/infrastructure/source/local_source.dart';

import '../../support/activation/activation_fakes.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory repositoryDirectory;
  late FileSystemActivationOccupancyProbe probe;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-occupancy-',
    );
    repositoryDirectory = Directory(
      path.join(temporaryDirectory.path, 'repository'),
    );
    await repositoryDirectory.create();
    probe = FileSystemActivationOccupancyProbe(
      repositoryCopyPathForSkill: (skill) =>
          path.join(repositoryDirectory.path, skill.slotKey),
      locationIdentity: const PosixActivationLocationIdentity(),
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  for (final shape in [
    'empty',
    'dsStore',
    'invalid',
    'file',
    'linkFile',
    'linkEmpty',
    'linkSameSlot',
    'linkOtherSlot',
    'dangling',
    'cycle',
    'sameSlot',
    'otherSlot',
  ]) {
    test(
      'adoption occupant facts: $shape',
      () async {
        final source = await _writeSkill(
          path.join(temporaryDirectory.path, 'source'),
          name: 'example',
          body: 'managed',
        );
        final skill = await _skillFromSource(source);
        final occupied = path.join(temporaryDirectory.path, 'occupied');
        final referent = path.join(temporaryDirectory.path, 'referent');
        switch (shape) {
          case 'empty':
          case 'dsStore':
          case 'invalid':
            await Directory(occupied).create();
            if (shape != 'empty') {
              await File(
                path.join(
                  occupied,
                  shape == 'dsStore' ? '.DS_Store' : 'SKILL.md',
                ),
              ).writeAsString('invalid');
            }
          case 'file':
            await File(occupied).writeAsString('keep');
          case 'linkFile':
            await File(referent).writeAsString('keep');
            await Link(occupied).create(referent);
          case 'linkEmpty':
            await Directory(referent).create();
            await Link(occupied).create(referent);
          case 'linkSameSlot':
          case 'linkOtherSlot':
            await _writeSkill(
              referent,
              name: shape == 'linkSameSlot' ? 'example' : 'other',
              body: 'managed',
            );
            await Link(occupied).create(referent);
          case 'dangling':
            await Link(occupied).create(referent);
          case 'cycle':
            await Link(occupied).create(occupied);
          case 'sameSlot':
          case 'otherSlot':
            await _writeSkill(
              occupied,
              name: shape == 'sameSlot' ? 'example' : 'other',
              body: 'managed',
            );
        }
        final result = await probe.inspect(
          skill: skill,
          target: _target(temporaryDirectory.path),
          targetPath: occupied,
          cancellationToken: CancellationToken.none(),
        );
        final expected = switch (shape) {
          'empty' => AdoptionTargetOccupant.emptyDirectory,
          'dsStore' => AdoptionTargetOccupant.directoryWithContent,
          'invalid' => AdoptionTargetOccupant.invalidSkill,
          'file' => AdoptionTargetOccupant.file,
          'dangling' => AdoptionTargetOccupant.danglingLink,
          'sameSlot' || 'linkSameSlot' => AdoptionTargetOccupant.sameSlotSkill,
          'otherSlot' || 'linkOtherSlot' => AdoptionTargetOccupant.otherSkill,
          'cycle' => AdoptionTargetOccupant.unknown,
          _ => AdoptionTargetOccupant.link,
        };
        expect(result.valueOrNull!.adoptionOccupant, expected);
        expect(
          result.valueOrNull!.adoptionOccupant.isInert,
          shape == 'empty' || shape == 'dangling',
        );
      },
      skip:
          Platform.isWindows &&
          (shape.startsWith('link') || shape == 'dangling' || shape == 'cycle'),
    );
  }

  for (final shape in ['external', 'broken', 'cycle']) {
    test('valid markdown preserves content link failure: $shape', () async {
      final source = await _writeSkill(
        path.join(temporaryDirectory.path, 'source'),
        name: 'example',
        body: 'managed',
      );
      final skill = await _skillFromSource(source);
      final occupied = path.join(temporaryDirectory.path, 'occupied');
      await _writeSkill(occupied, name: 'example', body: 'valid markdown');
      final outside = File(path.join(temporaryDirectory.path, 'outside.txt'));
      await outside.writeAsString('private fixture');
      final link = path.join(occupied, 'reference.txt');
      await Link(link).create(switch (shape) {
        'external' => outside.path,
        'broken' => path.join(occupied, 'missing.txt'),
        _ => link,
      });
      final reason = shape == 'external'
          ? 'symbolicLinkEscapesSkillRoot'
          : 'brokenOrCyclicSymbolicLink';
      final acquired = await LocalSourceAdapter().acquire(
        LocalSourceDescriptor(locator: occupied),
      );
      expect(acquired.failureOrNull!.context['reason'], reason);
      final result = await probe.inspect(
        skill: skill,
        target: _target(temporaryDirectory.path),
        targetPath: occupied,
        cancellationToken: CancellationToken.none(),
      );
      expect(
        result.valueOrNull!.adoptionOccupant,
        AdoptionTargetOccupant.invalidSkill,
      );
      expect(result.valueOrNull!.rootSkillPresent, isTrue);
      expect(result.valueOrNull!.occupantFailureCode, 'contentInvalid');
      expect(result.valueOrNull!.occupantFailureReason, reason);
    }, skip: Platform.isWindows ? 'requires POSIX symlink privileges' : false);
  }

  for (final (code, reason, expectedCode) in [
    (
      SkillContentFailureCode.limitExceeded,
      'fileCountExceeded',
      'contentLimitExceeded',
    ),
    (
      SkillContentFailureCode.unavailable,
      'filesystemReadFailed',
      'unavailable',
    ),
    (SkillContentFailureCode.invalidContent, 'futureReason', 'contentInvalid'),
  ]) {
    test('occupancy preserves worker failure: $reason', () async {
      final source = await _writeSkill(
        path.join(temporaryDirectory.path, 'source'),
        name: 'example',
        body: 'managed',
      );
      final skill = await _skillFromSource(source);
      final occupied = path.join(temporaryDirectory.path, 'occupied');
      await _writeSkill(occupied, name: 'example', body: 'valid');
      final workerProbe = FileSystemActivationOccupancyProbe(
        repositoryCopyPathForSkill: (skill) =>
            path.join(repositoryDirectory.path, skill.slotKey),
        locationIdentity: const PosixActivationLocationIdentity(),
        localSource: LocalSourceAdapter(
          contentWorker: _FailingContentWorker(code, reason),
        ),
      );
      final result = await workerProbe.inspect(
        skill: skill,
        target: _target(temporaryDirectory.path),
        targetPath: occupied,
        cancellationToken: CancellationToken.none(),
      );
      expect(
        result.valueOrNull!.adoptionOccupant,
        AdoptionTargetOccupant.invalidSkill,
      );
      expect(result.valueOrNull!.occupantFailureCode, expectedCode);
      expect(result.valueOrNull!.occupantFailureReason, reason);
    });
  }

  test('vacant target is represented by a successful null result', () async {
    final source = await _writeSkill(
      path.join(temporaryDirectory.path, 'source'),
      name: 'example',
      body: 'managed',
    );
    final skill = await _skillFromSource(source);

    final result = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: path.join(temporaryDirectory.path, 'missing'),
      cancellationToken: CancellationToken.none(),
    );

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, isNull);
  });

  test('ordinary file is replaceable and has a content fingerprint', () async {
    final source = await _writeSkill(
      path.join(temporaryDirectory.path, 'source'),
      name: 'example',
      body: 'managed',
    );
    final skill = await _skillFromSource(source);
    final occupied = File(path.join(temporaryDirectory.path, 'occupied'));
    await occupied.writeAsString('external');

    final first = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: occupied.path,
      cancellationToken: CancellationToken.none(),
    );
    await occupied.writeAsString('changed');
    final second = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: occupied.path,
      cancellationToken: CancellationToken.none(),
    );

    expect(first.valueOrNull!.kind, InspectedActivationOccupancyKind.file);
    expect(first.valueOrNull!.replaceable, isTrue);
    expect(first.valueOrNull!.fingerprint, startsWith('file:'));
    expect(
      second.valueOrNull!.fingerprint,
      isNot(first.valueOrNull!.fingerprint),
    );
  });

  test('canonical matching Skill content is recognized exactly', () async {
    final source = await _writeSkill(
      path.join(temporaryDirectory.path, 'source'),
      name: 'example',
      body: 'same',
    );
    final target = await _writeSkill(
      path.join(temporaryDirectory.path, 'target'),
      name: 'example',
      body: 'same',
    );
    final skill = await _skillFromSource(source);

    final result = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: target.path,
      cancellationToken: CancellationToken.none(),
    );

    final occupancy = result.valueOrNull!;
    expect(occupancy.kind, InspectedActivationOccupancyKind.skillDirectory);
    expect(
      occupancy.contentRelation,
      InspectedActivationContentRelation.matchesCurrentRevision,
    );
    expect(occupancy.existingDeclaredName, 'example');
    expect(occupancy.existingContentHash, skill.currentRevision.contentHash);
  });

  test(
    'divergent Skill and mismatched declared name remain distinguishable',
    () async {
      final source = await _writeSkill(
        path.join(temporaryDirectory.path, 'source'),
        name: 'example',
        body: 'managed',
      );
      final divergent = await _writeSkill(
        path.join(temporaryDirectory.path, 'divergent'),
        name: 'example',
        body: 'external',
      );
      final renamed = await _writeSkill(
        path.join(temporaryDirectory.path, 'renamed'),
        name: 'other',
        body: 'managed',
      );
      final skill = await _skillFromSource(source);

      final divergentResult = await probe.inspect(
        skill: skill,
        target: _target(temporaryDirectory.path),
        targetPath: divergent.path,
        cancellationToken: CancellationToken.none(),
      );
      final renamedResult = await probe.inspect(
        skill: skill,
        target: _target(temporaryDirectory.path),
        targetPath: renamed.path,
        cancellationToken: CancellationToken.none(),
      );

      expect(
        divergentResult.valueOrNull!.contentRelation,
        InspectedActivationContentRelation.differsFromCurrentRevision,
      );
      expect(
        renamedResult.valueOrNull!.contentRelation,
        InspectedActivationContentRelation.indeterminate,
      );
      expect(renamedResult.valueOrNull!.existingDeclaredName, 'other');
    },
  );

  test('invalid directory is fingerprinted as safely replaceable', () async {
    final source = await _writeSkill(
      path.join(temporaryDirectory.path, 'source'),
      name: 'example',
      body: 'managed',
    );
    final invalid = Directory(path.join(temporaryDirectory.path, 'invalid'));
    await invalid.create();
    await File(path.join(invalid.path, 'notes.txt')).writeAsString('notes');
    final skill = await _skillFromSource(source);

    final result = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: invalid.path,
      cancellationToken: CancellationToken.none(),
    );

    expect(
      result.valueOrNull!.kind,
      InspectedActivationOccupancyKind.invalidDirectory,
    );
    expect(result.valueOrNull!.replaceable, isTrue);
    expect(result.valueOrNull!.fingerprint, startsWith('invalidDirectory:'));
  });

  test('cancellation prevents filesystem classification', () async {
    final source = await _writeSkill(
      path.join(temporaryDirectory.path, 'source'),
      name: 'example',
      body: 'managed',
    );
    final skill = await _skillFromSource(source);
    final cancellation = CancellationSource();
    await cancellation.cancel();

    final result = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: source.path,
      cancellationToken: cancellation.token,
    );

    expect(
      result.failureOrNull?.code,
      ActivationFailureCode.operationCancelled,
    );
  });

  test('symbolic link identifies repository copy and broken links', () async {
    if (Platform.isWindows) {
      return;
    }
    final source = await _writeSkill(
      path.join(temporaryDirectory.path, 'source'),
      name: 'example',
      body: 'managed',
    );
    final skill = await _skillFromSource(source);
    final repositoryCopy = await _writeSkill(
      path.join(repositoryDirectory.path, skill.slotKey),
      name: 'example',
      body: 'managed',
    );
    final linked = path.join(temporaryDirectory.path, 'linked');
    await Link(linked).create(repositoryCopy.path);

    final linkedResult = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: linked,
      cancellationToken: CancellationToken.none(),
    );

    expect(
      linkedResult.valueOrNull!.kind,
      InspectedActivationOccupancyKind.skillSymbolicLink,
    );
    expect(linkedResult.valueOrNull!.pointsToRepositoryCopy, isTrue);

    await Link(linked).delete();
    await Link(linked).create(path.join(temporaryDirectory.path, 'missing'));
    final brokenResult = await probe.inspect(
      skill: skill,
      target: _target(temporaryDirectory.path),
      targetPath: linked,
      cancellationToken: CancellationToken.none(),
    );
    expect(
      brokenResult.valueOrNull!.kind,
      InspectedActivationOccupancyKind.brokenSymbolicLink,
    );
    expect(brokenResult.valueOrNull!.replaceable, isTrue);
  });
}

Future<Directory> _writeSkill(
  String directoryPath, {
  required String name,
  required String body,
}) async {
  final directory = Directory(directoryPath);
  await directory.create(recursive: true);
  await File(path.join(directory.path, 'SKILL.md')).writeAsString('''
---
name: $name
description: Example Skill
---
$body
''');
  return directory;
}

Future<ManagedSkill> _skillFromSource(Directory source) async {
  final tree = (await const FilesystemSkillTreeReader().read(
    source.path,
  )).valueOrNull!;
  return ManagedSkill(
    id: ManagedSkillId('00000000-0000-4000-8000-000000000001'),
    slotKey: 'example',
    declaredName: 'example',
    displayName: 'Example',
    description: 'Example Skill',
    source: LocalSourceDescriptor(locator: source.path),
    currentRevision: ManagedSkillRevisionSummary(
      contentHash: tree.contentHash,
      fileCount: tree.fileCount,
      byteSize: tree.byteSize,
      publishedAt: DateTime.utc(2026),
    ),
  );
}

ResolvedActivationTarget _target(String location) => ResolvedActivationTarget(
  location: location,
  scope: ActivationScope.global,
  mode: ActivationMode.copy,
  agentIds: const <String>['agent'],
);

final class _FailingContentWorker implements RevisionContentWorkerPort {
  _FailingContentWorker(this.code, this.reason);
  final SkillContentFailureCode code;
  final String reason;

  @override
  Future<SkillContentResult<NormalizedSkillTree>> readFilesystemTree(
    String rootPath, {
    required GitMetadataDisposition gitMetadataDisposition,
    required bool capturePosixExecutableIntent,
    required Map<String, bool> executableIntentOverrides,
    required int maximumFileCount,
    required int maximumByteSize,
    required bool Function() isCancelled,
  }) async => SkillContentFailure(
    code: code,
    context: {'reason': reason, 'path': '/private/not-for-telemetry'},
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
