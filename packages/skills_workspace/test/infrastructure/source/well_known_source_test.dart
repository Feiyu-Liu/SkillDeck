import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/source/source_result.dart';
import 'package:skills_workspace/src/infrastructure/source/well_known_http.dart';
import 'package:skills_workspace/src/infrastructure/source/well_known_index.dart';
import 'package:skills_workspace/src/infrastructure/source/well_known_source.dart';
import 'package:test/test.dart';

import '../../support/content/revision_content_worker_fake.dart';

void main() {
  test('verifies and normalizes a v2 skill-md artifact', () async {
    final skillBytes = utf8.encode('''
---
name: example
description: Example description
---
# Example
''');
    final digest = 'sha256:${sha256.convert(skillBytes)}';
    final client = _clientFor(
      index:
          '''
{"\$schema":"$wellKnownDiscoverySchemaV2","skills":[{"name":"example","description":"Example description","type":"skill-md","url":"./example.md","digest":"$digest"}]}
''',
      artifactBytes: skillBytes,
    );

    final contentWorker = RecordingRevisionContentWorker();
    final result = await WellKnownSourceAdapter(
      httpClient: client,
      contentWorker: contentWorker,
    ).acquire(WellKnownSourceDescriptor(locator: 'http://127.0.0.1'));

    final skill = result.valueOrNull!.skills.single;
    expect(skill.declaredName, 'example');
    expect(skill.tree.contentHash, hasLength(64));
    expect(
      (skill.provenance as WellKnownSourceDescriptor).skillPath,
      'example',
    );
    expect(contentWorker.normalizationCalls, 1);
    expect(contentWorker.filesystemReadCalls, 0);
  });

  test('rejects an artifact whose digest does not match', () async {
    final client = _clientFor(
      index:
          '''
{"\$schema":"$wellKnownDiscoverySchemaV2","skills":[{"name":"example","description":"Example description","type":"skill-md","url":"./example.md","digest":"sha256:${'0' * 64}"}]}
''',
      artifactBytes: utf8.encode('different'),
    );

    final result = await WellKnownSourceAdapter(httpClient: client).acquire(
      WellKnownSourceDescriptor(
        locator: 'http://127.0.0.1',
        skillPath: 'example',
      ),
    );

    expect(result.failureOrNull?.code, SourceFailureCode.digestMismatch);
  });
}

WellKnownHttpClient _clientFor({
  required String index,
  required List<int> artifactBytes,
}) => WellKnownHttpClient(
  client: MockClient((request) async {
    if (request.url.path.endsWith('index.json')) {
      return http.Response(
        index,
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    }
    return http.Response.bytes(artifactBytes, 200);
  }),
  addressResolver: (_) async => <InternetAddress>[InternetAddress.loopbackIPv4],
);
