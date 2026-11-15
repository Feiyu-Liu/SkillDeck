import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../domain/revision_transfer.dart';
import '../../application/revision_transfer/revision_transfer_models.dart';
import '../../application/runtime/revision_engine_port.dart';
import '../../domain/source_descriptor.dart';
import '../../domain/public_models.dart';
import '../database/source_descriptor_codec.dart';

CommittedRevisionReference revisionTransferReference(RevisionObjectId oid) =>
    CommittedRevisionReference(
      sha256.convert(utf8.encode('revision:sha1:${oid.value}')).toString(),
    );

final class RevisionTransferHistoryEntry {
  const RevisionTransferHistoryEntry({
    required this.objectId,
    required this.descriptor,
  });
  final RevisionObjectId objectId;
  final CommittedRevisionHistoryDescriptor descriptor;
}

/// Credential-free manifest codec; it never changes lineage or selection.
final class RevisionTransferCodec {
  const RevisionTransferCodec();
  static const maximumBytes = 64 * 1024 * 1024;

  CommittedRevisionBatch encode({
    required WorkspaceIdentity identity,
    required SourceDescriptor source,
    required String slotKey,
    required String contentHash,
    required RevisionObjectId upstream,
    required RevisionObjectId effective,
    required List<RevisionTransferHistoryEntry> history,
    required Uint8List packBytes,
    required Uint8List indexBytes,
  }) {
    if (history.length > 10000 ||
        packBytes.length + indexBytes.length > maximumBytes) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.limitExceeded,
      );
    }
    final encodedSource = const SourceDescriptorCodec().encode(source);
    final manifest = utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'objectFormat': 'sha1',
        'source': {
          'kind': encodedSource.kind,
          'payloadSchemaVersion': encodedSource.payloadSchemaVersion,
          'payload': jsonDecode(encodedSource.payloadJson),
        },
        'slotKey': slotKey,
        'contentHash': contentHash,
        'currentUpstream': upstream.value,
        'currentEffective': effective.value,
        'publishedHistory': [
          for (final item in history)
            {
              'eventFingerprint': item.descriptor.eventFingerprint,
              'revision': item.objectId.value,
              'kind': item.descriptor.kind.name,
              'contentHash': item.descriptor.contentHash,
              'publishedAtMicros': item
                  .descriptor
                  .publishedAt
                  .microsecondsSinceEpoch
                  .toString(),
            },
        ],
      }),
    );
    if (manifest.length > 4 * 1024 * 1024 ||
        manifest.length + packBytes.length + indexBytes.length > maximumBytes) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.limitExceeded,
      );
    }
    return CommittedRevisionBatch(
      identity: identity,
      source: source,
      slotKey: slotKey,
      contentHash: contentHash,
      currentUpstream: revisionTransferReference(upstream),
      currentEffective: revisionTransferReference(effective),
      publishedHistory: history.map((entry) => entry.descriptor).toList(),
      packSha256: sha256.convert(packBytes).toString(),
      indexSha256: sha256.convert(indexBytes).toString(),
      wireManifest: manifest,
      packBytes: packBytes,
      indexBytes: indexBytes,
    );
  }

  CommittedRevisionBatch fromContentManifest({
    required WorkspaceIdentity identity,
    required Uint8List manifest,
    required Uint8List packBytes,
    required Uint8List indexBytes,
  }) {
    if (manifest.length > 4 * 1024 * 1024 ||
        manifest.length + packBytes.length + indexBytes.length > maximumBytes) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.limitExceeded,
      );
    }
    try {
      final map = jsonDecode(utf8.decode(manifest)) as Map<String, Object?>;
      final sourceMap = map['source'] as Map<String, Object?>;
      final source = const SourceDescriptorCodec().decode(
        kind: sourceMap['kind'] as String,
        payloadSchemaVersion: sourceMap['payloadSchemaVersion'] as int,
        payloadJson: jsonEncode(sourceMap['payload']),
      );
      final history = (map['publishedHistory'] as List<Object?>).map((value) {
        final entry = value as Map<String, Object?>;
        return CommittedRevisionHistoryDescriptor(
          eventFingerprint: entry['eventFingerprint'] as String,
          revision: revisionTransferReference(
            RevisionObjectId(entry['revision'] as String),
          ),
          kind: WorkspaceOperationKind.values.byName(entry['kind'] as String),
          contentHash: entry['contentHash'] as String,
          publishedAt: DateTime.fromMicrosecondsSinceEpoch(
            _micros(entry['publishedAtMicros']),
            isUtc: true,
          ),
        );
      }).toList();
      final batch = CommittedRevisionBatch(
        identity: identity,
        source: source,
        slotKey: map['slotKey'] as String,
        contentHash: map['contentHash'] as String,
        currentUpstream: revisionTransferReference(
          RevisionObjectId(map['currentUpstream'] as String),
        ),
        currentEffective: revisionTransferReference(
          RevisionObjectId(map['currentEffective'] as String),
        ),
        publishedHistory: history,
        wireManifest: manifest,
        packBytes: packBytes,
        indexBytes: indexBytes,
        packSha256: sha256.convert(packBytes).toString(),
        indexSha256: sha256.convert(indexBytes).toString(),
      );
      decode(batch);
      return batch;
    } on IncomingRevisionRejected {
      rethrow;
    } on Object {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.invalidPayload,
      );
    }
  }

  IncomingRevisionContent decode(CommittedRevisionBatch batch) {
    if (batch.wireManifest.length > 4 * 1024 * 1024 ||
        batch.packBytes.length +
                batch.indexBytes.length +
                batch.wireManifest.length >
            maximumBytes) {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.limitExceeded,
      );
    }
    try {
      final map =
          jsonDecode(utf8.decode(batch.wireManifest)) as Map<String, Object?>;
      if (map.keys.toSet().difference({
            'schemaVersion',
            'objectFormat',
            'source',
            'slotKey',
            'contentHash',
            'currentUpstream',
            'currentEffective',
            'publishedHistory',
          }).isNotEmpty ||
          map.length != 8) {
        throw const FormatException();
      }
      if (map['schemaVersion'] != 1 ||
          map['objectFormat'] != 'sha1' ||
          batch.packSha256 != sha256.convert(batch.packBytes).toString() ||
          batch.indexSha256 != sha256.convert(batch.indexBytes).toString()) {
        throw const FormatException();
      }
      final sourceMap = map['source'] as Map<String, Object?>;
      final source = const SourceDescriptorCodec().decode(
        kind: sourceMap['kind'] as String,
        payloadSchemaVersion: sourceMap['payloadSchemaVersion'] as int,
        payloadJson: jsonEncode(sourceMap['payload']),
      );
      final upstream = RevisionObjectId(map['currentUpstream'] as String);
      final effective = RevisionObjectId(map['currentEffective'] as String);
      if (source != batch.source ||
          map['slotKey'] != batch.slotKey ||
          map['contentHash'] != batch.contentHash ||
          revisionTransferReference(upstream) != batch.currentUpstream ||
          revisionTransferReference(effective) != batch.currentEffective ||
          !_hash(batch.contentHash) ||
          batch.slotKey.length > 255 ||
          batch.slotKey.isEmpty ||
          !RegExp(r'^[a-z0-9._-]+$').hasMatch(batch.slotKey) ||
          batch.slotKey == '.' ||
          batch.slotKey == '..') {
        throw const FormatException();
      }
      final history = map['publishedHistory'] as List<Object?>;
      if (history.length != batch.publishedHistory.length ||
          history.length > 10000) {
        throw const FormatException();
      }
      final roots = <RevisionObjectId>{upstream, effective};
      final eventIds = <String>{};
      final historyEntries =
          <
            ({
              RevisionObjectId objectId,
              CommittedRevisionHistoryDescriptor descriptor,
            })
          >[];
      for (var i = 0; i < history.length; i++) {
        final item = history[i] as Map<String, Object?>;
        final expected = batch.publishedHistory[i];
        final oid = RevisionObjectId(item['revision'] as String);
        final kind = item['kind'];
        final micros = _micros(item['publishedAtMicros']);
        if (kind is! String ||
            !{
              WorkspaceOperationKind.install.name,
              WorkspaceOperationKind.adopt.name,
              WorkspaceOperationKind.update.name,
              WorkspaceOperationKind.publishDraft.name,
              WorkspaceOperationKind.publishUpdateCandidate.name,
              WorkspaceOperationKind.restorePublish.name,
              WorkspaceOperationKind.replaceSource.name,
              WorkspaceOperationKind.resolveSkillDrift.name,
            }.contains(kind) ||
            !_hash(expected.eventFingerprint) ||
            !_hash(expected.contentHash) ||
            !eventIds.add(expected.eventFingerprint)) {
          throw const FormatException();
        }
        if (revisionTransferReference(oid) != expected.revision ||
            item['eventFingerprint'] != expected.eventFingerprint ||
            item['kind'] != expected.kind.name ||
            item['contentHash'] != expected.contentHash ||
            micros != expected.publishedAt.microsecondsSinceEpoch) {
          throw const FormatException();
        }
        roots.add(oid);
        historyEntries.add((objectId: oid, descriptor: expected));
      }
      if (!historyEntries.any((entry) => entry.objectId == effective)) {
        throw const FormatException();
      }
      return IncomingRevisionContent(
        upstream: upstream,
        effective: effective,
        roots: roots.toList(),
        packBytes: batch.packBytes,
        indexBytes: batch.indexBytes,
        contentHash: batch.contentHash,
        history: historyEntries,
      );
    } on IncomingRevisionRejected {
      rethrow;
    } on Object {
      throw const IncomingRevisionRejected(
        IncomingRevisionPendingReason.invalidPayload,
      );
    }
  }
}

bool _hash(String value) =>
    value.length == 64 && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

int _micros(Object? value) {
  if (value is! String ||
      value.length > 19 ||
      value.trim() != value ||
      !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw const FormatException();
  }
  final parsed = BigInt.parse(value);
  if (parsed > BigInt.from(8640000000000000000)) throw const FormatException();
  return parsed.toInt();
}
