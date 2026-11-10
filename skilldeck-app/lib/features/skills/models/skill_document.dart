final class SkillDocumentEntry {
  const SkillDocumentEntry({
    required this.relativePath,
    required this.name,
    required this.contentHash,
  });

  final String relativePath;
  final String name;

  /// Effective Revision hash returned with the manifest that listed this file.
  ///
  /// A subsequent read must send this value back as its stale-state
  /// precondition. It deliberately belongs to the entry instead of being read
  /// from a newer Snapshot after a user has made a document selection.
  final String contentHash;

  List<String> get pathSegments => relativePath.split('/');

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillDocumentEntry &&
          relativePath == other.relativePath &&
          name == other.name &&
          contentHash == other.contentHash;

  @override
  int get hashCode => Object.hash(relativePath, name, contentHash);
}
