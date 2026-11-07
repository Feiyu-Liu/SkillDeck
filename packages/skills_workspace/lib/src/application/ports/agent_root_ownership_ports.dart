enum AgentRootEntryType { file, directory, symbolicLink, other }

final class AgentRootEntryMetadata {
  const AgentRootEntryMetadata({required this.type, required this.ownerUserId});

  final AgentRootEntryType type;
  final int ownerUserId;
}

abstract interface class AgentRootOwnershipInspectionPort {
  bool get supported;

  int currentUserId();

  Future<AgentRootEntryMetadata?> inspect(String path);

  Stream<String> descendants(String rootPath);

  Future<String> physicalDirectoryPath(String path);
}
