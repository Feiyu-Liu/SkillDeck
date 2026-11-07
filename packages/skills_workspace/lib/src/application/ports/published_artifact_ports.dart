import '../../domain/cancellation.dart';

enum PublishedArtifactState { missing, matching, mismatching, unsafe }

enum PublishedArtifactMismatchKind {
  contentChanged,
  wrongEntryType,
  wrongLinkTarget,
}

enum ObservedEntryKind { directory, symbolicLink, file, other }

final class PublishedArtifactInspection {
  const PublishedArtifactInspection({
    required this.state,
    this.fileCount = 0,
    this.byteSize = 0,
    this.mismatchKind,
    this.observedEntryKind,
    this.fingerprint,
    this.metadataFingerprint,
    this.containsSymbolicLinks = false,
  });

  final PublishedArtifactState state;
  final int fileCount;
  final int byteSize;
  final PublishedArtifactMismatchKind? mismatchKind;
  final ObservedEntryKind? observedEntryKind;
  final String? fingerprint;

  /// Bounded, no-follow entry metadata used for restore-only wrong types.
  final String? metadataFingerprint;
  final bool containsSymbolicLinks;

  bool get needsRepair =>
      state == PublishedArtifactState.missing ||
      state == PublishedArtifactState.mismatching;
}

abstract interface class PublishedArtifactMetadataObserverPort {
  Future<PublishedArtifactInspection> observeMetadata({
    required String path,
    required CancellationToken cancellationToken,
  });
}

abstract interface class PublishedArtifactInspectorPort
    implements PublishedArtifactMetadataObserverPort {
  /// Observes an entry without following symbolic links or selecting its role.
  Future<PublishedArtifactInspection> observe({
    required String path,
    required CancellationToken cancellationToken,
  });

  Future<PublishedArtifactInspection> inspectDirectory({
    required String path,
    required String expectedContentHash,
    required CancellationToken cancellationToken,
  });

  Future<PublishedArtifactInspection> inspectSymbolicLink({
    required String path,
    required String expectedTarget,
    required CancellationToken cancellationToken,
  });
}
