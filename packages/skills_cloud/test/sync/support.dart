import 'dart:async';

import 'package:skills_cloud/skills_cloud.dart';

const identity = CloudWorkspaceIdentity(
  workspaceId: 'workspace',
  recoveryIncarnation: 'incarnation',
);
CloudWorkspaceCapture captureState({
  int revision = 0,
  CloudWorkspaceIdentity id = identity,
  bool ready = true,
}) => CloudWorkspaceCapture(
  identity: id,
  revision: '$revision',
  recoveryComplete: ready,
  finalizationComplete: ready,
  isComplete: ready,
);
CloudSyncScope scope({CloudWorkspaceIdentity id = identity}) => CloudSyncScope(
  accountId: 'account',
  deviceId: 'device-1',
  workspaceIdentity: id,
);
Map<String, Object?> revision(
  int sequence,
  String lineage, {
  int generation = 1,
}) => {
  'sequence': '$sequence',
  'kind': 'revision',
  'lineageId': lineage,
  'generation': generation,
  'payload': {
    'lineageId': lineage,
    'generation': generation,
    'selectedCommitId': 'a' * 40,
    'slotKey': 'sample',
    'sourceDescriptor': {
      'kind': 'git',
      'payloadSchemaVersion': 1,
      'payload': {
        'locator': 'https://example.invalid/owner/repo.git',
        'ref': 'main',
        'repositorySubpath': '',
        'skillPath': 'sample',
      },
    },
    'metadata': {'favorite': false, 'note': '', 'tags': <Object?>[]},
    'contentManifestVersion': 1,
    'contentStatus': 'ready',
    'contentManifest': {
      'schemaVersion': 1,
      'objectFormat': 'sha1',
      'source': {
        'kind': 'git',
        'payloadSchemaVersion': 1,
        'payload': {
          'locator': 'https://example.invalid/owner/repo.git',
          'ref': 'main',
          'repositorySubpath': '',
          'skillPath': 'sample',
        },
      },
      'slotKey': 'sample',
      'contentHash': 'b' * 64,
      'currentUpstream': 'a' * 40,
      'currentEffective': 'a' * 40,
      'publishedHistory': [
        {
          'eventFingerprint': 'c' * 64,
          'revision': 'a' * 40,
          'kind': 'install',
          'publishedAtMicros': '1000000',
          'contentHash': 'b' * 64,
        },
      ],
    },
  },
};
Map<String, Object?> tag(
  int sequence, {
  String kind = 'tagCreate',
  String id = 'tag',
}) => {
  'sequence': '$sequence',
  'kind': 'personalTag',
  'lineageId': null,
  'generation': null,
  'payload': {
    'kind': kind,
    'tagId': id,
    if (kind == 'tagCreate') ...{
      'name': 'Tag',
      'color': null,
      'createdAt': 1000,
      'updatedAt': 1000,
    },
    if (kind == 'tagPatch') ...{
      'patch': {'name': 'Updated'},
      'updatedAt': 2000,
    },
    if (kind == 'tagDelete') 'deletedAt': 3000,
  },
};
Map<String, Object?> metadata(int sequence, String lineage) => {
  'sequence': '$sequence',
  'kind': 'metadata',
  'lineageId': lineage,
  'generation': 1,
  'payload': {
    'kind': 'fields',
    'lineageId': lineage,
    'generation': 1,
    'patch': {'note': null, 'favorite': false},
  },
};
Map<String, Object?> removal(int sequence, String lineage) => {
  'sequence': '$sequence',
  'kind': 'removal',
  'lineageId': lineage,
  'generation': 1,
  'payload': {'lineageId': lineage, 'generation': 1, 'removedAt': 1000},
};
CloudChangesPage changes(
  List<Map<String, Object?>> entries, {
  int after = 0,
  int? high,
}) => CloudChangesPage.fromJson({
  'after': '$after',
  'highWatermark':
      '${high ?? (entries.isEmpty ? after : int.parse(entries.last['sequence']! as String))}',
  'nextCursor': entries.isEmpty ? '$after' : entries.last['sequence'],
  'entries': entries,
});
CloudSnapshotPage snapshot({
  String? cursor,
  String? next = 'next',
  bool complete = false,
  bool includeLineage = true,
  bool includeTag = false,
}) => CloudSnapshotPage.fromJson({
  'snapshotId': 'snapshot',
  'highWatermark': '20',
  'pageCursor': cursor,
  'nextPageCursor': next,
  'complete': complete,
  'items': includeLineage ? [revision(20, 'lineage')['payload']] : <Object?>[],
  'personalTags': includeTag
      ? [
          {
            'tagId': 'tag',
            'name': 'Unassigned',
            'color': null,
            'createdAt': 1000,
            'updatedAt': 1000,
          },
        ]
      : <Object?>[],
});

