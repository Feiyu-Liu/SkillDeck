import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../../application/ports/source_transport_native_port.dart';
import '../generated/skills_workspace_bindings_generated.dart' as bindings;

/// The production port backed by the package's Native Asset.
final class SourceTransportNative implements SourceTransportNativePort {
  const SourceTransportNative();

  @override
  Future<SourceTransportFetchOutcome> fetch({
    required String repositoryPath,
    required String url,
    required String? ref,
    required SourceTransportProxyMode proxyMode,
    required String? proxyUrl,
    required int cancelFlagAddress,
  }) => Isolate.run(
    () => _fetch(
      repositoryPath: repositoryPath,
      url: url,
      ref: ref,
      proxyMode: proxyMode,
      proxyUrl: proxyUrl,
      cancelFlagAddress: cancelFlagAddress,
    ),
  );

  @override
  Future<SourceTransportBytesOutcome> listTree({
    required String repositoryPath,
    required String commit,
    required String subpath,
  }) => Isolate.run(
    () => _listTree(
      repositoryPath: repositoryPath,
      commit: commit,
      subpath: subpath,
    ),
  );

  @override
  Future<SourceTransportBlobsOutcome> readBlobs({
    required String repositoryPath,
    required List<String> objectIds,
    required int maximumTotalBytes,
    required int cancelFlagAddress,
  }) {
    final ids = List<String>.of(objectIds);
    return Isolate.run(
      () => _readBlobs(
        repositoryPath: repositoryPath,
        objectIds: ids,
        maximumTotalBytes: maximumTotalBytes,
        cancelFlagAddress: cancelFlagAddress,
      ),
    );
  }

  @override
  Future<({SourceTransportStatus status, String? value})> windowsProxy() =>
      Isolate.run(_windowsProxy);
}

SourceTransportFetchOutcome _fetch({
  required String repositoryPath,
  required String url,
  required String? ref,
  required SourceTransportProxyMode proxyMode,
  required String? proxyUrl,
  required int cancelFlagAddress,
}) => using((arena) {
  const capacity = 65;
  final output = arena<ffi.Char>(capacity);
  final status = SourceTransportStatus.fromNative(
    bindings.skills_workspace_transport_fetch(
      repositoryPath.toNativeUtf8(allocator: arena).cast(),
      url.toNativeUtf8(allocator: arena).cast(),
      ref == null ? ffi.nullptr : ref.toNativeUtf8(allocator: arena).cast(),
      proxyMode.index,
      proxyUrl == null
          ? ffi.nullptr
          : proxyUrl.toNativeUtf8(allocator: arena).cast(),
      ffi.Pointer<ffi.Int32>.fromAddress(cancelFlagAddress),
      output,
      capacity,
    ),
  );
  return (
    status: status,
    commit: status == SourceTransportStatus.ok
        ? output.cast<Utf8>().toDartString()
        : null,
  );
});

SourceTransportBytesOutcome _listTree({
  required String repositoryPath,
  required String commit,
  required String subpath,
}) => using((arena) {
  final repository = repositoryPath
      .toNativeUtf8(allocator: arena)
      .cast<ffi.Char>();
  final object = commit.toNativeUtf8(allocator: arena).cast<ffi.Char>();
  final selection = subpath.toNativeUtf8(allocator: arena).cast<ffi.Char>();
  return _readVariable(
    arena,
    (output, capacity, required) =>
        bindings.skills_workspace_transport_tree_list(
          repository,
          object,
          selection,
          output,
          capacity,
          required,
        ),
  );
});

SourceTransportBlobsOutcome _readBlobs({
  required String repositoryPath,
  required List<String> objectIds,
  required int maximumTotalBytes,
  required int cancelFlagAddress,
}) => using((arena) {
  final cancelFlag = ffi.Pointer<ffi.Int32>.fromAddress(cancelFlagAddress);
  final repository = repositoryPath
      .toNativeUtf8(allocator: arena)
      .cast<ffi.Char>();
  final blobs = <Uint8List>[];
  var remaining = maximumTotalBytes;
  for (final objectId in objectIds) {
    if (cancelFlag.value != 0) {
      return (status: SourceTransportStatus.cancelled, blobs: null);
    }
    // A nested arena releases each native copy before the next blob.
    final budget = remaining;
    final outcome = using((blobArena) {
      final object = objectId
          .toNativeUtf8(allocator: blobArena)
          .cast<ffi.Char>();
      return _readVariable(
        blobArena,
        (output, capacity, required) =>
            bindings.skills_workspace_transport_blob_read(
              repository,
              object,
              budget,
              output,
              capacity,
              required,
            ),
      );
    });
    if (outcome.status != SourceTransportStatus.ok) {
      return (status: outcome.status, blobs: null);
    }
    remaining -= outcome.bytes!.length;
    blobs.add(outcome.bytes!);
  }
  return (status: SourceTransportStatus.ok, blobs: blobs);
});

({SourceTransportStatus status, String? value}) _windowsProxy() =>
    using((arena) {
      final outcome = _readVariable(
        arena,
        bindings.skills_workspace_transport_windows_proxy,
      );
      return (
        status: outcome.status,
        value: outcome.bytes == null
            ? null
            : utf8.decode(outcome.bytes!, allowMalformed: false),
      );
    });

SourceTransportBytesOutcome _readVariable(
  Arena arena,
  int Function(
    ffi.Pointer<ffi.Uint8> output,
    int capacity,
    ffi.Pointer<ffi.IntPtr> required,
  )
  invoke,
) {
  final required = arena<ffi.IntPtr>();
  final first = SourceTransportStatus.fromNative(
    invoke(ffi.nullptr, 0, required),
  );
  if (first == SourceTransportStatus.ok) {
    return (status: first, bytes: Uint8List(0));
  }
  if (first != SourceTransportStatus.bufferTooSmall || required.value <= 0) {
    return (status: first, bytes: null);
  }
  final length = required.value;
  final output = arena<ffi.Uint8>(length);
  final second = SourceTransportStatus.fromNative(
    invoke(output, length, required),
  );
  if (second != SourceTransportStatus.ok) {
    return (status: second, bytes: null);
  }
  return (
    status: second,
    bytes: Uint8List.fromList(output.asTypedList(length)),
  );
}
