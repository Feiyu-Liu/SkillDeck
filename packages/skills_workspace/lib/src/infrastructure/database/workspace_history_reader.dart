import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';

import '../../application/ports/history_ports.dart';
import '../../domain/identifiers.dart';
import '../../domain/public_models.dart' as domain;
import 'workspace_database.dart' as db;

final class WorkspaceHistoryReader implements WorkspaceHistoryPort {
  const WorkspaceHistoryReader(db.WorkspaceDatabase database)
    : _database = database;

  final db.WorkspaceDatabase _database;

  @override
  Future<domain.OperationHistoryPage> readOperationHistory({
    ManagedSkillId? managedSkillId,
    String? cursor,
    required int limit,
  }) {
    _requireLimit(limit);
    final decodedCursor = cursor == null
        ? null
        : _HistoryCursor.decode(cursor, expectedKind: _CursorKind.operations);
    return _database.transaction(() async {
      final records = await _operationRecords(
        managedSkillId: managedSkillId,
        cursor: decodedCursor,
        limit: limit + 1,
      );
      final hasMore = records.length > limit;
      final pageRecords = hasMore ? records.take(limit).toList() : records;
      final operationIds = pageRecords
          .map((record) => record.operationId)
          .toList(growable: false);
      final subjects = operationIds.isEmpty
          ? const <db.OperationSubject>[]
          : await (_database.select(
              _database.operationSubjects,
            )..where((row) => row.operationId.isIn(operationIds))).get();
      final subjectsByOperation = <String, List<db.OperationSubject>>{};
      for (final subject in subjects) {
        subjectsByOperation
            .putIfAbsent(subject.operationId, () => [])
            .add(subject);
      }
      for (final values in subjectsByOperation.values) {
        values.sort((a, b) => a.subjectId.compareTo(b.subjectId));
      }

      final entries = pageRecords
          .map(
            (record) => domain.OperationHistoryEntry(
              operationId: OperationId(record.operationId),
              kind: _operationKind(record.kind),
              status: _terminalStatus(record.status),
              startedAt: _utc(record.startedAtMicros),
              completedAt: _utc(record.completedAtMicros),
              subjects:
                  (subjectsByOperation[record.operationId] ??
                          const <db.OperationSubject>[])
                      .map(_operationSubject)
                      .toList(growable: false),
            ),
          )
          .toList(growable: false);
      return domain.OperationHistoryPage(
        entries: entries,
        nextCursor: hasMore
            ? _HistoryCursor(
                kind: _CursorKind.operations,
                orderedAtMicros: pageRecords.last.startedAtMicros,
                operationId: pageRecords.last.operationId,
              ).encode()
            : null,
      );
    });
  }

  @override
  Future<domain.PublishedHistoryPage> readPublishedHistory({
    required ManagedSkillId managedSkillId,
    String? cursor,
    required int limit,
  }) async {
    _requireLimit(limit);
    int? beforeMicros;
    String? beforeKey;
    if (cursor != null) {
      try {
        final map =
            jsonDecode(utf8.decode(base64Url.decode(cursor)))
                as Map<String, Object?>;
        if (map['kind'] != 'published' || map['orderedAtMicros'] is! int) {
          throw const FormatException();
        }
        beforeMicros = map['orderedAtMicros'] as int;
        if (map['schemaVersion'] == 1) {
          beforeKey = 'l:${OperationId(map['operationId'] as String).value}';
        } else if (map['schemaVersion'] == 2 && map['referenceKey'] is String) {
          beforeKey = map['referenceKey'] as String;
          if (!(RegExp(r'^l:[0-9a-f-]{36}$').hasMatch(beforeKey) ||
              RegExp(r'^i:[0-9a-f]{64}$').hasMatch(beforeKey))) {
            throw const FormatException();
          }
        } else {
          throw const FormatException();
        }
      } on Object {
        throw ArgumentError('Invalid published history cursor.');
      }
    }
    final rows = await _database
        .customSelect(
          '''
      SELECT * FROM (
        SELECT 'l:' || r.operation_id AS reference_key, r.operation_id AS operation_id,
          s.subject_id AS subject_id, s.source_lineage_id AS lineage,
          r.kind AS kind, r.completed_at_micros AS published_at, s.after_content_hash AS content_hash
        FROM operation_subjects s JOIN operation_records r ON r.operation_id = s.operation_id
        WHERE s.managed_skill_id = ? AND s.after_object_id IS NOT NULL AND s.after_content_hash IS NOT NULL AND r.status = 'succeeded'
        UNION ALL
        SELECT 'i:' || e.event_fingerprint, NULL, e.event_fingerprint, e.source_lineage_id,
          e.kind, e.published_at_micros, e.content_hash
        FROM revision_published_events e JOIN source_lineages l ON l.id = e.source_lineage_id
        WHERE l.managed_skill_id = ?
      ) WHERE (? IS NULL OR published_at < ? OR (published_at = ? AND reference_key < ?))
      ORDER BY published_at DESC, reference_key DESC LIMIT ?
    ''',
          variables: [
            Variable.withString(managedSkillId.value),
            Variable.withString(managedSkillId.value),
            Variable<int>(beforeMicros),
            Variable<int>(beforeMicros),
            Variable<int>(beforeMicros),
            Variable<String>(beforeKey),
            Variable.withInt(limit + 1),
          ],
          readsFrom: {
            _database.operationSubjects,
            _database.operationRecords,
            _database.revisionPublishedEvents,
            _database.sourceLineages,
          },
        )
        .get();
    final page = rows.take(limit).toList();
    return domain.PublishedHistoryPage(
      revisions: [
        for (final row in page)
          domain.PublishedRevisionSummary(
            reference: row.readNullable<String>('operation_id') != null
                ? OperationSubjectReference(
                    operationId: OperationId(row.read<String>('operation_id')),
                    subjectId: row.read<String>('subject_id'),
                  )
                : ImportedPublishedRevisionReference(
                    eventFingerprint: row.read<String>('subject_id'),
                    localLineageFingerprint: sha256
                        .convert(
                          utf8.encode(
                            'local-lineage:${row.read<String>('lineage')}',
                          ),
                        )
                        .toString(),
                  ),
            managedSkillId: managedSkillId,
            kind: _operationKind(row.read<String>('kind')),
            origin: row.readNullable<String>('operation_id') == null
                ? domain.PublishedRevisionOrigin.imported
                : domain.PublishedRevisionOrigin.local,
            publishedAt: _utc(row.read<int>('published_at')),
            contentHash: row.read<String>('content_hash'),
          ),
      ],
      nextCursor: rows.length > limit
          ? base64Url.encode(
              utf8.encode(
                jsonEncode({
                  'schemaVersion': 2,
                  'kind': 'published',
                  'orderedAtMicros': page.last.read<int>('published_at'),
                  'referenceKey': page.last.read<String>('reference_key'),
                }),
              ),
            )
          : null,
    );
  }

