import 'dart:convert';
import 'dart:typed_data';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';

import 'control_plane_backup_models.dart';

const int controlPlaneBackupManifestSchemaVersion = 1;
const int backupEligibilitySchemaVersion = 1;

enum ControlPlaneBackupCodecFailureReason {
  invalidManifest,
  invalidCompletionFence,
  unsupportedSchema,
  manifestDigestMismatch,
  invalidEligibility,
  eligibilityDigestMismatch,
}

final class ControlPlaneBackupCodecException implements Exception {
  const ControlPlaneBackupCodecException(this.reason);

  final ControlPlaneBackupCodecFailureReason reason;

  @override
  String toString() => 'ControlPlaneBackupCodecException(${reason.name})';
}

final class ControlPlaneBackupCodec {
  const ControlPlaneBackupCodec();

  Uint8List encodeManifest(ControlPlaneBackupManifest manifest) {
    _validateManifest(manifest);
    return Uint8List.fromList(
      canonicalJson.encode(<String, Object>{
        'schema': controlPlaneBackupManifestSchemaVersion,
        'backupId': manifest.backupId,
        'databaseSchemaVersion': manifest.identity.schemaVersion,
        'repositoryRevision': manifest.identity.repositoryRevision,
        'destructionEpoch': manifest.identity.destructionEpoch,
        'createdAtMicros': manifest.createdAtMicros,
        'databaseByteSize': manifest.databaseByteSize,
        'databaseSha256': manifest.databaseSha256,
      }),
    );
  }

  ControlPlaneBackupManifest decodeManifest(List<int> bytes) {
    final map = _decodeMap(
      bytes,
      ControlPlaneBackupCodecFailureReason.invalidManifest,
    );
    if (map['schema'] != controlPlaneBackupManifestSchemaVersion) {
      throw const ControlPlaneBackupCodecException(
        ControlPlaneBackupCodecFailureReason.unsupportedSchema,
      );
    }
    try {
      final manifest = ControlPlaneBackupManifest(
        backupId: map['backupId']! as String,
        identity: ControlPlaneIdentity(
          schemaVersion: map['databaseSchemaVersion']! as int,
          repositoryRevision: map['repositoryRevision']! as int,
          destructionEpoch: map['destructionEpoch']! as int,
        ),
        createdAtMicros: map['createdAtMicros']! as int,
        databaseByteSize: map['databaseByteSize']! as int,
        databaseSha256: map['databaseSha256']! as String,
      );
      _validateManifest(manifest);
      return manifest;
    } on ControlPlaneBackupCodecException {
      rethrow;
    } on Object {
      throw const ControlPlaneBackupCodecException(
        ControlPlaneBackupCodecFailureReason.invalidManifest,
      );
    }
  }

  Uint8List createCompletionFence(List<int> manifestBytes) {
    return Uint8List.fromList(
      canonicalJson.encode(<String, Object>{
        'schema': controlPlaneBackupManifestSchemaVersion,
        'manifestSha256': sha256.convert(manifestBytes).toString(),
      }),
    );
  }

  void verifyCompletionFence({
    required List<int> manifestBytes,
    required List<int> completionFenceBytes,
  }) {
    final fence = _decodeMap(
      completionFenceBytes,
      ControlPlaneBackupCodecFailureReason.invalidCompletionFence,
    );
    if (fence['schema'] != controlPlaneBackupManifestSchemaVersion ||
        fence['manifestSha256'] is! String) {
      throw const ControlPlaneBackupCodecException(
        ControlPlaneBackupCodecFailureReason.invalidCompletionFence,
      );
    }
    if (!_digestEquals(
      fence['manifestSha256']! as String,
      sha256.convert(manifestBytes).toString(),
    )) {
      throw const ControlPlaneBackupCodecException(
        ControlPlaneBackupCodecFailureReason.manifestDigestMismatch,
      );
    }
  }

  Uint8List encodeEligibility(BackupEligibility eligibility) {
    final payload = switch (eligibility) {
      SteadyBackupEligibility() => <String, Object>{
        'state': 'steady',
        'destructionEpoch': eligibility.destructionEpoch,
        'establishedAtRepositoryRevision':
            eligibility.establishedAtRepositoryRevision,
      },
      ArmedBackupEligibility() => <String, Object>{
        'state': 'armed',
        'operationId': eligibility.operationId,
        'previousDestructionEpoch': eligibility.previousDestructionEpoch,
        'intendedDestructionEpoch': eligibility.intendedDestructionEpoch,
        'previousSteadyRepositoryRevision':
            eligibility.previousSteadyRepositoryRevision,
        'armedAtRepositoryRevision': eligibility.armedAtRepositoryRevision,
      },
    };
    _validateEligibility(eligibility);
    final payloadBytes = canonicalJson.encode(payload);
    return Uint8List.fromList(
      canonicalJson.encode(<String, Object>{
        'schema': backupEligibilitySchemaVersion,
        'payload': payload,
        'payloadSha256': sha256.convert(payloadBytes).toString(),
      }),
    );
  }

