import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:skills_cloud/skills_cloud.dart';

enum FileSyncStateDiagnostic { corrupt, unreadable, quarantineFailed }

/// Local state for one account and Device. Serialize access through one store
/// instance for each open scope.
final class FileSyncStateStore implements SyncStateStore {
  FileSyncStateStore({
    required String supportDirectory,
    required CloudServiceOrigin origin,
    required String accountId,
    required String deviceId,
    required void Function(FileSyncStateDiagnostic) onDiagnostic,
  }) : _file = File(
         p.join(
           supportDirectory,
           'cloud',
           _hash([origin.toString(), accountId]),
           '${_hash([deviceId])}.json',
         ),
       ),
       _onDiagnostic = onDiagnostic;

  final File _file;
  final void Function(FileSyncStateDiagnostic) _onDiagnostic;
  Future<void> _tail = Future.value();
  _SyncState? _cached;

  @override
  Future<List<SyncLink>> links() =>
      _read((state) => List.unmodifiable(state.links.values));

  @override
  Future<void> put(SyncLink link) =>
      _write((state) => state.links[link.managedSkillId] = link);

  @override
  Future<void> unlink(String managedSkillId) =>
      _write((state) => state.links.remove(managedSkillId));

  @override
  Future<String?> feedCursor() => _read((state) => state.feedCursor);

  @override
  Future<void> setFeedCursor(String? cursor) =>
      _write((state) => state.feedCursor = cursor);

  @override
  Future<String?> workspaceCursor() => _read((state) => state.workspaceCursor);

  @override
  Future<void> setWorkspaceCursor(String cursor) =>
      _write((state) => state.workspaceCursor = cursor);

  @override
  Future<SyncMetadataState> metadataState() => _read((state) => state.metadata);

  @override
  Future<void> setMetadataState(SyncMetadataState metadata) =>
      _write((state) => state.metadata = metadata);

  @override
  Future<Set<String>> exclusions() =>
      _read((state) => Set.unmodifiable(state.exclusions));

  @override
  Future<void> setExcluded(String lineageId, bool excluded) => _write((state) {
    if (excluded) {
      state.exclusions.add(lineageId);
    } else {
      state.exclusions.remove(lineageId);
    }
  });

  Future<T> _serialize<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<T> _read<T>(T Function(_SyncState) read) =>
      _serialize(() async => read(await _load()));

  Future<void> _write(void Function(_SyncState) update) => _serialize(() async {
    final next = (await _load()).copy();
    update(next);
    final temporary = File('${_file.path}.${_suffix()}.tmp');
    try {
      await _file.parent.create(recursive: true);
      await temporary.writeAsString(jsonEncode(next.toJson()), flush: true);
      await temporary.rename(_file.path);
      _cached = next;
    } on FileSystemException {
      try {
        await temporary.delete();
      } on FileSystemException {
        // A failed cleanup must not mask the original write failure.
      }
      throw StateError('local_state_io');
    }
  });

  Future<_SyncState> _load() async {
    if (_cached case final state?) return state;
    try {
      return _cached = _SyncState.fromJson(
        jsonDecode(await _file.readAsString()),
      );
    } on FileSystemException catch (error) {
      // ENOENT is normal for a Device that has never synced this account.
      if (error.osError?.errorCode != 2) {
        await _quarantine(FileSyncStateDiagnostic.unreadable);
      }
    } on FormatException {
      await _quarantine(FileSyncStateDiagnostic.corrupt);
    }
    return _cached = _SyncState();
  }

  Future<void> _quarantine(FileSyncStateDiagnostic reason) async {
    _onDiagnostic(reason);
    try {
      await _file.rename('${_file.path}.${_suffix()}.invalid');
    } on FileSystemException {
      _onDiagnostic(FileSyncStateDiagnostic.quarantineFailed);
      throw StateError('sync_state_quarantine_failed');
    }
  }
}

String _hash(List<String> fields) =>
    sha256.convert(utf8.encode(jsonEncode(fields))).toString();

String _suffix() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';

final class _SyncState {
  _SyncState({
    this.feedCursor,
    this.workspaceCursor,
    this.metadata = const SyncMetadataState(),
    Map<String, SyncLink>? links,
    Set<String>? exclusions,
  }) : links = links ?? {},
       exclusions = exclusions ?? {};