  Future<List<db.OperationRecord>> _operationRecords({
    required ManagedSkillId? managedSkillId,
    required _HistoryCursor? cursor,
    required int limit,
  }) async {
    if (managedSkillId == null) {
      final query = _database.select(_database.operationRecords);
      _applyOperationCursor(query, cursor);
      query
        ..orderBy([
          (row) => OrderingTerm.desc(row.startedAtMicros),
          (row) => OrderingTerm.desc(row.operationId),
        ])
        ..limit(limit);
      return query.get();
    }

    final query = _database.select(_database.operationRecords).join([
      innerJoin(
        _database.operationSubjects,
        _database.operationSubjects.operationId.equalsExp(
              _database.operationRecords.operationId,
            ) &
            _database.operationSubjects.managedSkillId.equals(
              managedSkillId.value,
            ),
      ),
    ]);
    if (cursor != null) {
      query.where(
        _database.operationRecords.startedAtMicros.isSmallerThanValue(
              cursor.orderedAtMicros,
            ) |
            (_database.operationRecords.startedAtMicros.equals(
                  cursor.orderedAtMicros,
                ) &
                _database.operationRecords.operationId.isSmallerThanValue(
                  cursor.operationId,
                )),
      );
    }
    query
      ..orderBy([
        OrderingTerm.desc(_database.operationRecords.startedAtMicros),
        OrderingTerm.desc(_database.operationRecords.operationId),
      ])
      ..limit(limit);
    return (await query.get())
        .map((row) => row.readTable(_database.operationRecords))
        .toList(growable: false);
  }

  void _applyOperationCursor(
    SimpleSelectStatement<db.$OperationRecordsTable, db.OperationRecord> query,
    _HistoryCursor? cursor,
  ) {
    if (cursor == null) return;
    query.where(
      (row) =>
          row.startedAtMicros.isSmallerThanValue(cursor.orderedAtMicros) |
          (row.startedAtMicros.equals(cursor.orderedAtMicros) &
              row.operationId.isSmallerThanValue(cursor.operationId)),
    );
  }
}

domain.OperationSubjectSummary _operationSubject(db.OperationSubject subject) =>
    domain.OperationSubjectSummary(
      reference: OperationSubjectReference(
        operationId: OperationId(subject.operationId),
        subjectId: subject.subjectId,
      ),
      managedSkillId: ManagedSkillId(subject.managedSkillId),
      displayName: subject.displayName,
      beforeContentHash: subject.beforeContentHash,
      afterContentHash: subject.afterContentHash,
    );

domain.WorkspaceOperationKind _operationKind(String value) {
  for (final kind in domain.WorkspaceOperationKind.values) {
    if (kind.name == value) return kind;
  }
  throw StateError('Unsupported persisted operation kind.');
}

domain.OperationTerminalStatus _terminalStatus(String value) => switch (value) {
  'succeeded' => domain.OperationTerminalStatus.succeeded,
  'failed' => domain.OperationTerminalStatus.failed,
  'cancelled' => domain.OperationTerminalStatus.cancelled,
  _ => throw StateError('Unsupported persisted operation status.'),
};

void _requireLimit(int value) {
  if (value <= 0) {
    throw ArgumentError.value(value, 'limit', 'must be positive');
  }
}

DateTime _utc(int micros) =>
    DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);

enum _CursorKind { operations }

final class _HistoryCursor {
  const _HistoryCursor({
    required this.kind,
    required this.orderedAtMicros,
    required this.operationId,
  });

  final _CursorKind kind;
  final int orderedAtMicros;
  final String operationId;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'kind': kind.name,
        'orderedAtMicros': orderedAtMicros,
        'operationId': operationId,
      }),
    ),
  );

  static _HistoryCursor decode(
    String value, {
    required _CursorKind expectedKind,
  }) {
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(value)));
      if (decoded is! Map<String, Object?> ||
          decoded['schemaVersion'] != 1 ||
          decoded['kind'] != expectedKind.name ||
          decoded['orderedAtMicros'] is! int ||
          decoded['operationId'] is! String) {
        throw const FormatException();
      }
      final operationId = decoded['operationId']! as String;
      OperationId(operationId);
      return _HistoryCursor(
        kind: expectedKind,
        orderedAtMicros: decoded['orderedAtMicros']! as int,
        operationId: operationId,
      );
    } on Object {
      throw ArgumentError.value(value, 'cursor', 'is not a valid cursor');
    }
  }
}
