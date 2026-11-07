import 'dart:io';

import 'package:posix/posix.dart' as posix;

import '../../application/ports/agent_root_ownership_ports.dart';

final class PlatformAgentRootOwnershipInspection
    implements AgentRootOwnershipInspectionPort {
  const PlatformAgentRootOwnershipInspection();

  @override
  bool get supported => Platform.isMacOS;

  @override
  int currentUserId() {
    _requireSupported();
    return posix.getuid();
  }

  @override
  Future<AgentRootEntryMetadata?> inspect(String path) async {
    _requireSupported();
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    final stat = posix.lstat(path);
    return AgentRootEntryMetadata(
      type: switch (type) {
        FileSystemEntityType.file => AgentRootEntryType.file,
        FileSystemEntityType.directory => AgentRootEntryType.directory,
        FileSystemEntityType.link => AgentRootEntryType.symbolicLink,
        _ => AgentRootEntryType.other,
      },
      ownerUserId: stat.uid,
    );
  }

  @override
  Stream<String> descendants(String rootPath) async* {
    _requireSupported();
    await for (final entity in Directory(
      rootPath,
    ).list(recursive: true, followLinks: false)) {
      yield entity.path;
    }
  }

  @override
  Future<String> physicalDirectoryPath(String path) {
    _requireSupported();
    return Directory(path).resolveSymbolicLinks();
  }

  void _requireSupported() {
    if (!supported) {
      throw UnsupportedError(
        'Agent root ownership inspection is currently supported on macOS.',
      );
    }
  }
}
