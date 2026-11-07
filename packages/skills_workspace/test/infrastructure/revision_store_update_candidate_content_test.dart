import 'dart:convert';

import 'package:skills_workspace/src/application/operations/operation_models.dart';
import 'package:skills_workspace/src/application/ports/revision_store_access_ports.dart';
import 'package:skills_workspace/src/application/revision_store/managed_skill_revision_access_gate.dart';
import 'package:skills_workspace/src/application/revision_store/revision_store_access_models.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/cancellation.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/infrastructure/revision_store_update_candidate_content.dart';
import 'package:test/test.dart';

void main() {
  late _Pointers pointers;
  late _RevisionEngine revisions;
  late RevisionStoreUpdateCandidateContent content;

  setUp(() {
    pointers = _Pointers();
    revisions = _RevisionEngine();
    content = RevisionStoreUpdateCandidateContent(
      accessGate: ManagedSkillRevisionAccessGate(),
      storePath: (_) => '/store',
      pointers: pointers,
      revisionEngine: revisions,
    );
  });

  test('projects candidate metadata from immutable SKILL.md bytes', () async {
    final result = await content.readCandidateContent(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      candidateObjectId: _candidate,
      cancellationToken: CancellationToken.none(),
    );

    expect(result?.declaredName, 'Renamed Skill');
    expect(result?.slotKey, 'renamed-skill');
    expect(result?.description, 'Incoming description');
  });

  test('active Source Lineage is revalidated under the gate', () async {
    pointers.sourceLineage = SourceLineageReference('different-lineage');

    final result = await content.readCandidateContent(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      candidateObjectId: _candidate,
      cancellationToken: CancellationToken.none(),
    );

    expect(result, isNull);
    expect(revisions.reads, 0);
  });

  test('invalid or missing frontmatter fails closed', () async {
    revisions.skillDocument = 'not frontmatter';

    final result = await content.readCandidateContent(
      managedSkillId: _skillId,
      sourceLineage: _lineage,
      candidateObjectId: _candidate,
      cancellationToken: CancellationToken.none(),
    );

    expect(result, isNull);
  });
}

final class _Pointers implements RevisionPointerReaderPort {
  SourceLineageReference sourceLineage = _lineage;

  @override
  Future<CurrentEffectiveRevisionSelection?> readCurrentEffective(
    ManagedSkillId managedSkillId,
  ) async => CurrentEffectiveRevisionSelection(
    sourceLineage: sourceLineage,
    objectId: RevisionObjectId('2' * 40),
  );
}

final class _RevisionEngine implements RevisionEnginePort {
  var reads = 0;
  var skillDocument = '''---
name: Renamed Skill
description: Incoming description
---
''';

  @override
  Future<NormalizedSkillTree> readTree(
    String repositoryPath,
    RevisionObjectId commit,
  ) async {
    reads += 1;
    final bytes = utf8.encode(skillDocument);
    return NormalizedSkillTree(
      files: <NormalizedSkillFile>[
        NormalizedSkillFile(
          relativePath: 'SKILL.md',
          bytes: bytes,
          isExecutable: false,
        ),
      ],
      contentHash: 'a' * 64,
      byteSize: bytes.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _skillId = ManagedSkillId('123e4567-e89b-42d3-a456-426614174000');
final _lineage = SourceLineageReference('lineage-1');
final _candidate = RevisionObjectId('1' * 40);
