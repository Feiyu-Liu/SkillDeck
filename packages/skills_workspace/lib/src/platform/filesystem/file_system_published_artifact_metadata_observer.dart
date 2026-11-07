import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as paths;

import '../../application/ports/published_artifact_ports.dart';
import '../../domain/cancellation.dart';
import 'filesystem_primitives.dart';
import 'posix_filesystem_primitives.dart';
import 'windows_filesystem_primitives.dart';

/// Captures bounded, no-follow metadata for restore-only wrong entry types.
///
/// Evidence includes native physical identity and metadata for every visited
/// entry. More than 4096 entries, unreadable entries, races, and cancellation
/// fail closed rather than producing partial evidence.
final class FileSystemPublishedArtifactMetadataObserver
    implements PublishedArtifactMetadataObserverPort {
  const FileSystemPublishedArtifactMetadataObserver({
    FilesystemPrimitives? primitives,
  }) : _primitives = primitives;

  static const _maximumMetadataEntries = 4096;
  final FilesystemPrimitives? _primitives;
  FilesystemPrimitives get _filesystemPrimitives =>
      _primitives ??
      (Platform.isWindows
          ? const WindowsFilesystemPrimitives()
          : const PosixFilesystemPrimitives());

  @override
  Future<PublishedArtifactInspection> observeMetadata({
    required String path,
    required CancellationToken cancellationToken,
  }) async {
    ObservedEntryKind? kind;
    try {
      if (cancellationToken.isCancelled) return _unsafe();
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return _missing;
      kind = _kind(type);
      if (kind == ObservedEntryKind.other) return _unsafe(kind);
      final records = <String>[];
      var containsLinks = false;
      Future<void> collect(String entryPath) async {
        if (cancellationToken.isCancelled ||
            records.length >= _maximumMetadataEntries) {
          throw const _MetadataUnavailable();
        }
        final before = await _filesystemPrimitives.stat(
          entryPath,
          followLinks: false,
        );
        if (before.kind == FilesystemEntryKind.other) {
          throw const _MetadataUnavailable();
        }
        final stat = before.kind == FilesystemEntryKind.symbolicLink
            ? null
            : await FileStat.stat(entryPath);
        final target = before.kind == FilesystemEntryKind.symbolicLink
            ? await Link(entryPath).target()
            : null;
        containsLinks = containsLinks || target != null;
        records.add(
          jsonEncode([
            paths.relative(entryPath, from: path),
            before.kind.name,
            before.physicalKey,
            before.posixMode,
            stat?.size,
            stat?.modified.toUtc().microsecondsSinceEpoch,
            stat?.changed.toUtc().microsecondsSinceEpoch,
            stat?.mode,
            target,
          ]),
        );
        if (before.kind == FilesystemEntryKind.directory) {
          await for (final child in Directory(
            entryPath,
          ).list(followLinks: false)) {
            await collect(child.path);
          }
        }
        final after = await _filesystemPrimitives.stat(
          entryPath,
          followLinks: false,
        );
        if (after.kind != before.kind ||
            after.physicalKey != before.physicalKey ||
            after.posixMode != before.posixMode) {
          throw const _MetadataUnavailable();
        }
        if (stat != null) {
          final afterStat = await FileStat.stat(entryPath);
          if (stat.type != afterStat.type ||
              stat.size != afterStat.size ||
              stat.modified != afterStat.modified ||
              stat.changed != afterStat.changed ||
              stat.mode != afterStat.mode) {
            throw const _MetadataUnavailable();
          }
        } else if (await Link(entryPath).target() != target) {
          throw const _MetadataUnavailable();
        }
      }

      await collect(path);
      if (cancellationToken.isCancelled) return _unsafe(kind);
      records.sort();
      return PublishedArtifactInspection(
        state: PublishedArtifactState.matching,
        observedEntryKind: kind,
        metadataFingerprint: sha256
            .convert(utf8.encode(jsonEncode(records)))
            .toString(),
        containsSymbolicLinks: containsLinks,
      );
    } on FileSystemException {
      return _unsafe(kind);
    } on _MetadataUnavailable {
      return _unsafe(kind);
    }
  }
}

const _missing = PublishedArtifactInspection(
  state: PublishedArtifactState.missing,
);

final class _MetadataUnavailable implements Exception {
  const _MetadataUnavailable();
}

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