  BackupEligibility decodeEligibility(List<int> bytes) {
    final envelope = _decodeMap(
      bytes,
      ControlPlaneBackupCodecFailureReason.invalidEligibility,
    );
    if (envelope['schema'] != backupEligibilitySchemaVersion) {
      throw const ControlPlaneBackupCodecException(
        ControlPlaneBackupCodecFailureReason.unsupportedSchema,
      );
    }
    try {
      final payload = (envelope['payload']! as Map<Object?, Object?>).map(
        (key, value) => MapEntry(key! as String, value),
      );
      final expectedDigest = envelope['payloadSha256']! as String;
      final actualDigest = sha256
          .convert(canonicalJson.encode(payload))
          .toString();
      if (!_digestEquals(expectedDigest, actualDigest)) {
        throw const ControlPlaneBackupCodecException(
          ControlPlaneBackupCodecFailureReason.eligibilityDigestMismatch,
        );
      }
      final eligibility = switch (payload['state']) {
        'steady' => SteadyBackupEligibility(
          destructionEpoch: payload['destructionEpoch']! as int,
          establishedAtRepositoryRevision:
              payload['establishedAtRepositoryRevision']! as int,
        ),
        'armed' => ArmedBackupEligibility(
          operationId: payload['operationId']! as String,
          previousDestructionEpoch: payload['previousDestructionEpoch']! as int,
          intendedDestructionEpoch: payload['intendedDestructionEpoch']! as int,
          previousSteadyRepositoryRevision:
              payload['previousSteadyRepositoryRevision']! as int,
          armedAtRepositoryRevision:
              payload['armedAtRepositoryRevision']! as int,
        ),
        _ => throw const FormatException(),
      };
      _validateEligibility(eligibility);
      return eligibility;
    } on ControlPlaneBackupCodecException {
      rethrow;
    } on Object {
      throw const ControlPlaneBackupCodecException(
        ControlPlaneBackupCodecFailureReason.invalidEligibility,
      );
    }
  }
}

Map<String, Object?> _decodeMap(
  List<int> bytes,
  ControlPlaneBackupCodecFailureReason failure,
) {
  try {
    // canonical_json 1.1.3 encodes zero but its decoder rejects zero. Decode
    // with dart:convert, then require byte-for-byte canonical re-encoding so
    // the on-disk contract remains canonical without excluding initial
    // Repository Revision or Destruction Epoch values.
    final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (decoded is! Map<String, Object?>) throw const FormatException();
    if (!_bytesEqual(bytes, canonicalJson.encode(decoded))) {
      throw const FormatException();
    }
    return decoded;
  } on Object {
    throw ControlPlaneBackupCodecException(failure);
  }
}

void _validateManifest(ControlPlaneBackupManifest manifest) {
  if (manifest.backupId.isEmpty ||
      manifest.identity.schemaVersion < 1 ||
      manifest.identity.repositoryRevision < 0 ||
      manifest.identity.destructionEpoch < 0 ||
      manifest.createdAtMicros < 0 ||
      manifest.databaseByteSize < 1 ||
      !RegExp(r'^[0-9a-f]{64}$').hasMatch(manifest.databaseSha256)) {
    throw const ControlPlaneBackupCodecException(
      ControlPlaneBackupCodecFailureReason.invalidManifest,
    );
  }
}

void _validateEligibility(BackupEligibility eligibility) {
  final valid = switch (eligibility) {
    SteadyBackupEligibility() =>
      eligibility.destructionEpoch >= 0 &&
          eligibility.establishedAtRepositoryRevision >= 0,
    ArmedBackupEligibility() =>
      eligibility.operationId.isNotEmpty &&
          eligibility.previousDestructionEpoch >= 0 &&
          eligibility.intendedDestructionEpoch ==
              eligibility.previousDestructionEpoch + 1 &&
          eligibility.previousSteadyRepositoryRevision >= 0 &&
          eligibility.previousSteadyRepositoryRevision <=
              eligibility.armedAtRepositoryRevision &&
          eligibility.armedAtRepositoryRevision >= 0,
  };
  if (!valid) {
    throw const ControlPlaneBackupCodecException(
      ControlPlaneBackupCodecFailureReason.invalidEligibility,
    );
  }
}

bool _digestEquals(String left, String right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}
