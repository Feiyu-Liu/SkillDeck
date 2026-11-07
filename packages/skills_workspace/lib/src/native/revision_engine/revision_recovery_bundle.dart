import 'dart:typed_data';

import 'package:canonical_json/canonical_json.dart';
import 'package:crypto/crypto.dart';

import '../../application/runtime/revision_engine_port.dart';

const int revisionRecoveryBundleSchemaVersion = 2;

final class RevisionRecoveryBundleManifest {
  RevisionRecoveryBundleManifest({
    required this.sourceLineageId,
    required this.currentUpstream,
    required this.currentEffective,
    required List<RevisionObjectId> retainedPublishedRoots,
    required this.packSha256,
    required this.indexSha256,
  }) : retainedPublishedRoots = List<RevisionObjectId>.unmodifiable(
         _normalizeRoots(retainedPublishedRoots),
       ) {
    if (sourceLineageId.isEmpty) {
      throw ArgumentError.value(
        sourceLineageId,
        'sourceLineageId',
        'must not be empty',
      );
    }
    _requireSha256(packSha256, 'packSha256');
    _requireSha256(indexSha256, 'indexSha256');
  }

  final String sourceLineageId;
  final RevisionObjectId currentUpstream;
  final RevisionObjectId currentEffective;
  final List<RevisionObjectId> retainedPublishedRoots;
  final String packSha256;
  final String indexSha256;

  Map<String, Object> toJson() => <String, Object>{
    'schema': revisionRecoveryBundleSchemaVersion,
    'sourceLineageId': sourceLineageId,
    'objectFormat': 'sha1',
    'currentPointers': <String, Object>{
      'upstream': currentUpstream.value,
      'effective': currentEffective.value,
    },
    'retainedPublishedRoots': retainedPublishedRoots
        .map((root) => root.value)
        .toList(growable: false),
    'artifacts': <String, Object>{
      'objects.pack': <String, Object>{'sha256': packSha256},
      'objects.idx': <String, Object>{'sha256': indexSha256},
    },
  };
}

final class RevisionRecoveryBundleException implements Exception {
  const RevisionRecoveryBundleException(this.reason);

  final RevisionRecoveryBundleFailureReason reason;

  @override
  String toString() => 'RevisionRecoveryBundleException(${reason.name})';
}

enum RevisionRecoveryBundleFailureReason {
  invalidManifest,
  unsupportedSchema,
  unsupportedObjectFormat,
  invalidFence,
  manifestDigestMismatch,
  packDigestMismatch,
  indexDigestMismatch,
}

/// Canonical manifest and completion-fence codec for a recovery Bundle.
///
/// Filesystem durability and atomic directory publication are intentionally
/// outside this codec. The operation filesystem adapter writes these bytes,
/// flushes them, reopens them and calls [verify] before the Business Commit
/// Point.
final class RevisionRecoveryBundleCodec {
  const RevisionRecoveryBundleCodec();

  RevisionRecoveryBundleManifest createManifest({
    required String sourceLineageId,
    required RevisionObjectId currentUpstream,
    required RevisionObjectId currentEffective,
    required List<RevisionObjectId> retainedPublishedRoots,
    required List<int> packBytes,
    required List<int> indexBytes,
  }) {
    return RevisionRecoveryBundleManifest(
      sourceLineageId: sourceLineageId,
      currentUpstream: currentUpstream,
      currentEffective: currentEffective,
      retainedPublishedRoots: retainedPublishedRoots,
      packSha256: sha256.convert(packBytes).toString(),
      indexSha256: sha256.convert(indexBytes).toString(),
    );
  }

  Uint8List encodeManifest(RevisionRecoveryBundleManifest manifest) =>
      Uint8List.fromList(canonicalJson.encode(manifest.toJson()));

  Uint8List createCompletionFence(List<int> manifestBytes) {
    final payload = <String, Object>{
      'schema': revisionRecoveryBundleSchemaVersion,
      'manifestSha256': sha256.convert(manifestBytes).toString(),
    };
    return Uint8List.fromList(canonicalJson.encode(payload));
  }

