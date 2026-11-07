import 'dart:io';

import '../../application/ports/agent_activation_ports.dart';
import '../filesystem/workspace_path_identity.dart';

final class WorkspaceActivationLocationIdentity
    implements ActivationLocationIdentityPort {
  const WorkspaceActivationLocationIdentity(this._resolver);

  final WorkspacePathIdentityResolver _resolver;

  @override
  String normalize(String location) => _resolver.normalize(location);

  @override
  String key(String location) => _resolver.lexicalKey(location);

  @override
  Future<bool> sameExistingObject(String left, String right) async {
    try {
      return await _resolver.sameObject(left, right, followLinks: false);
    } on Object {
      return false;
    }
  }

  @override
  Future<String?> resolveExistingDirectory(String location) async {
    try {
      final resolved = await Directory(
        _resolver.normalize(location),
      ).resolveSymbolicLinks();
      if (await FileSystemEntity.type(resolved, followLinks: false) !=
          FileSystemEntityType.directory) {
        return null;
      }
      return _resolver.normalize(resolved);
    } on Object {
      return null;
    }
  }
}
