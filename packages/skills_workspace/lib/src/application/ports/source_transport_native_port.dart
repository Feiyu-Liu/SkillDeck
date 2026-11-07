import 'dart:typed_data';

/// Status classes reported by the native Source transport.
///
/// The values mirror `skills_workspace_transport_status`; no libgit2 message
/// text crosses the boundary.
enum SourceTransportStatus {
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
  unexpected;

  static SourceTransportStatus fromNative(int value) =>
      value >= 0 && value < unexpected.index
      ? SourceTransportStatus.values[value]
      : unexpected;
}

/// How a fetch reaches the network.
enum SourceTransportProxyMode {
  /// Connect directly.
  none,

  /// Honour `https_proxy`, `HTTPS_PROXY`, and `no_proxy` from the environment.
  environment,

  /// Use an explicit proxy URL.
  specified,
}

/// Outcome of a native fetch: the fetched commit on success.
typedef SourceTransportFetchOutcome = ({
  SourceTransportStatus status,
  String? commit,
});

/// Outcome of a native read: the bytes on success.
typedef SourceTransportBytesOutcome = ({
  SourceTransportStatus status,
  Uint8List? bytes,
});

/// Outcome of reading several blobs: one byte buffer per requested object.
typedef SourceTransportBlobsOutcome = ({
  SourceTransportStatus status,
  List<Uint8List>? blobs,
});

/// Native Source transport operations.
///
/// Every operation may block on disk or network, so production calls run on
/// a short-lived background isolate. [cancelFlagAddress] is the address of a
/// caller-owned `int32` that the caller sets to a non-zero value to stop the
/// operation; the caller frees it only after the returned future completes.
abstract interface class SourceTransportNativePort {
  Future<SourceTransportFetchOutcome> fetch({
    required String repositoryPath,
    required String url,
    required String? ref,
    required SourceTransportProxyMode proxyMode,
    required String? proxyUrl,
    required int cancelFlagAddress,
  });

  Future<SourceTransportBytesOutcome> listTree({
    required String repositoryPath,
    required String commit,
    required String subpath,
  });

  /// Reads [objectIds] in order while their total size stays within
  /// [maximumTotalBytes]; returns `limitExceeded` as soon as it would not.
  Future<SourceTransportBlobsOutcome> readBlobs({
    required String repositoryPath,
    required List<String> objectIds,
    required int maximumTotalBytes,
    required int cancelFlagAddress,
  });

  /// The current user's Windows proxy settings as
  /// `proxy TAB bypass TAB auto-config-flag`; `unsupported` elsewhere.
  Future<({SourceTransportStatus status, String? value})> windowsProxy();
}
