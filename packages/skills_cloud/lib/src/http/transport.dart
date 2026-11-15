import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../cancellation.dart';
import '../errors.dart';

/// A credential whose text representation is always redacted.
final class CloudCredential {
  /// Creates an in-memory credential for trusted transport or secure storage.
  CloudCredential(this.token) {
    if (token.isEmpty || token.length > 4096 || RegExp(r'\s').hasMatch(token)) {
      throw const CloudException(CloudErrorCode.invalidResponse);
    }
  }

  /// The secret value, used only by transport and secure-storage adapters.
  final String token;

  @override
  String toString() => 'CloudCredential([redacted])';
}

/// An immutable, same-origin JSON request with no caller-selected auth headers.
final class CloudRequest {
  /// Creates a request to a relative API path.
  CloudRequest({
    required this.method,
    required this.path,
    Map<String, String> query = const {},
    Map<String, Object?>? body,
  }) : query = Map.unmodifiable(query),
       body = body == null ? null : freezeMap(body) {
    if (!['GET', 'POST'].contains(method) ||
        !path.startsWith('/v1/') ||
        path.contains(RegExp(r'[\\?#\x00-\x20]')) ||
        path.split('/').any((part) => part == '.' || part == '..') ||
        (method == 'GET' && body != null)) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
  }

  /// The HTTP method.
  final String method;

  /// The API path relative to the configured origin.
  final String path;

  /// The encoded query parameters.
  final Map<String, String> query;

  /// The immutable JSON body.
  final Map<String, Object?>? body;

  @override
  String toString() => 'CloudRequest($method, [redacted path/body])';
}

/// A bounded JSON response containing only a status and parsed object.
final class CloudResponse {
  /// Creates a response from already bounded UTF-8 JSON.
  CloudResponse({required this.statusCode, required Map<String, Object?> body})
    : body = freezeMap(body);

  /// The HTTP status.
  final int statusCode;

  /// The immutable decoded body, never included in [toString].
  final Map<String, Object?> body;
  @override
  String toString() => 'CloudResponse(status: $statusCode, [redacted body])';
}

/// The HTTPS boundary, replaceable only through trusted application composition.
abstract interface class CloudTransport {
  /// The trusted service origin.
  Uri get baseUri;

  /// Sends one request without automatic retries or redirects.
  Future<CloudResponse> request(
    CloudRequest request, {
    CloudCredential? credential,
    CloudCancellation? cancellation,
  });

  /// Closes owned connections and rejects future requests.
  void close();
}

/// An IO transport that requires HTTPS and never follows redirects.
final class HttpsCloudTransport implements CloudTransport {
  /// Creates a transport with byte budgets and a complete request deadline.
  ///
  /// An optional [_securityContext] trusts an explicit CA set, while preserving
  /// TLS certificate and hostname verification. No insecure HTTP mode exists.
  HttpsCloudTransport({
    required this.baseUri,
    this.timeout = const Duration(seconds: 30),
    this.maximumResponseBytes = 1024 * 1024,
    this.maximumRequestBytes = 64 * 1024,
    this._securityContext,
  }) {
    if (baseUri.scheme != 'https' ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        !['', '/'].contains(baseUri.path) ||
        timeout <= Duration.zero ||
        maximumResponseBytes <= 0 ||
        maximumRequestBytes <= 0) {
      throw const CloudException(CloudErrorCode.invalidConfiguration);
    }
  }
  @override
  final Uri baseUri;

  /// The complete request deadline, including body consumption.
  final Duration timeout;

  /// The maximum encoded response bytes accepted before decoding.
  final int maximumResponseBytes;

  /// The maximum encoded JSON request bytes.
  final int maximumRequestBytes;
  final SecurityContext? _securityContext;
  final Set<HttpClient> _clients = {};
  // Dart 3.14 cannot physically cancel every TCP-complete/TLS-pending open.
  // Retain slots until the real opening future finishes, across instances.
  static final Set<Future<HttpClientRequest>> _pendingOpenings = {};
  static const _maximumPendingOpenings = 4;
  bool _closed = false;

