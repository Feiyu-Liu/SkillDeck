import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:crypto/crypto.dart';

import '../errors.dart';
import '../protocol/canonical.dart';
import '../protocol/codec.dart';
import '../protocol/models.dart';
import '../protocol/content_manifest.dart';
import '../sync/models.dart';
import '../sync/store.dart';
import '../sync/workspace_port.dart';

String _localOperationId() {
  final random = Random.secure(),
      bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Synchronous worker-side implementation; App composition uses its isolate wrapper.
final class SqliteSyncStore implements CloudSyncStore {
  SqliteSyncStore(this.database, this.serviceOrigin);
  final Database database;
  final Uri serviceOrigin;
  static const maximumRetainedInboxRows = 10000,
      maximumPageBytes = 1024 * 1024,
      maximumPageItems = 2000;
  List<Object?> _scope(CloudSyncScope scope) => [
    serviceOrigin.origin,
    scope.accountId,
    scope.deviceId,
    scope.workspaceIdentity.workspaceId,
  ];
  static const _where =
      'origin=? AND account_id=? AND device_id=? AND workspace_id=?';
  T _transaction<T>(T Function() action) {
    var active = false;
    try {
      database.execute('BEGIN IMMEDIATE');
      active = true;
      final result = action();
      database.execute('COMMIT');
      return result;
    } on CloudException {
      if (active) {
        try {
          database.execute('ROLLBACK');
        } catch (_) {}
      }
      rethrow;
    } catch (_) {
      if (active) {
        try {
          database.execute('ROLLBACK');
        } catch (_) {}
      }
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  Row _state(CloudSyncScope scope, {bool ready = true}) {
    final rows = database.select(
      'SELECT * FROM cloud_sync_scope WHERE $_where',
      _scope(scope),
    );
    if (rows.length != 1 ||
        rows.single['incarnation'] !=
            scope.workspaceIdentity.recoveryIncarnation ||
        (ready && rows.single['status'] != 'enabled')) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return rows.single;
  }

  Set<String> _selected(CloudSyncScope scope, String kind) => database
      .select(
        'SELECT subject_id FROM cloud_sync_selection WHERE $_where AND subject_kind=?',
        [..._scope(scope), kind],
      )
      .map((row) => row['subject_id'] as String)
      .toSet();
  @override
  Future<void> initializeOptInScope({
    required CloudSyncScope scope,
    required CloudWorkspaceCapture capture,
    required CloudSyncSelection selection,
    required CloudSequence initialCursor,
  }) async {
    if (initialCursor.value != BigInt.zero ||
        !capture.ready ||
        capture.identity != scope.workspaceIdentity ||
        selection.isEmpty) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    _transaction(() {
      if (database
          .select(
            'SELECT 1 FROM cloud_device_scope WHERE origin=? AND account_id=? AND device_id=? AND ready=1',
            _scope(scope).take(3).toList(),
          )
          .isEmpty) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final prior = database.select(
        'SELECT * FROM cloud_sync_scope WHERE $_where',
        _scope(scope),
      );
      if (prior.isNotEmpty) {
        final row = _state(scope, ready: false);
        if (row['status'] == 'needsReconciliation') {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        if (row['revision'] != capture.revision ||
            canonicalPayload(_selected(scope, 'cloud').toList()..sort()) !=
                canonicalPayload(selection.cloudLineageIds.toList()..sort()) ||
            canonicalPayload(_selected(scope, 'local').toList()..sort()) !=
                canonicalPayload(selection.localSkillIds.toList()..sort())) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        return;
      }
      database.execute(
        'INSERT INTO cloud_sync_scope VALUES(?,?,?,?,?,?,\'enabled\',?,?,NULL,NULL,NULL,NULL,NULL)',
        [
          ..._scope(scope),
          scope.workspaceIdentity.recoveryIncarnation,
          capture.revision,
          initialCursor.toJson(),
          initialCursor.toJson(),
        ],
      );
      database.execute(
        'INSERT INTO cloud_workspace_scope VALUES(?,?,?,?,1) ON CONFLICT DO UPDATE SET ready=1',
        _scope(scope),
      );
      for (final kind in ['cloud', 'local']) {
        for (final id
            in kind == 'cloud'
                ? selection.cloudLineageIds
                : selection.localSkillIds) {
          database.execute(
            'INSERT INTO cloud_sync_selection VALUES(?,?,?,?,?,?)',
            [..._scope(scope), kind, id],
          );
        }
      }
    });
  }

  CloudOutboundTask? _sendTask(
    CloudSyncScope scope,
    String kind,
    String subject,
  ) {
    final rows = database.select(
      'SELECT * FROM cloud_sync_send_task WHERE $_where AND kind=? AND subject_id=?',
      [..._scope(scope), kind, subject],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CloudOutboundTask(
      kind: kind,
      subjectId: subject,
      operationId: row['operation_id'] as String,
      data: object(jsonDecode(row['data'] as String)),
      localContext: object(jsonDecode(row['local_context'] as String)),
      acknowledged: row['acknowledged'] == 1,
    );
  }

  @override
  Future<List<CloudOutboundTask>> pendingOutboundTasks(
    CloudSyncScope scope,
  ) async {
    _state(scope);
    final rows = database.select(
      'SELECT kind,subject_id FROM cloud_sync_send_task WHERE $_where AND acknowledged=0 ORDER BY rowid',
      _scope(scope),
    );
    return List.unmodifiable([
      for (final row in rows)
        _sendTask(scope, row['kind'] as String, row['subject_id'] as String)!,
    ]);
  }

  @override
  Future<CloudOutboundTask?> outboundTask(
    CloudSyncScope scope,
    String kind,
    String subjectId,
  ) async {
    _state(scope, ready: false);
    return _sendTask(scope, kind, subjectId);
  }

  @override
  Future<CloudOutboundTask> stageOutboundTask(
    CloudSyncScope scope, {
    required String kind,
    required String subjectId,
    required Map<String, Object?> data,
    required Map<String, Object?> localContext,
  }) async => _transaction(() {
    _state(scope);
    identifier(kind);
    identifier(subjectId);
    if (![
          'content',
          'replacement',
          'repair',
          'fields',
          'tagCreate',
          'tagPatch',
          'tagDelete',
          'assignment',
          'removal',
        ].contains(kind) ||
        utf8.encode(jsonEncode([data, localContext])).length >
            maximumPageBytes) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    final previous = _sendTask(scope, kind, subjectId);
    if (previous != null && !previous.acknowledged) {
      return previous;
    }
    final id = _localOperationId();
    database.execute(
      'INSERT INTO cloud_sync_send_task VALUES(?,?,?,?,?,?,?,?,?,0) ON CONFLICT(origin,account_id,device_id,workspace_id,kind,subject_id) DO UPDATE SET operation_id=excluded.operation_id,data=excluded.data,local_context=excluded.local_context,acknowledged=0',
      [
        ..._scope(scope),
        kind,
        subjectId,
        id,
        jsonEncode(data),
        jsonEncode(localContext),
      ],
    );
    return _sendTask(scope, kind, subjectId)!;
  });
  @override
  Future<void> completeOutboundTask(
    CloudSyncScope scope,
    CloudOutboundTask task,
    Map<String, Object?> result,
    CloudWorkspaceCapture capture,
  ) async {
    _transaction(() {
      _state(scope);
      final stored = _sendTask(scope, task.kind, task.subjectId);
      if (stored == null ||
          stored.operationId != task.operationId ||
          canonicalPayload(stored.data) != canonicalPayload(task.data) ||
          canonicalPayload(stored.localContext) !=
              canonicalPayload(task.localContext) ||
          result['operationId'] != task.operationId ||
          !capture.ready ||
          capture.identity != scope.workspaceIdentity) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      if (stored.acknowledged) return;
      final data = stored.data, context = stored.localContext;
      final echoKind = stored.kind == 'repair'
          ? 'repairReady'
          : stored.kind == 'replacement'
          ? 'replacement'
          : stored.kind == 'content'
          ? 'revision'
          : stored.kind == 'removal'
          ? 'removal'
          : stored.kind.startsWith('tag')
          ? 'personalTag'
          : 'metadata';
      final sequence = CloudSequence.parse(text(result['sequence'])).toJson();
      if (!['content', 'replacement', 'repair'].contains(stored.kind) &&
          (result['kind'] != stored.kind ||
              !['committed', 'replay'].contains(result['outcome']) ||
              result['lineageId'] != data['lineageId'] ||
              result['generation'] != data['generation'] ||
              (stored.kind != 'tagCreate' &&
                  result['tagId'] != data['tagId']))) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      final echoData = {
        ...stored.data,
        if (['content', 'replacement', 'repair'].contains(stored.kind)) ...{
          'lineageId': result['lineageId'],
          'generation': result['generation'],
        },
        if (stored.kind == 'tagCreate') 'tagId': identifier(result['tagId']),
      };
      final priorEcho = database.select(
        'SELECT * FROM cloud_sync_echo WHERE $_where AND sequence=?',
        [..._scope(scope), sequence],
      );
      if (priorEcho.isNotEmpty &&
          (priorEcho.single['operation_id'] != stored.operationId ||
              priorEcho.single['kind'] != echoKind ||
              canonicalPayload(
                    jsonDecode(priorEcho.single['data'] as String),
                  ) !=
                  canonicalPayload(echoData))) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      final contentKind = [
        'content',
        'replacement',
        'repair',
      ].contains(stored.kind);
      if (contentKind) {
        final receipt = CloudCommitReceipt.fromJson(result);
        final desired = CloudContentManifest.fromJson(
          object(data['contentManifest']),
        );
        if (receipt.commitId != desired.currentEffective ||
            canonicalPayload(receipt.contentManifest.toJson()) !=
                canonicalPayload(desired.toJson()) ||
            data.containsKey('lineageId') &&
                (receipt.lineageId != data['lineageId'] ||
                    receipt.generation !=
                        (data['generation']! as int) +
                            (stored.kind == 'replacement' ? 1 : 0))) {
          throw const CloudException(CloudErrorCode.operationConflict);
        }
      }
      var historical = false;
      if (result['lineageId'] != null) {
        final current = database.select(
          'SELECT generation,retired,last_sequence FROM cloud_sync_mapping WHERE $_where AND lineage_id=?',
          [..._scope(scope), result['lineageId']],
        );
        if (current.isNotEmpty) {
          final row = current.single, generation = result['generation']! as int;
          historical =
              (row['generation'] as int) > generation ||
              row['retired'] == 1 && (row['generation'] as int) >= generation ||
              CloudSequence.parse(row['last_sequence'])
                      .compareTo(CloudSequence.parse(sequence)) >
                  0;
          if (!historical && !contentKind && row['generation'] != generation) {
            throw const CloudException(CloudErrorCode.needsReconciliation);
          }
        } else if (!contentKind) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
      } else if (stored.kind.startsWith('tag')) {
        final current = database.select(
          'SELECT local_tag_id,deleted,last_sequence FROM cloud_sync_tags WHERE $_where AND tag_id=?',
          [..._scope(scope), result['tagId']],
        );
        if (current.isNotEmpty) {
          final row = current.single;
          if (row['local_tag_id'] != stored.subjectId) {
            throw const CloudException(CloudErrorCode.operationConflict);
          }
          historical =
              row['deleted'] == 1 ||
              CloudSequence.parse(row['last_sequence'])
                      .compareTo(CloudSequence.parse(sequence)) >
                  0;
        } else if (stored.kind != 'tagCreate') {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
      }
      // Old receipts settle only their original task; they cannot roll back a
      // later generation, deletion, field baseline or tag retirement.
      if (!historical) {
        switch (stored.kind) {
          case 'content':
          case 'replacement':
          case 'repair':
            final receipt = CloudCommitReceipt.fromJson(result),
                manifest = CloudContentManifest.fromJson(
                  object(data['contentManifest']),
                );
            final fp = text(context['localLineageFingerprint']);
            if (receipt.commitId != manifest.currentEffective ||
                canonicalPayload(receipt.contentManifest.toJson()) !=
                    canonicalPayload(manifest.toJson()) ||
                data.containsKey('lineageId') &&
                    (receipt.lineageId != data['lineageId'] ||
                        receipt.generation !=
                            (data['generation']! as int) +
                                (stored.kind == 'replacement' ? 1 : 0))) {
              throw const CloudException(CloudErrorCode.needsReconciliation);
            }

            if (stored.kind == 'repair') {
              final original = _baseline(scope, stored.subjectId);
              if (original == null ||
                  original.retired ||
                  canonicalPayload(original.contentManifest?.toJson()) !=
                      canonicalPayload(manifest.toJson())) {
                throw const CloudException(CloudErrorCode.operationConflict);
              }
            }
            _integrity(
              scope,
              receipt.lineageId,
              receipt.generation,
              receipt.sequence,
              CloudContentStatus.ready,
              manifest,
            );
            final prior = _baseline(scope, stored.subjectId);
            if (prior != null &&
                (prior.lineageId != receipt.lineageId || prior.retired)) {
              throw const CloudException(CloudErrorCode.needsReconciliation);
            }
            database.execute(
              'INSERT INTO cloud_sync_mapping VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET generation=excluded.generation,last_sequence=excluded.last_sequence,local_lineage_fingerprint=excluded.local_lineage_fingerprint',
              [
                ..._scope(scope),
                receipt.lineageId,
                receipt.generation,
                stored.subjectId,
                0,
                receipt.sequence.toJson(),
                fp,
              ],
            );
            database.execute(
              'INSERT INTO cloud_sync_baseline VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET manifest=excluded.manifest,generation=excluded.generation,local_lineage_fingerprint=excluded.local_lineage_fingerprint',
              [
                ..._scope(scope),
                stored.subjectId,
                receipt.lineageId,
                receipt.generation,
                fp,
                jsonEncode(manifest.toJson()),
                1,
                1,
                0,
                null,
                '[]',
                0,
                0,
              ],
            );
          case 'fields':
            _fields(scope, stored.subjectId, object(data['patch']));
          case 'assignment':
            _assignment(
              scope,
              text(context['localSkillId']),
              text(context['localTagId']),
              data['action'] == 'add',
            );
          case 'removal':
            database.execute(
              'DELETE FROM cloud_sync_integrity WHERE $_where AND lineage_id=?',
              [..._scope(scope), data['lineageId']],
            );
            database.execute(
              'UPDATE cloud_sync_mapping SET retired=1 WHERE $_where AND local_skill_id=?',
              [..._scope(scope), stored.subjectId],
            );
            database.execute(
              'UPDATE cloud_sync_baseline SET retired=1 WHERE $_where AND local_skill_id=?',
              [..._scope(scope), stored.subjectId],
            );
          case 'tagCreate':
            final tagId = identifier(result['tagId']);
            database.execute(
              'INSERT INTO cloud_sync_tags VALUES(?,?,?,?,?,?,?,?,?)',
              [
                ..._scope(scope),
                tagId,
                jsonEncode({
                  'tagId': tagId,
                  'name': data['name'],
                  'color': data['color'],
                }),
                result['sequence'],
                0,
                stored.subjectId,
              ],
            );
          case 'tagPatch':
            final rows = database.select(
              'SELECT body FROM cloud_sync_tags WHERE $_where AND tag_id=? AND local_tag_id=?',
              [..._scope(scope), data['tagId'], stored.subjectId],
            );
            if (rows.length != 1) {
              throw const CloudException(CloudErrorCode.needsReconciliation);
            }
            final body = object(jsonDecode(rows.single['body'] as String));
            database.execute(
              'UPDATE cloud_sync_tags SET body=?,last_sequence=? WHERE $_where AND tag_id=?',
              [
                jsonEncode({...body, ...object(data['patch'])}),
                result['sequence'],
                ..._scope(scope),
                data['tagId'],
              ],
            );
          case 'tagDelete':
            database.execute(
              'UPDATE cloud_sync_tags SET deleted=1,last_sequence=? WHERE $_where AND tag_id=? AND local_tag_id=?',
              [
                result['sequence'],
                ..._scope(scope),
                data['tagId'],
                stored.subjectId,
              ],
            );
            _removeTagBaseline(scope, stored.subjectId);
        }
        if (result['lineageId'] != null) {
          database.execute(
            'UPDATE cloud_sync_mapping SET last_sequence=? WHERE $_where AND lineage_id=?',
            [sequence, ..._scope(scope), result['lineageId']],
          );
        }
      }
      if (!historical && ['replacement', 'removal'].contains(stored.kind)) {
        database.execute(
          "UPDATE cloud_sync_inbox SET status='supersededByLifecycle',pending_reason=NULL WHERE $_where AND lineage_id=? AND status='pending' AND generation${stored.kind == 'replacement' ? '<' : '<='}? AND (pending_reason IS NULL OR pending_reason<>'unknownOutcome')",
          [..._scope(scope), result['lineageId'], result['generation']],
        );
      }
      database.execute(
        'INSERT INTO cloud_sync_echo VALUES(?,?,?,?,?,?,?,?) ON CONFLICT DO NOTHING',
        [
          ..._scope(scope),
          sequence,
          echoKind,
          stored.operationId,
          jsonEncode(echoData),
        ],
      );
      database.execute(
        'UPDATE cloud_sync_send_task SET acknowledged=1 WHERE $_where AND kind=? AND subject_id=? AND operation_id=?',
        [..._scope(scope), stored.kind, stored.subjectId, stored.operationId],
      );
      _advance(scope);
    });
  }

  void _removeTagBaseline(CloudSyncScope scope, String localTagId) {
    final skills = database.select(
      'SELECT local_skill_id FROM cloud_sync_baseline WHERE $_where',
      _scope(scope),
    );
    for (final row in skills) {
      _assignment(scope, row['local_skill_id'] as String, localTagId, false);
    }
  }

  @override
  Future<void> setEnabled(CloudSyncScope scope, bool enabled) async {
    _transaction(() {
      final row = _state(scope, ready: false);
      if (row['status'] == 'needsReconciliation') {
        if (enabled) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        database.execute(
          'UPDATE cloud_workspace_scope SET ready=0 WHERE $_where',
          _scope(scope),
        );
        return;
      }
      database.execute('UPDATE cloud_sync_scope SET status=? WHERE $_where', [
        enabled ? 'enabled' : 'paused',
        ..._scope(scope),
      ]);
      database.execute(
        'UPDATE cloud_workspace_scope SET ready=? WHERE $_where',
        [enabled ? 1 : 0, ..._scope(scope)],
      );
    });
  }

  CloudPublisherBaseline? _baseline(CloudSyncScope scope, String localSkillId) {
    final rows = database.select(
      'SELECT * FROM cloud_sync_baseline WHERE $_where AND local_skill_id=?',
      [..._scope(scope), localSkillId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final tags = jsonDecode(row['local_tags'] as String);
    if (tags is! List<Object?> || tags.any((id) => id is! String)) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return CloudPublisherBaseline(
      localSkillId: localSkillId,
      lineageId: row['lineage_id'] as String,
      generation: row['generation'] as int,
      localLineageFingerprint: row['local_lineage_fingerprint'] as String,
      contentManifest: row['manifest'] == null
          ? null
          : CloudContentManifest.fromJson(
              object(jsonDecode(row['manifest'] as String)),
            ),
      favoriteKnown: row['favorite_known'] == 1,
      noteKnown: row['note_known'] == 1,
      favorite: row['favorite'] == 1,
      note: row['note'] as String?,
      localTagIds: Set.unmodifiable(tags.cast<String>()),
      retired: row['retired'] == 1,
      initialLink: row['initial_link'] == 1,
    );
  }

  @override
  Future<CloudPublisherBaseline?> publisherBaseline(
    CloudSyncScope scope,
    String localSkillId,
  ) async {
    _state(scope, ready: false);
    return _baseline(scope, localSkillId);
  }

  @override
  Future<void> linkOutboundCommit(
    CloudSyncScope scope, {
    required String localSkillId,
    required String localLineageFingerprint,
    required CloudContentManifest manifest,
    required CloudCommitReceipt receipt,
    required CloudWorkspaceCapture capture,
  }) async {
    _transaction(() {
      _state(scope);
      if (!capture.ready ||
          capture.identity != scope.workspaceIdentity ||
          !_selected(scope, 'local').contains(localSkillId) ||
          receipt.commitId != manifest.currentEffective) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final prior = _baseline(scope, localSkillId);
      if (prior != null &&
          (prior.lineageId != receipt.lineageId ||
              prior.generation != receipt.generation ||
              prior.retired)) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      database.execute(
        'INSERT INTO cloud_sync_mapping VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET generation=excluded.generation,last_sequence=excluded.last_sequence,local_lineage_fingerprint=excluded.local_lineage_fingerprint',
        [
          ..._scope(scope),
          receipt.lineageId,
          receipt.generation,
          localSkillId,
          0,
          receipt.sequence.toJson(),
          localLineageFingerprint,
        ],
      );
      database.execute(
        'INSERT INTO cloud_sync_baseline VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET manifest=excluded.manifest,generation=excluded.generation',
        [
          ..._scope(scope),
          localSkillId,
          receipt.lineageId,
          receipt.generation,
          localLineageFingerprint,
          jsonEncode(manifest.toJson()),
          1,
          1,
          0,
          null,
          '[]',
          0,
          0,
        ],
      );
    });
  }

  void _fields(
    CloudSyncScope scope,
    String localSkillId,
    Map<String, Object?> patch,
  ) {
    if (patch.keys.any((key) => !['favorite', 'note'].contains(key))) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    if (patch.containsKey('favorite')) {
      database.execute(
        'UPDATE cloud_sync_baseline SET favorite=?,favorite_known=1 WHERE $_where AND local_skill_id=?',
        [patch['favorite'] == true ? 1 : 0, ..._scope(scope), localSkillId],
      );
    }
    if (patch.containsKey('note')) {
      database.execute(
        'UPDATE cloud_sync_baseline SET note=?,note_known=1 WHERE $_where AND local_skill_id=?',
        [
          patch['note'] == '' ? null : patch['note'],
          ..._scope(scope),
          localSkillId,
        ],
      );
    }
  }

  @override
  Future<void> acknowledgeOutboundFields(
    CloudSyncScope scope,
    String localSkillId,
    Map<String, Object?> patch,
  ) async {
    _transaction(() {
      _state(scope);
      if (_baseline(scope, localSkillId) == null) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      _fields(scope, localSkillId, patch);
    });
  }

  @override
  Future<void> bindOutboundPersonalTag(
    CloudSyncScope scope, {
    required String cloudTagId,
    required String localTagId,
    required String name,
    String? color,
  }) async {
    _transaction(() {
      _state(scope);
      identifier(cloudTagId);
      identifier(localTagId);
      final prior = database.select(
        'SELECT * FROM cloud_sync_tags WHERE $_where AND tag_id=?',
        [..._scope(scope), cloudTagId],
      );
      if (prior.isNotEmpty && prior.single['local_tag_id'] != localTagId) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      database.execute(
        'INSERT INTO cloud_sync_tags VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET body=excluded.body',
        [
          ..._scope(scope),
          cloudTagId,
          jsonEncode({'tagId': cloudTagId, 'name': name, 'color': color}),
          prior.isEmpty ? '0' : prior.single['last_sequence'],
          0,
          localTagId,
        ],
      );
    });
  }

  void _assignment(
    CloudSyncScope scope,
    String localSkillId,
    String localTagId,
    bool assigned,
  ) {
    final baseline = _baseline(scope, localSkillId);
    if (baseline == null) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final tags = {...baseline.localTagIds};
    if (assigned) {
      tags.add(localTagId);
    } else {
      tags.remove(localTagId);
    }
    database.execute(
      'UPDATE cloud_sync_baseline SET local_tags=? WHERE $_where AND local_skill_id=?',
      [jsonEncode(tags.toList()..sort()), ..._scope(scope), localSkillId],
    );
  }

  @override
  Future<void> acknowledgeOutboundAssignment(
    CloudSyncScope scope, {
    required String localSkillId,
    required String localTagId,
    required bool assigned,
  }) async {
    _transaction(() {
      _state(scope);
      _assignment(scope, localSkillId, localTagId, assigned);
    });
  }

  @override
  Future<void> acknowledgeOutboundRemoval(
    CloudSyncScope scope,
    String localSkillId,
  ) async {
    _transaction(() {
      _state(scope);
      database.execute(
        'UPDATE cloud_sync_mapping SET retired=1 WHERE $_where AND local_skill_id=?',
        [..._scope(scope), localSkillId],
      );
      database.execute(
        'UPDATE cloud_sync_baseline SET retired=1 WHERE $_where AND local_skill_id=?',
        [..._scope(scope), localSkillId],
      );
    });
  }

  void _receivedBaseline(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudApplyBinding binding,
    String localSkill,
    bool retired,
    bool initialLink,
  ) {
    if (item.change.lineageId == null) return;
    final change = item.change;
    if (change.kind == 'revision' || change.kind == 'replacement') {
      final manifest = CloudLineage.fromJson(change.payload).contentManifest;
      database.execute(
        'INSERT INTO cloud_sync_baseline VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET manifest=excluded.manifest,generation=excluded.generation,local_lineage_fingerprint=excluded.local_lineage_fingerprint,retired=excluded.retired',
        [
          ..._scope(scope),
          localSkill,
          change.lineageId,
          change.generation,
          binding.localLineageFingerprint ?? '',
          manifest == null ? null : jsonEncode(manifest.toJson()),
          0,
          0,
          0,
          null,
          '[]',
          initialLink ? 1 : 0,
          retired ? 1 : 0,
        ],
      );
    } else if (change.kind == 'metadata') {
      if (change.payload['kind'] == 'fields') {
        _fields(scope, localSkill, object(change.payload['patch']));
      }
      if (change.payload['kind'] == 'assignment') {
        final rows = database.select(
          'SELECT local_tag_id FROM cloud_sync_tags WHERE $_where AND tag_id=?',
          [..._scope(scope), change.payload['tagId']],
        );
        if (rows.isEmpty) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        _assignment(
          scope,
          localSkill,
          rows.single['local_tag_id'] as String,
          change.payload['action'] == 'add',
        );
      }
    } else if (retired) {
      database.execute(
        'UPDATE cloud_sync_baseline SET retired=1 WHERE $_where AND local_skill_id=?',
        [..._scope(scope), localSkill],
      );
    }
  }

  @override
  Future<bool> hasPendingVocabulary(CloudSyncScope scope) async {
    _state(scope);
    return database
        .select(
          "SELECT 1 FROM cloud_sync_inbox WHERE $_where AND status='pending' AND kind='personalTag' LIMIT 1",
          _scope(scope),
        )
        .isNotEmpty;
  }

  @override
  Future<bool> hasPendingLineageConflict(
    CloudSyncScope scope,
    String lineageId,
  ) async {
    _state(scope);
    return database.select(
      "SELECT 1 FROM cloud_sync_inbox WHERE $_where AND status='pending' AND lineage_id=? AND pending_reason IN ('metadataConflict','receiptConflict','unknownOutcome','unsupportedNormalization','needsReconciliation','metadataProofUnavailable','unsupportedReplacement') LIMIT 1",
      [..._scope(scope), lineageId],
    ).isNotEmpty;
  }

  @override
  Future<List<CloudIntegrityState>> integrityStates(
    CloudSyncScope scope,
  ) async {
    _state(scope, ready: false);
    return List.unmodifiable(
      database
          .select(
            'SELECT * FROM cloud_sync_integrity WHERE $_where',
            _scope(scope),
          )
          .map(
            (row) => CloudIntegrityState(
              lineageId: row['lineage_id'] as String,
              generation: row['generation'] as int,
              sequence: CloudSequence.parse(row['sequence']),
              status: row['status'] == 'ready'
                  ? CloudContentStatus.ready
                  : CloudContentStatus.needsReupload,
              manifest: row['manifest'] == null
                  ? null
                  : CloudContentManifest.fromJson(
                      object(jsonDecode(row['manifest'] as String)),
                    ),
            ),
          ),
    );
  }

  void _integrity(
    CloudSyncScope scope,
    String lineage,
    int generation,
    CloudSequence sequence,
    CloudContentStatus status,
    CloudContentManifest? manifest,
  ) {
    final mapped = database.select(
      'SELECT retired,generation FROM cloud_sync_mapping WHERE $_where AND lineage_id=?',
      [..._scope(scope), lineage],
    );
    if (mapped.isNotEmpty &&
        (mapped.single['retired'] == 1 ||
            (mapped.single['generation'] as int) > generation)) {
      return;
    }
    final prior = database.select(
      'SELECT generation,sequence FROM cloud_sync_integrity WHERE $_where AND lineage_id=?',
      [..._scope(scope), lineage],
    );
    if (prior.isNotEmpty &&
        ((prior.single['generation'] as int) > generation ||
            CloudSequence.parse(prior.single['sequence']).compareTo(sequence) >
                0)) {
      return;
    }
    database.execute(
      'INSERT INTO cloud_sync_integrity VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET generation=excluded.generation,sequence=excluded.sequence,status=excluded.status,manifest=excluded.manifest',
      [
        ..._scope(scope),
        lineage,
        generation,
        sequence.toJson(),
        status.name,
        manifest == null ? null : jsonEncode(manifest.toJson()),
      ],
    );
  }

  @override
  Future<String> ensureSnapshotRequestKey(CloudSyncScope scope) async =>
      _transaction(() {
        final state = _state(scope);
        if (state['snapshot_id'] != null) {
          throw const CloudException(CloudErrorCode.operationConflict);
        }
        final prior = state['snapshot_request_key'] as String?;
        if (prior != null) return prior;
        final key = _localOperationId();
        database.execute(
          'UPDATE cloud_sync_scope SET snapshot_request_key=? WHERE $_where',
          [key, ..._scope(scope)],
        );
        return key;
      });
  @override
  Future<void> clearSnapshotRequestKey(
    CloudSyncScope scope,
    String expectedKey,
  ) async {
    _transaction(() {
      final state = _state(scope);
      if (state['snapshot_id'] != null ||
          state['snapshot_request_key'] != expectedKey) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      database.execute(
        'UPDATE cloud_sync_scope SET snapshot_request_key=NULL WHERE $_where',
        _scope(scope),
      );
    });
  }

  @override
  Future<CloudSyncProgress> progress(CloudSyncScope scope) async {
    final row = _state(scope, ready: false);
    return CloudSyncProgress(
      scope: scope,
      expectedRevision: row['revision'] as String,
      received: CloudSequence.parse(row['received']),
      applied: CloudSequence.parse(row['applied']),
      needsReconciliation: row['status'] == 'needsReconciliation',
      isEnabled: row['status'] == 'enabled',
      pendingCount:
          database.select(
                'SELECT (SELECT count(*) FROM cloud_sync_inbox WHERE $_where AND status=\'pending\') + (SELECT count(*) FROM cloud_sync_integrity WHERE $_where AND status=\'needsReupload\') AS n',
                [..._scope(scope), ..._scope(scope)],
              ).single['n']
              as int,
      selection: CloudSyncSelection(
        cloudLineageIds: _selected(scope, 'cloud'),
        localSkillIds: _selected(scope, 'local'),
      ),
      snapshotId: row['snapshot_id'] as String?,
      snapshotCursor: row['snapshot_cursor'] as String?,
      snapshotHighWatermark: row['snapshot_high'] == null
          ? null
          : CloudSequence.parse(row['snapshot_high']),
      traversalHighWatermark: row['traversal_high'] == null
          ? null
          : CloudSequence.parse(row['traversal_high']),
    );
  }

  @override
  Future<void> observeCapture(
    CloudSyncScope scope,
    CloudWorkspaceCapture capture,
  ) async {
    _transaction(() {
      final row = _state(scope);
      final old = BigInt.tryParse(row['revision'] as String),
          next = BigInt.tryParse(capture.revision);
      if (!capture.ready ||
          capture.identity != scope.workspaceIdentity ||
          old == null ||
          next == null ||
          next < old) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      database.execute('UPDATE cloud_sync_scope SET revision=? WHERE $_where', [
        capture.revision,
        ..._scope(scope),
      ]);
    });
  }

  CloudApplyBinding _binding(CloudSyncScope scope, CloudInboxItem item) {
    final row = database.select(
      'SELECT * FROM cloud_sync_apply_intent WHERE $_where AND event_key=?',
      [..._scope(scope), item.eventKey],
    ).single;
    return CloudApplyBinding(
      operationId: row['operation_id'] as String,
      eventKey: item.eventKey,
      desiredFingerprint: row['fingerprint'] as String,
      localTargetId: row['local_target'] as String?,
      workspaceRequestFingerprint: row['workspace_fingerprint'] as String?,
      localLineageFingerprint: row['local_lineage_fingerprint'] as String?,
      preexistingTarget: row['preexisting_target'] == null
          ? null
          : row['preexisting_target'] == 1,
    );
  }

  @override
  Future<CloudApplyBinding> bindApplyIntent(
    CloudSyncScope scope,
    CloudInboxItem item, {
    String? localTargetId,
    String? workspaceRequestFingerprint,
    String? localLineageFingerprint,
    bool? preexistingTarget,
  }) async => _transaction(() {
    _state(scope);
    _pending(scope, item);
    final fingerprint = sha256
        .convert(utf8.encode(canonicalPayload(_changeJson(item.change))))
        .toString();
    database.execute(
      'INSERT INTO cloud_sync_apply_intent VALUES(?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO NOTHING',
      [
        ..._scope(scope),
        item.eventKey,
        _localOperationId(),
        fingerprint,
        localTargetId,
        workspaceRequestFingerprint,
        localLineageFingerprint,
        preexistingTarget == null
            ? null
            : preexistingTarget
            ? 1
            : 0,
      ],
    );
    final binding = _binding(scope, item);
    if (binding.desiredFingerprint != fingerprint ||
        localTargetId != null &&
            binding.localTargetId != null &&
            localTargetId != binding.localTargetId) {
      throw const CloudException(CloudErrorCode.operationConflict);
    }
    if (localTargetId != null && binding.localTargetId == null) {
      identifier(localTargetId);
      database.execute(
        'UPDATE cloud_sync_apply_intent SET local_target=? WHERE $_where AND event_key=?',
        [localTargetId, ..._scope(scope), item.eventKey],
      );
    }
    for (final pair in [
      (
        workspaceRequestFingerprint,
        binding.workspaceRequestFingerprint,
        'workspace_fingerprint',
      ),
      (
        localLineageFingerprint,
        binding.localLineageFingerprint,
        'local_lineage_fingerprint',
      ),
    ]) {
      if (pair.$1 != null && pair.$2 != null && pair.$1 != pair.$2) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      if (pair.$1 != null && pair.$2 == null) {
        database.execute(
          'UPDATE cloud_sync_apply_intent SET ${pair.$3}=? WHERE $_where AND event_key=?',
          [pair.$1, ..._scope(scope), item.eventKey],
        );
      }
    }
    if (preexistingTarget != null) {
      if (binding.preexistingTarget != null &&
          binding.preexistingTarget != preexistingTarget) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      database.execute(
        'UPDATE cloud_sync_apply_intent SET preexisting_target=? WHERE $_where AND event_key=?',
        [preexistingTarget ? 1 : 0, ..._scope(scope), item.eventKey],
      );
    }
    return _binding(scope, item);
  });
  @override
  Future<void> recordDesiredRemovalRetry(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudRetryDesiredRemovalAllowed proof,
  ) async {
    _transaction(() {
      _state(scope);
      _pending(scope, item);
      final binding = _binding(scope, item);
      if (item.change.kind != 'removal' ||
          proof.eventKey != item.eventKey ||
          proof.operationId != binding.operationId ||
          proof.localTargetId != binding.localTargetId ||
          proof.localLineageFingerprint != binding.localLineageFingerprint ||
          !proof.capture.ready ||
          proof.capture.identity != scope.workspaceIdentity ||
          proof.capture.localLineageFingerprints[proof.localTargetId] !=
              proof.localLineageFingerprint) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      database.execute(
        'UPDATE cloud_sync_inbox SET pending_reason=? WHERE id=?',
        [CloudPendingReason.desiredRemovalRetry.name, item.id],
      );
    });
  }

  @override
  Future<void> recordNotStarted(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudConfirmedNotStarted proof,
  ) async {
    _transaction(() {
      _state(scope);
      _pending(scope, item);
      final binding = _binding(scope, item);
      if (proof.eventKey != item.eventKey ||
          proof.operationId != binding.operationId ||
          proof.proofId.isEmpty ||
          !proof.capture.ready ||
          proof.capture.identity != scope.workspaceIdentity) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      database.execute(
        'UPDATE cloud_sync_inbox SET pending_reason=? WHERE id=?',
        [CloudPendingReason.unavailable.name, item.id],
      );
    });
  }

  void _budget(CloudSyncScope scope, int rows, int bytes) {
    final pending =
        database
                .select(
                  'SELECT count(*) AS n FROM cloud_sync_inbox WHERE $_where',
                  _scope(scope),
                )
                .single['n']
            as int;
    if (rows > maximumPageItems ||
        bytes > maximumPageBytes ||
        pending + rows > maximumRetainedInboxRows) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
  }

  Map<String, Object?> _changeJson(CloudChange change) => {
    'sequence': change.sequence.toJson(),
    'kind': change.kind,
    'lineageId': change.lineageId,
    'generation': change.generation,
    'payload': change.payload,
  };
  // null: no receipt; false: conflicting event at a confirmed sequence.
  bool? _echo(CloudSyncScope scope, CloudChange change) {
    final rows = database.select(
      'SELECT * FROM cloud_sync_echo WHERE $_where AND sequence=?',
      [..._scope(scope), change.sequence.toJson()],
    );
    if (rows.isEmpty) return null;
    final row = rows.single,
        data = object(jsonDecode(row['data'] as String)),
        payload = change.payload;
    if (row['kind'] != change.kind) return false;
    if (change.lineageId != data['lineageId'] ||
        change.generation != data['generation']) {
      return false;
    }
    if (['revision', 'replacement', 'repairReady'].contains(change.kind)) {
      return canonicalPayload(payload['contentManifest']) ==
          canonicalPayload(data['contentManifest']);
    }
    if (change.kind == 'removal') return true;
    for (final entry in data.entries) {
      if (entry.key == 'operationId') continue;
      // Omission, null, false and empty are distinct wire states.
      if (!payload.containsKey(entry.key) ||
          canonicalPayload(payload[entry.key]) !=
              canonicalPayload(entry.value)) {
        return false;
      }
    }
    return true;
  }

  void _insert(CloudSyncScope scope, String eventKey, CloudChange change) {
    final selected =
        change.lineageId == null ||
        _selected(scope, 'cloud').contains(change.lineageId) ||
        database.select(
          'SELECT 1 FROM cloud_sync_mapping WHERE $_where AND lineage_id=?',
          [..._scope(scope), change.lineageId],
        ).isNotEmpty;
    final echo = _echo(scope, change);
    final availability = ['repairNeeded', 'repairReady'].contains(change.kind);
    if (selected &&
        echo != false &&
        (availability ||
            (change.kind == 'revision' || change.kind == 'replacement') &&
                change.payload.containsKey('contentStatus'))) {
      final lineage = CloudLineage.fromJson(change.payload);
      _integrity(
        scope,
        lineage.lineageId,
        lineage.generation,
        change.sequence,
        lineage.contentStatus,
        lineage.contentManifest,
      );
    }
    database.execute(
      '''INSERT INTO cloud_sync_inbox(origin,account_id,device_id,workspace_id,event_key,sequence,kind,lineage_id,generation,payload,status,pending_reason,proof_id)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,NULL)''',
      [
        ..._scope(scope),
        eventKey,
        change.sequence.toJson(),
        change.kind,
        change.lineageId,
        change.generation,
        jsonEncode(change.payload),
        echo == true
            ? 'echo'
            : availability && echo != false
            ? 'stateObserved'
            : selected || echo == false
            ? 'pending'
            : 'ignored',
        echo == false ? CloudPendingReason.receiptConflict.name : null,
      ],
    );
  }

  bool _pageReplay(CloudSyncScope scope, String key, Object? payload) {
    final digest = sha256
        .convert(utf8.encode(canonicalPayload(payload)))
        .toString();
    final prior = database.select(
      'SELECT digest FROM cloud_sync_page WHERE $_where AND page_key=?',
      [..._scope(scope), key],
    );
    if (prior.isNotEmpty) {
      if (prior.single['digest'] != digest) {
        throw const CloudException(CloudErrorCode.operationConflict);
      }
      return true;
    }
    database.execute(
      'INSERT INTO cloud_sync_page(origin,account_id,device_id,workspace_id,page_key,digest) VALUES(?,?,?,?,?,?)',
      [..._scope(scope), key, digest],
    );
    database.execute(
      'DELETE FROM cloud_sync_page WHERE $_where AND id NOT IN (SELECT id FROM cloud_sync_page WHERE $_where ORDER BY id DESC LIMIT 64)',
      [..._scope(scope), ..._scope(scope)],
    );
    return false;
  }

  @override
  Future<void> stageChangesPage(
    CloudSyncScope scope,
    CloudChangesPage page,
  ) async {
    _transaction(() {
      final row = _state(scope);
      if (_pageReplay(
        scope,
        'changes:${page.after.toJson()}:${page.highWatermark.toJson()}',
        {
          'after': page.after.toJson(),
          'next': page.nextCursor.toJson(),
          'high': page.highWatermark.toJson(),
          'entries': page.entries.map(_changeJson).toList(),
        },
      )) {
        return;
      }
      if (row['traversal_high'] != null &&
          row['traversal_high'] != page.highWatermark.toJson()) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      if (row['received'] != page.after.toJson() ||
          row['snapshot_cursor'] != null) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      _budget(
        scope,
        page.entries.length,
        utf8.encode(jsonEncode(page.entries.map(_changeJson).toList())).length,
      );
      for (final entry in page.entries) {
        _insert(scope, 'change:${entry.sequence.toJson()}', entry);
      }
      database.execute(
        'UPDATE cloud_sync_scope SET received=?,traversal_high=? WHERE $_where',
        [
          page.nextCursor.toJson(),
          page.nextCursor == page.highWatermark
              ? null
              : page.highWatermark.toJson(),
          ..._scope(scope),
        ],
      );
      _advance(scope);
      database.execute(
        'DELETE FROM cloud_sync_echo WHERE $_where AND CAST(sequence AS INTEGER)<=CAST(? AS INTEGER)',
        [..._scope(scope), page.nextCursor.toJson()],
      );
    });
  }

  Map<String, Object?> _lineageJson(CloudLineage item) => {
    'lineageId': item.lineageId,
    'generation': item.generation,
    'selectedCommitId': item.selectedCommitId,
    'slotKey': item.slotKey,
    'sourceDescriptor': item.sourceDescriptor.toJson(),
    'metadata': item.metadata,
    'contentManifestVersion': 1,
    'contentStatus': item.contentStatus.name,
    'contentManifest': item.contentManifest?.toJson(),
  };
  Map<String, Object?> _tagJson(CloudPersonalTag tag) => {
    'tagId': tag.tagId,
    'name': tag.name,
    'color': tag.color,
    'createdAt': tag.createdAt.millisecondsSinceEpoch,
    'updatedAt': tag.updatedAt.millisecondsSinceEpoch,
  };
  @override
  Future<void> stageSnapshotPage(
    CloudSyncScope scope,
    CloudSnapshotPage page,
  ) async {
    _transaction(() {
      final row = _state(scope);
      if (_pageReplay(
        scope,
        'snapshot:${page.snapshotId}:${page.pageCursor ?? 'first'}',
        {
          'id': page.snapshotId,
          'high': page.highWatermark.toJson(),
          'cursor': page.pageCursor,
          'next': page.nextPageCursor,
          'complete': page.complete,
          'items': page.items.map(_lineageJson).toList(),
          'tags': page.personalTags.map(_tagJson).toList(),
        },
      )) {
        return;
      }
      if (page.pageCursor == null) {
        if (row['snapshot_id'] != null ||
            database
                .select(
                  'SELECT 1 FROM cloud_sync_inbox WHERE $_where LIMIT 1',
                  _scope(scope),
                )
                .isNotEmpty) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
      } else if (row['snapshot_id'] != page.snapshotId ||
          row['snapshot_cursor'] != page.pageCursor ||
          row['snapshot_high'] != page.highWatermark.toJson()) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      if (page.highWatermark.compareTo(CloudSequence.parse(row['received'])) <
              0 ||
          page.nextPageCursor == page.pageCursor && !page.complete) {
        throw const CloudException(CloudErrorCode.invalidResponse);
      }
      final projections = [
        ...page.items.map(_lineageJson),
        ...page.personalTags.map(_tagJson),
      ];
      _budget(
        scope,
        page.personalTags.length +
            page.items.fold<int>(
              0,
              (count, item) =>
                  count +
                  2 +
                  (item.metadata['tags'] is List
                      ? (item.metadata['tags']! as List<Object?>).length
                      : 0),
            ),
        utf8.encode(jsonEncode(projections)).length * 2,
      );
      for (final item in page.items) {
        database.execute(
          'INSERT INTO cloud_sync_snapshot_seen VALUES(?,?,?,?,?,?,?)',
          [..._scope(scope), page.snapshotId, 'lineage', item.lineageId],
        );
        _insert(
          scope,
          'snapshot:${page.snapshotId}:lineage:${item.lineageId}',
          CloudChange.fromJson({
            'sequence': page.highWatermark.toJson(),
            'lineageId': item.lineageId,
            'generation': item.generation,
            'kind': 'revision',
            'payload': _lineageJson(item),
          }),
        );
        final metadata = item.metadata;
        _insert(
          scope,
          'snapshot:${page.snapshotId}:fields:${item.lineageId}',
          CloudChange.fromJson({
            'sequence': page.highWatermark.toJson(),
            'kind': 'metadata',
            'lineageId': item.lineageId,
            'generation': item.generation,
            'payload': {
              'kind': 'fields',
              'lineageId': item.lineageId,
              'generation': item.generation,
              'patch': {
                'favorite': metadata['favorite'],
                'note': metadata['note'],
              },
            },
          }),
        );
        final tags = metadata['tags'];
        if (tags is! List<Object?>) {
          throw const CloudException(CloudErrorCode.invalidResponse);
        }
        for (final id in tags) {
          identifier(id);
          _insert(
            scope,
            'snapshot:${page.snapshotId}:assignment:${item.lineageId}:$id',
            CloudChange.fromJson({
              'sequence': page.highWatermark.toJson(),
              'kind': 'metadata',
              'lineageId': item.lineageId,
              'generation': item.generation,
              'payload': {
                'kind': 'assignment',
                'lineageId': item.lineageId,
                'generation': item.generation,
                'tagId': id,
                'action': 'add',
              },
            }),
          );
        }
      }
      for (final tag in page.personalTags) {
        database.execute(
          'INSERT INTO cloud_sync_snapshot_seen VALUES(?,?,?,?,?,?,?)',
          [..._scope(scope), page.snapshotId, 'tag', tag.tagId],
        );
        _insert(
          scope,
          'snapshot:${page.snapshotId}:tag:${tag.tagId}',
          CloudChange.fromJson({
            'sequence': page.highWatermark.toJson(),
            'lineageId': null,
            'generation': null,
            'kind': 'personalTag',
            'payload': {'kind': 'tagCreate', ..._tagJson(tag)},
          }),
        );
      }
      database.execute(
        'UPDATE cloud_sync_scope SET snapshot_id=?,snapshot_cursor=?,snapshot_high=?${page.complete ? ',received=?' : ''} WHERE $_where',
        [
          page.snapshotId,
          page.nextPageCursor,
          page.highWatermark.toJson(),
          if (page.complete) page.highWatermark.toJson(),
          ..._scope(scope),
        ],
      );
      if (page.complete) _advance(scope);
    });
  }

  @override
  Future<void> discardIncompleteSnapshot(
    CloudSyncScope scope,
    String snapshotId,
  ) async {
    _transaction(() {
      final state = _state(scope);
      if (state['snapshot_id'] != snapshotId ||
          state['snapshot_cursor'] == null) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final prefix = 'snapshot:$snapshotId:';
      final rows = database.select(
        'SELECT event_key,status FROM cloud_sync_inbox WHERE $_where',
        _scope(scope),
      );
      for (final row in rows) {
        final key = row['event_key'] as String;
        if (!key.startsWith(prefix)) {
          continue;
        }
        if (row['status'] == 'applied') {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        database.execute(
          'DELETE FROM cloud_sync_inbox WHERE $_where AND event_key=?',
          [..._scope(scope), key],
        );
        database.execute(
          'DELETE FROM cloud_sync_apply_intent WHERE $_where AND event_key=?',
          [..._scope(scope), key],
        );
      }
      database.execute(
        'DELETE FROM cloud_sync_snapshot_seen WHERE $_where AND snapshot_id=?',
        [..._scope(scope), snapshotId],
      );
      final pages = database.select(
        'SELECT id,page_key FROM cloud_sync_page WHERE $_where',
        _scope(scope),
      );
      for (final page in pages) {
        if ((page['page_key'] as String).startsWith(prefix)) {
          database.execute('DELETE FROM cloud_sync_page WHERE id=?', [
            page['id'],
          ]);
        }
      }
      database.execute(
        'UPDATE cloud_sync_scope SET snapshot_id=NULL,snapshot_cursor=NULL,snapshot_high=NULL,snapshot_request_key=NULL WHERE $_where',
        _scope(scope),
      );
    });
  }

  CloudInboxItem _item(Row row) => CloudInboxItem(
    id: row['id'] as int,
    eventKey: row['event_key'] as String,
    change: CloudChange.fromJson({
      'sequence': row['sequence'],
      'kind': row['kind'],
      'lineageId': row['lineage_id'],
      'generation': row['generation'],
      'payload': jsonDecode(row['payload'] as String),
    }),
    pendingReason: row['pending_reason'] == null
        ? null
        : CloudPendingReason.values.byName(row['pending_reason'] as String),
  );
  @override
  Future<List<CloudInboxItem>> pendingItems(
    CloudSyncScope scope, {
    int maximum = 100,
  }) async {
    final state = _state(scope);
    if (state['snapshot_cursor'] != null) return const [];
    if (maximum < 1 || maximum > maximumPageItems) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    return List.unmodifiable(
      database
          .select(
            'SELECT * FROM cloud_sync_inbox WHERE $_where AND status=\'pending\' ORDER BY CAST(sequence AS INTEGER),id LIMIT ?',
            [..._scope(scope), maximum],
          )
          .map(_item),
    );
  }

  @override
  Future<List<CloudPersonalTagMapping>> personalTagMappings(
    CloudSyncScope scope,
  ) async {
    _state(scope);
    final ids = database.select(
      'SELECT tag_id FROM cloud_sync_tags WHERE $_where ORDER BY tag_id',
      _scope(scope),
    );
    return List.unmodifiable([
      for (final row in ids)
        (await personalTagMapping(scope, row['tag_id'] as String))!,
    ]);
  }

  @override
  Future<CloudPersonalTagMapping?> personalTagMapping(
    CloudSyncScope scope,
    String cloudTagId,
  ) async {
    _state(scope);
    final rows = database.select(
      'SELECT * FROM cloud_sync_tags WHERE $_where AND tag_id=?',
      [..._scope(scope), cloudTagId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single, body = object(jsonDecode(row['body'] as String));
    return CloudPersonalTagMapping(
      cloudTagId: cloudTagId,
      localTagId: row['local_tag_id'] as String,
      deleted: row['deleted'] == 1,
      name: body['name'] as String? ?? '',
      color: body['color'] as String?,
    );
  }

  @override
  Future<CloudLineageMapping?> mapping(
    CloudSyncScope scope,
    String lineageId,
  ) async {
    _state(scope);
    final rows = database.select(
      'SELECT * FROM cloud_sync_mapping WHERE $_where AND lineage_id=?',
      [..._scope(scope), lineageId],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CloudLineageMapping(
      lineageId: lineageId,
      generation: row['generation'] as int,
      localSkillId: row['local_skill_id'] as String,
      retired: row['retired'] == 1,
      lastSequence: CloudSequence.parse(row['last_sequence']),
      localLineageFingerprint: row['local_lineage_fingerprint'] as String?,
    );
  }

  Row _pending(CloudSyncScope scope, CloudInboxItem item) {
    final rows = database.select(
      'SELECT * FROM cloud_sync_inbox WHERE $_where AND id=? AND event_key=? AND status=\'pending\'',
      [..._scope(scope), item.id, item.eventKey],
    );
    if (rows.length != 1 ||
        canonicalPayload(_changeJson(_item(rows.single).change)) !=
            canonicalPayload(_changeJson(item.change))) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    return rows.single;
  }

  @override
  Future<void> recordPending(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudPendingReason reason,
  ) async {
    _transaction(() {
      _state(scope);
      _pending(scope, item);
      database.execute(
        'UPDATE cloud_sync_inbox SET pending_reason=? WHERE id=?',
        [reason.name, item.id],
      );
    });
  }

  @override
  Future<void> recordApplyProof(
    CloudSyncScope scope,
    CloudInboxItem item,
    CloudApplyResult proof,
  ) async {
    _transaction(() {
      final state = _state(scope);
      if (state['snapshot_cursor'] != null) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final (eventKey, capture, localSkill, proofId, retired) = switch (proof) {
        CloudStateAlreadySatisfied() => (
          proof.eventKey,
          proof.capture,
          proof.localSkillId,
          proof.proofId,
          false,
        ),
        CloudApplied() => (
          proof.eventKey,
          proof.capture,
          proof.localSkillId,
          proof.proofId,
          false,
        ),
        CloudTargetAbsent() when proof.cleanupComplete => (
          proof.eventKey,
          proof.capture,
          proof.localSkillId,
          proof.proofId,
          true,
        ),
        CloudSuperseded()
            when item.change.generation != null &&
                proof.retiredGeneration >= item.change.generation! =>
          (
            proof.eventKey,
            proof.capture,
            proof.localSkillId,
            proof.proofId,
            true,
          ),
        _ => throw const CloudException(CloudErrorCode.needsReconciliation),
      };
      if (eventKey != item.eventKey ||
          !capture.ready ||
          capture.identity != scope.workspaceIdentity ||
          proofId.isEmpty) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final bindingRows = database.select(
        'SELECT * FROM cloud_sync_apply_intent WHERE $_where AND event_key=?',
        [..._scope(scope), item.eventKey],
      );
      if (bindingRows.length != 1) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final binding = _binding(scope, item);
      final (operationId, fingerprint) = switch (proof) {
        CloudStateAlreadySatisfied() => (
          proof.operationId,
          proof.desiredFingerprint,
        ),
        CloudApplied() => (proof.operationId, proof.desiredFingerprint),
        CloudTargetAbsent() => (proof.operationId, proof.desiredFingerprint),
        CloudSuperseded() => (proof.operationId, proof.desiredFingerprint),
        _ => throw const CloudException(CloudErrorCode.needsReconciliation),
      };
      if (operationId != binding.operationId ||
          fingerprint != binding.desiredFingerprint ||
          item.change.lineageId != null &&
              binding.localTargetId != localSkill) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final digest = sha256
          .convert(
            utf8.encode(
              canonicalPayload({
                'event': _changeJson(item.change),
                'key': eventKey,
                'identity': [
                  capture.identity.workspaceId,
                  capture.identity.recoveryIncarnation,
                ],
                'local': localSkill,
                'proof': proofId,
                'proofKind': proof is CloudStateAlreadySatisfied
                    ? 'desiredStateSatisfied'
                    : 'operationOutcome',
                'retired': retired,
                'retiredGeneration': proof is CloudSuperseded
                    ? proof.retiredGeneration
                    : null,
                'operation': operationId,
                'fingerprint': fingerprint,
              }),
            ),
          )
          .toString();
      final previous = database.select(
        'SELECT digest FROM cloud_sync_result WHERE $_where AND event_key=?',
        [..._scope(scope), eventKey],
      );
      if (previous.isNotEmpty) {
        if (previous.single['digest'] != digest) {
          throw const CloudException(CloudErrorCode.operationConflict);
        }
        return;
      }
      if (proof is CloudStateAlreadySatisfied &&
          (!item.eventKey.startsWith('snapshot:') ||
              item.change.kind != 'revision' ||
              item.pendingReason != null ||
              binding.workspaceRequestFingerprint != null ||
              binding.localLineageFingerprint !=
                  proof.localLineageFingerprint ||
              capture.localLineageFingerprints[localSkill] !=
                  proof.localLineageFingerprint ||
              database.select(
                'SELECT 1 FROM cloud_sync_mapping WHERE $_where AND lineage_id=?',
                [..._scope(scope), item.change.lineageId],
              ).isNotEmpty)) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      _pending(scope, item);
      final oldRevision = BigInt.tryParse(state['revision'] as String),
          newRevision = BigInt.tryParse(capture.revision);
      if (oldRevision == null ||
          newRevision == null ||
          newRevision < oldRevision) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final preceding = database.select(
        "SELECT payload,lineage_id FROM cloud_sync_inbox WHERE $_where AND status='pending' AND id<?",
        [..._scope(scope), item.id],
      );
      if (preceding.any(
        (row) => item.change.lineageId != null
            ? row['lineage_id'] == item.change.lineageId
            : row['lineage_id'] == null &&
                  object(jsonDecode(row['payload'] as String))['tagId'] ==
                      item.change.payload['tagId'],
      )) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      if (item.change.lineageId case final lineage?) {
        identifier(localSkill);
        final prior = database.select(
          'SELECT * FROM cloud_sync_mapping WHERE $_where AND lineage_id=?',
          [..._scope(scope), lineage],
        );
        if (prior.isNotEmpty &&
            (prior.single['local_skill_id'] != localSkill ||
                (prior.single['generation'] as int) > item.change.generation! ||
                prior.single['retired'] == 1 && !retired)) {
          throw const CloudException(CloudErrorCode.needsReconciliation);
        }
        database.execute(
          'INSERT INTO cloud_sync_mapping VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET generation=excluded.generation,retired=excluded.retired,last_sequence=excluded.last_sequence,local_lineage_fingerprint=excluded.local_lineage_fingerprint',
          [
            ..._scope(scope),
            lineage,
            item.change.generation,
            localSkill,
            retired ? 1 : 0,
            item.change.sequence.toJson(),
            binding.localLineageFingerprint,
          ],
        );
      } else {
        _tag(scope, item.change, localSkill);
      }
      if (retired) {
        database.execute(
          'DELETE FROM cloud_sync_integrity WHERE $_where AND lineage_id=?',
          [..._scope(scope), item.change.lineageId],
        );
      }
      _receivedBaseline(
        scope,
        item,
        binding,
        localSkill,
        retired,
        proof is CloudStateAlreadySatisfied ||
            binding.preexistingTarget == true,
      );
      database.execute(
        'UPDATE cloud_sync_inbox SET status=\'applied\',pending_reason=NULL,proof_id=? WHERE id=?',
        [proofId, item.id],
      );
      database.execute('UPDATE cloud_sync_scope SET revision=? WHERE $_where', [
        capture.revision,
        ..._scope(scope),
      ]);
      database.execute(
        'INSERT INTO cloud_sync_result(origin,account_id,device_id,workspace_id,event_key,digest,sequence) VALUES(?,?,?,?,?,?,?)',
        [..._scope(scope), eventKey, digest, item.change.sequence.toJson()],
      );
      database.execute(
        'DELETE FROM cloud_sync_result WHERE $_where AND id NOT IN (SELECT id FROM cloud_sync_result WHERE $_where ORDER BY id DESC LIMIT 1024)',
        [..._scope(scope), ..._scope(scope)],
      );
      _advance(scope);
    });
  }

  void _tag(CloudSyncScope scope, CloudChange change, String localTagId) {
    final payload = change.payload, tagId = identifier(payload['tagId']);
    final prior = database.select(
      'SELECT * FROM cloud_sync_tags WHERE $_where AND tag_id=?',
      [..._scope(scope), tagId],
    );
    if (prior.isNotEmpty &&
        CloudSequence.parse(prior.single['last_sequence'])
                .compareTo(change.sequence) >=
            0) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    if (prior.isNotEmpty &&
        prior.single['deleted'] == 1 &&
        payload['kind'] != 'tagDelete') {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final existing = prior.isEmpty
        ? <String, Object?>{}
        : object(jsonDecode(prior.single['body'] as String));
    final kind = payload['kind'];
    if (kind == 'tagPatch' && prior.isEmpty) {
      throw const CloudException(CloudErrorCode.needsReconciliation);
    }
    final body = switch (kind) {
      'tagCreate' => {...payload}..remove('kind'),
      'tagPatch' => {
        ...existing,
        ...object(payload['patch']),
        'updatedAt': payload['updatedAt'],
      },
      'tagDelete' => {
        ...existing,
        'tagId': tagId,
        'deletedAt': payload['deletedAt'],
      },
      _ => throw const CloudException(CloudErrorCode.invalidResponse),
    };
    database.execute(
      'INSERT INTO cloud_sync_tags VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT DO UPDATE SET body=excluded.body,last_sequence=excluded.last_sequence,deleted=excluded.deleted,local_tag_id=excluded.local_tag_id',
      [
        ..._scope(scope),
        tagId,
        jsonEncode(body),
        change.sequence.toJson(),
        kind == 'tagDelete' ? 1 : 0,
        localTagId,
      ],
    );
    if (kind == 'tagDelete') _removeTagBaseline(scope, localTagId);
  }

  void _advance(CloudSyncScope scope) {
    final state = _state(scope);
    if (state['snapshot_cursor'] != null) return;
    final pending = database
        .select(
          'SELECT min(CAST(sequence AS INTEGER)) AS n FROM cloud_sync_inbox WHERE $_where AND status=\'pending\'',
          _scope(scope),
        )
        .single['n'];
    String candidate;
    if (pending == null) {
      candidate = state['received'] as String;
    } else {
      candidate =
          database.select(
                'SELECT CAST(max(CAST(sequence AS INTEGER)) AS TEXT) AS n FROM cloud_sync_inbox WHERE $_where AND status<>\'pending\' AND CAST(sequence AS INTEGER)<?',
                [..._scope(scope), pending],
              ).single['n']
              as String? ??
          state['applied'] as String;
    }
    if (CloudSequence.parse(candidate)
            .compareTo(CloudSequence.parse(state['applied'])) <
        0) {
      return;
    }
    database.execute('UPDATE cloud_sync_scope SET applied=? WHERE $_where', [
      candidate,
      ..._scope(scope),
    ]);
    database.execute(
      'DELETE FROM cloud_sync_inbox WHERE $_where AND status<>\'pending\' AND CAST(sequence AS INTEGER)<=CAST(? AS INTEGER)',
      [..._scope(scope), candidate],
    );
    database.execute(
      "DELETE FROM cloud_sync_apply_intent WHERE $_where AND event_key NOT IN (SELECT event_key FROM cloud_sync_inbox WHERE $_where) AND event_key NOT IN (SELECT event_key FROM cloud_sync_result WHERE $_where)",
      [..._scope(scope), ..._scope(scope), ..._scope(scope)],
    );
    database.execute(
      'DELETE FROM cloud_sync_echo WHERE $_where AND CAST(sequence AS INTEGER)<=CAST(? AS INTEGER)',
      [..._scope(scope), candidate],
    );
    if (state['snapshot_id'] != null && candidate == state['snapshot_high']) {
      database.execute(
        'DELETE FROM cloud_sync_snapshot_seen WHERE $_where',
        _scope(scope),
      );
    }
  }

  @override
  Future<void> requireReconciliation(CloudSyncScope scope) async {
    _transaction(() {
      database.execute(
        'UPDATE cloud_sync_scope SET status=\'needsReconciliation\' WHERE $_where',
        _scope(scope),
      );
      database.execute(
        'UPDATE cloud_workspace_scope SET ready=0 WHERE $_where',
        _scope(scope),
      );
    });
  }

  @override
  Future<void> stageOutboxCandidate(
    CloudSyncScope scope,
    CloudOutboxCandidate candidate,
  ) async {
    _transaction(() {
      _state(scope);
      identifier(candidate.operationId);
      identifier(candidate.localSkillId);
      if (!_selected(scope, 'local').contains(candidate.localSkillId)) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      final prior = database.select(
        'SELECT * FROM cloud_sync_outbox WHERE origin=? AND account_id=? AND operation_id=?',
        [serviceOrigin.origin, scope.accountId, candidate.operationId],
      );
      if (prior.isNotEmpty) {
        final row = prior.single;
        if (row['device_id'] != scope.deviceId ||
            row['workspace_id'] != scope.workspaceIdentity.workspaceId ||
            row['local_skill_id'] != candidate.localSkillId ||
            row['source_lineage'] != candidate.sourceLineageIdentity ||
            row['history_id'] != candidate.historyIdentity) {
          throw const CloudException(CloudErrorCode.operationConflict);
        }
        return;
      }
      final count =
          database.select(
                'SELECT count(*) AS n FROM cloud_sync_outbox WHERE origin=? AND account_id=?',
                [serviceOrigin.origin, scope.accountId],
              ).single['n']
              as int;
      if (count >= maximumRetainedInboxRows ||
          candidate.state != CloudOutboxState.candidate ||
          candidate.firstAttemptUtc != null) {
        throw const CloudException(CloudErrorCode.needsReconciliation);
      }
      database.execute(
        'INSERT INTO cloud_sync_outbox VALUES(?,?,?,?,?,?,?,?,?,NULL)',
        [
          ..._scope(scope),
          candidate.operationId,
          candidate.localSkillId,
          candidate.sourceLineageIdentity,
          candidate.historyIdentity,
          candidate.state.name,
        ],
      );
    });
  }

  @override
  Future<List<CloudOutboxCandidate>> outboxCandidates(
    CloudSyncScope scope, {
    int maximum = 100,
  }) async {
    _state(scope);
    if (maximum < 1 || maximum > maximumPageItems) {
      throw const CloudException(CloudErrorCode.invalidRequest);
    }
    return database
        .select(
          'SELECT * FROM cloud_sync_outbox WHERE $_where ORDER BY operation_id LIMIT ?',
          [..._scope(scope), maximum],
        )
        .map(
          (row) => CloudOutboxCandidate(
            operationId: row['operation_id'] as String,
            localSkillId: row['local_skill_id'] as String,
            sourceLineageIdentity: row['source_lineage'] as String,
            historyIdentity: row['history_id'] as String,
            state: CloudOutboxState.values.byName(row['state'] as String),
            firstAttemptUtc: row['first_attempt'] == null
                ? null
                : DateTime.parse(row['first_attempt'] as String),
          ),
        )
        .toList(growable: false);
  }
}
