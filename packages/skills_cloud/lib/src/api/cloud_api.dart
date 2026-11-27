import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../sign_in/cloud_service_origin.dart';
import '../sign_in/cloud_session_store.dart';
import '../sign_in/cloud_sign_in.dart';
import 'cloud_result.dart';
import 'cloud_values.dart';

/// Contract v0.1 over the App's injected platform client. Owns no HTTP client.
final class CloudApi {
  CloudApi({
    required this._client,
    required this.origin,
    required this._sessions,
  });
  final http.Client _client;
  final CloudServiceOrigin origin;
  final CloudSessionStore _sessions;
  static const maxPackBytes = 16 * 1024 * 1024;
  static const _maxJsonBytes = 4 * 1024 * 1024;

  Future<CloudApiResult<LibraryPage>> listLibrary({
    String? cursor,
    int limit = 100,
  }) => _json(
    'GET',
    '/v0/library',
    LibraryPage.fromJson,
    query: {'cursor': ?cursor, 'limit': '$limit'},
  );
  Future<CloudApiResult<Lineage>> readLineage(String id) =>
      _json('GET', _lineage(id), Lineage.fromJson);
  Future<CloudApiResult<Lineage>> createLineage({
    required String clientKey,
    required Map<String, Object?> source,
  }) => _json(
    'POST',
    '/v0/lineages',
    Lineage.fromJson,
    body: {'clientKey': clientKey, 'source': source},
  );
  Future<CloudApiResult<Lineage>> advanceHead(
    String id, {
    required int generation,
    required LineageHead? expected,
    required LineageHead next,
  }) => _json(
    'POST',
    '${_lineage(id)}/head',
    Lineage.fromJson,
    body: {
      'generation': generation,
      'expected': expected?.selection,
      'next': next.next,
    },
  );
  Future<CloudApiResult<Lineage>> changeGeneration(
    String id, {
    required int expectedGeneration,
    required Map<String, Object?> source,
    required LineageHead next,
  }) => _json(
    'POST',
    '${_lineage(id)}/generations',
    Lineage.fromJson,
    body: {
      'expectedGeneration': expectedGeneration,
      'source': source,
      'next': next.next,
    },
  );
  Future<CloudApiResult<Lineage>> remove(String id) =>
      _json('POST', '${_lineage(id)}/removal', Lineage.fromJson, body: {});
  Future<CloudApiResult<Lineage>> stop(String id) =>
      _json('POST', '${_lineage(id)}/stop', Lineage.fromJson, body: {});
  Future<CloudApiResult<FeedPage>> checkFeed({
    String? after,
    int limit = 1000,
  }) => _json(
    'GET',
    '/v0/feed',
    FeedPage.fromJson,
    query: {'after': ?after, 'limit': '$limit'},
  );
  String _lineage(String id) {
    if (id.isEmpty ||
        id.length > 64 ||
        id.contains('/') ||
        id == '.' ||
        id == '..') {
      throw ArgumentError('Invalid lineage identifier');
    }
    return '/v0/lineages/$id';
  }

  String _packPath(String id, int generation, PackDigest digest) =>
      '${_lineage(id)}/generations/$generation/packs/${digest.value}';

  Future<StoredCloudSession?> _session() async {
    final value = await _sessions.read(origin);
    return value?.origin == origin ? value : null;
  }

  Future<CloudApiResult<T>> _json<T>(
    String method,
    String path,
    T Function(Object?) decode, {
    Map<String, String>? query,
    Map<String, Object?>? body,
  }) async {
    final session = await _session();
    if (session == null) return const ApiSignInRequired();
    final request = http.AbortableRequest(
      method,
      origin.resolve(path).replace(queryParameters: query),
    )..followRedirects = false;
    request.headers['authorization'] = 'Bearer ${session.token}';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _sendJson(request, decode);
  }

  Future<CloudApiResult<T>> _sendJson<T>(
    http.BaseRequest request,
    T Function(Object?) decode,
  ) async {
    try {
      final response = await _client.send(request);
      return await _jsonResponse(response, decode, request);
    } on FormatException {
      return const ApiUnavailable(CloudFailureCode.protocol);
    } on ArgumentError {
      return const ApiUnavailable(CloudFailureCode.protocol);
    } on TypeError {
      return const ApiUnavailable(CloudFailureCode.protocol);
    } on Exception {
      return const ApiUnavailable(CloudFailureCode.network);
    }
  }

