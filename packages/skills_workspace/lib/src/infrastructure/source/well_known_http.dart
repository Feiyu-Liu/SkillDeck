import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'source_result.dart';

typedef WellKnownAddressResolver =
    Future<List<InternetAddress>> Function(String host);

final class WellKnownHttpResponse {
  WellKnownHttpResponse({
    required this.uri,
    required this.contentType,
    required List<int> bytes,
  }) : bytes = List<int>.unmodifiable(bytes);

  final Uri uri;
  final String contentType;
  final List<int> bytes;
}

/// A bounded redirect-aware client with SSRF checks on every hop.
final class WellKnownHttpClient {
  WellKnownHttpClient({
    http.Client? client,
    WellKnownAddressResolver? addressResolver,
    this.maximumRedirects = 5,
    this.requestTimeout = const Duration(seconds: 30),
  }) : assert(maximumRedirects >= 0),
       assert(requestTimeout > Duration.zero),
       _client = client,
       _addressResolver = addressResolver ?? InternetAddress.lookup;

  final http.Client? _client;
  final WellKnownAddressResolver _addressResolver;
  final int maximumRedirects;
  final Duration requestTimeout;

  Future<SourceResult<WellKnownHttpResponse>> get(
    Uri initialUri, {
    required int maximumBytes,
    SourceCancellationSignal cancellation = const NoSourceCancellationSignal(),
  }) async {
    if (maximumBytes < 0) {
      throw ArgumentError.value(
        maximumBytes,
        'maximumBytes',
        'must not be negative',
      );
    }
    if (cancellation.isCancelled) {
      return _cancelled();
    }

    var uri = initialUri;
    for (var redirectCount = 0; ; redirectCount += 1) {
      final validation = await _validateDestination(uri);
      final addresses = validation.valueOrNull;
      if (addresses == null) {
        return copySourceFailure<List<InternetAddress>, WellKnownHttpResponse>(
          validation.failureOrNull!,
        );
      }
      if (cancellation.isCancelled) {
        return _cancelled();
      }

      final hopClient = _client ?? _pinnedClient(addresses);
      try {
        http.StreamedResponse response;
        try {
          final request =
              http.AbortableRequest(
                  'GET',
                  uri,
                  abortTrigger: cancellation.whenCancelled,
                )
                ..followRedirects = false
                ..persistentConnection = false;
          response = await hopClient.send(request).timeout(requestTimeout);
        } on http.RequestAbortedException {
          return _cancelled();
        } on TimeoutException {
          return _httpFailure('timeout', uri: uri);
        } on Object {
          if (cancellation.isCancelled) {
            return _cancelled();
          }
          return _httpFailure('transportFailure', uri: uri);
        }

        final contentLength = response.contentLength;
        if (contentLength != null && contentLength > maximumBytes) {
          await _discard(response);
          return _sizeFailure(contentLength, maximumBytes);
        }
        if (_isRedirect(response.statusCode)) {
          await _discard(response);
          if (redirectCount >= maximumRedirects) {
            return _httpFailure('tooManyRedirects');
          }
          final location = response.headers['location'];
          if (location == null || location.trim().isEmpty) {
            return _httpFailure('redirectMissingLocation');
          }
          try {
            uri = uri.resolve(location);
          } on FormatException {
            return SourceFailure<WellKnownHttpResponse>(
              code: SourceFailureCode.rejected,
              context: const <String, Object?>{
                'reason': 'invalidRedirectDestination',
              },
            );
          }
          continue;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          await _discard(response);
          return SourceFailure<WellKnownHttpResponse>(
            code: SourceFailureCode.httpFailure,
            context: <String, Object?>{
              'reason': 'unexpectedStatus',
              'statusCode': response.statusCode,
              'destination': _safeOrigin(uri),
            },
          );
        }

        final builder = BytesBuilder(copy: false);
        var received = 0;
        try {
          await for (final chunk in response.stream.timeout(requestTimeout)) {
            if (cancellation.isCancelled) {
              return _cancelled();
            }
            received += chunk.length;
            if (received > maximumBytes) {
              return _sizeFailure(received, maximumBytes);
            }
            builder.add(chunk);
          }
        } on http.RequestAbortedException {
          return _cancelled();
        } on TimeoutException {
          return _httpFailure('timeout', uri: uri);
        } on Object {
          if (cancellation.isCancelled) {
            return _cancelled();
          }
          return _httpFailure('responseReadFailed', uri: uri);
        }
        return SourceSuccess<WellKnownHttpResponse>(
          value: WellKnownHttpResponse(
            uri: uri,
            contentType: response.headers['content-type'] ?? '',
            bytes: builder.takeBytes(),
          ),
        );
      } finally {
        if (_client == null) {
          hopClient.close();
        }
      }
    }
  }

  Future<SourceResult<List<InternetAddress>>> _validateDestination(
    Uri uri,
  ) async {
    final scheme = uri.scheme.toLowerCase();
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (scheme != 'https' && scheme != 'http')) {
      return SourceFailure<List<InternetAddress>>(
        code: SourceFailureCode.rejected,
        context: const <String, Object?>{
          'reason': 'unsupportedOrCredentialBearingTransport',
        },
      );
    }

