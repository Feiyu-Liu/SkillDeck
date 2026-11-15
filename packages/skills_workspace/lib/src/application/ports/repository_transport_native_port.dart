import 'source_transport_native_port.dart';

/// Safe classes only; native/server diagnostic text never crosses the seam.
enum RepositoryTransportStatus {
  ok,
  invalidArgument,
  runtimeFailure,
  cancelled,
  authenticationRequired,
  certificateFailure,
  tlsFailure,
  networkFailure,
  timedOut,
  refNotFound,
  repositoryFailure,
  objectFailure,
  bufferTooSmall,
  limitExceeded,
  unsupported,
  rejectedRef,
  outcomeUnknown;

  static RepositoryTransportStatus fromNative(int value) =>
      value >= 0 && value < values.length ? values[value] : outcomeUnknown;
}

/// A missing report is never evidence of remote acceptance.
enum RepositoryTransportRefStatus { unreported, accepted, rejected }

/// Results in request order, without remote URLs, headers, or server messages.
final class RepositoryTransportOutcome {
  RepositoryTransportOutcome({
    required this.status,
    required List<RepositoryTransportRefStatus> refs,
  }) : refs = List.unmodifiable(refs);

  final RepositoryTransportStatus status;
  final List<RepositoryTransportRefStatus> refs;
}

/// Private object transport, independent of Source acquisition and lifecycle.
///
/// Only private bare staging/export repositories belong here. This port never
/// selects an Effective Revision. Remote locations and [customHeaders] exist for
/// one operation only; no remote, FETCH_HEAD, credentials, or account identity
/// is persisted. Callers obtain fresh credentials outside Workspace and own
/// retries/reconciliation. Cancellation may leave remote writes and must never
/// be interpreted as a server rollback. Authenticated calls have no system Git
/// fallback. Redirects and implicit credential acquisition are disabled.
///
/// [cancelFlagAddress] points at a caller-owned native int32, freed only after
/// completion. Native progress callbacks observe it independently per call.
/// Optional [progressBytesAddress] points at caller-owned int64 transfer bytes;
/// it follows the same lifetime and may be read while the operation runs.
abstract interface class RepositoryTransportNativePort {
  Future<RepositoryTransportOutcome> fetchInto({
    required String repositoryPath,
    required String url,
    required List<String> refspecs,
    required List<String> customHeaders,
    required int cancelFlagAddress,
    int progressBytesAddress = 0,
    SourceTransportProxyMode proxyMode = SourceTransportProxyMode.none,
    String? proxyUrl,
  });

  Future<RepositoryTransportOutcome> push({
    required String repositoryPath,
    required String url,
    required List<String> refspecs,
    required List<String> customHeaders,
    required int cancelFlagAddress,
    int progressBytesAddress = 0,
    SourceTransportProxyMode proxyMode = SourceTransportProxyMode.none,
    String? proxyUrl,
  });
}
