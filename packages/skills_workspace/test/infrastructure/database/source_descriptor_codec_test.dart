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
