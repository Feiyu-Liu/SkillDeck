import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/testing.dart';
import 'package:test/test.dart';

const key = '00000000-0000-4000-8000-000000000001';
final origin = CloudServiceOrigin.parse('https://cloud.example.invalid');
String commit(int n) => n.toRadixString(16).padLeft(40, '0');
Future<CloudApi> api(
  http.Client client, {
  InMemoryCloudSessionStore? store,
  String token = 'private-token',
}) async {
  store ??= InMemoryCloudSessionStore();
  await store.write(StoredCloudSession(origin: origin, token: token));
  return CloudApi(client: client, origin: origin, sessions: store);
}

Map<String, Object?> lineageJson() => {
  'lineageId': 'l1',
  'version': 1,
  'generation': 1,
  'state': 'live',
  'source': {'private': 'source'},
  'head': null,
  'updatedAt': '2026-11-27T00:00:00Z',
};
void main() {
  test('request methods, headers, bodies and query encoding stay on the authenticated origin', () async {
    final requests = <http.Request>[];
    final client = await api(
      MockClient((r) async {
        requests.add(r);
        return http.Response(
          jsonEncode(
            r.url.path == '/v0/library'
                ? {'lineages': [], 'next': null, 'feedCursor': 'c'}
                : r.url.path == '/v0/feed'
                ? {'entries': [], 'cursor': 'c', 'more': false}
                : lineageJson(),
          ),
          200,
        );
      }),
    );
    final head = LineageHead(
      effective: commit(1),
      upstream: null,
      pack: PackDigest('a' * 64),
      declaredName: 'private-name',
    );
    await client.listLibrary(cursor: 'a+/=');
    await client.readLineage('l1');
    await client.createLineage(clientKey: key, source: {'private': 'source'});
    await client.advanceHead('l1', generation: 1, expected: null, next: head);
    await client.changeGeneration(
      'l1',
      expectedGeneration: 1,
      source: {},
      next: head,
    );
    await client.remove('l1');
    await client.stop('l1');
    await client.checkFeed(after: 'a+/=');
    expect(requests.map((r) => (r.method, r.url.path)), [
      ('GET', '/v0/library'),
      ('GET', '/v0/lineages/l1'),
      ('POST', '/v0/lineages'),
      ('POST', '/v0/lineages/l1/head'),
      ('POST', '/v0/lineages/l1/generations'),
      ('POST', '/v0/lineages/l1/removal'),
      ('POST', '/v0/lineages/l1/stop'),
      ('GET', '/v0/feed'),
    ]);
    for (final r in requests) {
      expect(r.headers['authorization'], 'Bearer private-token');
      expect(r.url.origin, origin.toString());
      expect(r.url.toString(), isNot(contains('private-token')));
      expect(r.followRedirects, isFalse);
    }
    expect(requests.first.url.queryParameters['cursor'], 'a+/=');
    expect(jsonDecode(requests[3].body), {
      'generation': 1,
      'expected': null,
      'next': head.next,
    });
    expect(jsonDecode(requests[4].body), {
      'expectedGeneration': 1,
      'source': {},
      'next': head.next,
    });
    expect(jsonDecode(requests[5].body), isEmpty);
  });
  test('documented error codes preserve typed fields and never expose server messages', () async {
    final cases = <({int status, Map<String, Object?> body, Type type})>[
      (status: 400, body: {'error': 'invalidRequest'}, type: ApiInvalidRequest),
      (
        status: 403,
        body: {'error': 'storageLimitReached'},
        type: ApiStorageLimitReached,
      ),
      (status: 404, body: {'error': 'notFound'}, type: ApiNotFound),
      (status: 410, body: {'error': 'cursorExpired'}, type: ApiCursorExpired),
      (
        status: 409,
        body: {'error': 'staleHead', 'lineage': lineageJson()},
        type: ApiStaleHead,
      ),
      (
        status: 409,
        body: {'error': 'wrongGeneration', 'lineage': lineageJson()},
        type: ApiWrongGeneration,
      ),
      (
        status: 409,
        body: {'error': 'wrongGeneration', 'generation': 2},
        type: ApiWrongGeneration,
      ),
      (
        status: 410,
        body: {'error': 'lineageEnded', 'lineage': lineageJson()},
        type: ApiLineageEnded,
      ),
      (status: 410, body: {'error': 'lineageEnded'}, type: ApiLineageEnded),
      (status: 409, body: {'error': 'packMissing'}, type: ApiPackMissing),
      (status: 409, body: {'error': 'packLacksHead'}, type: ApiPackLacksHead),
      (status: 409, body: {'error': 'notDescendant'}, type: ApiNotDescendant),
      for (final size in PackSizeLimit.values)
        (
          status: 413,
          body: {'error': 'packTooLarge', 'limit': size.name},
          type: ApiPackTooLarge,
        ),
      for (final reason in PackRejectionReason.values)
        (
          status: 422,
          body: {'error': 'packRejected', 'reason': reason.name},
          type: ApiPackRejected,
        ),
    ];
    final directory = await Directory.systemTemp.createTemp('api-errors-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/pack');
    await file.writeAsBytes([]);
    final head = LineageHead(
      effective: commit(1),
      upstream: null,
      pack: PackDigest('a' * 64),
      declaredName: 'fixture',
    );
    for (final c in cases) {
      final client = await api(
        MockClient(
          (_) async => http.Response(
            jsonEncode({...c.body, 'message': 'private-token'}),
            c.status,
          ),
        ),
      );
      final CloudApiResult<Object?> result;
      final code = c.body['error'];
      if (code == 'cursorExpired') {
        result = await client.checkFeed();
      } else if (code == 'invalidRequest' || code == 'storageLimitReached') {
        result = await client.createLineage(clientKey: key, source: {});
      } else if (code == 'notFound') {
        result = await client.readLineage('l1');
      } else if (code == 'packTooLarge' ||
          code == 'packRejected' ||
          code == 'lineageEnded' && !c.body.containsKey('lineage') ||
          code == 'wrongGeneration' && c.body.containsKey('generation')) {
        result = await client.uploadPack(
          'l1',
          generation: 1,
          path: file.path,
          digest: head.pack,
          effective: head.effective,
          upstream: null,
        );
      } else if (code == 'lineageEnded') {
        result = await client.remove('l1');
      } else {
        result = await client.advanceHead(
          'l1',
          generation: 1,
          expected: null,
          next: head,
        );
      }
      expect(result.runtimeType, c.type);
      expect('$result', isNot(contains('private-token')));
      if (result is ApiStaleHead) expect(result.lineage.id, 'l1');
    }
  });
  test('401 clears session, 429/503 retain it and forward retry delay; malformed and transport errors are stable', () async {
    for (final status in [401, 429, 503, 302]) {
      final store = InMemoryCloudSessionStore();
      final client = await api(
        MockClient(
          (_) async =>
              http.Response('', status, headers: {'retry-after': '17'}),
        ),
        store: store,
      );
      final result = await client.readLineage('l1');
      if (status == 401) {
        expect(result, isA<ApiSignInRequired>());
        expect(await store.read(origin), isNull);
      } else {
        expect(await store.read(origin), isNotNull);
        expect(result, isA<ApiUnavailable>());
        if (status != 302) {
          expect(
            (result as ApiUnavailable).retryAfter,
            const Duration(seconds: 17),
          );
        }
      }
    }
    final broken = await api(MockClient((_) async => http.Response('{', 200)));
    expect(
      (await broken.readLineage('l1') as ApiUnavailable).code,
      CloudFailureCode.protocol,
    );
    final offline = await api(
      MockClient((_) async => throw http.ClientException('private-token')),
    );
    final result = await offline.readLineage('l1');
    expect((result as ApiUnavailable).code, CloudFailureCode.network);
    expect('$result', isNot(contains('private-token')));
  });
  test('errors from the wrong endpoint and incomplete generation errors are protocol failures', () async {
    var body = <String, Object?>{'error': 'packMissing'};
    final client = await api(
      MockClient((_) async => http.Response(jsonEncode(body), 409)),
    );
    expect(
      (await client.readLineage('l1') as ApiUnavailable).code,
      CloudFailureCode.protocol,
    );
    body = {'error': 'wrongGeneration', 'generation': 2};
    final head = LineageHead(
      effective: commit(1),
      upstream: null,
      pack: PackDigest('a' * 64),
      declaredName: 'fixture',
    );
    expect(
      (await client.advanceHead(
        'l1',
        generation: 1,
        expected: null,
        next: head,
      ) as ApiUnavailable).code,
      CloudFailureCode.protocol,
    );
    final feed = await api(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'entries': [
              {'kind': 'future-kind', 'id': 'future', 'version': 1},
            ],
            'cursor': 'c',
            'more': false,
          }),
          200,
          headers: {'retry-after': '120'},
        ),
      ),
    );
    final result = await feed.checkFeed() as CloudApiSuccess<FeedPage>;
    expect(result.value.entries.single.isLineage, isFalse);
    expect(result.retryAfter, const Duration(seconds: 120));
  });
  test('fake contract: create retry, visibility, advance guards, feed, generation, ending and retention', () async {
    var now = DateTime.utc(2026, 11, 27);
    final service = FakeCloudService(now: () => now);
    addTearDown(service.client.close);
    final a = await api(service.client, token: service.session('a')),
        b = await api(service.client, token: service.session('b'));
    final l = (await a.createLineage(
      clientKey: key,
      source: {},
    ) as CloudApiSuccess<Lineage>).value;
    expect(
      (await a.createLineage(
        clientKey: key,
        source: {},
      ) as CloudApiSuccess<Lineage>).value.id,
      l.id,
    );
    expect(
      (await b.createLineage(
        clientKey: key,
        source: {},
      ) as CloudApiSuccess<Lineage>).value.id,
      isNot(l.id),
    );
    expect(await b.readLineage(l.id), isA<ApiNotFound>());
    final dir = await Directory.systemTemp.createTemp('cloud-api-');
    addTearDown(() => dir.delete(recursive: true));
    Future<LineageHead> upload(
      int n,
      List<String> parents, {
      int generation = 1,
    }) async {
      final bytes = FakePack([
        FakeCommit(id: commit(1), parents: [], files: {}),
        if (n != 1) FakeCommit(id: commit(n), parents: parents, files: {}),
      ], {}).encode();
      final file = File('${dir.path}/$n-$generation');
      await file.writeAsBytes(bytes);
      final digest = PackDigest(sha256.convert(bytes).toString());
      final result = await a.uploadPack(
        l.id,
        generation: generation,
        path: file.path,
        digest: digest,
        effective: commit(n),
        upstream: null,
      );
      expect(result, isA<CloudApiSuccess<PackUploaded>>());
      return LineageHead(
        effective: commit(n),
        upstream: null,
        pack: digest,
        declaredName: 'fixture',
      );
    }

    final initial = await upload(1, []);
    expect(
      (await a.listLibrary() as CloudApiSuccess<LibraryPage>).value.lineages,
      isEmpty,
    );
    expect(
      await a.advanceHead(l.id, generation: 2, expected: null, next: initial),
      isA<ApiWrongGeneration>(),
    );
    expect(
      await a.advanceHead(
        l.id,
        generation: 1,
        expected: initial,
        next: initial,
      ),
      isA<ApiStaleHead>(),
    );
    final first = (await a.advanceHead(
      l.id,
      generation: 1,
      expected: null,
      next: initial,
    ) as CloudApiSuccess<Lineage>).value;
    expect(
      (await a.advanceHead(
        l.id,
        generation: 1,
        expected: null,
        next: initial,
      ) as CloudApiSuccess<Lineage>).value.version,
      first.version,
    );
    final start = (await a.listLibrary() as CloudApiSuccess<LibraryPage>)
        .value
        .feedCursor;
    final side = await upload(2, []);
    expect(
      await a.advanceHead(l.id, generation: 1, expected: initial, next: side),
      isA<ApiNotDescendant>(),
    );
    final child = await upload(3, [commit(1)]);
    expect(
      await a.advanceHead(l.id, generation: 1, expected: initial, next: child),
      isA<CloudApiSuccess<Lineage>>(),
    );
    final feed =
        (await a.checkFeed(after: start) as CloudApiSuccess<FeedPage>).value;
    expect(feed.entries.single.id, l.id);
    expect(
      (await a.checkFeed(
        after: feed.cursor,
      ) as CloudApiSuccess<FeedPage>).value.entries,
      isEmpty,
    );
    expect(await b.checkFeed(after: feed.cursor), isA<ApiCursorExpired>());
    expect(await a.checkFeed(after: '!'), isA<ApiInvalidRequest>());
    final download = await a.downloadPack(
      l.id,
      generation: 1,
      digest: child.pack,
      path: '${dir.path}/download',
    );
    expect(download, isA<CloudApiSuccess<String>>());
    final replacement = await upload(4, [], generation: 2);
    expect(
      await a.changeGeneration(
        l.id,
        expectedGeneration: 1,
        source: {'new': true},
        next: replacement,
      ),
      isA<CloudApiSuccess<Lineage>>(),
    );
    expect(
      (await a.changeGeneration(
        l.id,
        expectedGeneration: 1,
        source: {'new': true},
        next: replacement,
      ) as CloudApiSuccess<Lineage>).value.generation,
      2,
    );
    expect(await a.stop(l.id), isA<CloudApiSuccess<Lineage>>());
    expect(await a.stop(l.id), isA<CloudApiSuccess<Lineage>>());
    expect(await a.remove(l.id), isA<ApiLineageEnded>());
    now = now.add(const Duration(days: 91));
    expect(await a.readLineage(l.id), isA<ApiNotFound>());
    expect(await a.checkFeed(after: feed.cursor), isA<ApiCursorExpired>());
  });
  test('downloads validate digest, delete partial files and preserve an existing destination', () async {
    final dir = await Directory.systemTemp.createTemp('cloud-download-');
    addTearDown(() => dir.delete(recursive: true));
    final target = File('${dir.path}/pack');
    final bytes = [1, 2, 3], digest = PackDigest('a' * 64);
    final client = await api(
      MockClient(
        (_) async => http.Response.bytes(
          bytes,
          200,
          headers: {
            'content-length': '3',
            'content-type': 'application/x-git-packed-objects',
          },
        ),
      ),
    );
    expect(
      await client.downloadPack(
        'l',
        generation: 1,
        digest: digest,
        path: target.path,
      ),
      isA<ApiUnavailable>(),
    );
    expect(await target.exists(), isFalse);
    await target.writeAsString('keep');
    await client.downloadPack(
      'l',
      generation: 1,
      digest: digest,
      path: target.path,
    );
    expect(await target.readAsString(), 'keep');
  });
  test('file upload streams chunks and an early transport failure cannot strand the file producer', () async {
    final dir = await Directory.systemTemp.createTemp('cloud-stream-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/pack');
    await file.writeAsBytes(List.filled(2 * 1024 * 1024, 42));
    final digest = PackDigest(
      (await sha256.bind(file.openRead()).single).toString(),
    );
    var chunks = 0;
    final probe = _ProbeClient((request) async {
      expect(request.contentLength, 2 * 1024 * 1024);
      await for (final chunk in request.finalize()) {
        expect(chunk.length, lessThan(2 * 1024 * 1024));
        chunks++;
      }
      return http.StreamedResponse(
        Stream.value(
          utf8.encode(jsonEncode({'sha256': digest.value, 'commits': 1})),
        ),
        200,
      );
    });
    final streaming = await api(probe);
    expect(
      await streaming.uploadPack(
        'l',
        generation: 1,
        path: file.path,
        digest: digest,
        effective: commit(1),
        upstream: null,
      ),
      isA<CloudApiSuccess<PackUploaded>>(),
    );
    expect(chunks, greaterThan(1));
    final failing = await api(
      _ProbeClient((_) async => throw http.ClientException('synthetic')),
    );
    expect(
      await failing
          .uploadPack(
            'l',
            generation: 1,
            path: file.path,
            digest: digest,
            effective: commit(1),
            upstream: null,
          )
          .timeout(const Duration(seconds: 1)),
      isA<ApiUnavailable>(),
    );
  });
  test('over-limit upload is refused before any HTTP request', () async {
    final dir = await Directory.systemTemp.createTemp('cloud-large-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/pack');
    final handle = await file.open(mode: FileMode.write);
    await handle.truncate(CloudApi.maxPackBytes + 1);
    await handle.close();
    final client = await api(
      MockClient((_) async => throw StateError('must not send')),
    );
    expect(
      await client.uploadPack(
        'l',
        generation: 1,
        path: file.path,
        digest: PackDigest('a' * 64),
        effective: commit(1),
        upstream: null,
      ),
      isA<ApiPackTooLarge>(),
    );
  });
}

final class _ProbeClient extends http.BaseClient {
  _ProbeClient(this._send);
  final Future<http.StreamedResponse> Function(http.BaseRequest) _send;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);
}