final class Incoming implements CloudIncomingHandle {
  Incoming(this.item);
  final CloudInboxItem item;
  bool disposed = false;
  @override
  String? get localTargetId => 'local-${item.change.lineageId}';
  @override
  String? get workspaceRequestFingerprint =>
      'receiver-fingerprint-${item.eventKey}';
  @override
  String? get localLineageFingerprint =>
      'receiver-lineage-${item.change.lineageId}';
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

final class FakeWorkspace implements CloudWorkspacePort {
  int revisionNumber = 0, activePrepares = 0, maximumPrepares = 0;
  CloudWorkspaceIdentity currentIdentity = identity;
  bool ready = true, throwAfterApply = false;
  final Map<String, CloudPendingReason> pending = {};
  final List<Incoming> handles = [];
  final List<String> applied = [], resolved = [];
  final Map<String, CloudApplyResult> outcomes = {};
  Duration prepareDelay = const Duration(milliseconds: 10);
  @override
  Future<CloudWorkspaceCapture> capture() async => captureValue;
  CloudWorkspaceCapture get captureValue =>
      captureState(revision: revisionNumber, id: currentIdentity, ready: ready);
  @override
  Future<CloudIncomingHandle> prepareIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) async {
    activePrepares++;
    if (activePrepares > maximumPrepares) maximumPrepares = activePrepares;
    try {
      await Future<void>.delayed(prepareDelay);
      cancellation.throwIfCancelled();
      final handle = Incoming(item);
      handles.add(handle);
      return handle;
    } finally {
      activePrepares--;
    }
  }

  @override
  Future<CloudIncomingHandle> prepareStateChange({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) async {
    final handle = Incoming(item);
    handles.add(handle);
    return handle;
  }

  Future<CloudApplyResult> _apply(
    CloudInboxItem item,
    CloudApplyBinding binding,
    CloudWorkspaceCapture expected,
  ) async {
    if (expected.identity != currentIdentity ||
        expected.revision != '$revisionNumber') {
      return const CloudApplyPending(CloudPendingReason.needsReconciliation);
    }
    final reason =
        pending[item.change.lineageId ?? item.change.payload['tagId']];
    if (reason != null) return CloudApplyPending(reason);
    applied.add(item.eventKey);
    revisionNumber++;
    final proof = CloudApplied(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      desiredFingerprint: binding.desiredFingerprint,
      capture: captureValue,
      localSkillId: item.change.lineageId == null
          ? 'vocabulary'
          : 'local-${item.change.lineageId}',
      proofId: 'proof-${item.eventKey}',
    );
    outcomes[item.eventKey] = proof;
    if (throwAfterApply) {
      throwAfterApply = false;
      throw StateError('lost response');
    }
    return proof;
  }

  @override
  Future<CloudApplyResult> applyIncoming({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => _apply(item, binding, expected);
  @override
  Future<CloudApplyResult> applyMetadata({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) => _apply(item, binding, expected);
  @override
  Future<CloudApplyResult> applyLifecycle({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudIncomingHandle handle,
    required CloudWorkspaceCapture expected,
    required CloudLineageMapping? mapping,
    required CloudCancellation cancellation,
  }) async {
    revisionNumber++;
    final proof = CloudTargetAbsent(
      eventKey: item.eventKey,
      operationId: binding.operationId,
      desiredFingerprint: binding.desiredFingerprint,
      capture: captureValue,
      localSkillId: 'local-${item.change.lineageId}',
      cleanupComplete: true,
      proofId: 'absence-${item.eventKey}',
    );
    outcomes[item.eventKey] = proof;
    return proof;
  }

  @override
  Future<CloudApplyResult> resolveOutcome({
    required CloudInboxItem item,
    required CloudApplyBinding binding,
    required CloudSyncScope scope,
    required CloudCancellation cancellation,
  }) async {
    resolved.add(item.eventKey);
    return outcomes[item.eventKey] ??
        const CloudApplyPending(CloudPendingReason.unknownOutcome);
  }
}
