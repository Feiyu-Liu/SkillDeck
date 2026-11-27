import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../api/cloud_values.dart';
import '../api/cloud_api.dart';
import 'fake_pack.dart';

/// Contract v0.1 fake behind a real package:http client, with explicit fault controls.
final class FakeCloudService {
  FakeCloudService({DateTime Function()? now}) : _now = now ?? DateTime.now {
    client = MockClient(_handle);
  }
  final DateTime Function() _now;
  late final http.Client client;
  final _sessions = <String, ({String account, String name})>{};
  final _accounts = <String, _Account>{};
  final _faults =
      <({String? path, int status, bool lost, Duration? retryAfter})>[];
  final requests = <({String method, String path})>[];
  int _nextId = 0;
  String session(String account, {String deviceName = 'Test device'}) {
    final token = 'fake-session-${_nextId++}';
    _sessions[token] = (account: account, name: deviceName);
    return token;
  }

  void failNext({
    String? path,
    int status = 503,
    bool afterCommit = false,
    Duration? retryAfter,
  }) => _faults.add((
    path: path,
    status: status,
    lost: afterCommit,
    retryAfter: retryAfter,
  ));
  Duration? retryAfter;
  void expireFeed(String account) {
    final a = _accounts[account];
    if (a != null) a.floor = ++a.sequence;
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add((method: request.method, path: request.url.path));
    final index = _faults.indexWhere(
      (f) => f.path == null || f.path == request.url.path,
    );
    final fault = index < 0 ? null : _faults.removeAt(index);
    if (fault != null && !fault.lost) {
      return _json({'error': 'rate_limited'}, fault.status, fault.retryAfter);
    }
    http.Response response;
    try {
      response = _route(request);
    } on FormatException {
      response = _json({'error': 'invalidRequest'}, 400);
    } on ArgumentError {
      response = _json({'error': 'invalidRequest'}, 400);
    } on TypeError {
      response = _json({'error': 'invalidRequest'}, 400);
    }
    if (fault?.lost == true) {
      throw http.ClientException('synthetic connection failure');
    }
    return response;
  }

