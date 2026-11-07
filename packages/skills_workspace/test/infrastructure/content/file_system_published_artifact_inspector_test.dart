import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/infrastructure/content/direct_revision_content_worker.dart';
import 'package:skills_workspace/src/infrastructure/content/file_system_published_artifact_inspector.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'package:test/test.dart';

void main() {
  const inspector = FileSystemPublishedArtifactInspector(
    contentWorker: DirectRevisionContentWorker(),
    metadataObserver: FileSystemPublishedArtifactMetadataObserver(),
  );
  late Directory temporary;
  late String target;
  late CancellationToken token;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('published-inspection-');
    target = path.join(temporary.path, 'artifact');
    token = CancellationToken.none();
  });
  tearDown(() => temporary.delete(recursive: true));

  test('missing observations retain missing semantics', () async {
    final observation = await inspector.observe(
      path: target,
      cancellationToken: token,
    );
    expect(observation.state, PublishedArtifactState.missing);
    expect(observation.fingerprint, isNull);
    expect(observation.observedEntryKind, isNull);
  });

  test('directory drift carries the normalized tree fingerprint', () async {
    await Directory(target).create();
    await File(path.join(target, 'SKILL.md')).writeAsString('external');
    final observation = await inspector.observe(
      path: target,
      cancellationToken: token,
    );
    final mismatch = await inspector.inspectDirectory(
      path: target,
      expectedContentHash: 'different',
      cancellationToken: token,
    );
    final match = await inspector.inspectDirectory(
      path: target,
      expectedContentHash: observation.fingerprint!,
      cancellationToken: token,
    );
    expect(observation.observedEntryKind, ObservedEntryKind.directory);
    expect(observation.state, PublishedArtifactState.matching);
    expect(observation.fileCount, 1);
    expect(observation.byteSize, 8);
    expect(mismatch.state, PublishedArtifactState.mismatching);
    expect(mismatch.mismatchKind, PublishedArtifactMismatchKind.contentChanged);
    expect(mismatch.fingerprint, observation.fingerprint);
    expect(match.state, PublishedArtifactState.matching);
    expect(match.mismatchKind, isNull);
  });

  test(
    'plain-file replacements retain wrong-type semantics without content reads',
    () async {
      await File(target).writeAsString('external');
      final inspection = await inspector.inspectDirectory(
        path: target,
        expectedContentHash: 'managed',
        cancellationToken: token,
      );
      final observation = await inspector.observe(
        path: target,
        cancellationToken: token,
      );
      final contentHash = sha256.convert(utf8.encode('external')).toString();
      expect(inspection.state, PublishedArtifactState.mismatching);
      expect(inspection.observedEntryKind, ObservedEntryKind.file);
      expect(
        inspection.mismatchKind,
        PublishedArtifactMismatchKind.wrongEntryType,
      );
      expect(
        observation.fingerprint,
        sha256.convert(utf8.encode('file\u0000$contentHash')).toString(),
      );
      expect(inspection.fingerprint, isNull);
      expect(inspection.fileCount, 0);
      expect(inspection.byteSize, 0);
    },
  );

  test(
    'oversized wrong-type files remain mismatching with metadata-only review evidence',
    () async {
      final file = await File(target).open(mode: FileMode.write);
      try {
        await file.truncate(maximumNormalizedSkillByteSize + 1);
      } finally {
        await file.close();
      }
      final inspection = await inspector.inspectDirectory(
        path: target,
        expectedContentHash: 'managed',
        cancellationToken: token,
      );
      expect(inspection.state, PublishedArtifactState.mismatching);
      final observation = await inspector.observe(
        path: target,
        cancellationToken: token,
      );
      expect(observation.state, PublishedArtifactState.unsafe);
      final metadata = await inspector.observeMetadata(
        path: target,
        cancellationToken: token,
      );
      expect(metadata.state, PublishedArtifactState.matching);
      expect(metadata.metadataFingerprint, isNotNull);
      expect(inspection.observedEntryKind, ObservedEntryKind.file);
      expect(inspection.fingerprint, isNull);
    },
  );

  test('directories containing Git metadata fail closed', () async {
    await Directory(path.join(target, '.git')).create(recursive: true);
    await File(path.join(target, 'SKILL.md')).writeAsString('external');
    final inspection = await inspector.observe(
      path: target,
      cancellationToken: token,
    );
    expect(inspection.state, PublishedArtifactState.unsafe);
    expect(inspection.observedEntryKind, ObservedEntryKind.directory);
  });

  test(
    'wrong-type Git directories preserve ordinary mismatch semantics',
    () async {
      await Directory(path.join(target, '.git')).create(recursive: true);
      await File(path.join(target, '.git', 'config')).writeAsString('metadata');
      final inspection = await inspector.inspectSymbolicLink(
        path: target,
        expectedTarget: temporary.path,
        cancellationToken: token,
      );
      expect(inspection.state, PublishedArtifactState.mismatching);
      expect(
        inspection.mismatchKind,
        PublishedArtifactMismatchKind.wrongEntryType,
      );
      expect(inspection.fingerprint, isNull);
      final before = await inspector.observeMetadata(
        path: target,
        cancellationToken: token,
      );
      expect(before.state, PublishedArtifactState.matching);
      await File(
        path.join(target, '.git', 'config'),
      ).writeAsString('changed metadata');
      final after = await inspector.observeMetadata(
        path: target,
        cancellationToken: token,
      );
      expect(after.metadataFingerprint, isNot(before.metadataFingerprint));
    },
  );

  test(
    'bounded metadata inspection fails closed without a complete tree',
    () async {
      await Directory(target).create();
      for (var index = 0; index < 4096; index += 1) {
        await File(path.join(target, '$index')).writeAsBytes(const []);
      }
      final metadata = await inspector.observeMetadata(
        path: target,
        cancellationToken: token,
      );
      expect(metadata.state, PublishedArtifactState.unsafe);
      expect(metadata.metadataFingerprint, isNull);
    },
  );

  test(
    'metadata inspection and strong observations honor cancellation',
    () async {
      await Directory(target).create();
      final cancellation = CancellationSource();
      await cancellation.cancel();
      expect(
        (await inspector.observeMetadata(
          path: target,
          cancellationToken: cancellation.token,
        )).state,
        PublishedArtifactState.unsafe,
      );
      expect(
        (await inspector.observe(
          path: target,
          cancellationToken: cancellation.token,
        )).state,
        PublishedArtifactState.unsafe,
      );
    },
  );

  test(
    'contained directory links remain visible as non-exportable evidence',
    () async {
      await Directory(target).create();
      await File(path.join(target, 'SKILL.md')).writeAsString('external');
      await Link(path.join(target, 'copy.md')).create('SKILL.md');
      final observation = await inspector.observe(
        path: target,
        cancellationToken: token,
      );
      expect(observation.state, PublishedArtifactState.matching);
      expect(observation.fingerprint, isNotNull);
      expect(observation.containsSymbolicLinks, isTrue);
    },
    skip: Platform.isWindows ? 'Requires symbolic-link capability.' : false,
  );

  test(
    'special entries retain mismatching inspection semantics but are unsafe to observe',
    () async {
      final socket = await ServerSocket.bind(
        InternetAddress(target, type: InternetAddressType.unix),
        0,
      );
      try {
        final observation = await inspector.observe(
          path: target,
          cancellationToken: token,
        );
        final directoryInspection = await inspector.inspectDirectory(
          path: target,
          expectedContentHash: 'managed',
          cancellationToken: token,
        );
        final linkInspection = await inspector.inspectSymbolicLink(
          path: target,
          expectedTarget: temporary.path,
          cancellationToken: token,
        );
        expect(observation.state, PublishedArtifactState.unsafe);
        expect(observation.observedEntryKind, ObservedEntryKind.other);
        expect(directoryInspection.state, PublishedArtifactState.mismatching);
        expect(
          directoryInspection.mismatchKind,
          PublishedArtifactMismatchKind.wrongEntryType,
        );
        expect(directoryInspection.fingerprint, isNull);
        expect(linkInspection.state, PublishedArtifactState.mismatching);
        expect(
          linkInspection.mismatchKind,
          PublishedArtifactMismatchKind.wrongEntryType,
        );
      } finally {
        await socket.close();
      }
    },
    skip: Platform.isWindows
        ? 'Unix domain sockets require a POSIX host.'
        : false,
  );

  test(
    'link fingerprints use raw targets and never inspect their contents',
    () async {
      final destination = Directory(path.join(temporary.path, 'outside'));
      await Directory(
        path.join(destination.path, '.git'),
      ).create(recursive: true);
      await Link(target).create('outside');
      final observation = await inspector.observe(
        path: target,
        cancellationToken: token,
      );
      final match = await inspector.inspectSymbolicLink(
        path: target,
        expectedTarget: destination.path,
        cancellationToken: token,
      );
      final mismatch = await inspector.inspectSymbolicLink(
        path: target,
        expectedTarget: temporary.path,
        cancellationToken: token,
      );
      final wrongType = await inspector.inspectDirectory(
        path: target,
        expectedContentHash: 'managed',
        cancellationToken: token,
      );
      expect(
        observation.fingerprint,
        sha256.convert(utf8.encode('link\u0000outside')).toString(),
      );
      expect(observation.observedEntryKind, ObservedEntryKind.symbolicLink);
      expect(match.state, PublishedArtifactState.matching);
      expect(mismatch.state, PublishedArtifactState.mismatching);
      expect(
        mismatch.mismatchKind,
        PublishedArtifactMismatchKind.wrongLinkTarget,
      );
      expect(
        wrongType.mismatchKind,
        PublishedArtifactMismatchKind.wrongEntryType,
      );
    },
    skip: Platform.isWindows ? 'Requires symbolic-link capability.' : false,
  );

  test(
    'a directory replacing a link is observed without changing its bytes',
    () async {
      await Directory(target).create();
      await File(path.join(target, 'SKILL.md')).writeAsString('external');
      final inspection = await inspector.inspectSymbolicLink(
        path: target,
        expectedTarget: temporary.path,
        cancellationToken: token,
      );
      expect(inspection.state, PublishedArtifactState.mismatching);
      expect(
        inspection.mismatchKind,
        PublishedArtifactMismatchKind.wrongEntryType,
      );
      expect(inspection.observedEntryKind, ObservedEntryKind.directory);
      expect(inspection.fingerprint, isNull);
      expect(
        await File(path.join(target, 'SKILL.md')).readAsString(),
        'external',
      );
    },
  );
}
