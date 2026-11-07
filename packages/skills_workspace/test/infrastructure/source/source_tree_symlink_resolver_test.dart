import 'dart:convert';

import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/infrastructure/source/source_result.dart';
import 'package:skills_workspace/src/infrastructure/source/source_tree_symlink_resolver.dart';
import 'package:test/test.dart';

void main() {
  test('retains final directory identity across intermediate links', () {
    final result = const SourceTreeSymlinkResolver().resolveWithOrigins([
      SourceTreeEntry.file(
        path: 'skills/demo/SKILL.md',
        bytes: utf8.encode('skill'),
      ),
      SourceTreeEntry.symbolicLink(
        path: 'bridge',
        targetBytes: utf8.encode('skills'),
      ),
      SourceTreeEntry.symbolicLink(
        path: 'plugins/demo',
        targetBytes: utf8.encode('../bridge/demo'),
      ),
      SourceTreeEntry.symbolicLink(
        path: 'document.md',
        targetBytes: utf8.encode('skills/demo/SKILL.md'),
      ),
    ]);
    expect(result.failureOrNull, isNull);
    expect(
      result.valueOrNull!.canonicalDirectory('plugins/demo'),
      'skills/demo',
    );
    expect(
      result.valueOrNull!.canonicalDirectory('bridge/demo'),
      'skills/demo',
    );
    expect(
      result.valueOrNull!.canonicalDirectory('document.md'),
      'document.md',
    );
  });

  test('dereferences file, chained, and directory symbolic links', () {
    final executable = SourceTreeEntry.file(
      path: 'assets/run.sh',
      bytes: utf8.encode('#!/bin/sh\n'),
      isExecutable: true,
    );
    final result = const SourceTreeSymlinkResolver().resolve([
      SourceTreeEntry.file(path: 'SKILL.md', bytes: utf8.encode('skill')),
      SourceTreeEntry.directory(path: 'assets'),
      executable,
      SourceTreeEntry.symbolicLink(
        path: 'links/readme.md',
        targetBytes: utf8.encode('../SKILL.md'),
      ),
      SourceTreeEntry.symbolicLink(
        path: 'README.md',
        targetBytes: utf8.encode('links/readme.md'),
      ),
      SourceTreeEntry.symbolicLink(
        path: 'bin',
        targetBytes: utf8.encode('assets'),
      ),
    ]);

    expect(result, isA<SourceSuccess>());
    final files = _files(result.valueOrNull!);
    expect(files.keys, [
      'README.md',
      'SKILL.md',
      'assets/run.sh',
      'bin/run.sh',
      'links/readme.md',
    ]);
    expect(utf8.decode(files['README.md']!.bytes), 'skill');
    expect(files['bin/run.sh']!.isExecutable, isTrue);
  });

  for (final fixture in <({String name, List<SourceTreeEntry> entries})>[
    (
      name: 'escaping',
      entries: [
        SourceTreeEntry.symbolicLink(
          path: 'alias',
          targetBytes: utf8.encode('../outside'),
        ),
      ],
    ),
    (
      name: 'cyclic',
      entries: [
        SourceTreeEntry.symbolicLink(path: 'a', targetBytes: utf8.encode('b')),
        SourceTreeEntry.symbolicLink(path: 'b', targetBytes: utf8.encode('a')),
      ],
    ),
    (
      name: 'unresolved',
      entries: [
        SourceTreeEntry.symbolicLink(
          path: 'alias',
          targetBytes: utf8.encode('missing'),
        ),
      ],
    ),
  ]) {
    test('rejects ${fixture.name} symbolic links', () {
      final result = const SourceTreeSymlinkResolver().resolve(fixture.entries);

      expect(result.failureOrNull?.code, SourceFailureCode.contentInvalid);
      expect(result.failureOrNull?.context['reason'], switch (fixture.name) {
        'escaping' => 'symbolicLinkEscapesSource',
        'cyclic' => 'symbolicLinkCycle',
        _ => 'symbolicLinkUnresolved',
      });
    });
  }

  test('rejects collisions introduced by link dereferencing', () {
    final result = const SourceTreeSymlinkResolver().resolve([
      SourceTreeEntry.file(path: 'readme.md', bytes: utf8.encode('one')),
      SourceTreeEntry.file(path: 'target.md', bytes: utf8.encode('two')),
      SourceTreeEntry.symbolicLink(
        path: 'README.md',
        targetBytes: utf8.encode('target.md'),
      ),
    ]);

    expect(result.failureOrNull?.code, SourceFailureCode.contentInvalid);
    expect(result.failureOrNull?.context['reason'], 'portablePathCollision');
  });

  test('rejects the same source entry instance listed twice', () {
    final duplicated = SourceTreeEntry.file(
      path: 'SKILL.md',
      bytes: utf8.encode('skill'),
    );

    final result = const SourceTreeSymlinkResolver().resolve([
      duplicated,
      duplicated,
    ]);

    expect(result.failureOrNull?.code, SourceFailureCode.contentInvalid);
    expect(result.failureOrNull?.context['reason'], 'duplicateSourcePath');
  });

  test('counts directory-link expansion against normalized limits', () {
    final result =
        const SourceTreeSymlinkResolver(
          maximumFileCount: 2,
          maximumByteSize: 100,
        ).resolve([
          SourceTreeEntry.file(path: 'SKILL.md', bytes: utf8.encode('skill')),
          SourceTreeEntry.file(
            path: 'assets/icon.txt',
            bytes: utf8.encode('x'),
          ),
          SourceTreeEntry.symbolicLink(
            path: 'docs',
            targetBytes: utf8.encode('assets'),
          ),
        ]);

    expect(result.failureOrNull?.code, SourceFailureCode.contentLimitExceeded);
    expect(result.failureOrNull?.context['limit'], 'fileCount');
    expect(result.failureOrNull?.context['actual'], 3);
  });
}

Map<String, SkillContentEntry> _files(List<SkillContentEntry> entries) => {
  for (final entry in entries) utf8.decode(entry.pathBytes): entry,
};