  http.Response _json(Object? value, [int status = 200, Duration? delay]) =>
      http.Response(
        jsonEncode(value),
        status,
        headers: {
          'content-type': 'application/json',
          if (delay ?? retryAfter case final d?)
            'retry-after': '${d.inSeconds}',
        },
      );
  http.Response _route(http.Request r) {
    final token = r.headers['authorization'];
    final session = token == null
        ? null
        : _sessions[token.replaceFirst('Bearer ', '')];
    if (session == null || !token!.startsWith('Bearer ')) {
      return _json({'error': 'unauthorized'}, 401);
    }
    final a = _accounts.putIfAbsent(session.account, _Account.new);
    _sweep(a);
    final path = r.url.path, parts = r.url.pathSegments;
    final allowed = path == '/v0/library'
        ? {'cursor', 'limit'}
        : path == '/v0/feed'
        ? {'after', 'limit'}
        : <String>{};
    if (r.url.queryParametersAll.entries.any(
      (e) => !allowed.contains(e.key) || e.value.length != 1,
    )) {
      throw const FormatException();
    }
    Map<String, Object?> body() {
      if (r.headers['content-type']?.split(';').first != 'application/json') {
        throw const FormatException();
      }
      return jsonObject(jsonDecode(r.body));
    }

    if (path == '/v0/library' && r.method == 'GET') {
      final cursor = r.url.queryParameters['cursor'];
      final parsed = cursor == null ? null : _cursor(cursor, true);
      if (parsed != null &&
          (parsed.$1 != session.account ||
              parsed.$2 > a.sequence ||
              parsed.$2 < a.floor)) {
        return _json({'error': 'cursorExpired'}, 410);
      }
      final start = parsed?.$3 ?? '', seq = parsed?.$2 ?? a.sequence;
      final limit = int.parse(r.url.queryParameters['limit'] ?? '100');
      if (limit < 1 || limit > 500) throw const FormatException();
      final rows =
          a.lineages.values
              .where(
                (l) =>
                    l.state == LineageState.live &&
                    l.head != null &&
                    l.id.compareTo(start) > 0,
              )
              .toList()
            ..sort((x, y) => x.id.compareTo(y.id));
      final page = rows.take(limit).toList();
      return _json({
        'lineages': page.map((l) => l.value.toJson()).toList(),
        'next': rows.length > limit
            ? _encode(session.account, seq, page.last.id)
            : null,
        'feedCursor': _encode(session.account, seq),
      });
    }
    if (path == '/v0/feed' && r.method == 'GET') {
      final after = r.url.queryParameters['after'],
          parsed = after == null ? null : _cursor(after, false);
      if (parsed != null &&
          (parsed.$1 != session.account ||
              parsed.$2 > a.sequence ||
              parsed.$2 < a.floor)) {
        return _json({'error': 'cursorExpired'}, 410);
      }
      final limit = int.parse(r.url.queryParameters['limit'] ?? '1000');
      if (limit < 1 || limit > 1000) throw const FormatException();
      final rows =
          a.feed.entries.where((e) => e.value > (parsed?.$2 ?? 0)).toList()
            ..sort((x, y) => x.value.compareTo(y.value));
      final page = rows.take(limit).toList();
      return _json({
        'entries': page
            .map(
              (e) => {
                'kind': 'lineage',
                'id': e.key,
                'version': a.lineages[e.key]!.version,
              },
            )
            .toList(),
        'cursor': page.isEmpty
            ? after ?? _encode(session.account, 0)
            : _encode(session.account, page.last.value),
        'more': rows.length > limit,
      });
    }
    if (path == '/v0/lineages' && r.method == 'POST') {
      final b = body();
      _fields(b, ['clientKey', 'source']);
      final key = jsonString(b['clientKey']);
      final source = jsonObject(b['source']);
      if (!RegExp(r'^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$')
              .hasMatch(key) ||
          utf8.encode(jsonEncode(source)).length > 4096) {
        throw const FormatException();
      }
      final old = a.keys[key];
      if (old != null) return _json(a.lineages[old]!.value.toJson());
      final id = 'lineage-${(_nextId++).toString().padLeft(8, '0')}';
      final l = _FakeLineage(id, source, _now());
      a.lineages[id] = l;
      a.keys[key] = id;
      return _json(l.value.toJson(), 201);
    }
    if (parts.length < 3 || parts[0] != 'v0' || parts[1] != 'lineages') {
      return _json({'error': 'notFound'}, 404);
    }
    final l = a.lineages[parts[2]];
    if (l == null) return _json({'error': 'notFound'}, 404);
    if (parts.length == 3 && r.method == 'GET') return _json(l.value.toJson());
    if (parts.length == 6 &&
        parts[3] == 'generations' &&
        parts[5].length == 64) {
      throw const FormatException();
    }
    if (parts.length == 6 && parts[3] == 'generations' && parts[4] == 'packs') {
      throw const FormatException();
    }
    if (parts.length == 7 && parts[3] == 'generations' && parts[5] == 'packs') {
      final g = int.parse(parts[4]),
          digest = parts[6],
          key = '$g/$digest',
          p = l.packs[key];
      if (r.method == 'GET') {
        final isCurrent =
            l.state == LineageState.live &&
            l.generation == g &&
            l.head?.pack.value == digest;
        if (p == null ||
            (!isCurrent &&
                (p.unreferenced == null ||
                    _now().difference(p.unreferenced!) >=
                        const Duration(hours: 24)))) {
          return _json({'error': 'notFound'}, 404);
        }
        return http.Response.bytes(
          p.bytes,
          200,
          headers: {
            'content-length': '${p.bytes.length}',
            'content-type': 'application/x-git-packed-objects',
          },
        );
      }
      if (r.method != 'PUT') throw const FormatException();
      if (l.state != LineageState.live) {
        return _json({'error': 'lineageEnded'}, 410);
      }
      if (g != l.generation && g != l.generation + 1) {
        return _json({
          'error': 'wrongGeneration',
          'generation': l.generation,
        }, 409);
      }
      if (r.bodyBytes.length > CloudApi.maxPackBytes) {
        return _json({'error': 'packTooLarge', 'limit': 'packed'}, 413);
      }
      if (sha256.convert(r.bodyBytes).toString() != digest) {
        return _json({
          'error': 'packRejected',
          'reason': 'digestMismatch',
        }, 422);
      }
      final roots = (r.headers['skilldeck-pack-roots'] ?? '').split(',');
      if (roots.isEmpty ||
          roots.length > 2 ||
          r.contentLength != r.bodyBytes.length ||
          r.headers['content-type'] != 'application/x-git-packed-objects') {
        throw const FormatException();
      }
      FakePack decoded;
      try {
        decoded = FakePack.decode(r.bodyBytes);
      } on Exception {
        return _json({'error': 'packRejected', 'reason': 'packFormat'}, 422);
      }
      if (roots.any((root) => !decoded.commits.containsKey(root))) {
        return _json({'error': 'packRejected', 'reason': 'missingRoot'}, 422);
      }
      if (!decoded.containsClosure(decoded.commits.keys)) {
        return _json({'error': 'packRejected', 'reason': 'missingObject'}, 422);
      }
      if (p == null) {
        l.packs[key] = _FakePack(r.bodyBytes, decoded, roots.toSet(), _now());
      } else {
        p.roots.addAll(roots);
      }
      return _json({'sha256': digest, 'commits': decoded.commits.length});
    }
    if (parts.length != 4 || r.method != 'POST') throw const FormatException();
    final action = parts[3], b = body();
    if (action == 'removal' || action == 'stop') {
      _fields(b, []);
      final state = action == 'removal'
          ? LineageState.removed
          : LineageState.stopped;
      if (l.state == state) return _json(l.value.toJson());
      if (l.state != LineageState.live) {
        return _json({
          'error': 'lineageEnded',
          'lineage': l.value.toJson(),
        }, 410);
      }
      _unreference(l);
      l.endedGenerations[l.generation] = _now();
      l.state = state;
      l.head = null;
      _change(a, l);
      return _json(l.value.toJson());
    }
    if (action != 'head' && action != 'generations') {
      throw const FormatException();
    }
    final change = action == 'generations';
    _fields(
      b,
      change
          ? ['expectedGeneration', 'source', 'next']
          : ['generation', 'expected', 'next'],
    );
    final n = jsonObject(b['next']);
    _fields(n, ['effective', 'upstream', 'pack', 'declaredName']);
    if (change &&
        utf8.encode(jsonEncode(jsonObject(b['source']))).length > 4096) {
      throw const FormatException();
    }
    if (!change && b['expected'] != null) {
      final e = jsonObject(b['expected']);
      _fields(e, ['effective', 'upstream']);
      revision(jsonString(e['effective']));
      if (e['upstream'] != null) revision(jsonString(e['upstream']));
    }
    final next = LineageHead.fromJson({
          ...n,
          'device': {'name': session.name, 'platform': 'macos'},
        }),
        g = positive(b[change ? 'expectedGeneration' : 'generation']);
    if (utf8.encode(next.declaredName).length > 256) {
      throw const FormatException();
    }
    if (_same(l.head, next) &&
        (!change ||
            (l.generation == g + 1 &&
                _canonical(l.source) == _canonical(b['source'])))) {
      return _json(l.value.toJson());
    }
    if (l.state != LineageState.live) {
      return _json({'error': 'lineageEnded', 'lineage': l.value.toJson()}, 410);
    }
    if (l.generation != g) {
      return _json({
        'error': 'wrongGeneration',
        'lineage': l.value.toJson(),
      }, 409);
    }
    final expected = change || b['expected'] == null
        ? null
        : jsonObject(b['expected']);
    if (!change &&
        (expected == null
            ? l.head != null
            : l.head == null ||
                  l.head!.effective != expected['effective'] ||
                  l.head!.upstream != expected['upstream'])) {
      return _json({'error': 'staleHead', 'lineage': l.value.toJson()}, 409);
    }
    final target = change ? g + 1 : g,
        p = l.packs['$target/${next.pack.value}'];
    if (p == null) return _json({'error': 'packMissing'}, 409);
    if (!p.roots.contains(next.effective) ||
        (next.upstream != null && !p.roots.contains(next.upstream))) {
      return _json({'error': 'packLacksHead'}, 409);
    }
    if (!change && expected != null) {
      if (!p.pack.descends(next.effective, jsonString(expected['effective']))) {
        return _json({'error': 'notDescendant'}, 409);
      }
      if (expected['upstream'] == null
          ? next.upstream != null
          : next.upstream == null ||
                !p.pack.descends(
                  next.upstream!,
                  jsonString(expected['upstream']),
                )) {
        return _json({'error': 'notDescendant'}, 409);
      }
    }
    _unreference(l);
    if (change) {
      l.endedGenerations[l.generation] = _now();
      l.source = jsonObject(b['source']);
      l.generation = target;
    }
    l.head = next;
    p.unreferenced = null;
    p.referenced = true;
    _change(a, l);
    return _json(l.value.toJson());
  }