  RevisionRecoveryBundleManifest verify({
    required List<int> manifestBytes,
    required List<int> completionFenceBytes,
    required List<int> packBytes,
    required List<int> indexBytes,
  }) {
    final manifest = decodeManifest(manifestBytes);
    final fence = _decodeMap(
      completionFenceBytes,
      RevisionRecoveryBundleFailureReason.invalidFence,
    );
    if (fence['schema'] != revisionRecoveryBundleSchemaVersion ||
        fence['manifestSha256'] is! String) {
      throw const RevisionRecoveryBundleException(
        RevisionRecoveryBundleFailureReason.invalidFence,
      );
    }
    if (!_digestEquals(
      fence['manifestSha256']! as String,
      sha256.convert(manifestBytes).toString(),
    )) {
      throw const RevisionRecoveryBundleException(
        RevisionRecoveryBundleFailureReason.manifestDigestMismatch,
      );
    }
    if (!_digestEquals(
      manifest.packSha256,
      sha256.convert(packBytes).toString(),
    )) {
      throw const RevisionRecoveryBundleException(
        RevisionRecoveryBundleFailureReason.packDigestMismatch,
      );
    }
    if (!_digestEquals(
      manifest.indexSha256,
      sha256.convert(indexBytes).toString(),
    )) {
      throw const RevisionRecoveryBundleException(
        RevisionRecoveryBundleFailureReason.indexDigestMismatch,
      );
    }
    return manifest;
  }

  RevisionRecoveryBundleManifest decodeManifest(List<int> bytes) {
    final value = _decodeMap(
      bytes,
      RevisionRecoveryBundleFailureReason.invalidManifest,
    );
    if (value['schema'] != revisionRecoveryBundleSchemaVersion) {
      throw const RevisionRecoveryBundleException(
        RevisionRecoveryBundleFailureReason.unsupportedSchema,
      );
    }
    if (value['objectFormat'] != 'sha1') {
      throw const RevisionRecoveryBundleException(
        RevisionRecoveryBundleFailureReason.unsupportedObjectFormat,
      );
    }
    try {
      final pointers = value['currentPointers']! as Map<Object?, Object?>;
      final artifacts = value['artifacts']! as Map<Object?, Object?>;
      final pack = artifacts['objects.pack']! as Map<Object?, Object?>;
      final index = artifacts['objects.idx']! as Map<Object?, Object?>;
      final roots = value['retainedPublishedRoots']! as List<Object?>;
      return RevisionRecoveryBundleManifest(
        sourceLineageId: value['sourceLineageId']! as String,
        currentUpstream: RevisionObjectId(pointers['upstream']! as String),
        currentEffective: RevisionObjectId(pointers['effective']! as String),
        retainedPublishedRoots: roots
            .map((root) => RevisionObjectId(root! as String))
            .toList(growable: false),
        packSha256: pack['sha256']! as String,
        indexSha256: index['sha256']! as String,
      );
    } on Object {
      throw const RevisionRecoveryBundleException(
        RevisionRecoveryBundleFailureReason.invalidManifest,
      );
    }
  }
}

Map<String, Object?> _decodeMap(
  List<int> bytes,
  RevisionRecoveryBundleFailureReason failure,
) {
  try {
    final decoded = canonicalJson.decode(bytes);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException();
    }
    return decoded;
  } on Object {
    throw RevisionRecoveryBundleException(failure);
  }
}

List<RevisionObjectId> _normalizeRoots(List<RevisionObjectId> roots) {
  if (roots.isEmpty) {
    throw ArgumentError.value(
      roots,
      'retainedPublishedRoots',
      'must not be empty',
    );
  }
  final byValue = <String, RevisionObjectId>{
    for (final root in roots) root.value: root,
  };
  final values = byValue.keys.toList()..sort();
  return values.map((value) => byValue[value]!).toList(growable: false);
}

void _requireSha256(String value, String name) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      name,
      'must be a lowercase SHA-256 digest',
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