  Future<CloudApiResult<T>> _jsonResponse<T>(
    http.StreamedResponse response,
    T Function(Object?) decode,
    http.BaseRequest request,
  ) async {
    final delay = _retryAfter(response.headers['retry-after']);
    if (response.statusCode == 401) {
      await response.stream.listen((_) {}).cancel();
      await _sessions.delete(origin);
      return const ApiSignInRequired();
    }
    if (response.statusCode == 429 || response.statusCode >= 500) {
      await response.stream.listen((_) {}).cancel();
      return ApiUnavailable(CloudFailureCode.server, retryAfter: delay);
    }
    final bytes = <int>[];
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > _maxJsonBytes) {
        throw const FormatException('cloud_protocol');
      }
      bytes.addAll(chunk);
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (response.statusCode == 200 ||
        (response.statusCode == 201 &&
            request.method == 'POST' &&
            request.url.path == '/v0/lineages')) {
      return CloudApiSuccess(decode(value), retryAfter: delay);
    }
    final error = jsonObject(value), code = jsonString(error['error']);
    if (!_allowedErrors(request).contains(code)) {
      return const ApiUnavailable(CloudFailureCode.protocol);
    }
    return switch ((response.statusCode, code)) {
      (400, 'invalidRequest') => const ApiInvalidRequest(),
      (403, 'storageLimitReached') => const ApiStorageLimitReached(),
      (404, 'notFound') => const ApiNotFound(),
      (410, 'cursorExpired') => const ApiCursorExpired(),
      (409, 'staleHead') => ApiStaleHead(Lineage.fromJson(error['lineage'])),
      (409, 'wrongGeneration') =>
        request.method == 'PUT'
            ? ApiWrongGeneration(generation: positive(error['generation']))
            : ApiWrongGeneration(
                lineage: Lineage.fromJson(error['lineage']),
                generation: Lineage.fromJson(error['lineage']).generation,
              ),
      (410, 'lineageEnded') => ApiLineageEnded(
        request.method == 'PUT' ? null : Lineage.fromJson(error['lineage']),
      ),
      (409, 'packMissing') => const ApiPackMissing(),
      (409, 'packLacksHead') => const ApiPackLacksHead(),
      (409, 'notDescendant') => const ApiNotDescendant(),
      (413, 'packTooLarge') => ApiPackTooLarge(
        PackSizeLimit.values.byName(jsonString(error['limit'])),
      ),
      (422, 'packRejected') => ApiPackRejected(
        PackRejectionReason.values.byName(jsonString(error['reason'])),
      ),
      _ => const ApiUnavailable(CloudFailureCode.protocol),
    };
  }

  Future<CloudApiResult<PackUploaded>> uploadPack(
    String id, {
    required int generation,
    required String path,
    required PackDigest digest,
    required String effective,
    required String? upstream,
  }) async {
    revision(effective);
    if (upstream != null) revision(upstream);
    final file = File(path), session = await _session();
    if (session == null) return const ApiSignInRequired();
    final abort = Completer<void>();
    try {
      final length = await file.length();
      if (length > maxPackBytes) {
        return const ApiPackTooLarge(PackSizeLimit.packed);
      }
      final request =
          _FileRequest(
              origin.resolve(_packPath(id, generation, digest)),
              file,
              abort.future,
            )
            ..followRedirects = false
            ..contentLength = length;
      request.headers.addAll({
        'authorization': 'Bearer ${session.token}',
        'content-type': 'application/x-git-packed-objects',
        'skilldeck-pack-roots': [effective, ?upstream].join(','),
      });
      return await _sendJson(request, (value) {
        final m = jsonObject(value), count = m['commits'];
        if (count is! int || count < 0 || m['sha256'] != digest.value) {
          throw const FormatException('cloud_protocol');
        }
        return PackUploaded(digest, count);
      });
    } on Exception {
      return const ApiUnavailable(CloudFailureCode.network);
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  /// Writes a verified pack to a new destination. Existing files are never replaced.
  Future<CloudApiResult<String>> downloadPack(
    String id, {
    required int generation,
    required PackDigest digest,
    required String path,
  }) async {
    final session = await _session();
    if (session == null) return const ApiSignInRequired();
    final file = File(path), abort = Completer<void>();
    RandomAccessFile? output;
    var created = false, complete = false;
    try {
      await file.create(exclusive: true);
      created = true;
      output = await file.open(mode: FileMode.writeOnly);
      final request = http.AbortableRequest(
        'GET',
        origin.resolve(_packPath(id, generation, digest)),
        abortTrigger: abort.future,
      )..followRedirects = false;
      request.headers['authorization'] = 'Bearer ${session.token}';
      final response = await _client.send(request);
      if (response.statusCode != 200) {
        return await _jsonResponse(
          response,
          (_) => throw const FormatException('cloud_protocol'),
          request,
        );
      }
      final declared = int.tryParse(response.headers['content-length'] ?? '');
      if (declared == null ||
          declared < 0 ||
          declared > maxPackBytes ||
          response.headers['content-type'] !=
              'application/x-git-packed-objects') {
        return const ApiUnavailable(CloudFailureCode.protocol);
      }
      var size = 0;
      final hash = await sha256
          .bind(
            response.stream
                .map((chunk) {
                  size += chunk.length;
                  if (size > declared) {
                    throw const FormatException('cloud_protocol');
                  }
                  return chunk;
                })
                .asyncMap((chunk) async {
                  await output!.writeFrom(chunk);
                  return chunk;
                }),
          )
          .single;
      if (size != declared || hash.toString() != digest.value) {
        return const ApiUnavailable(CloudFailureCode.protocol);
      }
      await output.close();
      output = null;
      complete = true;
      return CloudApiSuccess(path);
    } on FormatException {
      return const ApiUnavailable(CloudFailureCode.protocol);
    } on ArgumentError {
      return const ApiUnavailable(CloudFailureCode.protocol);
    } on TypeError {
      return const ApiUnavailable(CloudFailureCode.protocol);
    } on Exception {
      return const ApiUnavailable(CloudFailureCode.network);
    } finally {
      if (!abort.isCompleted) abort.complete();
      await output?.close();
      if (created && !complete) await file.delete();
    }
  }
}

/// File.openRead is consumed only after the client finalizes the request. This
/// preserves backpressure and cannot strand a producer after an early refusal.
final class _FileRequest extends http.BaseRequest with http.Abortable {
  _FileRequest(Uri uri, this._file, this.abortTrigger) : super('PUT', uri);
  final File _file;
  @override
  final Future<void> abortTrigger;
  @override
  http.ByteStream finalize() {
    super.finalize();
    return http.ByteStream(_file.openRead());
  }
}

Duration? _retryAfter(String? value) {
  if (value == null) return null;
  final seconds = int.tryParse(value);
  if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
  final match = RegExp(
    r'^[A-Za-z]{3}, (\d{2}) ([A-Za-z]{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
  ).firstMatch(value);
  if (match == null) return null;
  final month =
      const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ].indexOf(match[2]!) +
      1;
  if (month == 0) return null;
  final date = DateTime.utc(
    int.parse(match[3]!),
    month,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6]!),
  );
  final delay = date.difference(DateTime.now().toUtc());
  return delay.isNegative ? Duration.zero : delay;
}

Set<String> _allowedErrors(http.BaseRequest request) {
  final path = request.url.path;
  if (path == '/v0/library' || path == '/v0/feed') {
    return {'invalidRequest', 'cursorExpired'};
  }
  if (path == '/v0/lineages') return {'invalidRequest', 'storageLimitReached'};
  if (path.contains('/packs/')) {
    return request.method == 'PUT'
        ? {
            'invalidRequest',
            'notFound',
            'wrongGeneration',
            'lineageEnded',
            'packTooLarge',
            'packRejected',
            'storageLimitReached',
          }
        : {'invalidRequest', 'notFound'};
  }
  if (path.endsWith('/head') || path.endsWith('/generations')) {
    return {
      'invalidRequest',
      'notFound',
      'wrongGeneration',
      'lineageEnded',
      'packMissing',
      'packLacksHead',
      'storageLimitReached',
      if (path.endsWith('/head')) ...['staleHead', 'notDescendant'],
    };
  }
  return {
    'invalidRequest',
    'notFound',
    if (path.endsWith('/removal') || path.endsWith('/stop')) 'lineageEnded',
  };
}
