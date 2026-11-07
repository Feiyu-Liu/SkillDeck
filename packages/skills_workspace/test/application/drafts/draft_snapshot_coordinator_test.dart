import 'package:skills_workspace/src/application/drafts/draft_snapshot_coordinator.dart';
import 'package:skills_workspace/src/application/ports/draft_snapshot_ports.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:test/test.dart';

void main() {
  late _FakeDraftFilesystem filesystem;
  late _FakeDraftContent content;
  late DraftSnapshotCoordinator coordinator;
  late DraftCaptureRequest request;

  setUp(() {
    filesystem = _FakeDraftFilesystem();
    content = _FakeDraftContent();
    coordinator = DraftSnapshotCoordinator(
      filesystem: filesystem,
      content: content,
    );
    request = DraftCaptureRequest(
      liveDraftPath: '/workspace/draft',
      stagingDestinationPath: '/workspace/staging/snapshot',
    );
  });

  test('stable direct Publish returns the sole immutable snapshot', () async {
    final capture = _capture('one');
    filesystem.captures.add(DraftSnapshotSuccess<DraftCapture>(capture));
    filesystem.fingerprints.add(
      DraftSnapshotSuccess<DraftFingerprint>(capture.fingerprint),
    );
    content.trees.add(_tree('one'));
    content.declaredName = 'example';

    final result = await coordinator.captureForDirectPublish(
      request: request,
      expectedDeclaredName: 'example',
    );

    expect(result.failureOrNull, isNull);
    expect(result.valueOrNull!.capture, same(capture));
    expect(result.valueOrNull!.normalizedTree.files.single.bytes, [1]);
    expect(filesystem.discarded, isEmpty);
  });

  test('capture retries the complete protocol at most three times', () async {
    final first = _capture('first');
    final second = _capture('second');
    final third = _capture('third');
    filesystem.captures.addAll(<DraftSnapshotResult<DraftCapture>>[
      DraftSnapshotSuccess<DraftCapture>(first),
      DraftSnapshotSuccess<DraftCapture>(second),
      DraftSnapshotSuccess<DraftCapture>(third),
    ]);
    filesystem.fingerprints.addAll(<DraftSnapshotResult<DraftFingerprint>>[
      DraftSnapshotSuccess<DraftFingerprint>(_fingerprint('changed-1')),
      DraftSnapshotSuccess<DraftFingerprint>(_fingerprint('changed-2')),
      DraftSnapshotSuccess<DraftFingerprint>(_fingerprint('changed-3')),
    ]);
    content.trees.addAll(<NormalizedSkillTree>[
      _tree('first'),
      _tree('second'),
      _tree('third'),
    ]);

    final result = await coordinator.captureForDirectPublish(
      request: request,
      expectedDeclaredName: 'example',
    );

    expect(
      result.failureOrNull!.code,
      DraftSnapshotFailureCode.draftChangedDuringPublish,
    );
    expect(filesystem.captureCalls, 3);
    expect(filesystem.discarded, [first, second, third]);
  });

  test(
    'capture-level overlap retries without normalizing partial bytes',
    () async {
      final stable = _capture('stable');
      filesystem.captures.addAll(<DraftSnapshotResult<DraftCapture>>[
        DraftSnapshotFailure<DraftCapture>(
          code: DraftSnapshotFailureCode.draftChangedDuringPublish,
        ),
        DraftSnapshotSuccess<DraftCapture>(stable),
      ]);
      filesystem.fingerprints.add(
        DraftSnapshotSuccess<DraftFingerprint>(stable.fingerprint),
      );
      content.trees.add(_tree('stable'));
      content.declaredName = 'example';

      final result = await coordinator.captureForDirectPublish(
        request: request,
        expectedDeclaredName: 'example',
      );

      expect(result.valueOrNull, isNotNull);
      expect(content.normalizeCalls, 1);
      expect(filesystem.captureCalls, 2);
    },
  );

  test('direct Publish rejects a changed Declared Skill Name', () async {
    final capture = _capture('name');
    filesystem.captures.add(DraftSnapshotSuccess<DraftCapture>(capture));
    filesystem.fingerprints.add(
      DraftSnapshotSuccess<DraftFingerprint>(capture.fingerprint),
    );
    content.trees.add(_tree('name'));
    content.declaredName = 'renamed';

    final result = await coordinator.captureForDirectPublish(
      request: request,
      expectedDeclaredName: 'original',
    );

    expect(
      result.failureOrNull!.code,
      DraftSnapshotFailureCode.declaredNameChangeNotAllowed,
    );
    expect(filesystem.discarded, [capture]);
  });

  test('staging cleanup failure is returned as typed I/O failure', () async {
    final capture = _capture('cleanup');
    filesystem.captures.add(DraftSnapshotSuccess<DraftCapture>(capture));
    filesystem.fingerprints.add(
      DraftSnapshotSuccess<DraftFingerprint>(capture.fingerprint),
    );
    filesystem.failDiscard = true;
    content.trees.add(_tree('cleanup'));
    content.declaredName = 'renamed';

    final result = await coordinator.captureForDirectPublish(
      request: request,
      expectedDeclaredName: 'original',
    );

    expect(result.failureOrNull!.code, DraftSnapshotFailureCode.ioFailure);
    expect(result.failureOrNull!.context['reason'], 'stagingCleanupFailed');
  });

  test(
    'dirty state compares complete normalized bytes, not hash alone',
    () async {
      final capture = _capture('dirty');
      filesystem.captures.add(DraftSnapshotSuccess<DraftCapture>(capture));
      filesystem.fingerprints.add(
        DraftSnapshotSuccess<DraftFingerprint>(capture.fingerprint),
      );
      content.trees.add(_tree('dirty', byte: 2, hashSeed: 'a'));

      final result = await coordinator.inspectDirty(
        request: request,
        draftBase: _tree('base', byte: 1, hashSeed: 'a'),
      );

      expect(result.valueOrNull, isTrue);
      expect(filesystem.discarded, [capture]);
    },
  );

  test('a post-capture save is preserved and re-anchored', () async {
    final capture = _capture('published');
    final snapshot = DraftPublishSnapshot(
      capture: capture,
      normalizedTree: _tree('published'),
      declaredName: 'example',
    );
    filesystem.fingerprints.add(
      DraftSnapshotSuccess<DraftFingerprint>(_fingerprint('later-save')),
    );

    final disposition = await coordinator.decidePublishedDraftDisposition(
      snapshot: snapshot,
      request: request,
    );

    expect(disposition, PublishedDraftDisposition.preserveAndReanchor);
  });

  test('inconclusive finalization preserves user bytes', () async {
    final capture = _capture('published');
    filesystem.fingerprints.add(
      DraftSnapshotFailure<DraftFingerprint>(
        code: DraftSnapshotFailureCode.ioFailure,
      ),
    );

    final disposition = await coordinator.decidePublishedDraftDisposition(
      snapshot: DraftPublishSnapshot(
        capture: capture,
        normalizedTree: _tree('published'),
        declaredName: 'example',
      ),
      request: request,
    );

    expect(disposition, PublishedDraftDisposition.preserveAndReanchor);
  });

  test('Restore uses its distinct historical name mismatch', () async {
    content.declaredName = 'historical-name';

    final result = await coordinator.validateRestoreDeclaredName(
      expectedDeclaredName: 'current-name',
      historicalTree: _tree('history'),
    );

    expect(
      result.failureOrNull!.code,
      DraftSnapshotFailureCode.historicalNameMismatch,
    );
  });
}

