import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/ports/agent_activation_ports.dart';

final class FileSystemSymbolicLinkCapability
    implements SymbolicLinkCapabilityPort {
  const FileSystemSymbolicLinkCapability();

  @override
  Future<bool> supportsSymbolicLinks(String targetLocation) async {
    final probeParent = await _nearestExistingDirectory(targetLocation);
    if (probeParent == null) {
      return false;
    }
    Directory? probeRoot;
    try {
      probeRoot = await Directory(
        probeParent,
      ).createTemp('.skills-workspace-link-probe-$pid-');
      final target = Directory(path.join(probeRoot.path, 'target'));
      await target.create();
      final sentinel = File(path.join(target.path, 'sentinel'));
      await sentinel.writeAsString('skills-workspace-link-probe');
      final link = Link(path.join(probeRoot.path, 'link'));
      await link.create(target.path);
      if (await FileSystemEntity.type(link.path, followLinks: false) !=
          FileSystemEntityType.link) {
        return false;
      }
      return await File(
            path.join(link.path, path.basename(sentinel.path)),
          ).readAsString() ==
          'skills-workspace-link-probe';
    } on FileSystemException {
      return false;
    } finally {
      try {
        if (probeRoot != null && await probeRoot.exists()) {
          await probeRoot.delete(recursive: true);
        }
      } on FileSystemException {
        // Capability detection is independent from best-effort cleanup.
      }
    }
  }
}

Future<String?> _nearestExistingDirectory(String targetPath) async {
  var candidate = path.normalize(path.absolute(targetPath));
  while (true) {
    if (await FileSystemEntity.type(candidate, followLinks: true) ==
        FileSystemEntityType.directory) {
      return candidate;
    }
    final parent = path.dirname(candidate);
    if (parent == candidate) {
      return null;
    }
    candidate = parent;
  }
}
