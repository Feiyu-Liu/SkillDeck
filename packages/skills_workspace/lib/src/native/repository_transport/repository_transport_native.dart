import 'dart:ffi' as ffi;
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../../application/ports/repository_transport_native_port.dart';
import '../../application/ports/source_transport_native_port.dart';
import '../generated/skills_workspace_bindings_generated.dart' as bindings;

/// Native Asset implementation. No operation runs on the UI isolate.
final class RepositoryTransportNative implements RepositoryTransportNativePort {
  const RepositoryTransportNative({this.allowLoopbackHttpForTesting = false});

  /// Explicit qualification policy; production requires credential-free HTTPS.
  final bool allowLoopbackHttpForTesting;

  @override
  Future<RepositoryTransportOutcome> fetchInto({
    required String repositoryPath,
    required String url,
    required List<String> refspecs,
    required List<String> customHeaders,
    required int cancelFlagAddress,
    int progressBytesAddress = 0,
    SourceTransportProxyMode proxyMode = SourceTransportProxyMode.none,
    String? proxyUrl,
  }) => _transfer(
    push: false,
    repositoryPath: repositoryPath,
    url: url,
    refspecs: refspecs,
    customHeaders: customHeaders,
    cancelFlagAddress: cancelFlagAddress,
    progressBytesAddress: progressBytesAddress,
    proxyMode: proxyMode,
    proxyUrl: proxyUrl,
  );

  @override
  Future<RepositoryTransportOutcome> push({
    required String repositoryPath,
    required String url,
    required List<String> refspecs,
    required List<String> customHeaders,
    required int cancelFlagAddress,
    int progressBytesAddress = 0,
    SourceTransportProxyMode proxyMode = SourceTransportProxyMode.none,
    String? proxyUrl,
  }) => _transfer(
    push: true,
    repositoryPath: repositoryPath,
    url: url,
    refspecs: refspecs,
    customHeaders: customHeaders,
    cancelFlagAddress: cancelFlagAddress,
    progressBytesAddress: progressBytesAddress,
    proxyMode: proxyMode,
    proxyUrl: proxyUrl,
  );

  Future<RepositoryTransportOutcome> _transfer({
    required bool push,
    required String repositoryPath,
    required String url,
    required List<String> refspecs,
    required List<String> customHeaders,
    required int cancelFlagAddress,
    required int progressBytesAddress,
    required SourceTransportProxyMode proxyMode,
    required String? proxyUrl,
  }) {
    // Snapshot mutable caller collections before scheduling the worker.
    final specs = List<String>.of(refspecs);
    final headers = List<String>.of(customHeaders);
    final allowLoopback = allowLoopbackHttpForTesting;
    // Reject embedded NUL rather than passing a silently truncated value to C.
    if ([
          repositoryPath,
          url,
          ?proxyUrl,
          ...specs,
          ...headers,
        ].any((value) => value.contains('\u0000')) ||
        specs.isEmpty ||
        specs.length > 256 ||
        headers.length > 32) {
      return Future.value(
        RepositoryTransportOutcome(
          status: RepositoryTransportStatus.invalidArgument,
          refs: List.filled(
            specs.length,
            RepositoryTransportRefStatus.unreported,
          ),
        ),
      );
    }
    return Isolate.run(
      () => using((arena) {
        final nativeSpecs = arena<ffi.Pointer<ffi.Char>>(specs.length);
        final nativeHeaders = arena<ffi.Pointer<ffi.Char>>(headers.length);
        final headerBuffers = <ffi.Pointer<Utf8>>[];
        final headerLengths = <int>[];
        for (var i = 0; i < specs.length; i++) {
          nativeSpecs[i] = specs[i].toNativeUtf8(allocator: arena).cast();
        }
        for (var i = 0; i < headers.length; i++) {
          final buffer = headers[i].toNativeUtf8(allocator: arena);
          headerBuffers.add(buffer);
          headerLengths.add(buffer.length);
          nativeHeaders[i] = buffer.cast();
        }
        final statuses = arena<ffi.Int32>(specs.length);
        try {
          final invoke = push
              ? bindings.skills_workspace_transport_push
              : bindings.skills_workspace_transport_fetch_into;
          final status = RepositoryTransportStatus.fromNative(
            invoke(
              repositoryPath.toNativeUtf8(allocator: arena).cast(),
              url.toNativeUtf8(allocator: arena).cast(),
              nativeSpecs,
              specs.length,
              nativeHeaders,
              headers.length,
              proxyMode.index,
              proxyUrl == null
                  ? ffi.nullptr
                  : proxyUrl.toNativeUtf8(allocator: arena).cast(),
              ffi.Pointer<ffi.Int32>.fromAddress(cancelFlagAddress),
              allowLoopback ? 1 : 0,
              statuses,
              ffi.Pointer<ffi.Int64>.fromAddress(progressBytesAddress),
            ),
          );
          return RepositoryTransportOutcome(
            status: status,
            refs: [
              for (var i = 0; i < specs.length; i++)
                switch (statuses[i]) {
                  1 => RepositoryTransportRefStatus.accepted,
                  2 => RepositoryTransportRefStatus.rejected,
                  _ => RepositoryTransportRefStatus.unreported,
                },
            ],
          );
        } finally {
          // Dart's immutable input Strings cannot be erased. Explicitly clear
          // the additional native header copies before their arena releases.
          for (var i = 0; i < headerBuffers.length; i++) {
            headerBuffers[i]
                .cast<ffi.Uint8>()
                .asTypedList(headerLengths[i])
                .fillRange(0, headerLengths[i], 0);
          }
        }
      }),
    );
  }
}