final class _FakeDraftFilesystem implements DraftSnapshotFilesystemPort {
  final List<DraftSnapshotResult<DraftCapture>> captures = [];
  final List<DraftSnapshotResult<DraftFingerprint>> fingerprints = [];
  final List<DraftCapture> discarded = [];
  var captureCalls = 0;
  var failDiscard = false;

  @override
  Future<DraftSnapshotResult<DraftCapture>> capture(
    DraftCaptureRequest request,
  ) async => captures[captureCalls++];

  @override
  Future<void> discardStaging(DraftCapture capture) async {
    if (failDiscard) throw StateError('injected');
    discarded.add(capture);
  }

  @override
  Future<DraftSnapshotResult<DraftFingerprint>> fingerprint(
    DraftCaptureRequest request,
  ) async => fingerprints.removeAt(0);
}

final class _FakeDraftContent implements DraftContentPort {
  final List<NormalizedSkillTree> trees = [];
  String? declaredName = 'example';
  var normalizeCalls = 0;

  @override
  Future<DraftSnapshotResult<NormalizedSkillTree>> normalize(
    List<CapturedDraftFile> files, {
    bool Function()? isCancelled,
  }) async {
    normalizeCalls += 1;
    return DraftSnapshotSuccess<NormalizedSkillTree>(trees.removeAt(0));
  }

  @override
  Future<String?> readDeclaredName(NormalizedSkillTree tree) async =>
      declaredName;
}

DraftCapture _capture(String seed) => DraftCapture(
  liveDraftPath: '/workspace/draft',
  stagingPath: '/workspace/staging/$seed',
  fingerprint: _fingerprint(seed),
  files: <CapturedDraftFile>[
    CapturedDraftFile(
      relativePath: 'SKILL.md',
      bytes: const <int>[1],
      isExecutable: false,
    ),
  ],
);

DraftFingerprint _fingerprint(String seed) =>
    DraftFingerprint(<DraftEntryEvidence>[
      DraftEntryEvidence(
        relativePath: '',
        kind: DraftFilesystemEntryKind.directory,
        entryIdentity: DraftPhysicalIdentity(volumeId: 'volume', fileId: seed),
        resolvedIdentity: DraftPhysicalIdentity(
          volumeId: 'volume',
          fileId: seed,
        ),
        modifiedAtMicrosecondsUtc: 1,
        byteSize: null,
        contentHash: null,
        isExecutable: false,
      ),
    ]);

NormalizedSkillTree _tree(String seed, {int byte = 1, String? hashSeed}) =>
    NormalizedSkillTree(
      files: <NormalizedSkillFile>[
        NormalizedSkillFile(
          relativePath: 'SKILL.md',
          bytes: <int>[byte],
          isExecutable: false,
        ),
      ],
      contentHash: (hashSeed ?? 'a').padRight(64, '0').substring(0, 64),
      byteSize: 1,
    );