  String? feedCursor;
  String? workspaceCursor;
  SyncMetadataState metadata;
  final Map<String, SyncLink> links;
  final Set<String> exclusions;

  _SyncState copy() => _SyncState(
    feedCursor: feedCursor,
    workspaceCursor: workspaceCursor,
    metadata: metadata,
    links: Map.of(links),
    exclusions: Set.of(exclusions),
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'feedCursor': feedCursor,
    'workspaceCursor': workspaceCursor,
    'metadata': metadata.toJson(),
    'exclusions': exclusions.toList(),
    'links': [
      for (final link in links.values)
        {
          'managedSkillId': link.managedSkillId,
          'lineageId': link.lineageId,
          'clientKey': link.clientKey,
          'version': link.version,
          'generation': link.generation,
          'effective': link.effective,
          'sourceEpoch': ?link.sourceEpoch,
          if (link.uploadBlockedByQuota) 'uploadBlockedByQuota': true,
          'attentionAttempt': switch (link.attentionAttempt) {
            final attempt? => {
              'version': attempt.version,
              'effective': attempt.effective,
              'reason': attempt.outcome.reason.name,
              'deviceName': attempt.outcome.deviceName,
              'occupant': attempt.outcome.occupant,
            },
            null => null,
          },
        },
    ],
  };

  factory _SyncState.fromJson(Object? json) {
    if (json is! Map<String, dynamic> ||
        json['version'] != 1 ||
        json['links'] is! List ||
        json['exclusions'] is! List) {
      throw const FormatException('sync_state_shape');
    }
    final links = <String, SyncLink>{};
    for (final value in json['links'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('sync_state_link');
      }
      final id = _string(value['managedSkillId']);
      final lineageId = _nullableString(value['lineageId']);
      final clientKey = _nullableString(value['clientKey']);
      if (lineageId == null && clientKey == null) {
        throw const FormatException('sync_state_unlinked');
      }
      final row = value['attentionAttempt'];
      final blockedByQuota = value['uploadBlockedByQuota'] ?? false;
      if (blockedByQuota is! bool) {
        throw const FormatException('sync_state_quota');
      }
      ({int version, String? effective, SyncNeedsAttention outcome})? attempt;
      if (row != null) {
        if (row is! Map<String, dynamic>) {
          throw const FormatException('sync_state_attempt');
        }
        final reason = AttentionReason.values
            .where((reason) => reason.name == row['reason'])
            .firstOrNull;
        if (reason == null) throw const FormatException('sync_state_reason');
        attempt = (
          version: _integer(row['version'], 0),
          effective: _nullableString(row['effective']),
          outcome: SyncNeedsAttention(
            reason,
            deviceName: _nullableString(row['deviceName']),
            occupant: _nullableString(row['occupant']),
          ),
        );
      }
      if (links.containsKey(id)) throw const FormatException('sync_state_id');
      links[id] = SyncLink(
        managedSkillId: id,
        lineageId: lineageId,
        clientKey: clientKey,
        version: _integer(value['version'], 0),
        generation: _integer(value['generation'], 1),
        effective: _nullableString(value['effective']),
        sourceEpoch: _nullableString(value['sourceEpoch']),
        uploadBlockedByQuota: blockedByQuota,
        attentionAttempt: attempt,
      );
    }
    final workspaceCursor = _nullableString(json['workspaceCursor']);
    if (workspaceCursor != null && (int.tryParse(workspaceCursor) ?? -1) < 0) {
      throw const FormatException('sync_state_workspace_cursor');
    }
    final metadata = json['metadata'];
    if (metadata != null && metadata is! Map<String, Object?>) {
      throw const FormatException('sync_state_metadata');
    }
    return _SyncState(
      feedCursor: _nullableString(json['feedCursor']),
      workspaceCursor: workspaceCursor,
      metadata: metadata == null
          ? const SyncMetadataState()
          : SyncMetadataState.fromJson(metadata as Map<String, Object?>),
      links: links,
      exclusions: {for (final id in json['exclusions'] as List) _string(id)},
    );
  }
}

int _integer(Object? value, int minimum) {
  if (value is int && value >= minimum) return value;
  throw const FormatException('sync_state_integer');
}

String _string(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  throw const FormatException('sync_state_string');
}

String? _nullableString(Object? value) => value == null ? null : _string(value);
