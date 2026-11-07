import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;

import '../../application/ports/published_artifact_ports.dart';
import '../../application/ports/revision_content_worker_ports.dart';
import '../../domain/cancellation.dart';
import 'normalized_skill_tree.dart';

final class FileSystemPublishedArtifactInspector
    implements PublishedArtifactInspectorPort {
  const FileSystemPublishedArtifactInspector({
    required RevisionContentWorkerPort contentWorker,
    required PublishedArtifactMetadataObserverPort metadataObserver,
  }) : _contentWorker = contentWorker,
       _metadataObserver = metadataObserver;

  final RevisionContentWorkerPort _contentWorker;
  final PublishedArtifactMetadataObserverPort _metadataObserver;

  @override
  Future<PublishedArtifactInspection> observeMetadata({
    required String path,
    required CancellationToken cancellationToken,
  }) => _metadataObserver.observeMetadata(
    path: path,
    cancellationToken: cancellationToken,
  );

  @override
  Future<PublishedArtifactInspection> observe({
    required String path,
    required CancellationToken cancellationToken,
  }) async {
    final before = await observeMetadata(
      path: path,
      cancellationToken: cancellationToken,
    );
    if (before.state != PublishedArtifactState.matching) return before;
    final kind = before.observedEntryKind!;
    try {
      String fingerprint;
      var fileCount = 0;
      var byteSize = 0;
      switch (kind) {
        case ObservedEntryKind.directory:
          final result = await _contentWorker.readFilesystemTree(
            path,
            gitMetadataDisposition: GitMetadataDisposition.reject,
            capturePosixExecutableIntent: !Platform.isWindows,
            executableIntentOverrides: const <String, bool>{},
            maximumFileCount: maximumNormalizedSkillFileCount,
            maximumByteSize: maximumNormalizedSkillByteSize,
            isCancelled: () => cancellationToken.isCancelled,
          );
          final tree = result.valueOrNull;
          if (tree == null) return _unsafe(kind);
          fingerprint = tree.contentHash;
          fileCount = tree.fileCount;
          byteSize = tree.byteSize;
        case ObservedEntryKind.symbolicLink:
          final target = await Link(path).target();
          fingerprint = sha256
              .convert(utf8.encode('link\u0000$target'))
              .toString();
        case ObservedEntryKind.file:
          final file = File(path);
          if (await file.length() > maximumNormalizedSkillByteSize) {
            return _unsafe(kind);
          }
          final bytes = BytesBuilder(copy: false);
          await for (final chunk in file.openRead(
            0,
            maximumNormalizedSkillByteSize + 1,
          )) {
            if (cancellationToken.isCancelled ||
                bytes.length + chunk.length > maximumNormalizedSkillByteSize) {
              return _unsafe(kind);
            }
            bytes.add(chunk);
          }
          byteSize = bytes.length;
          fingerprint = sha256
              .convert(
                utf8.encode('file\u0000${sha256.convert(bytes.takeBytes())}'),
              )
              .toString();
          fileCount = 1;
        case ObservedEntryKind.other:
          return _unsafe(kind);
      }
      final after = await observeMetadata(
        path: path,
        cancellationToken: cancellationToken,
      );
      if (after.state != PublishedArtifactState.matching ||
          after.metadataFingerprint != before.metadataFingerprint) {
        return _unsafe(kind);
      }
      return PublishedArtifactInspection(
        state: PublishedArtifactState.matching,
        observedEntryKind: kind,
        fingerprint: fingerprint,
        metadataFingerprint: before.metadataFingerprint,
        containsSymbolicLinks: before.containsSymbolicLinks,
        fileCount: fileCount,
        byteSize: byteSize,
      );
    } on FileSystemException {
      return _unsafe(kind);
    }
  }

  @override
  Future<PublishedArtifactInspection> inspectDirectory({
    required String path,
    required String expectedContentHash,
    required CancellationToken cancellationToken,
  }) async {
    try {
      if (cancellationToken.isCancelled) return _unsafe();
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return _missing;
      if (type != FileSystemEntityType.directory) {
        return _wrongType(_kind(type));
      }
      final result = await _contentWorker.readFilesystemTree(
        path,
        gitMetadataDisposition: GitMetadataDisposition.reject,
        capturePosixExecutableIntent: !Platform.isWindows,
        executableIntentOverrides: const <String, bool>{},
        maximumFileCount: maximumNormalizedSkillFileCount,
        maximumByteSize: maximumNormalizedSkillByteSize,
        isCancelled: () => cancellationToken.isCancelled,
      );
      final tree = result.valueOrNull;
      if (tree == null) return _unsafe(ObservedEntryKind.directory);
      return _withExpectation(
        PublishedArtifactInspection(
          state: PublishedArtifactState.matching,
          observedEntryKind: ObservedEntryKind.directory,
          fingerprint: tree.contentHash,
          fileCount: tree.fileCount,
          byteSize: tree.byteSize,
        ),
        matching: tree.contentHash == expectedContentHash,
        mismatchKind: PublishedArtifactMismatchKind.contentChanged,
      );
    } on FileSystemException {
      return _unsafe();
    }
  }

  @override
  Future<PublishedArtifactInspection> inspectSymbolicLink({
    required String path,
    required String expectedTarget,
    required CancellationToken cancellationToken,
  }) async {
    try {
      if (cancellationToken.isCancelled) return _unsafe();
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return _missing;
      if (type != FileSystemEntityType.link) return _wrongType(_kind(type));
      final rawTarget = await Link(path).target();
      final actualTarget = paths.normalize(
        paths.isAbsolute(rawTarget)
            ? rawTarget
            : paths.join(paths.dirname(path), rawTarget),
      );
      return _withExpectation(
        PublishedArtifactInspection(
          state: PublishedArtifactState.matching,
          observedEntryKind: ObservedEntryKind.symbolicLink,
          fingerprint: sha256
              .convert(utf8.encode('link\u0000$rawTarget'))
              .toString(),
        ),
        matching: paths.equals(
          actualTarget,
          paths.normalize(paths.absolute(expectedTarget)),
        ),
        mismatchKind: PublishedArtifactMismatchKind.wrongLinkTarget,
      );
    } on FileSystemException {
      return _unsafe();
    }
  }
}

