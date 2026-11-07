import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:skills_workspace/src/platform/filesystem/durable_workspace_filesystem.dart';
import 'package:skills_workspace/src/platform/filesystem/filesystem_primitives.dart';
import 'package:skills_workspace/src/platform/filesystem/workspace_path_identity.dart';
import 'package:test/test.dart';

void main() {
  test(
    'Windows lexical identity normalizes separators, case, and dot segments',
    () {
      final resolver = WorkspacePathIdentityResolver(
        primitives: const _UnusedPrimitives(),
        flavor: WorkspacePathFlavor.windows,
      );

      expect(
        resolver.lexicallyEquals(
          r'C:/Users/Alice/../BOB/Skills/.',
          r'c:\users\bob\skills',
        ),
        isTrue,
      );
      expect(resolver.lexicallyEquals(r'C:\skills', r'D:\skills'), isFalse);
      expect(
        resolver.lexicallyEquals(
          r'\\SERVER\Share\Skills\.',
          r'//server/share/skills',
        ),
        isTrue,
      );
    },
  );

  test('POSIX lexical identity remains case-sensitive', () {
    final resolver = WorkspacePathIdentityResolver(
      primitives: const _UnusedPrimitives(),
      flavor: WorkspacePathFlavor.posix,
    );

    expect(resolver.lexicallyEquals('/tmp/Skills', '/tmp/skills'), isFalse);
    expect(resolver.lexicallyEquals('/tmp/a/../skills', '/tmp/skills'), isTrue);
  });

  test('physical identity recognizes a symbolic-link alias', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'skills-workspace-path-identity-',
    );
    final filesystem = PlatformDurableWorkspaceFilesystem();
    addTearDown(() async {
      if (!await temporary.exists()) {
        return;
      }
      await for (final entity in temporary.list(followLinks: false)) {
        await filesystem.removeOwnedPath(
          targetPath: entity.path,
          ownerRoot: temporary.path,
        );
      }
      await temporary.delete();
    });
    final target = Directory(path.join(temporary.path, 'target'));
    await target.create();
    final alias = Link(path.join(temporary.path, 'alias'));
    try {
      await alias.create(target.path);
    } on FileSystemException {
      markTestSkipped('Symbolic links are unavailable at this location.');
      return;
    }

    final targetIdentity = await filesystem.pathIdentity(target.path);
    final aliasIdentity = await filesystem.pathIdentity(alias.path);
    final linkIdentity = await filesystem.pathIdentity(
      alias.path,
      followLinks: false,
    );

    expect(aliasIdentity.sameObjectAs(targetIdentity), isTrue);
    expect(linkIdentity.sameObjectAs(targetIdentity), isFalse);
    expect(linkIdentity.metadata.kind, FilesystemEntryKind.symbolicLink);
  });

  test('rejects empty paths as caller errors', () {
    final resolver = WorkspacePathIdentityResolver(
      primitives: const _UnusedPrimitives(),
    );

    expect(() => resolver.normalize(''), throwsArgumentError);
  });
}

final class _UnusedPrimitives implements FilesystemPrimitives {
  const _UnusedPrimitives();

  Never _unused() => throw UnsupportedError('not used by lexical tests');

  @override
  Future<void> writeNewFile(String path, List<int> bytes) async => _unused();

  @override
  Future<void> applyPosixMode(String path, int mode) async => _unused();

  @override
  Future<void> applyReadOnly(String path, bool readOnly) async => _unused();

  @override
  Future<bool?> captureReadOnly(String path) async => _unused();

  @override
  Future<bool> exchangeSameParent({
    required String parentPath,
    required String firstName,
    required String secondName,
  }) async => _unused();

  @override
  Future<void> flushDirectory(String path) async => _unused();

  @override
  Future<void> flushFile(String path) async => _unused();

  @override
  Future<void> renameSameParent({
    required String parentPath,
    required String sourceName,
    required String destinationName,
    required bool replaceExisting,
  }) async => _unused();

  @override
  Future<FilesystemPathMetadata> stat(
    String path, {
    required bool followLinks,
  }) async => _unused();
}
