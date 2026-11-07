import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:skills_workspace/src/application/runtime/revision_engine_port.dart';
import 'package:skills_workspace/src/domain/revision_content.dart';
import 'package:skills_workspace/src/native/revision_engine/revision_native_engine.dart';
import 'package:test/test.dart';

void main() {
  test('retention reference values confine names to the private namespace', () {
    final target = RevisionObjectId('1' * 40);

    expect(
      () => RevisionRetentionRef(name: 'refs/heads/main', target: target),
      throwsArgumentError,
    );
    expect(
      () => RevisionRetentionRef(
        name: 'refs/skills-workspace/../heads/main',
        target: target,
      ),
      throwsArgumentError,
    );
  });

  test('loads the pinned libgit2 runtime and shuts down idempotently', () {
    final engine = RevisionNativeEngine.open();

    expect(engine.version(), const RevisionNativeVersion(1, 9, 7));

    engine.close();
    engine.close();
    expect(engine.version, throwsA(_hasCode(RevisionNativeFailureCode.closed)));
  });

  test(
    'creates and verifies a bare root commit through the narrow ABI',
    () async {
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        'skills-workspace-revision-',
      );
      final repositoryPath = '${temporaryDirectory.path}/store.git';
      final content = Uint8List.fromList(
        utf8.encode('# Managed Skill\n\nNative revision smoke gate.\n'),
      );
      final engine = RevisionNativeEngine.open();

      try {
        engine.createStore(repositoryPath);
        engine.verifyStore(repositoryPath);

        final blobOid = engine.createBlob(repositoryPath, content);
        final treeOid = engine.createSingleBlobTree(
          repositoryPath: repositoryPath,
          entryName: 'SKILL.md',
          blobOid: blobOid,
        );
        final commitOid = engine.createRootCommit(
          repositoryPath: repositoryPath,
          treeOid: treeOid,
        );

        expect(blobOid, _isSha1Oid);
        expect(treeOid, _isSha1Oid);
        expect(commitOid, _isSha1Oid);
        engine.verifyRootCommit(
          repositoryPath: repositoryPath,
          commitOid: commitOid,
          entryName: 'SKILL.md',
          expectedBytes: content,
        );
        engine.verifyStore(repositoryPath);
      } finally {
        engine.close();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );

  test(
    'maps verification failures without exposing paths or native text',
    () async {
      const secretPathSegment = 'private-customer-workspace';
      final temporaryDirectory = await Directory.systemTemp.createTemp(
        '$secretPathSegment-',
      );
      final repositoryPath = '${temporaryDirectory.path}/missing.git';
      final engine = RevisionNativeEngine.open();

      try {
        Object? failure;
        try {
          engine.verifyStore(repositoryPath);
        } on Object catch (error) {
          failure = error;
        }

        expect(failure, _hasCode(RevisionNativeFailureCode.repositoryFailure));
        expect(failure.toString(), isNot(contains(secretPathSegment)));
        expect(failure.toString(), isNot(contains(repositoryPath)));
      } finally {
        engine.close();
        await temporaryDirectory.delete(recursive: true);
      }
    },
  );

  test('replaces only derived retention refs as one authoritative set', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'skills-workspace-retention-refs-',
    );
    final repositoryPath = '${temporaryDirectory.path}/store.git';
    final engine = RevisionNativeEngine.open();
    try {
      engine.createStore(repositoryPath);
      final firstTree = engine.writeTree(repositoryPath, _tree('# First\n'));
      final first = engine.createCommit(
        repositoryPath: repositoryPath,
        request: RevisionCommitRequest(
          tree: firstTree,
          parents: const [],
          kind: RevisionCommitKind.initial,
        ),
      );
      final secondTree = engine.writeTree(repositoryPath, _tree('# Second\n'));
      final second = engine.createCommit(
        repositoryPath: repositoryPath,
        request: RevisionCommitRequest(
          tree: secondTree,
          parents: <RevisionObjectId>[first],
          kind: RevisionCommitKind.localPublish,
        ),
      );

      engine.replaceRetentionRefs(
        repositoryPath: repositoryPath,
        references: <RevisionRetentionRef>[
          RevisionRetentionRef(
            name: 'refs/skills-workspace/current/skill/effective',
            target: first,
          ),
          RevisionRetentionRef(
            name: 'refs/skills-workspace/history/operation/subject/after',
            target: first,
          ),
        ],
      );
      expect(
        await _readLooseRef(
          repositoryPath,
          'refs/skills-workspace/current/skill/effective',
        ),
        first.value,
      );

      engine.replaceRetentionRefs(
        repositoryPath: repositoryPath,
        references: <RevisionRetentionRef>[
          RevisionRetentionRef(
            name: 'refs/skills-workspace/current/skill/effective',
            target: second,
          ),
        ],
      );
      expect(
        await _readLooseRef(
          repositoryPath,
          'refs/skills-workspace/current/skill/effective',
        ),
        second.value,
      );
      expect(
        File(
          '$repositoryPath/refs/skills-workspace/history/operation/subject/after',
        ).existsSync(),
        isFalse,
      );

      engine.replaceRetentionRefs(
        repositoryPath: repositoryPath,
        references: const <RevisionRetentionRef>[],
      );
      final retentionDirectory = Directory(
        '$repositoryPath/refs/skills-workspace',
      );
      expect(
        retentionDirectory.existsSync()
            ? retentionDirectory
                  .listSync(recursive: true)
                  .whereType<File>()
                  .toList()
            : const <File>[],
        isEmpty,
      );
    } finally {
      engine.close();
      await temporaryDirectory.delete(recursive: true);
    }
  });
}

NormalizedSkillTree _tree(String contents) {
  final bytes = utf8.encode(contents);
  return NormalizedSkillTree(
    files: <NormalizedSkillFile>[
      NormalizedSkillFile(
        relativePath: 'SKILL.md',
        bytes: bytes,
        isExecutable: false,
      ),
    ],
    contentHash: sha256.convert(bytes).toString(),
    byteSize: bytes.length,
  );
}

Future<String> _readLooseRef(String repositoryPath, String name) async =>
    (await File('$repositoryPath/$name').readAsString()).trim();

final _isSha1Oid = matches(RegExp(r'^[0-9a-f]{40}$'));

Matcher _hasCode(RevisionNativeFailureCode code) {
  return isA<RevisionNativeException>().having(
    (error) => error.code,
    'code',
    code,
  );
}
