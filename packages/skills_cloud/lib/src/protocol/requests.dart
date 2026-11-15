import '../errors.dart';
import 'codec.dart';
import 'content_manifest.dart';

/// A first upload preserving the complete versioned content manifest.
final class CloudPrepareRequest {
  CloudPrepareRequest({
    required this.operationId,
    required this.contentManifest,
    this.replacement,
  }) {
    identifier(operationId);
  }
  final String operationId;
  final CloudContentManifest contentManifest;
  final CloudReplacementTarget? replacement;
  Map<String, Object?> toJson() => {
    'contentManifestVersion': 1,
    'operationId': operationId,
    'contentManifest': contentManifest.toJson(),
    if (replacement != null) 'replacement': replacement!.toJson(),
  };
  @override
  String toString() => 'CloudPrepareRequest([redacted intent and content])';
}

/// A manifest-backed commit with mutually exclusive first/existing identities.
final class CloudCommitRequest {
  CloudCommitRequest._(
    this.operationId,
    this.contentManifest,
    this.uploadId,
    this.lineageId,
    this.generation,
    this.baseCommitId,
  );
  factory CloudCommitRequest.firstUpload({
    required String operationId,
    required String uploadId,
    required CloudContentManifest contentManifest,
  }) {
    identifier(operationId);
    identifier(uploadId);
    return CloudCommitRequest._(
      operationId,
      contentManifest,
      uploadId,
      null,
      null,
      null,
    );
  }
  factory CloudCommitRequest.existing({
    required String operationId,
    required String lineageId,
    required int generation,
    required String baseCommitId,
    required CloudContentManifest contentManifest,
  }) {
    identifier(operationId);
    identifier(lineageId);
    integer(generation, minimum: 1);
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(baseCommitId)) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    return CloudCommitRequest._(
      operationId,
      contentManifest,
      null,
      lineageId,
      generation,
      baseCommitId,
    );
  }
  final String operationId;
  final CloudContentManifest contentManifest;
  final String? uploadId, lineageId, baseCommitId;
  final int? generation;
  Map<String, Object?> toJson() => {
    'contentManifestVersion': 1,
    'operationId': operationId,
    'contentManifest': contentManifest.toJson(),
    if (uploadId != null)
      'uploadId': uploadId
    else ...{
      'lineageId': lineageId,
      'generation': generation,
    },
    'baseCommitId': baseCommitId,
  };
  @override
  String toString() => 'CloudCommitRequest([redacted intent])';
}

/// A prepared upload handle whose original expiry never extends on retry.
final class CloudPreparedUpload {
  CloudPreparedUpload.fromJson(Map<String, Object?> json)
    : uploadId = identifier(json['uploadId']),
      state = text(json['state'], maximum: 16),
      expiresAt = timestamp(json['expiresAt']) {
    if (!['requested', 'ready', 'committed'].contains(state)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }
  final String uploadId, state;
  final DateTime expiresAt;
  @override
  String toString() => 'CloudPreparedUpload(state: $state, [redacted])';
}

/// The immutable prior generation guarded by replacement admission.
final class CloudReplacementTarget {
  CloudReplacementTarget({
    required this.lineageId,
    required this.generation,
    required this.baseCommitId,
  }) {
    identifier(lineageId);
    integer(generation, minimum: 1);
    if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(baseCommitId)) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
  }
  final String lineageId, baseCommitId;
  final int generation;
  Map<String, Object?> toJson() => {
    'lineageId': lineageId,
    'generation': generation,
    'baseCommitId': baseCommitId,
  };
}

/// Finalizes a previously prepared new source generation under the same operation.
final class CloudReplacementRequest {
  CloudReplacementRequest({
    required this.operationId,
    required this.uploadId,
    required this.previous,
    required this.contentManifest,
  }) {
    identifier(operationId);
    identifier(uploadId);
  }
  final String operationId, uploadId;
  final CloudReplacementTarget previous;
  final CloudContentManifest contentManifest;
  Map<String, Object?> toJson() => {
    'kind': 'replacement',
    'contentManifestVersion': 1,
    'operationId': operationId,
    'uploadId': uploadId,
    ...previous.toJson(),
    'contentManifest': contentManifest.toJson(),
  };
}

/// Repairs retained selected roots without adding a new published event.
final class CloudRepairRequest {
  CloudRepairRequest({
    required this.operationId,
    required this.target,
    required this.contentManifest,
  }) {
    identifier(operationId);
  }
  final String operationId;
  final CloudReplacementTarget target;
  final CloudContentManifest contentManifest;
  Map<String, Object?> toJson() => {
    'kind': 'repair',
    'contentManifestVersion': 1,
    'operationId': operationId,
    ...target.toJson(),
    'contentManifest': contentManifest.toJson(),
  };
}