const _missing = PublishedArtifactInspection(
  state: PublishedArtifactState.missing,
);

ObservedEntryKind _kind(FileSystemEntityType type) => switch (type) {
  FileSystemEntityType.directory => ObservedEntryKind.directory,
  FileSystemEntityType.link => ObservedEntryKind.symbolicLink,
  FileSystemEntityType.file => ObservedEntryKind.file,
  _ => ObservedEntryKind.other,
};
PublishedArtifactInspection _unsafe([ObservedEntryKind? kind]) =>
    PublishedArtifactInspection(
      state: PublishedArtifactState.unsafe,
      observedEntryKind: kind,
    );
PublishedArtifactInspection _wrongType(ObservedEntryKind kind) =>
    PublishedArtifactInspection(
      state: PublishedArtifactState.mismatching,
      observedEntryKind: kind,
      mismatchKind: PublishedArtifactMismatchKind.wrongEntryType,
    );
PublishedArtifactInspection _withExpectation(
  PublishedArtifactInspection observed, {
  required bool matching,
  required PublishedArtifactMismatchKind mismatchKind,
}) => PublishedArtifactInspection(
  state: matching
      ? PublishedArtifactState.matching
      : PublishedArtifactState.mismatching,
  mismatchKind: matching ? null : mismatchKind,
  observedEntryKind: observed.observedEntryKind,
  fingerprint: observed.fingerprint,
  metadataFingerprint: observed.metadataFingerprint,
  containsSymbolicLinks: observed.containsSymbolicLinks,
  fileCount: observed.fileCount,
  byteSize: observed.byteSize,
);
