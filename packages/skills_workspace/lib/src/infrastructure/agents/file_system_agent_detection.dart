import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../application/ports/agent_activation_ports.dart';
import '../../domain/public_models.dart';

final class FileSystemAgentDetection implements AgentDetectionPort {
  const FileSystemAgentDetection();

  @override
  Future<bool> matches(
    AgentDetectionPath detection, {
    ProjectRoot? projectRoot,
  }) async {
    if (detection.relativeToProject && projectRoot == null) {
      return false;
    }
    final targetPath = detection.relativeToProject
        ? path.join(projectRoot!.path, detection.path)
        : detection.path;
    if (detection.kind == AgentDetectionKind.pathExists) {
      return await FileSystemEntity.type(targetPath, followLinks: true) !=
          FileSystemEntityType.notFound;
    }

    try {
      final decoded = jsonDecode(await File(targetPath).readAsString());
      if (decoded is! Map<String, Object?>) {
        return false;
      }
      for (final section in const <String>['dependencies', 'devDependencies']) {
        final dependencies = decoded[section];
        if (dependencies is Map<String, Object?> &&
            dependencies.containsKey(detection.dependencyName)) {
          return true;
        }
      }
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
    return false;
  }
}
