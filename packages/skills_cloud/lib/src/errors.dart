/// Stable client failures that never contain remote diagnostics or credentials.
enum CloudErrorCode {
  invalidConfiguration,
  invalidRequest,
  invalidResponse,
  unauthorized,
  unavailable,
  rateLimited,
  timeout,
  cancelled,
  responseTooLarge,
  redirectRejected,
  secureStorage,
  operationInProgress,
  browserLaunch,
  deviceLimit,
  needsReconciliation,
  operationConflict,
  staleBase,
  quotaExceeded,
  resetRequired,
  snapshotExpired,
  protocolVersionUnsupported,
  invalidContent,
  contentManifestRequired,
  contentManifestUnsupported,
  needsReupload,
  unsupportedNormalization,
  nonFastForward,
  publishedHistoryMismatch,
  missingLineage,
  lifecycleMismatch,
  unsupportedSlotMigration,
  metadataConflict,
  dirtyDraftRequired,
  staleSnapshot,
  transferPending,
  transferAlreadyIssued,
}

/// A sanitized failure suitable for presentation without inspecting its cause.
final class CloudException implements Exception {
  /// Creates a failure containing only a stable code and retry classification.
  const CloudException(this.code, {this.retryable = false});

  /// The stable failure category.
  final CloudErrorCode code;

  /// Whether a caller may consider a bounded retry of the same operation.
  final bool retryable;

  @override
  String toString() => 'CloudException(${code.name}, retryable: $retryable)';
}
