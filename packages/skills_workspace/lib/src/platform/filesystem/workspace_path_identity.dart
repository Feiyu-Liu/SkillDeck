import 'dart:io';

import 'package:path/path.dart' as path;

import 'filesystem_primitives.dart';

enum WorkspacePathFlavor { posix, windows }

final class WorkspacePathIdentity {
  const WorkspacePathIdentity({
    required this.normalizedPath,
    required this.lexicalKey,
    required this.metadata,
  });

  final String normalizedPath;
  final String lexicalKey;
  final FilesystemPathMetadata metadata;

  String get physicalKey => metadata.physicalKey;

  bool sameObjectAs(WorkspacePathIdentity other) =>
      physicalKey == other.physicalKey;
}

final class WorkspacePathIdentityResolver {
  WorkspacePathIdentityResolver({
    required FilesystemPrimitives primitives,
    WorkspacePathFlavor? flavor,
  }) : _primitives = primitives,
       flavor =
           flavor ??
           (Platform.isWindows
               ? WorkspacePathFlavor.windows
               : WorkspacePathFlavor.posix);

  final FilesystemPrimitives _primitives;
  final WorkspacePathFlavor flavor;

  path.Context get _context =>
      flavor == WorkspacePathFlavor.windows ? path.windows : path.posix;

  String normalize(String targetPath) {
    if (targetPath.isEmpty) {
      throw ArgumentError.value(targetPath, 'targetPath', 'must not be empty');
    }
    final platformPath = flavor == WorkspacePathFlavor.windows
        ? targetPath.replaceAll('/', r'\')
        : targetPath;
    return _context.normalize(_context.absolute(platformPath));
  }

  String lexicalKey(String targetPath) {
    final normalized = normalize(targetPath);
    return flavor == WorkspacePathFlavor.windows
        ? normalized.toUpperCase()
        : normalized;
  }

  bool lexicallyEquals(String left, String right) =>
      lexicalKey(left) == lexicalKey(right);

  Future<WorkspacePathIdentity> resolve(
    String targetPath, {
    bool followLinks = true,
  }) async {
    final normalized = normalize(targetPath);
    final metadata = await _primitives.stat(
      normalized,
      followLinks: followLinks,
    );
    return WorkspacePathIdentity(
      normalizedPath: normalized,
      lexicalKey: lexicalKey(normalized),
      metadata: metadata,
    );
  }

  Future<bool> sameObject(
    String left,
    String right, {
    bool followLinks = true,
  }) async {
    final leftIdentity = await resolve(left, followLinks: followLinks);
    final rightIdentity = await resolve(right, followLinks: followLinks);
    return leftIdentity.sameObjectAs(rightIdentity);
  }
}
