import 'dart:io';

import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  const hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final absolutePath = Directory.systemTemp.absolute.path;

  group('SourceDescriptor identity', () {
    test('includes every Git identity field', () {
      final source = GitSourceDescriptor(
        locator: 'https://example.com/org/repo.git',
        ref: 'release/latest',
        repositorySubpath: 'packages',
        skillPath: 'skills/review',
      );

      expect(source.type, SourceType.git);
      expect(
        source.hasSameIdentity(
          GitSourceDescriptor(
            locator: 'https://example.com/org/repo.git',
            ref: 'release/latest',
            repositorySubpath: 'packages',
            skillPath: 'skills/review',
          ),
        ),
        isTrue,
      );
      expect(
        source.hasSameIdentity(
          GitSourceDescriptor(
            locator: 'https://example.com/org/repo.git',
            ref: 'main',
            repositorySubpath: 'packages',
            skillPath: 'skills/review',
          ),
        ),
        isFalse,
      );
    });

    test('keeps all four source variants type-distinct', () {
      final sources = <SourceDescriptor>[
        LocalSourceDescriptor(locator: absolutePath),
        GitSourceDescriptor(locator: 'https://example.com/repo.git'),
        WellKnownSourceDescriptor(locator: 'https://example.com/skills.json'),
        AdoptedSnapshotSourceDescriptor(
          authoritativeLocation: absolutePath,
          contentHash: hash,
        ),
      ];

      expect(sources.map((source) => source.type).toSet(), hasLength(4));
      expect(
        sources.take(3).every((source) => source.canCheckForUpdates),
        isTrue,
      );
      expect(sources.last.canCheckForUpdates, isFalse);
      expect(
        sources.every(
          (source) => sources.where(source.hasSameIdentity).length == 1,
        ),
        isTrue,
      );
    });

    test('local and adopted filesystem identities require absolute paths', () {
      expect(
        () => LocalSourceDescriptor(locator: 'relative/source'),
        throwsArgumentError,
      );
      expect(
        () => AdoptedSnapshotSourceDescriptor(
          authoritativeLocation: 'relative/source',
          contentHash: hash,
        ),
        throwsArgumentError,
      );
    });

    test('adopted content identity requires a lowercase SHA-256 digest', () {
      expect(
        () => AdoptedSnapshotSourceDescriptor(
          authoritativeLocation: absolutePath,
          contentHash: 'not-a-digest',
        ),
        throwsArgumentError,
      );
    });
  });
}
