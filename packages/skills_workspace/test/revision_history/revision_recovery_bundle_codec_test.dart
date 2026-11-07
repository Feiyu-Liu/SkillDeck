import 'dart:convert';

import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_recovery_bundle.dart';
import 'package:test/test.dart';

void main() {
  const codec = RevisionRecoveryBundleCodec();
  final upstream = RevisionObjectId(List.filled(40, '1').join());
  final effective = RevisionObjectId(List.filled(40, '2').join());

  test('encodes a deterministic canonical manifest and completion fence', () {
    final manifest = codec.createManifest(
      sourceLineageId: 'lineage-a',
      currentUpstream: upstream,
      currentEffective: effective,
      retainedPublishedRoots: <RevisionObjectId>[
        effective,
        upstream,
        effective,
      ],
      packBytes: const <int>[1, 2, 3],
      indexBytes: const <int>[4, 5, 6],
    );

    final first = codec.encodeManifest(manifest);
    final second = codec.encodeManifest(manifest);
    final fence = codec.createCompletionFence(first);

    expect(first, second);
    expect(utf8.decode(first), startsWith('{"artifacts":'));
    expect(
      codec
          .verify(
            manifestBytes: first,
            completionFenceBytes: fence,
            packBytes: const <int>[1, 2, 3],
            indexBytes: const <int>[4, 5, 6],
          )
          .retainedPublishedRoots,
      <RevisionObjectId>[upstream, effective],
    );
  });

  test('rejects a fence from another manifest', () {
    final manifest = codec.createManifest(
      sourceLineageId: 'lineage-a',
      currentUpstream: upstream,
      currentEffective: effective,
      retainedPublishedRoots: <RevisionObjectId>[upstream, effective],
      packBytes: const <int>[1],
      indexBytes: const <int>[2],
    );
    final bytes = codec.encodeManifest(manifest);
    final otherFence = codec.createCompletionFence(<int>[...bytes, 0]);

    expect(
      () => codec.verify(
        manifestBytes: bytes,
        completionFenceBytes: otherFence,
        packBytes: const <int>[1],
        indexBytes: const <int>[2],
      ),
      throwsA(
        isA<RevisionRecoveryBundleException>().having(
          (error) => error.reason,
          'reason',
          RevisionRecoveryBundleFailureReason.manifestDigestMismatch,
        ),
      ),
    );
  });

  test('requires at least one retained published history root', () {
    expect(
      () => RevisionRecoveryBundleManifest(
        sourceLineageId: 'lineage-a',
        currentUpstream: upstream,
        currentEffective: effective,
        retainedPublishedRoots: const <RevisionObjectId>[],
        packSha256: List.filled(64, 'a').join(),
        indexSha256: List.filled(64, 'b').join(),
      ),
      throwsArgumentError,
    );
  });
}
