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
import 'metadata_values.dart';

/// Cloud API over the App's injected platform client. Owns no HTTP client.
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
  static final _opaqueId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  Future<CloudApiResult<LibraryPage>> listLibrary({
    String? cursor,
    int limit = 100,
    bool includeMetadata = false,
  }) => _json(
    'GET',
    '/v0/library',
    (value) {
      final page = LibraryPage.fromJson(
        value,
        includeMetadata: includeMetadata,
      );
      if (includeMetadata && (page.tagVocabulary != null) != (cursor == null)) {
        throw const FormatException('cloud_protocol');
      }
      return page;
    },
    query: {
      'cursor': ?cursor,
      'limit': '$limit',
      if (includeMetadata) 'include': 'metadata',
    },
  );
  Future<CloudApiResult<LineageMetadata>> readMetadata(String id) =>
      _json('GET', '${_lineage(id)}/metadata', (json) {
        final metadata = LineageMetadata.fromJson(json);
        if (metadata.lineageId != id) {
          throw const FormatException('cloud_protocol');
        }
        return metadata;
      });
  Future<CloudApiResult<CloudFavorite>> readFavorite(String id) =>
      _json('GET', '${_lineage(id)}/metadata/favorite', CloudFavorite.fromJson);
  Future<CloudApiResult<CloudFavorite>> writeFavorite(
    String id, {
    required int expectedVersion,
    required bool value,
  }) => _json(
    'PUT',
    '${_lineage(id)}/metadata/favorite',
    CloudFavorite.fromJson,
    body: {'expectedVersion': expectedVersion, 'value': value},
  );
  Future<CloudApiResult<CloudNote>> readNote(String id) =>
      _json('GET', '${_lineage(id)}/metadata/note', CloudNote.fromJson);
  Future<CloudApiResult<CloudNote>> writeNote(
    String id, {
    required int expectedVersion,
    required String? value,
  }) => _writeNote('PUT', id, '', expectedVersion, value);
  Future<CloudApiResult<CloudNote>> openNoteConflict(
    String id, {
    required int expectedVersion,
    required String? value,
  }) => _writeNote('POST', id, '/conflicts', expectedVersion, value);
  Future<CloudApiResult<CloudNote>> resolveNote(
    String id, {
    required int expectedVersion,
    required String? value,
  }) => _writeNote('POST', id, '/resolve', expectedVersion, value);
  Future<CloudApiResult<CloudNote>> _writeNote(
    String method,
    String id,
    String suffix,
    int expectedVersion,
    String? value,
  ) => _json(
    method,
    '${_lineage(id)}/metadata/note$suffix',
    CloudNote.fromJson,
    body: {'expectedVersion': expectedVersion, 'value': value},
  );
  Future<CloudApiResult<CloudAssignment>> readAssignment(
    String id,
    String tagId,
  ) => _assignment('GET', id, tagId, null);
  Future<CloudApiResult<CloudAssignment>> writeAssignment(
    String id,
    String tagId, {
    required int expectedVersion,
    required bool assigned,
  }) => _assignment('PUT', id, tagId, {
    'expectedVersion': expectedVersion,
    'assigned': assigned,
  });
  Future<CloudApiResult<CloudAssignment>> _assignment(
    String method,
    String id,
    String tagId,
    Map<String, Object?>? body,
  ) => _json(
    method,
    '${_lineage(id)}/metadata/assignments/${_requestId(tagId)}',
    (json) {
      final assignment = CloudAssignment.fromJson(json);
      if (assignment.tagId != tagId) {
        throw const FormatException('cloud_protocol');
      }
      return assignment;
    },
    body: body,
  );
  Future<CloudApiResult<TagVocabulary>> readTags() =>
      _json('GET', '/v0/tags', TagVocabulary.fromJson);
  Future<CloudApiResult<CloudTag>> readTag(String id) =>
      _json('GET', '/v0/tags/${_requestId(id)}', (json) => _sameTag(id, json));
  Future<CloudApiResult<CloudTag>> createTag({
    required String clientKey,
    required String name,
    required String? color,
  }) => _json(
    'POST',
    '/v0/tags',
    CloudTag.fromJson,
    body: {
      'clientKey': clientKey,
      'expectedVersion': null,
      'name': name,
      'color': color,
    },
  );
  Future<CloudApiResult<CloudTag>> renameTag(
    String id, {
    required int expectedVersion,
    required String name,
  }) => _json(
    'PUT',
    '/v0/tags/${_requestId(id)}/name',
    CloudTag.fromJson,
    body: {'expectedVersion': expectedVersion, 'name': name},
  );
  Future<CloudApiResult<CloudTag>> recolorTag(
    String id, {
    required int expectedVersion,
    required String? color,
  }) => _json(
    'PUT',
    '/v0/tags/${_requestId(id)}/color',
    (json) => _sameTag(id, json),
    body: {'expectedVersion': expectedVersion, 'color': color},
  );
  Future<CloudApiResult<String>> deleteTag(
    String id, {
    required int expectedVersion,
  }) => _json('POST', '/v0/tags/${_requestId(id)}/delete', (json) {
    final deletedId = metadataId(jsonObject(json)['tagId']);
    if (deletedId != id) throw const FormatException('cloud_protocol');
    return deletedId;
  }, body: {'expectedVersion': expectedVersion});
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
  String _lineage(String id) => '/v0/lineages/${_requestId(id)}';

  String _requestId(String id) {
    if (_opaqueId.matchAsPrefix(id)?.end != id.length) {
      throw ArgumentError('Invalid cloud identifier');
    }
    return id;
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
    if (response.statusCode == 404 &&
        request.url.path == '/v0/tags' &&
        request.method == 'GET') {
      await response.stream.listen((_) {}).cancel();
      return const ApiNotFound();
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
            (request.url.path == '/v0/lineages' ||
                request.url.path == '/v0/tags'))) {
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
        request.url.path.contains('/packs/') && request.method == 'PUT'
            ? null
            : Lineage.fromJson(error['lineage']),
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
      (409, 'staleFieldVersion') => ApiStaleFieldVersion(
        _currentMetadata(request.url.path, error['current']),
      ),
      (409, 'noteConflict') => ApiNoteConflict(
        CloudNote.fromJson(error['current']),
      ),
      (409, 'noNoteConflict') => ApiNoNoteConflict(
        CloudNote.fromJson(error['current']),
      ),
      (410, 'tagDeleted') => const ApiTagDeleted(),
      (410, 'tagMerged') => ApiTagMerged(metadataId(error['replacementTagId'])),
      (413, 'metadataTooLarge') => ApiMetadataTooLarge(switch (error['field']) {
        'note' => MetadataLimit.note,
        'name' => MetadataLimit.name,
        _ => throw const FormatException('cloud_protocol'),
      }),
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
    final packUri = origin.resolve(_packPath(id, generation, digest));
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
      final request = _FileRequest(packUri, file, abort.future)
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
    final packUri = origin.resolve(_packPath(id, generation, digest));
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
        packUri,
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
  if (path.contains('/metadata') || path.startsWith('/v0/tags')) {
    final write = request.method != 'GET';
    final note = path.contains('/metadata/note');
    final resolve = path.endsWith('/note/resolve');
    final vocabulary = path.startsWith('/v0/tags');
    final collection = path == '/v0/tags';
    final assignment = path.contains('/assignments/');
    return {
      'invalidRequest',
      if (!collection) 'notFound',
      if (path.contains('/metadata')) 'lineageEnded',
      if (write) 'storageLimitReached',
      if (write && !collection) 'staleFieldVersion',
      if (assignment || (vocabulary && !collection)) 'tagMerged',
      if (assignment ||
          (vocabulary && (write || !collection) && !path.endsWith('/delete')))
        'tagDeleted',
      if (note && write) resolve ? 'noNoteConflict' : 'noteConflict',
      if (write && (note || collection || path.endsWith('/name')))
        'metadataTooLarge',
    };
  }
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

Object _currentMetadata(String path, Object? value) {
  if (path.contains('/metadata/note')) return CloudNote.fromJson(value);
  if (path.endsWith('/favorite')) return CloudFavorite.fromJson(value);
  if (path.contains('/assignments/')) return CloudAssignment.fromJson(value);
  return CloudTag.fromJson(value);
}

CloudTag _sameTag(String id, Object? value) {
  final tag = CloudTag.fromJson(value);
  if (tag.id != id) throw const FormatException('cloud_protocol');
  return tag;
}
