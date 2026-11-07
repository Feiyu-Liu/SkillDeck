import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/application/ports/published_artifact_ports.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/platform/filesystem/file_system_published_artifact_metadata_observer.dart';
import 'package:skills_workspace/src/platform/filesystem/filesystem_primitives.dart';
import 'package:skills_workspace/src/platform/filesystem/posix_filesystem_primitives.dart';
import 'package:skills_workspace/src/platform/filesystem/windows_filesystem_primitives.dart';
import 'package:test/test.dart';

import '../../support/filesystem/fault_injecting_filesystem_primitives.dart';

void main() {
  const observer = FileSystemPublishedArtifactMetadataObserver();
  late Directory temporary;
  late String target;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('metadata-observe-');
    target = path.join(temporary.path, 'entry');
  });
  tearDown(() => temporary.delete(recursive: true));

  Future<PublishedArtifactInspection> observe() => observer.observeMetadata(
    path: target,
    cancellationToken: CancellationToken.none(),
  );

  test('missing paths have no usable metadata evidence', () async {
    final result = await observe();
    expect(result.state, PublishedArtifactState.missing);
    expect(result.metadataFingerprint, isNull);
  });

  test(
    'physical replacement changes evidence even when bytes and mtime are equal',
    () async {
      final file = await File(target).writeAsString('same');
      final modified = DateTime.utc(2001);
      await file.setLastModified(modified);
      final before = await observe();
      await file.rename('$target-old');
      await File(target).writeAsString('same');
      await File(target).setLastModified(modified);
      final after = await observe();
      expect(before.state, PublishedArtifactState.matching);
      expect(after.state, PublishedArtifactState.matching);
      expect(after.metadataFingerprint, isNot(before.metadataFingerprint));
      expect(after.fingerprint, isNull);
    },
  );

  test('cancelled scans produce no partial witness', () async {
    await Directory(target).create();
    final cancellation = CancellationSource();
    await cancellation.cancel();
    final result = await observer.observeMetadata(
      path: target,
      cancellationToken: cancellation.token,
    );
    expect(result.state, PublishedArtifactState.unsafe);
    expect(result.metadataFingerprint, isNull);
  });

  test(
    'cancellation during a recursive scan discards collected metadata',
    () async {
      await Directory(target).create();
      await File(path.join(target, 'one')).writeAsString('one');
      final cancellation = CancellationSource();
      var inspections = 0;
      final cancellingObserver = FileSystemPublishedArtifactMetadataObserver(
        primitives: FaultInjectingFilesystemPrimitives(
          delegate: Platform.isWindows
              ? const WindowsFilesystemPrimitives()
              : const PosixFilesystemPrimitives(),
          beforeOperation: (operation, entryPath) {
            if (operation == DurableFilesystemOperation.inspectPath &&
                ++inspections == 2) {
              unawaited(cancellation.cancel());
            }
          },
        ),
      );
      final result = await cancellingObserver.observeMetadata(
        path: target,
        cancellationToken: cancellation.token,
      );
      expect(result.state, PublishedArtifactState.unsafe);
      expect(result.metadataFingerprint, isNull);
      expect(inspections, greaterThan(1));
    },
  );

  test('unreadable native metadata fails closed', () async {
    await File(target).writeAsString('external');
    final failingObserver = FileSystemPublishedArtifactMetadataObserver(
      primitives: FaultInjectingFilesystemPrimitives(
        delegate: Platform.isWindows
            ? const WindowsFilesystemPrimitives()
            : const PosixFilesystemPrimitives(),
        beforeOperation: (operation, entryPath) {
          throw DurableFilesystemException(
            operation: operation,
            message: 'Injected metadata failure.',
          );
        },
      ),
    );
    final result = await failingObserver.observeMetadata(
      path: target,
      cancellationToken: CancellationToken.none(),
    );
    expect(result.state, PublishedArtifactState.unsafe);
    expect(result.metadataFingerprint, isNull);
  });

  test(
    'dangling links are fingerprinted without resolving or following targets',
    () async {
      await Link(target).create('missing-target');
      final before = await observe();
      expect(before.state, PublishedArtifactState.matching);
      expect(before.observedEntryKind, ObservedEntryKind.symbolicLink);
      expect(before.containsSymbolicLinks, isTrue);
      await Link(target).update('another-missing-target');
      final after = await observe();
      expect(after.state, PublishedArtifactState.matching);
      expect(after.metadataFingerprint, isNot(before.metadataFingerprint));
    },
    skip: Platform.isWindows ? 'Requires symbolic-link capability.' : false,
  );
}