  void _unreference(_FakeLineage l) {
    final p = l.packs['${l.generation}/${l.head?.pack.value}'];
    if (p != null) p.unreferenced = _now();
  }

  void _change(_Account a, _FakeLineage l) {
    l.version++;
    l.updated = _now();
    a.feed[l.id] = ++a.sequence;
  }

  void _sweep(_Account a) {
    for (final l in a.lineages.values.toList()) {
      l.packs.removeWhere((key, pack) {
        final generation = int.parse(key.split('/').first),
            ended = l.endedGenerations[generation];
        if (ended != null) {
          return _now().difference(ended) >= const Duration(days: 7);
        }
        final current =
            l.state == LineageState.live &&
            l.generation == generation &&
            l.head?.pack.value == key.split('/').last;
        return !current &&
            _now().difference(pack.unreferenced ?? pack.uploaded) >=
                const Duration(hours: 24);
      });
      final pending =
          l.state == LineageState.live &&
          l.head == null &&
          _now().difference(l.created) >= const Duration(hours: 24);
      final ended =
          l.state != LineageState.live &&
          _now().difference(l.updated) >= const Duration(days: 90);
      if (pending || ended) {
        final seq = a.feed.remove(l.id);
        if (seq != null && seq > a.floor) a.floor = seq;
        a.lineages.remove(l.id);
        a.keys.removeWhere((_, id) => id == l.id);
      } else if (_now().difference(l.created) >= const Duration(days: 30)) {
        a.keys.removeWhere((_, id) => id == l.id);
      }
    }
  }
}

