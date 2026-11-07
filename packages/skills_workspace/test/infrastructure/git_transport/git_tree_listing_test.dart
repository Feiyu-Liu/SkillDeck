import 'dart:convert';

import 'package:skills_workspace/src/infrastructure/git_transport/git_source_transport.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_transport_result.dart';
import 'package:skills_workspace/src/infrastructure/git_transport/git_tree_listing.dart';
import 'package:test/test.dart';

const _oidA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _oidB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

List<int> _record(String mode, String type, String oid, List<int> path) => [
  ...ascii.encode('$mode $type $oid\t'),
  ...path,
  0,
];

List<int> _utf8Record(String mode, String type, String oid, String path) =>
    _record(mode, type, oid, utf8.encode(path));

String? _reason<T>(GitTransportResult<T> result) =>
    result.failureOrNull?.context['reason'] as String?;

void main() {
  test(
    'the repository bound accepts 50000 entries and rejects entry 50001',
    () {
      final records = <int>[
        for (var i = 0; i < maximumGitRepositoryEntryCount; i++)
          ..._utf8Record('100644', 'blob', _oidA, 'file$i'),
      ];
      expect(
        parseGitTreeListing(
          records,
          repositorySubpath: '',
          maximumRepositoryEntryCount: maximumGitRepositoryEntryCount,
        ).valueOrNull,
        hasLength(50000),
      );
      final result = parseGitTreeListing(
        [...records, ..._utf8Record('160000', 'commit', _oidB, 'vendor')],
        repositorySubpath: '',
        maximumRepositoryEntryCount: maximumGitRepositoryEntryCount,
      );
      expect(result.failureOrNull?.context, {
        'reason': 'repositoryEntryLimitExceeded',
        'actual': 50001,
        'actualIsLowerBound': true,
        'maximumRepositoryEntryCount': 50000,
      });
    },
  );

  test('maps regular, executable, and link entries in repository order', () {
    final result = parseGitTreeListing(
      [
        ..._utf8Record('120000', 'blob', _oidB, 'skill/link'),
        ..._utf8Record('100755', 'blob', _oidA, 'skill/run.sh'),
        ..._utf8Record('100644', 'blob', _oidA, 'skill/SKILL.md'),
      ],
      repositorySubpath: 'skill',
      maximumRepositoryEntryCount: 10,
    );

    final entries = result.valueOrNull!;
    expect(entries.map((entry) => entry.relativePath), [
      'skill/SKILL.md',
      'skill/link',
      'skill/run.sh',
    ]);
    expect(entries[0].kind, GitTreeEntryKind.blob);
    expect(entries[0].executable, isFalse);
    expect(entries[1].kind, GitTreeEntryKind.symbolicLink);
    expect(entries[2].executable, isTrue);
  });

  test('accepts a selection that names a link itself', () {
    final result = parseGitTreeListing(
      _utf8Record('120000', 'blob', _oidB, 'skill/link'),
      repositorySubpath: 'skill/link',
      maximumRepositoryEntryCount: 10,
    );
    expect(result.valueOrNull!.single.relativePath, 'skill/link');
  });

  test('accepts an empty listing', () {
    final result = parseGitTreeListing(
      const [],
      repositorySubpath: '',
      maximumRepositoryEntryCount: 1,
    );
    expect(result.valueOrNull, isEmpty);
  });

  test('retains gitlinks and rejects unsupported entries', () {
    expect(
      parseGitTreeListing(
        _utf8Record('160000', 'commit', _oidA, 'vendor'),
        repositorySubpath: '',
        maximumRepositoryEntryCount: 10,
      ).valueOrNull!.single.kind,
      GitTreeEntryKind.gitlink,
    );
    expect(
      _reason(
        parseGitTreeListing(
          _utf8Record('100664', 'blob', _oidA, 'odd'),
          repositorySubpath: '',
          maximumRepositoryEntryCount: 10,
        ),
      ),
      'unsupportedTreeEntry',
    );
  });

  test('rejects malformed and out-of-selection records', () {
    final cases = <List<int>, String>{
      ascii.encode('100644 blob $_oidA\tunterminated'): 'missingTreeTerminator',
      [...ascii.encode('100644 blob $_oidA no-tab'), 0]: 'invalidTreeRecord',
      _utf8Record('100644', 'blob', 'not-an-oid', 'a'): 'invalidTreeRecord',
      _record('100644', 'blob', _oidA, [0xff, 0xfe]): 'treePathNotUtf8',
      _utf8Record('100644', 'blob', _oidA, 'other/file'):
          'treePathOutsideSelection',
      _utf8Record('100644', 'blob', _oidA, 'skills/file'):
          'treePathOutsideSelection',
    };
    for (final MapEntry(key: bytes, value: reason) in cases.entries) {
      final result = parseGitTreeListing(
        bytes,
        repositorySubpath: 'skill',
        maximumRepositoryEntryCount: 10,
      );
      expect(result.failureOrNull?.code, GitTransportFailureCode.invalidOutput);
      expect(_reason(result), reason);
    }
  });

  test('rejects listings above the file-count bound', () {
    final result = parseGitTreeListing(
      [
        ..._utf8Record('100644', 'blob', _oidA, 'a'),
        ..._utf8Record('100644', 'blob', _oidA, 'b'),
      ],
      repositorySubpath: '',
      maximumRepositoryEntryCount: 1,
    );
    expect(_reason(result), 'repositoryEntryLimitExceeded');
    expect(result.failureOrNull!.context['actual'], 2);
  });

  test('recognizes full SHA-1 and SHA-256 object IDs only', () {
    expect(isGitObjectId(_oidA), isTrue);
    expect(isGitObjectId('c' * 64), isTrue);
    expect(isGitObjectId(_oidA.toUpperCase()), isFalse);
    expect(isGitObjectId('abc'), isFalse);
  });
}
