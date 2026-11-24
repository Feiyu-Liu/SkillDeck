import 'dart:convert';

import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:skills_workspace/src/infrastructure/database/source_descriptor_codec.dart';
import 'package:test/test.dart';

void main() {
  const codec = SourceDescriptorCodec();

  test('round-trips every current Source Descriptor variant', () {
    final sources = <SourceDescriptor>[
      LocalSourceDescriptor(locator: '/tmp/source', skillPath: 'one'),
      GitSourceDescriptor(
        locator: 'https://github.com/example/skills.git',
        ref: 'main',
        repositorySubpath: 'catalog',
        skillPath: 'one',
      ),
      GitSourceDescriptor(locator: 'ssh://git@github.com/example/skills.git'),
      WellKnownSourceDescriptor(
        locator: 'https://example.test/.well-known/skills/index.json',
        skillPath: 'one',
      ),
      AdoptedSnapshotSourceDescriptor(
        authoritativeLocation: '/tmp/agent/skills/one',
        contentHash: 'a' * 64,
      ),
      for (final originSourceType in SyncedOriginSourceType.values)
        SyncedOriginSourceDescriptor(
          originSourceType: originSourceType,
          originDeviceLabel: 'MacBook Pro',
          displayLabel: 'Team Skills',
        ),
    ];

    for (final source in sources) {
      final encoded = codec.encode(source);
      expect(encoded.payloadSchemaVersion, 1);
      expect(
        codec.decode(
          kind: encoded.kind,
          payloadSchemaVersion: encoded.payloadSchemaVersion,
          payloadJson: encoded.payloadJson,
        ),
        source,
      );
    }
  });

  test(
    'synced provenance allows ordinary names and rejects invalid labels',
    () {
      const payload = <String, Object?>{
        'originSourceType': 'local',
        'originDeviceLabel': 'MacBook Pro',
        'displayLabel': 'Team Skills',
      };
      SourceDescriptor decode(Map<String, Object?> data) => codec.decode(
        kind: 'syncedOrigin',
        payloadSchemaVersion: 1,
        payloadJson: jsonEncode(data),
      );

      for (final field in ['path', 'locator', 'url', 'token', 'deviceId']) {
        expect(
          () => decode({...payload, field: 'unexpected'}),
          throwsA(_reason('unexpectedField')),
        );
      }
      for (final field in ['originDeviceLabel', 'displayLabel']) {
        for (final value in ['notes:v2', 'Work / Personal', '..', '🐟' * 256]) {
          final source = decode({...payload, field: value});
          expect(jsonDecode(codec.encode(source).payloadJson)[field], value);
        }
        for (final value in ['', '   ']) {
          expect(
            () => decode({...payload, field: value}),
            throwsA(_reason('missingRequiredField')),
          );
        }
        for (final value in ['title\n', 'name\u0085', 'x' * 257]) {
          expect(
            () => decode({...payload, field: value}),
            throwsA(_reason('invalidPayloadValue')),
          );
        }
      }
      expect(
        () => decode({...payload, 'originSourceType': 'git'}),
        throwsA(_reason('invalidPayloadValue')),
      );
    },
  );

  test('normal reads reject unknown versions and kinds', () {
    expect(
      () =>
          codec.decode(kind: 'git', payloadSchemaVersion: 2, payloadJson: '{}'),
      throwsA(_reason('unsupportedPayloadSchemaVersion')),
    );
    expect(
      () => codec.decode(
        kind: 'marketplace',
        payloadSchemaVersion: 1,
        payloadJson: '{}',
      ),
      throwsA(_reason('unsupportedKind')),
    );
  });

  test('credential-bearing URL locators never enter persisted payloads', () {
    expect(
      () => codec.encode(
        GitSourceDescriptor(
          locator: 'https://secret-token@example.test/repository.git',
        ),
      ),
      throwsA(_reason('credentialBearingLocator')),
    );
    expect(
      () => codec.decode(
        kind: 'wellKnown',
        payloadSchemaVersion: 1,
        payloadJson:
            '{"locator":"https://secret@example.test/index.json",'
            '"skillPath":""}',
      ),
      throwsA(_reason('credentialBearingLocator')),
    );
  });

  test('invalid JSON and invalid domain values fail closed', () {
    expect(
      () => codec.decode(
        kind: 'local',
        payloadSchemaVersion: 1,
        payloadJson: 'not-json',
      ),
      throwsA(_reason('invalidJson')),
    );
    expect(
      () => codec.decode(
        kind: 'adoptedSnapshot',
        payloadSchemaVersion: 1,
        payloadJson:
            '{"authoritativeLocation":"relative",'
            '"contentHash":"${'a' * 64}"}',
      ),
      throwsA(_reason('invalidPayloadValue')),
    );
  });
}

Matcher _reason(String reason) => isA<SourceDescriptorCodecException>().having(
  (error) => error.reason,
  'reason',
  reason,
);
