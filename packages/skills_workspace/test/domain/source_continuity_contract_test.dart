import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  group('Source continuity uses only exact stable selection identity', () {
    final existing = LocalSourceDescriptor(
      locator: '/sources/catalog',
      skillPath: 'skills/review',
    );

    test('rejects a similar declared-name path', () {
      final similarName = LocalSourceDescriptor(
        locator: '/sources/catalog',
        skillPath: 'skills/reviewer',
      );

      expect(similarName.hasSameIdentity(existing), isFalse);
    });

    test('content hash similarity cannot establish continuity', () {
      final sameBytesElsewhere = AdoptedSnapshotSourceDescriptor(
        authoritativeLocation: '/agents/skills/review-copy',
        contentHash: 'a' * 64,
      );
      final originalBytes = AdoptedSnapshotSourceDescriptor(
        authoritativeLocation: '/agents/skills/review',
        contentHash: 'a' * 64,
      );

      expect(sameBytesElsewhere.hasSameIdentity(originalBytes), isFalse);
    });

    test('rejects an unrelated source locator', () {
      final unrelated = LocalSourceDescriptor(
        locator: '/other/catalog',
        skillPath: 'skills/review',
      );

      expect(unrelated.hasSameIdentity(existing), isFalse);
    });

    test('Git path rename heuristics alone cannot establish continuity', () {
      final before = GitSourceDescriptor(
        locator: 'https://example.test/catalog.git',
        ref: 'main',
        repositorySubpath: 'skills',
        skillPath: 'review',
      );
      final renamed = GitSourceDescriptor(
        locator: 'https://example.test/catalog.git',
        ref: 'main',
        repositorySubpath: 'skills',
        skillPath: 'review-renamed',
      );

      expect(renamed.hasSameIdentity(before), isFalse);
    });

    test('accepts only the exact persisted selection', () {
      final exact = LocalSourceDescriptor(
        locator: '/sources/catalog',
        skillPath: 'skills/review',
      );

      expect(exact.hasSameIdentity(existing), isTrue);
    });
  });
}
