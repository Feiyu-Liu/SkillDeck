import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../application/ports/repository_transport_native_port.dart';

/// Narrow Git smart-HTTP download (v2 exact ref-prefix, bounded v0 fallback). PACK bytes reach a bounded owned file
/// before any libgit2 object/index reader can allocate from remote size fields.
/// No checkout, system Git, redirects, implicit auth, or raw server diagnostics.
final class BoundedGitPackFetcher {
  // Dart may complete a timed-out connection late. Keep its slot until that
  // actual future settles, so repeated retries cannot accumulate open work.
  static int _pendingOpens = 0;
  const BoundedGitPackFetcher({
    this.createClient,
    this.connectTimeout = const Duration(seconds: 30),
    this.overallDeadline = const Duration(minutes: 2),
  });
  final HttpClient Function()? createClient;
  final Duration connectTimeout, overallDeadline;

  Future<void> fetch({
    required String remote,
    required List<String> roots,
    required List<String> headers,
    required String outputPath,
    required bool allowLoopbackHttpForTesting,
    required bool Function() isCancelled,
    int maximumPackBytes = 64 * 1024 * 1024,
  }) async {
    final uri = Uri.tryParse(remote);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        remote.contains('\\') ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(remote) ||
        !(uri.scheme == 'https' ||
            allowLoopbackHttpForTesting &&
                uri.scheme == 'http' &&
                uri.host == '127.0.0.1' &&
                uri.hasPort)) {
      throw const BoundedGitFetchFailure(
        RepositoryTransportStatus.invalidArgument,
      );
    }
    if (roots.isEmpty ||
        roots.length > 256 ||
        roots.any(
          (root) =>
              root.length != 40 || !RegExp(r'^[0-9a-f]{40}$').hasMatch(root),
        )) {
      throw const BoundedGitFetchFailure(
        RepositoryTransportStatus.invalidArgument,
      );
    }
    final client = (createClient?.call() ?? HttpClient())
      ..connectionTimeout = connectTimeout
      ..idleTimeout = const Duration(seconds: 60)
      ..autoUncompress = false;
    var deadlineExpired = false;
    var operationFinished = false;
    final deadline = Timer(overallDeadline, () {
      deadlineExpired = true;
      client.close(force: true);
    });
    final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (isCancelled()) client.close(force: true);
    });
    try {
      if (isCancelled()) {
        throw const BoundedGitFetchFailure(RepositoryTransportStatus.cancelled);
      }
      Future<HttpClientResponse> request(
        Uri endpoint, {
        List<int>? body,
      }) async {
        var abandoned = false;
        if (_pendingOpens >= 4) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.runtimeFailure,
          );
        }
        _pendingOpens++;
        final creating = body == null
            ? client.getUrl(endpoint)
            : client.postUrl(endpoint);
        unawaited(
          creating.then(
            (_) {
              _pendingOpens--;
            },
            onError: (_) {
              _pendingOpens--;
            },
          ),
        );
        unawaited(
          creating.then((lateRequest) {
            if (abandoned ||
                deadlineExpired ||
                operationFinished ||
                isCancelled()) {
              lateRequest.abort();
            }
          }, onError: (_) {}),
        );
        final request = await creating.timeout(
          connectTimeout,
          onTimeout: () {
            abandoned = true;
            client.close(force: true);
            throw TimeoutException('Git connection deadline');
          },
        );
        if (deadlineExpired || isCancelled()) {
          request.abort();
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.cancelled,
          );
        }
        request.headers.set('Git-Protocol', 'version=2');
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, 'SkillDeck');
        if (headers.length > 32 ||
            headers.fold<int>(0, (count, header) => count + header.length) >
                65536) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.invalidArgument,
          );
        }
        for (final header in headers) {
          final colon = header.indexOf(':');
          if (colon <= 0 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(header)) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.invalidArgument,
            );
          }
          final name = header.substring(0, colon);
          if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$").hasMatch(name) ||
              {
                'host',
                'content-length',
                'transfer-encoding',
                'connection',
                'git-protocol',
              }.contains(name.toLowerCase())) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.invalidArgument,
            );
          }
          request.headers.set(name, header.substring(colon + 1).trim());
        }
        if (body != null) {
          request.headers.contentType = ContentType(
            'application',
            'x-git-upload-pack-request',
          );
          request.contentLength = body.length;
          request.add(body);
        }
        final response = await request.close().timeout(
          const Duration(seconds: 60),
        );
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.authenticationRequired,
          );
        }
        if (response.statusCode != 200) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.networkFailure,
          );
        }
        final expectedType = body == null
            ? 'application/x-git-upload-pack-advertisement'
            : 'application/x-git-upload-pack-result';
        if (response.headers.contentType?.mimeType != expectedType) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.networkFailure,
          );
        }
        return response;
      }

      final base = remote.endsWith('/')
          ? remote.substring(0, remote.length - 1)
          : remote;
      final discovery = await request(
        Uri.parse('$base/info/refs?service=git-upload-pack'),
      );
      final discoveryBuffer = Uint8List(1024 * 1024);
      var discoveryLength = 0;
      await for (final chunk in discovery.timeout(
        const Duration(seconds: 60),
      )) {
        if (isCancelled()) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.cancelled,
          );
        }
        if (chunk.length > discoveryBuffer.length - discoveryLength) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.limitExceeded,
          );
        }
        discoveryBuffer.setRange(
          discoveryLength,
          discoveryLength + chunk.length,
          chunk,
        );
        discoveryLength += chunk.length;
      }
      final advertised = <String, String>{};
      final capabilities = <String>{};
      var version2 = false;
      void rememberRef(String name, String oid) {
        final previous = advertised[name];
        if (previous != null && previous != oid) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.networkFailure,
          );
        }
        advertised[name] = oid;
      }

      final discoveryPackets = _PktDecoder((packet) {
        final text = ascii.decode(packet, allowInvalid: true);
        if (text.startsWith('#')) return;
        if (text == 'version 2\n') {
          version2 = true;
          return;
        }
        if (version2) {
          if (text.startsWith('object-format=') &&
              text.trim() != 'object-format=sha1') {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.unsupported,
            );
          }
          capabilities.add(text.trim().split('=').first);
          return;
        }
        final fields = text.split('\u0000');
        final line = fields.first.trimRight();
        if (fields.length == 2) {
          capabilities.addAll(fields[1].trim().split(' '));
        }
        final space = line.indexOf(' ');
        if (space != 40) return;
        rememberRef(line.substring(space + 1), line.substring(0, space));
      });
      discoveryPackets.add(
        Uint8List.sublistView(discoveryBuffer, 0, discoveryLength),
      );
      discoveryPackets.finish();
      if (version2) {
        if (!capabilities.contains('ls-refs') ||
            !capabilities.contains('fetch')) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.unsupported,
          );
        }
        final command = BytesBuilder()
          ..add(_pkt('command=ls-refs\n'))
          ..add(ascii.encode('0001'));
        for (final oid in roots) {
          command.add(_pkt('ref-prefix refs/skilldeck/commits/$oid\n'));
        }
        command.add(ascii.encode('0000'));
        final listing = await request(
          Uri.parse('$base/git-upload-pack'),
          body: command.takeBytes(),
        );
        var listingBytes = 0;
        final parsed = _PktDecoder((packet) {
          final fields = ascii
              .decode(packet, allowInvalid: true)
              .trimRight()
              .split(' ');
          if (fields.length < 2 || fields[0].length != 40) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.networkFailure,
            );
          }
          rememberRef(fields[1], fields[0]);
        });
        await for (final chunk in listing.timeout(
          const Duration(seconds: 60),
        )) {
          if (deadlineExpired || isCancelled()) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.cancelled,
            );
          }
          listingBytes += chunk.length;
          if (listingBytes > 1024 * 1024) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.limitExceeded,
            );
          }
          parsed.add(chunk);
        }
        parsed.finish();
      } else if (!capabilities.contains('side-band-64k')) {
        throw const BoundedGitFetchFailure(
          RepositoryTransportStatus.unsupported,
        );
      }
      for (final oid in roots) {
        if (advertised['refs/skilldeck/commits/$oid'] != oid) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.refNotFound,
          );
        }
      }
      final body = BytesBuilder();
      if (version2) {
        body.add(_pkt('command=fetch\n'));
        body.add(ascii.encode('0001'));
        body.add(_pkt('no-progress\n'));
        body.add(_pkt('ofs-delta\n'));
        for (final oid in roots) {
          body.add(_pkt('want $oid\n'));
        }
        body.add(_pkt('done\n'));
        body.add(ascii.encode('0000'));
      } else {
        for (var i = 0; i < roots.length; i++) {
          body.add(
            _pkt(
              'want ${roots[i]}${i == 0 ? ' side-band-64k ofs-delta' : ''}\n',
            ),
          );
        }
        body.add(ascii.encode('0000'));
        body.add(_pkt('done\n'));
      }
      final response = await request(
        Uri.parse('$base/git-upload-pack'),
        body: body.takeBytes(),
      );
      final file = await File(outputPath).open(mode: FileMode.writeOnly);
      var written = 0;
      var first = true;
      final prefix = <int>[];
      final pending = <Uint8List>[];
      final packets = _PktDecoder(
        (packet) {
          if (first &&
              (ascii.decode(packet, allowInvalid: true).startsWith('NAK') ||
                  version2 &&
                      ascii.decode(packet, allowInvalid: true) ==
                          'packfile\n')) {
            first = false;
            return;
          }
          first = false;
          if (packet.isEmpty) return;
          if (packet[0] == 3) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.networkFailure,
            );
          }
          if (packet[0] == 2) {
            return; // Progress text never crosses the boundary.
          }
          if (packet[0] != 1) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.networkFailure,
            );
          }
          final payload = Uint8List.sublistView(packet, 1);
          if (payload.length > maximumPackBytes - written) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.limitExceeded,
            );
          }
          written += payload.length;
          for (final byte in payload.take(4 - prefix.length)) {
            prefix.add(byte);
          }
          pending.add(Uint8List.fromList(payload));
        },
        maximumWireBytes: maximumPackBytes + 8 * 1024 * 1024,
        maximumPackets: 100000,
      );
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          if (isCancelled()) {
            throw const BoundedGitFetchFailure(
              RepositoryTransportStatus.cancelled,
            );
          }
          // Bound one incoming event before pkt decoding; do not buffer an
          // arbitrary peer-controlled response while waiting for a packet.
          final chunkBytes = chunk is Uint8List
              ? chunk
              : Uint8List.fromList(chunk);
          for (var offset = 0; offset < chunk.length; offset += 32768) {
            packets.add(
              Uint8List.sublistView(
                chunkBytes,
                offset,
                offset + 32768 < chunk.length ? offset + 32768 : chunk.length,
              ),
            );
            for (final payload in pending) {
              await file.writeFrom(payload);
            }
            pending.clear();
          }
        }
        packets.finish();
        if (prefix.length != 4 ||
            ascii.decode(prefix) != 'PACK' ||
            written < 32) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.networkFailure,
          );
        }
        await file.flush();
      } finally {
        await file.close();
      }
    } on BoundedGitFetchFailure {
      rethrow;
    } on TimeoutException {
      throw const BoundedGitFetchFailure(RepositoryTransportStatus.timedOut);
    } on HandshakeException {
      throw const BoundedGitFetchFailure(
        RepositoryTransportStatus.certificateFailure,
      );
    } on Object {
      throw BoundedGitFetchFailure(
        deadlineExpired
            ? RepositoryTransportStatus.timedOut
            : isCancelled()
            ? RepositoryTransportStatus.cancelled
            : RepositoryTransportStatus.networkFailure,
      );
    } finally {
      operationFinished = true;
      timer.cancel();
      deadline.cancel();
      client.close(force: true);
    }
  }
}

