import 'dart:convert';

import 'package:skills_workspace/src/application/ports/draft_snapshot_ports.dart';
import 'package:skills_workspace/src/domain/draft_snapshot.dart';
import 'package:skills_workspace/src/infrastructure/content/draft_content_adapter.dart';
import 'package:test/test.dart';

void main() {
  const adapter = NormalizedDraftContentAdapter();

  test('normalizes captured bytes and reads the Declared Skill Name', () async {
    final result = await adapter.normalize(<CapturedDraftFile>[
      CapturedDraftFile(
        relativePath: 'SKILL.md',
        bytes: utf8.encode('''---
name: example-skill
description: Example
---
# Example
'''),
        isExecutable: false,
      ),
      CapturedDraftFile(
        relativePath: 'scripts/run.sh',
        bytes: utf8.encode('#!/bin/sh\n'),
        isExecutable: true,
      ),
    ]);

    expect(result.failureOrNull, isNull);
    expect(
      await adapter.readDeclaredName(result.valueOrNull!),
      'example-skill',
    );
    expect(result.valueOrNull!.files.last.isExecutable, isTrue);
  });

  test('maps portable path violations to invalid Skill', () async {
    final result = await adapter.normalize(<CapturedDraftFile>[
      CapturedDraftFile(
        relativePath: r'folder\file.md',
        bytes: const <int>[1],
        isExecutable: false,
      ),
      CapturedDraftFile(
        relativePath: 'folder/file.md',
        bytes: const <int>[2],
        isExecutable: false,
      ),
    ]);

    expect(result.failureOrNull!.code, DraftSnapshotFailureCode.invalidSkill);
  });

  test('invalid UTF-8 SKILL.md has no Declared Skill Name', () async {
    final result = await adapter.normalize(<CapturedDraftFile>[
      CapturedDraftFile(
        relativePath: 'SKILL.md',
        bytes: const <int>[0xff],
        isExecutable: false,
      ),
    ]);

    expect(result.failureOrNull, isNull);
    expect(await adapter.readDeclaredName(result.valueOrNull!), isNull);
  });
}
