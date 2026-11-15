import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_cloud/src/protocol/codec.dart' show envelope;
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  test('typed manifest requests preserve exact roots, history timestamps and version envelope', () async {
    final manifest = CloudContentManifest.fromJson({
      'schemaVersion': 1,
      'objectFormat': 'sha1',
      'source': CloudGitSource(
        locator: 'https://example.invalid/owner/repo.git',
        ref: 'main',
        repositorySubpath: 'skills',
        skillPath: 'sample',
      ).toJson(),
      'slotKey': 'sample',
      'contentHash': 'b' * 64,
      'currentUpstream': 'a' * 40,
      'currentEffective': 'a' * 40,
      'publishedHistory': [
        {
          'eventFingerprint': 'c' * 64,
          'revision': 'a' * 40,
          'kind': 'publishDraft',
          'publishedAtMicros': '9007199254740993',
          'contentHash': 'b' * 64,
        },
      ],
    });
    final f = AuthFixture();
    addTearDown(f.auth.close);
    await f.login();
    f.transport.handler = (request, credential, _) async {
      final body = request.body!['data']! as Map<String, Object?>;
      expect(body['contentManifestVersion'], 1);
      expect(body['contentManifest'], manifest.toJson());
      expect(body.containsKey('commitId'), isFalse);
      expect(body.containsKey('sourceDescriptor'), isFalse);
      if (request.path == '/v1/sync/commits/prepare') {
        return ok({'uploadId': 'upload', 'state': 'ready', 'expiresAt': 1000});
      }
      return ok({
        'operationId': 'operation',
        'lineageId': 'lineage',
        'generation': 1,
        'commitId': manifest.currentEffective,
        'sequence': '9007199254740993',
        'outcome': 'committed',
        'receiptExpiresAt': 1000,
        'contentManifestVersion': 1,
        'contentManifest': manifest.toJson(),
      });
    };
    final client = CloudSyncClient(auth: f.auth, intents: MemoryIntents());
    final prepared = client.createPrepareIntent(
      CloudPrepareRequest(operationId: 'operation', contentManifest: manifest),
    );
    final upload = await client.prepareUpload(prepared);
    final commit = client.createCommitIntent(
      CloudCommitRequest.firstUpload(
        operationId: 'operation',
        uploadId: upload.uploadId,
        contentManifest: manifest,
      ),
    );
    final receipt = await client.commit(commit);
    expect(receipt.sequence.toJson(), '9007199254740993');
    expect(
      manifest.publishedHistory.single.publishedAtMicros,
      BigInt.parse('9007199254740993'),
    );
    await expectLater(
      client.prepareUpload(commit),
      throwsA(isA<CloudException>()),
    );
    await expectLater(client.commit(prepared), throwsA(isA<CloudException>()));
    final existing = CloudCommitRequest.existing(
      operationId: 'next',
      lineageId: 'lineage',
      generation: 1,
      baseCommitId: 'a' * 40,
      contentManifest: manifest,
    );
    expect(existing.toJson().containsKey('uploadId'), isFalse);
    expect(
      () => CloudCommitRequest.existing(
        operationId: 'next',
        lineageId: 'lineage',
        generation: 1,
        baseCommitId: 'bad',
        contentManifest: manifest,
      ),
      throwsA(isA<CloudException>()),
    );
    expect(
      () => CloudContentManifest.fromJson({
        ...manifest.toJson(),
        'packSha256': 'private-sidecar',
      }),
      throwsA(isA<CloudException>()),
    );
  });
  test('typed manifest prepare/commit exactly match the actual v3 service requests', () async {
    final document = jsonDecode(
      await File('test/fixtures/sync-contract.json').readAsString(),
    ) as Map<String, Object?>;
    expect(document['fixtureVersion'], 'sync-service-2026-11-15-v3');
    final cases = (document['cases']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final prepare = cases.firstWhere((item) => item['name'] == 'prepare'),
        commit = cases.firstWhere(
          (item) => item['name'] == 'commitLargeSequence',
        );
    Map<String, Object?> data(Map<String, Object?> item) =>
        ((item['request']! as Map<String, Object?>)['body']!
                as Map<String, Object?>)['data']!
            as Map<String, Object?>;
    final manifest = CloudContentManifest.fromJson(
      data(prepare)['contentManifest']! as Map<String, Object?>,
    );
    final f = AuthFixture();
    addTearDown(f.auth.close);
    await f.login();
    f.transport.handler = (request, credential, _) async {
      final item = request.path == '/v1/sync/commits/prepare'
          ? prepare
          : commit;
      expect(request.body!['data'], data(item));
      final response = item['response']! as Map<String, Object?>;
      return CloudResponse(
        statusCode: response['status']! as int,
        body: response['body']! as Map<String, Object?>,
      );
    };
    final client = CloudSyncClient(auth: f.auth, intents: MemoryIntents());
    final upload = await client.prepareUpload(
      client.createPrepareIntent(
        CloudPrepareRequest(
          operationId: data(prepare)['operationId']! as String,
          contentManifest: manifest,
        ),
      ),
    );
    final receipt = await client.commit(
      client.createCommitIntent(
        CloudCommitRequest.firstUpload(
          operationId: data(commit)['operationId']! as String,
          uploadId: upload.uploadId,
          contentManifest: manifest,
        ),
      ),
    );
    expect(receipt.commitId, manifest.currentEffective);
    expect(receipt.sequence.toJson(), '9007199254740993');
  });
  test('typed replacement and repair requests exactly match v3 service contracts and separate operation families', () async {
    final fixture = jsonDecode(
      await File('test/fixtures/sync-contract.json').readAsString(),
    ) as Map<String, Object?>;
    final cases = (fixture['cases']! as List<Object?>)
        .cast<Map<String, Object?>>();
    Map<String, Object?> requestData(String name) =>
        ((cases.firstWhere((item) => item['name'] == name)['request']!
                    as Map<String, Object?>)['body']!
                as Map<String, Object?>)['data']!
            as Map<String, Object?>;
    final prepare = requestData('replacementPrepare');
    final previous = prepare['replacement']! as Map<String, Object?>;
    final target = CloudReplacementTarget(
      lineageId: previous['lineageId']! as String,
      generation: previous['generation']! as int,
      baseCommitId: previous['baseCommitId']! as String,
    );
    final manifest = CloudContentManifest.fromJson(
      prepare['contentManifest']! as Map<String, Object?>,
    );
    expect(
      CloudPrepareRequest(
        operationId: prepare['operationId']! as String,
        contentManifest: manifest,
        replacement: target,
      ).toJson(),
      prepare,
    );
    final replacement = cases
        .map((item) => item['request']! as Map<String, Object?>)
        .where((request) => request['path'] == '/v1/sync/lifecycle')
        .map(
          (request) =>
              (request['body']! as Map<String, Object?>)['data']!
                  as Map<String, Object?>,
        )
        .singleWhere((data) => data['kind'] == 'replacement');
    expect(
      CloudReplacementRequest(
        operationId: replacement['operationId']! as String,
        uploadId: replacement['uploadId']! as String,
        previous: target,
        contentManifest: manifest,
      ).toJson(),
      replacement,
    );
    final repair = requestData('verifiedRepairReady');
    expect(
      CloudRepairRequest(
        operationId: repair['operationId']! as String,
        target: CloudReplacementTarget(
          lineageId: repair['lineageId']! as String,
          generation: repair['generation']! as int,
          baseCommitId: repair['baseCommitId']! as String,
        ),
        contentManifest: CloudContentManifest.fromJson(
          repair['contentManifest']! as Map<String, Object?>,
        ),
      ).toJson(),
      repair,
    );
    final key = CloudOperationKey(
      accountId: 'account',
      deviceId: 'device',
      operationId: 'stable',
    );
    expect(
      CloudMutationIntent.fresh(
        key: key,
        path: '/v1/sync/commits/prepare',
        data: {...prepare, 'operationId': 'stable'},
      ).family,
      'replacement',
    );
    final finalize = CloudMutationIntent.fresh(
      key: key,
      path: '/v1/sync/lifecycle',
      data: {...replacement, 'operationId': 'stable'},
    );
    expect(finalize.family, 'replacement');
    expect(finalize.isFirstUploadCommit, isTrue);
    expect(
      CloudMutationIntent.fresh(
        key: key,
        path: '/v1/sync/repair',
        data: {...repair, 'operationId': 'stable'},
      ).family,
      'repair',
    );
  });
  test('manifest accepts actual Workspace slot derivation including truncation-boundary punctuation', () async {
    final fixtures = jsonDecode(
      await File('test/fixtures/slot-key-cases.json').readAsString(),
    ) as Map<String, Object?>;
    final wire = jsonDecode(
      await File('test/fixtures/sync-contract.json').readAsString(),
    ) as Map<String, Object?>;
    final first =
        (wire['cases']! as List<Object?>).first! as Map<String, Object?>;
    final data =
        (((first['request']! as Map<String, Object?>)['body']!
                as Map<String, Object?>)['data']!
            as Map<String, Object?>);
    final manifest = data['contentManifest']! as Map<String, Object?>;
    for (final raw in fixtures['cases']! as List<Object?>) {
      final expected = (raw! as Map<String, Object?>)['expected'];
      if (expected != null) {
        expect(
          CloudContentManifest.fromJson({...manifest, 'slotKey': expected})
              .slotKey,
          expected,
        );
      }
    }
    for (final invalid in ['name.', 'name-', 'con', 'con.txt', 'a' * 256]) {
      expect(
        () => CloudContentManifest.fromJson({...manifest, 'slotKey': invalid}),
        throwsA(isA<CloudException>()),
      );
    }
  });
  test('40 real-service wire fixtures share exact bytes and parse typed snapshots/events', () async {
    final bytes = await File('test/fixtures/sync-contract.json').readAsBytes();
    expect(
      sha256.convert(bytes).toString(),
      '80e009e0fb5661dbca1568beb0c71a913c634cd6bfeef08f13ee997a8adac3fa',
    );
    final document = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
    final cases = document['cases']! as List<Object?>;
    expect(cases, hasLength(40));
    var globalTags = 0, removals = 0, snapshots = 0;
    for (final raw in cases) {
      final item = raw! as Map<String, Object?>;
      final request = item['request']! as Map<String, Object?>;
      final response = item['response']! as Map<String, Object?>;
      final body = response['body']! as Map<String, Object?>;
      final cloud = CloudResponse(
        statusCode: response['status']! as int,
        body: body,
      );
      if (cloud.statusCode >= 400) {
        expect(
          () => envelope(cloud),
          throwsA(isA<CloudException>()),
          reason: item['name']! as String,
        );
        continue;
      }
      final data = envelope(cloud);
      final uri = Uri.parse(request['path']! as String);
      if (data.containsKey('entries')) {
        final page = CloudChangesPage.fromJson(data);
        for (final event in page.entries) {
          if (event is CloudPersonalTagChange) {
            globalTags++;
            expect(event.lineageId, isNull);
            expect(event.generation, isNull);
          }
          if (event.kind == 'removal') removals++;
          if (event.payload['kind'] == 'fields') {
            final patch = event.payload['patch']! as Map<String, Object?>;
            expect(patch.containsKey('favorite'), isTrue);
          }
        }
      } else if (data.containsKey('snapshotId')) {
        final page = CloudSnapshotPage.fromJson(data);
        snapshots++;
        for (final lineage in page.items) {
          expect(lineage.sourceDescriptor.toJson()['payloadSchemaVersion'], 1);
          expect(lineage.metadata['favorite'], isNull);
          expect(lineage.metadata['note'], isNull);
        }
        for (final tag in page.personalTags) {
          expect(tag.name, 'Unassigned 标签');
        }
      } else if (uri.path == '/v1/sync/commits') {
        final receipt = CloudCommitReceipt.fromJson(data);
        expect(receipt.sequence.toJson(), '9007199254740993');
      }
      if (request['body'] case final Map<String, Object?> requestBody) {
        final frozen = CloudRequest(
          method: 'POST',
          path: uri.path,
          body: requestBody,
        );
        expect(jsonDecode(jsonEncode(frozen.body)), requestBody);
      }
    }
    expect(globalTags, greaterThanOrEqualTo(3));
    expect(removals, 1);
    expect(snapshots, 3);
  });
  test('sequence precision, source provenance and global/lineage discriminator fail closed', () {
    for (final value in [
      1,
      '',
      '-1',
      '01',
      '1e3',
      '1\n',
      '9223372036854775808',
    ]) {
      expect(() => CloudSequence.parse(value), throwsA(isA<CloudException>()));
    }
    expect(
      CloudSequence.parse('9007199254740993').value,
      BigInt.parse('9007199254740993'),
    );
    final source = CloudGitSource(
      locator: 'git@example.invalid:owner/repo.git',
      ref: 'main',
      repositorySubpath: 'skills',
      skillPath: 'nested/sample',
    );
    expect(
      CloudSourceDescriptor.fromJson(source.toJson()).toJson(),
      source.toJson(),
    );
    for (final locator in [
      '/Users/private/repo',
      'https://user:password@example.invalid/repo',
      'https://example.invalid/repo?token=secret',
    ]) {
      expect(
        () => CloudGitSource(
          locator: locator,
          ref: null,
          repositorySubpath: '',
          skillPath: 'sample',
        ),
        throwsA(isA<CloudException>()),
      );
    }
    expect(
      () => CloudChange.fromJson({
        'sequence': '1',
        'kind': 'personalTag',
        'lineageId': 'invented',
        'generation': 1,
        'payload': {'kind': 'tagDelete', 'tagId': 'tag'},
      }),
      throwsA(isA<CloudException>()),
    );
    expect(
      () => CloudChange.fromJson({
        'sequence': '1',
        'kind': 'removal',
        'lineageId': null,
        'generation': null,
        'payload': <String, Object?>{},
      }),
      throwsA(isA<CloudException>()),
    );
  });
}
