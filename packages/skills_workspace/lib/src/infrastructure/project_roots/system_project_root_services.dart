import 'package:uuid/uuid.dart';

import '../../application/ports/external_discovery_ports.dart';

final class UuidProjectRootId implements ProjectRootIdPort {
  const UuidProjectRootId({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  @override
  String allocate(Set<String> reservedIds) {
    for (var attempt = 0; attempt < 100; attempt += 1) {
      final id = 'project-${_uuid.v4()}';
      if (!reservedIds.contains(id)) {
        return id;
      }
    }
    throw StateError('Unable to allocate a unique Project Root ID.');
  }
}

final class SystemWorkspaceClock implements WorkspaceClockPort {
  const SystemWorkspaceClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
