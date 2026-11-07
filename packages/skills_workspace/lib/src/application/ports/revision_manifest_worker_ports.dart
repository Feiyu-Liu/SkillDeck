/// Canonical bytes and completion fence created for one large manifest.
final class CanonicalManifestArtifacts {
  CanonicalManifestArtifacts({
    required List<int> manifestBytes,
    required List<int> completionFenceBytes,
  }) : manifestBytes = List<int>.unmodifiable(manifestBytes),
       completionFenceBytes = List<int>.unmodifiable(completionFenceBytes);

  final List<int> manifestBytes;
  final List<int> completionFenceBytes;
}

/// Worker-owned canonical serialization and SHA-256 for large manifests.
abstract interface class RevisionManifestWorkerPort {
  Future<CanonicalManifestArtifacts> encodeCanonicalManifest({
    required Map<String, Object?> value,
    required int schemaVersion,
  });
}
