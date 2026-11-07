import 'dart:convert';

import 'package:skills_workspace/src/application/backup/control_plane_backup_codec.dart';
import 'package:skills_workspace/src/application/backup/control_plane_backup_models.dart';
import 'package:test/test.dart';

void main() {
  const codec = ControlPlaneBackupCodec();
  const identity = ControlPlaneIdentity(
    schemaVersion: 1,
    repositoryRevision: 7,
    destructionEpoch: 2,
  );
  const manifest = ControlPlaneBackupManifest(
    backupId: '7',
    identity: identity,
    createdAtMicros: 123,
    databaseByteSize: 456,
    databaseSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  );

  test('manifest and completion fence round-trip canonically', () {
    final bytes = codec.encodeManifest(manifest);
    final decoded = codec.decodeManifest(bytes);

    expect(decoded.backupId, manifest.backupId);
    expect(decoded.identity, identity);
    expect(decoded.createdAtMicros, manifest.createdAtMicros);
    expect(decoded.databaseByteSize, manifest.databaseByteSize);
    expect(decoded.databaseSha256, manifest.databaseSha256);
    expect(codec.encodeManifest(decoded), bytes);
    expect(
      () => codec.verifyCompletionFence(
        manifestBytes: bytes,
        completionFenceBytes: codec.createCompletionFence(bytes),
      ),
      returnsNormally,
    );
  });

  test('completion fence rejects a changed manifest', () {
    final bytes = codec.encodeManifest(manifest);
    final fence = codec.createCompletionFence(bytes);
    final changed = List<int>.from(bytes)..[bytes.length - 2] ^= 1;

    expect(
      () => codec.verifyCompletionFence(
        manifestBytes: changed,
        completionFenceBytes: fence,
      ),
      throwsA(
        isA<ControlPlaneBackupCodecException>().having(
          (error) => error.reason,
          'reason',
          ControlPlaneBackupCodecFailureReason.manifestDigestMismatch,
        ),
      ),
    );
  });

  test('steady and armed eligibility round-trip with self-checking digest', () {
    const steady = SteadyBackupEligibility(
      destructionEpoch: 2,
      establishedAtRepositoryRevision: 7,
    );
    const armed = ArmedBackupEligibility(
      operationId: 'operation-1',
      previousDestructionEpoch: 2,
      intendedDestructionEpoch: 3,
      previousSteadyRepositoryRevision: 7,
      armedAtRepositoryRevision: 9,
    );

    final decodedSteady = codec.decodeEligibility(
      codec.encodeEligibility(steady),
    );
    final decodedArmed = codec.decodeEligibility(
      codec.encodeEligibility(armed),
    );

    expect(decodedSteady, isA<SteadyBackupEligibility>());
    expect(
      (decodedSteady as SteadyBackupEligibility).destructionEpoch,
      steady.destructionEpoch,
    );
    expect(decodedArmed, isA<ArmedBackupEligibility>());
    expect(
      (decodedArmed as ArmedBackupEligibility).operationId,
      armed.operationId,
    );
  });

  test('eligibility rejects a payload changed without its digest', () {
    const steady = SteadyBackupEligibility(
      destructionEpoch: 2,
      establishedAtRepositoryRevision: 7,
    );
    final original = utf8.decode(codec.encodeEligibility(steady));
    final changed = utf8.encode(
      original.replaceFirst(
        '"establishedAtRepositoryRevision":7',
        '"establishedAtRepositoryRevision":8',
      ),
    );

    expect(
      () => codec.decodeEligibility(changed),
      throwsA(
        isA<ControlPlaneBackupCodecException>().having(
          (error) => error.reason,
          'reason',
          ControlPlaneBackupCodecFailureReason.eligibilityDigestMismatch,
        ),
      ),
    );
  });
}
