import 'dart:convert';

import 'package:skills_workspace/src/infrastructure/content/content_result.dart';
import 'package:skills_workspace/src/infrastructure/content/normalized_skill_tree.dart';
import 'package:test/test.dart';

void main() {
  const normalizer = SkillContentNormalizer();

  group('path normalization', () {
    test('converts separators and composes Unicode names to NFC', () {
      final result = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(
          path: 'docs\\cafe\u0301.md',
          bytes: utf8.encode('text'),
        ),
      ]);

      expect(result, isA<SkillContentSuccess<NormalizedSkillTree>>());
      expect(result.valueOrNull!.files.single.relativePath, 'docs/café.md');
    });

    test('requires strict UTF-8 paths', () {
      final result = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry(pathBytes: const <int>[0xc3, 0x28], bytes: const []),
      ]);

      expect(
        result.failureOrNull?.code,
        SkillContentFailureCode.invalidContent,
      );
      expect(result.failureOrNull?.context['reason'], 'pathNotUtf8');
    });

    for (final entry in <String, String>{
      '/absolute': 'absolutePath',
      r'C:\absolute': 'absolutePath',
      '../escape': 'pathTraversal',
      'nested/./file': 'pathTraversal',
      'nested//file': 'emptyPathSegment',
      '.GIT/config': 'gitMetadataNotAllowed',
      'aux.txt': 'windowsReservedName',
      'COM¹.log': 'windowsReservedName',
      'trailing.': 'windowsTrailingDotOrSpace',
      'bad<name': 'windowsInvalidCharacter',
    }.entries) {
      test('rejects ${entry.key} as ${entry.value}', () {
        final result = normalizer.normalize(<SkillContentEntry>[
          SkillContentEntry.file(path: entry.key, bytes: const <int>[]),
        ]);

        expect(
          result.failureOrNull?.code,
          SkillContentFailureCode.invalidContent,
        );
        expect(result.failureOrNull?.context['reason'], entry.value);
      });
    }

    test('rejects exact and portable case-fold collisions', () {
      final exact = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'same', bytes: const <int>[1]),
        SkillContentEntry.file(path: 'same', bytes: const <int>[2]),
      ]);
      final portable = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'Kelvin.md', bytes: const <int>[1]),
        SkillContentEntry.file(path: 'kelvin.md', bytes: const <int>[2]),
      ]);

      expect(exact.failureOrNull?.context['reason'], 'duplicatePath');
      expect(
        portable.failureOrNull?.context['reason'],
        'portablePathCollision',
      );
    });

    test('rejects a file that is also another file parent', () {
      final result = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'docs', bytes: const <int>[1]),
        SkillContentEntry.file(path: 'docs/readme.md', bytes: const <int>[2]),
      ]);

      expect(result.failureOrNull?.context['reason'], 'fileDirectoryCollision');
    });
  });

  group('content identity', () {
    test('is input-order independent and preserves binary bytes', () {
      final first = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'z.bin', bytes: const <int>[0, 255]),
        SkillContentEntry.file(path: 'a.md', bytes: const <int>[1, 2]),
      ]);
      final second = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'a.md', bytes: const <int>[1, 2]),
        SkillContentEntry.file(path: 'z.bin', bytes: const <int>[0, 255]),
      ]);

      expect(first.valueOrNull!.contentHash, second.valueOrNull!.contentHash);
      expect(first.valueOrNull!.files.last.bytes, const <int>[0, 255]);
      expect(first.valueOrNull!.byteSize, 4);
    });

    test('path, bytes, and executable intent each affect the hash', () {
      String hash(String path, List<int> bytes, {bool executable = false}) =>
          normalizer
              .normalize(<SkillContentEntry>[
                SkillContentEntry.file(
                  path: path,
                  bytes: bytes,
                  isExecutable: executable,
                ),
              ])
              .valueOrNull!
              .contentHash;

      final baseline = hash('tool', const <int>[1]);
      expect(hash('other', const <int>[1]), isNot(baseline));
      expect(hash('tool', const <int>[2]), isNot(baseline));
      expect(hash('tool', const <int>[1], executable: true), isNot(baseline));
    });

    test('matches the v1 cross-platform golden digest', () {
      final tree = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'SKILL.md', bytes: utf8.encode('# Skill')),
        SkillContentEntry.file(
          path: 'bin/run',
          bytes: const <int>[0, 1, 2, 255],
          isExecutable: true,
        ),
      ]);

      expect(
        tree.valueOrNull!.contentHash,
        'e885feab13df1d118ed05daa1aee8b5e531a6f2f7fdfbc8792d01e37266b440a',
      );
    });

    test('copies caller-owned byte lists', () {
      final bytes = <int>[1, 2, 3];
      final entry = SkillContentEntry.file(path: 'file', bytes: bytes);
      bytes[0] = 9;
      final tree = normalizer.normalize(<SkillContentEntry>[
        entry,
      ]).valueOrNull!;

      expect(tree.files.single.bytes, const <int>[1, 2, 3]);
      expect(() => tree.files.single.bytes[0] = 8, throwsUnsupportedError);
    });
  });

  group('bounds and unsupported entries', () {
    test('enforces file and aggregate byte bounds', () {
      const bounded = SkillContentNormalizer(
        maximumFileCount: 1,
        maximumByteSize: 2,
      );
      final files = bounded.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'a', bytes: const <int>[1]),
        SkillContentEntry.file(path: 'b', bytes: const <int>[2]),
      ]);
      final bytes = bounded.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'a', bytes: const <int>[1, 2, 3]),
      ]);

      expect(files.failureOrNull?.code, SkillContentFailureCode.limitExceeded);
      expect(files.failureOrNull?.context['limit'], 'fileCount');
      expect(bytes.failureOrNull?.context['limit'], 'byteSize');
      expect(maximumNormalizedSkillFileCount, 1000);
      expect(maximumNormalizedSkillByteSize, 50 * 1024 * 1024);
    });

    for (final kind in <SkillContentEntryKind>[
      SkillContentEntryKind.symbolicLink,
      SkillContentEntryKind.gitlink,
    ]) {
      test('fails closed for unresolved $kind', () {
        final result = normalizer.normalize(<SkillContentEntry>[
          SkillContentEntry(
            pathBytes: utf8.encode('entry'),
            bytes: const <int>[],
            kind: kind,
          ),
        ]);

        expect(
          result.failureOrNull?.code,
          SkillContentFailureCode.invalidContent,
        );
      });
    }

    test('honors cancellation before work', () {
      final result = normalizer.normalize(<SkillContentEntry>[
        SkillContentEntry.file(path: 'entry', bytes: const <int>[]),
      ], isCancelled: () => true);

      expect(result.failureOrNull?.code, SkillContentFailureCode.cancelled);
    });
  });
}