void _fields(Map<String, Object?> m, List<String> names) {
  if (m.length != names.length || names.any((n) => !m.containsKey(n))) {
    throw const FormatException();
  }
}

bool _same(LineageHead? a, LineageHead b) =>
    a != null &&
    a.effective == b.effective &&
    a.upstream == b.upstream &&
    a.pack == b.pack &&
    a.declaredName == b.declaredName;
String _canonical(Object? v) => v is Map
    ? jsonEncode({
        for (final key in v.keys.cast<String>().toList()..sort())
          key: _canonical(v[key]),
      })
    : v is List
    ? jsonEncode(v.map(_canonical).toList())
    : jsonEncode(v);
String _encode(String account, int seq, [String? last]) =>
    base64Url.encode(utf8.encode(jsonEncode([account, seq, ?last])));
(String, int, String?) _cursor(String raw, bool library) {
  final v = jsonList(jsonDecode(utf8.decode(base64Url.decode(raw))));
  if (v.length != (library ? 3 : 2) ||
      v[0] is! String ||
      v[1] is! int ||
      (v[1] as int) < 0 ||
      (library && v[2] is! String)) {
    throw const FormatException();
  }
  return (v[0] as String, v[1] as int, library ? v[2] as String : null);
}

final class _Account {
  final lineages = <String, _FakeLineage>{};
  final keys = <String, String>{};
  final feed = <String, int>{};
  int sequence = 0, floor = 0;
}

final class _FakeLineage {
  _FakeLineage(this.id, this.source, this.created) : updated = created;
  final String id;
  Map<String, Object?> source;
  final DateTime created;
  DateTime updated;
  int version = 1, generation = 1;
  LineageState state = LineageState.live;
  LineageHead? head;
  final packs = <String, _FakePack>{};
  final endedGenerations = <int, DateTime>{};
  Lineage get value => Lineage(
    id: id,
    version: version,
    state: state,
    generation: generation,
    source: source,
    head: head,
    updatedAt: updated,
  );
}

final class _FakePack {
  _FakePack(this.bytes, this.pack, this.roots, this.uploaded);
  final List<int> bytes;
  final FakePack pack;
  final Set<String> roots;
  final DateTime uploaded;
  bool referenced = false;
  DateTime? unreferenced;
}