final class BoundedGitFetchFailure implements Exception {
  const BoundedGitFetchFailure(this.status);
  final RepositoryTransportStatus status;
}

List<int> _pkt(String line) {
  final bytes = ascii.encode(line);
  return [
    ...ascii.encode((bytes.length + 4).toRadixString(16).padLeft(4, '0')),
    ...bytes,
  ];
}

final class _PktDecoder {
  _PktDecoder(
    this.onPacket, {
    this.maximumWireBytes = 1024 * 1024,
    this.maximumPackets = 20000,
  });
  final int maximumWireBytes, maximumPackets;
  int _wireBytes = 0, _packets = 0;
  final void Function(Uint8List) onPacket;
  final _buffer = <int>[];
  void add(List<int> bytes) {
    _wireBytes += bytes.length;
    if (_wireBytes > maximumWireBytes) {
      throw const BoundedGitFetchFailure(
        RepositoryTransportStatus.limitExceeded,
      );
    }
    _buffer.addAll(bytes);
    var offset = 0;
    while (_buffer.length - offset >= 4) {
      final header = ascii.decode(
        _buffer.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      if (!RegExp(r'^[0-9a-fA-F]{4}$').hasMatch(header)) {
        throw const BoundedGitFetchFailure(
          RepositoryTransportStatus.networkFailure,
        );
      }
      final size = int.parse(header, radix: 16);
      if (size == 0 || size == 1 || size == 2) {
        if (++_packets > maximumPackets) {
          throw const BoundedGitFetchFailure(
            RepositoryTransportStatus.limitExceeded,
          );
        }
        offset += 4;
        continue;
      }
      if (size < 4 || size > 65520) {
        throw const BoundedGitFetchFailure(
          RepositoryTransportStatus.limitExceeded,
        );
      }
      if (_buffer.length - offset < size) break;
      if (++_packets > maximumPackets) {
        throw const BoundedGitFetchFailure(
          RepositoryTransportStatus.limitExceeded,
        );
      }
      onPacket(Uint8List.fromList(_buffer.sublist(offset + 4, offset + size)));
      offset += size;
    }
    if (offset > 0) _buffer.removeRange(0, offset);
    if (_buffer.length > 65520) {
      throw const BoundedGitFetchFailure(
        RepositoryTransportStatus.limitExceeded,
      );
    }
  }

  void finish() {
    if (_buffer.isNotEmpty) {
      throw const BoundedGitFetchFailure(
        RepositoryTransportStatus.networkFailure,
      );
    }
  }
}