    List<InternetAddress> addresses;
    try {
      addresses = await _addressResolver(uri.host);
    } on Object {
      return SourceFailure<List<InternetAddress>>(
        code: SourceFailureCode.unavailable,
        context: const <String, Object?>{
          'reason': 'destinationResolutionFailed',
        },
      );
    }
    if (addresses.isEmpty) {
      return SourceFailure<List<InternetAddress>>(
        code: SourceFailureCode.unavailable,
        context: const <String, Object?>{
          'reason': 'destinationResolutionFailed',
        },
      );
    }

    final allLoopback = addresses.every((address) => address.isLoopback);
    if (scheme == 'http') {
      if (!allLoopback) {
        return SourceFailure<List<InternetAddress>>(
          code: SourceFailureCode.rejected,
          context: const <String, Object?>{
            'reason': 'plainHttpRequiresLoopback',
          },
        );
      }
      return SourceSuccess<List<InternetAddress>>(value: addresses);
    }
    if (addresses.any((address) => !_isPublicAddress(address))) {
      return SourceFailure<List<InternetAddress>>(
        code: SourceFailureCode.rejected,
        context: const <String, Object?>{
          'reason': 'httpsRequiresPublicDestination',
        },
      );
    }
    return SourceSuccess<List<InternetAddress>>(value: addresses);
  }

  http.Client _pinnedClient(List<InternetAddress> addresses) {
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = requestTimeout;
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final rawTask = await Socket.startConnect(addresses.first, port);
      Socket? connected;
      final socket = rawTask.socket.then<Socket>((rawSocket) async {
        connected = rawSocket;
        if (uri.scheme != 'https') {
          return rawSocket;
        }
        final secure = await SecureSocket.secure(rawSocket, host: uri.host);
        connected = secure;
        return secure;
      });
      return ConnectionTask.fromSocket<Socket>(socket, () {
        rawTask.cancel();
        connected?.destroy();
      });
    };
    return IOClient(client);
  }
}

SourceFailure<WellKnownHttpResponse> _cancelled() =>
    SourceFailure<WellKnownHttpResponse>(code: SourceFailureCode.cancelled);

SourceFailure<WellKnownHttpResponse> _httpFailure(String reason, {Uri? uri}) =>
    SourceFailure<WellKnownHttpResponse>(
      code: SourceFailureCode.httpFailure,
      context: <String, Object?>{
        'reason': reason,
        if (uri != null) 'destination': _safeOrigin(uri),
      },
    );

SourceFailure<WellKnownHttpResponse> _sizeFailure(int actual, int maximum) =>
    SourceFailure<WellKnownHttpResponse>(
      code: SourceFailureCode.contentLimitExceeded,
      context: <String, Object?>{
        'limit': 'downloadByteSize',
        'actual': actual,
        'maximum': maximum,
      },
    );

bool _isRedirect(int statusCode) =>
    statusCode == 301 ||
    statusCode == 302 ||
    statusCode == 303 ||
    statusCode == 307 ||
    statusCode == 308;

Future<void> _discard(http.StreamedResponse response) async {
  final subscription = response.stream.listen(null);
  await subscription.cancel();
}

String _safeOrigin(Uri uri) {
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}

bool _isPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 4) {
    return _isPublicIpv4(bytes);
  }
  if (bytes.length != 16) {
    return false;
  }
  if (_isIpv4Mapped(bytes)) {
    return _isPublicIpv4(bytes.sublist(12));
  }

  final first = bytes[0];
  final second = bytes[1];
  if (bytes.every((byte) => byte == 0) ||
      address.isLoopback ||
      first & 0xe0 != 0x20 ||
      first & 0xfe == 0xfc ||
      (first == 0xfe && second & 0xc0 == 0x80) ||
      first == 0xff ||
      _matchesPrefix(bytes, const <int>[0x20, 0x01, 0x00], 23) ||
      _matchesPrefix(bytes, const <int>[0x20, 0x01, 0x0d, 0xb8], 32) ||
      _matchesPrefix(bytes, const <int>[0x20, 0x02], 16) ||
      _matchesPrefix(bytes, const <int>[0x3f, 0xff, 0x00], 20)) {
    return false;
  }
  return true;
}

bool _isPublicIpv4(List<int> bytes) {
  final first = bytes[0];
  final second = bytes[1];
  final third = bytes[2];
  return !(first == 0 ||
      first == 10 ||
      first == 127 ||
      first >= 224 ||
      (first == 100 && second >= 64 && second <= 127) ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 0 && third == 0) ||
      (first == 192 && second == 0 && third == 2) ||
      (first == 192 && second == 88 && third == 99) ||
      (first == 192 && second == 168) ||
      (first == 198 && (second == 18 || second == 19)) ||
      (first == 198 && second == 51 && third == 100) ||
      (first == 203 && second == 0 && third == 113));
}

bool _isIpv4Mapped(List<int> bytes) {
  for (var index = 0; index < 10; index += 1) {
    if (bytes[index] != 0) {
      return false;
    }
  }
  return bytes[10] == 0xff && bytes[11] == 0xff;
}

bool _matchesPrefix(List<int> bytes, List<int> prefix, int prefixLength) {
  final wholeBytes = prefixLength ~/ 8;
  for (var index = 0; index < wholeBytes; index += 1) {
    if (bytes[index] != prefix[index]) {
      return false;
    }
  }
  final remainingBits = prefixLength % 8;
  if (remainingBits == 0) {
    return true;
  }
  final mask = 0xff << (8 - remainingBits) & 0xff;
  return (bytes[wholeBytes] & mask) == (prefix[wholeBytes] & mask);
}
