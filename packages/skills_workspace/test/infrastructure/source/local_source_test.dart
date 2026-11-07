import 'dart:io';

import 'package:path/path.dart' as paths;
import 'package:skills_workspace/src/application/ports/revision_content_worker_ports.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/infrastructure/source/local_source.dart';
import 'package:skills_workspace/src/infrastructure/source/source_result.dart';
import 'package:test/test.dart';

import '../../support/content/revision_content_worker_fake.dart';

void main() {
  test(
    'acquires a selected local Skill through shared normalization',
    () async {
      final root = await Directory.systemTemp.createTemp('workspace-local-');
      addTearDown(() => root.delete(recursive: true));
      final skillRoot = Directory(paths.join(root.path, 'skills', 'example'));
      await skillRoot.create(recursive: true);
      await File(paths.join(skillRoot.path, 'SKILL.md')).writeAsString('''
---
name: example
description: Example description
---
# Example
''');
      await File(paths.join(skillRoot.path, 'notes.md')).writeAsString('notes');

      final source = LocalSourceDescriptor(
        locator: paths.normalize(root.absolute.path),
        skillPath: 'skills',
      );
      final contentWorker = RecordingRevisionContentWorker();
      final result = await LocalSourceAdapter(
        contentWorker: contentWorker,
      ).acquire(source, selectedSkills: const <String>['example']);

      final skill = result.valueOrNull!.skills.single;
      expect(skill.skillPath, 'skills/example');
      expect(skill.tree.files.map((file) => file.relativePath), <String>[
        'SKILL.md',
        'notes.md',
      ]);
      expect(skill.tree.contentHash, hasLength(64));
      expect(
        (skill.provenance as LocalSourceDescriptor).skillPath,
        'skills/example',
      );
      expect(contentWorker.filesystemReadCalls, 1);
      expect(contentWorker.normalizationCalls, 0);
    },
  );

  test('excludes Git metadata when acquiring a local checkout', () async {
    final root = await Directory.systemTemp.createTemp('workspace-local-');
    addTearDown(() => root.delete(recursive: true));
    await File(paths.join(root.path, 'SKILL.md')).writeAsString('''
---
name: example
description: Example description
---
''');
    await Directory(paths.join(root.path, '.git')).create();
    await File(paths.join(root.path, '.git', 'config')).writeAsString('unsafe');
    await File(paths.join(root.path, '.gitignore')).writeAsString('build/');

    final result = await LocalSourceAdapter().acquire(
      LocalSourceDescriptor(locator: paths.normalize(root.absolute.path)),
    );

    expect(result.failureOrNull, isNull);
    expect(
      result.valueOrNull!.skills.single.tree.files.map(
        (file) => file.relativePath,
      ),
      <String>['.gitignore', 'SKILL.md'],
    );
  });

  test(
    'explicit acquisition remains fail-fast across selected Skills',
    () async {
      final root = await Directory.systemTemp.createTemp('workspace-local-');
      addTearDown(() => root.delete(recursive: true));
      for (final name in <String>['invalid', 'valid']) {
        final skillRoot = Directory(paths.join(root.path, 'skills', name));
        await skillRoot.create(recursive: true);
        await File(paths.join(skillRoot.path, 'SKILL.md')).writeAsString('''
---
name: $name
description: Example description
---
''');
      }

      final result = await LocalSourceAdapter(
        contentWorker: const _RejectingRevisionContentWorker('invalid'),
      ).acquire(LocalSourceDescriptor(locator: root.path));

      expect(result.failureOrNull?.code, SourceFailureCode.contentInvalid);
      expect(result.valueOrNull, isNull);
    },
  );
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
    if (paths.basename(rootPath) == rejectedBasename) {
      return Future.value(
        SkillContentFailure<NormalizedSkillTree>(
          code: SkillContentFailureCode.invalidContent,
          context: const <String, Object?>{'reason': 'testInvalidCandidate'},
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
