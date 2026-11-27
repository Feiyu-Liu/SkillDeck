/// Local mapping and observation cursors only; never an operation outbox.
abstract interface class SyncStateStore {
  Future<List<SyncLink>> links();
  Future<void> put(SyncLink link);
  Future<void> unlink(String managedSkillId);
  Future<String?> feedCursor();
  Future<void> setFeedCursor(String? cursor);
  Future<String?> workspaceCursor();
  Future<void> setWorkspaceCursor(String cursor);
  Future<Set<String>> exclusions();
  Future<void> setExcluded(String lineageId, bool excluded);
}

final class SyncLink {
  const SyncLink({
    required this.managedSkillId,
    this.lineageId,
    this.clientKey,
    this.version = 0,
    this.generation = 1,
    this.effective,
  });
  final String managedSkillId;
  final String? lineageId, clientKey, effective;
  final int version, generation;
}

/// One account/device scope. The App must supply a different store when accounts change.
final class InMemorySyncStateStore implements SyncStateStore {
  final _links = <String, SyncLink>{};
  final _excluded = <String>{};
  String? _feed, _workspace;
  @override
  Future<List<SyncLink>> links() async => List.unmodifiable(_links.values);
  @override
  Future<void> put(SyncLink link) async {
    _links[link.managedSkillId] = link;
  }

  @override
  Future<void> unlink(String managedSkillId) async {
    _links.remove(managedSkillId);
  }

  @override
  Future<String?> feedCursor() async => _feed;
  @override
  Future<void> setFeedCursor(String? cursor) async {
    _feed = cursor;
  }

  @override
  Future<String?> workspaceCursor() async => _workspace;
  @override
  Future<void> setWorkspaceCursor(String cursor) async {
    _workspace = cursor;
  }

  @override
  Future<Set<String>> exclusions() async => Set.unmodifiable(_excluded);
  @override
  Future<void> setExcluded(String lineageId, bool excluded) async {
    if (excluded) {
      _excluded.add(lineageId);
    } else {
      _excluded.remove(lineageId);
    }
  }
}
