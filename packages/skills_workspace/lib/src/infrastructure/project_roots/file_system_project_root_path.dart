import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/ports/external_discovery_ports.dart';

final class FileSystemProjectRootPath implements ProjectRootPathPort {
  const FileSystemProjectRootPath();

  @override
  Future<String?> canonicalizeExistingDirectory(String candidatePath) async {
    if (!path.isAbsolute(candidatePath) || path.isRootRelative(candidatePath)) {
      return null;
    }
    final normalized = path.normalize(candidatePath);
    try {
      if (await FileSystemEntity.type(normalized, followLinks: true) !=
          FileSystemEntityType.directory) {
        return null;
      }
      return path.normalize(await Directory(normalized).resolveSymbolicLinks());
    } on FileSystemException {
      return null;
    }
  }
}