  @override
  Future<CloudResponse> request(
    CloudRequest request, {
    CloudCredential? credential,
    CloudCancellation? cancellation,
  }) async {
    if (_closed) throw const CloudException(CloudErrorCode.cancelled);
    cancellation?.throwIfCancelled();
    if (_pendingOpenings.length >= _maximumPendingOpenings) {
      throw const CloudException(CloudErrorCode.unavailable);
    }
    final uri = baseUri
        .resolve(request.path)
        .replace(queryParameters: request.query.isEmpty ? null : request.query);
    if (uri.origin != baseUri.origin ||
        uri.userInfo.isNotEmpty ||
        uri.scheme != 'https') {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    final encoded = request.body == null
        ? null
        : utf8.encode(jsonEncode(request.body));
    if (encoded != null && encoded.length > maximumRequestBytes) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    // A client per request permits force-closing a still-pending TCP/TLS open
    // without cancelling another operation or leaving a late handle behind.
    final client = HttpClient(context: _securityContext);
    _clients.add(client);
    HttpClientRequest? pending;
    StreamIterator<List<int>>? iterator;
    final stopped = Completer<void>();
    var expired = false, finished = false;
    void stop() {
      pending?.abort();
      client.close(force: true);
      if (!stopped.isCompleted) stopped.complete();
    }

    final timer = Timer(timeout, () {
      expired = true;
      stop();
    });
    final unlisten = cancellation?.listen(stop);
    Future<T> wait<T>(Future<T> work) => Future.any([
      work,
      stopped.future.then<T>((_) {
        if (expired) {
          throw const CloudException(CloudErrorCode.timeout, retryable: true);
        }
        throw const CloudException(CloudErrorCode.cancelled);
      }),
    ]);
    try {
      final opening = client.openUrl(request.method, uri).then((opened) {
        if (finished ||
            expired ||
            _closed ||
            (cancellation?.isCancelled ?? false)) {
          opened.abort();
        }
        return opened;
      });
      _pendingOpenings.add(opening);
      unawaited(
        opening.then<void>(
          (_) {
            _pendingOpenings.remove(opening);
          },
          onError: (Object _) {
            _pendingOpenings.remove(opening);
          },
        ),
      );
      final active = await wait(opening);
      pending = active;
      cancellation?.throwIfCancelled();
      active.followRedirects = false;
      active.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (credential != null) {
        active.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer ${credential.token}',
        );
      }
      if (encoded != null) {
        active.headers.contentType = ContentType.json;
        active.add(encoded);
      }
      final response = await wait(active.close());
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const CloudException(CloudErrorCode.redirectRejected);
      }
      if (response.contentLength > maximumResponseBytes) {
        throw const CloudException(CloudErrorCode.responseTooLarge);
      }
      final bytes = <int>[];
      iterator = StreamIterator(response);
      while (await wait(iterator.moveNext())) {
        final chunk = iterator.current;
        if (bytes.length + chunk.length > maximumResponseBytes) {
          throw const CloudException(CloudErrorCode.responseTooLarge);
        }
        bytes.addAll(chunk);
      }
      if (expired) {
        throw const CloudException(CloudErrorCode.timeout, retryable: true);
      }
      cancellation?.throwIfCancelled();
      final Object? json;
      try {
        json = jsonDecode(utf8.decode(bytes));
      } on FormatException {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      if (json is! Map<String, Object?>) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      return CloudResponse(statusCode: response.statusCode, body: json);
    } on CloudException {
      rethrow;
    } catch (_) {
      if (_closed || (cancellation?.isCancelled ?? false)) {
        throw const CloudException(CloudErrorCode.cancelled);
      }
      if (expired) {
        throw const CloudException(CloudErrorCode.timeout, retryable: true);
      }
      throw const CloudException(CloudErrorCode.unavailable, retryable: true);
    } finally {
      finished = true;
      timer.cancel();
      unlisten?.call();
      stop();
      try {
        await iterator?.cancel().timeout(const Duration(seconds: 1));
      } catch (_) {
        /* The owned client is already force-closed. */
      }
      _clients.remove(client);
    }
  }

  @override
  void close() {
    _closed = true;
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

/// Copies a JSON object into a deeply immutable tree.
Map<String, Object?> freezeMap(Map<String, Object?> input) =>
    Map.unmodifiable(input.map((key, value) => MapEntry(key, _freeze(value))));
Object? _freeze(Object? value) => switch (value) {
  null || String() || bool() || int() => value,
  double() when value.isFinite => value,
  List<Object?>() => List<Object?>.unmodifiable(value.map(_freeze)),
  Map<String, Object?>() => freezeMap(value),
  _ => throw const CloudException(CloudErrorCode.invalidRequest),
};
