import 'dart:convert';

import 'package:drift/drift.dart';

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
  }) {
    _requireLimit(limit);
    final decodedCursor = cursor == null
        ? null
        : _HistoryCursor.decode(cursor, expectedKind: _CursorKind.published);
    return _database.transaction(() async {
      final query = _database.select(_database.operationSubjects).join([
        innerJoin(
          _database.operationRecords,
          _database.operationRecords.operationId.equalsExp(
            _database.operationSubjects.operationId,
          ),
        ),
      ]);
      query.where(
        _database.operationSubjects.managedSkillId.equals(
              managedSkillId.value,
            ) &
            _database.operationSubjects.afterObjectId.isNotNull() &
            _database.operationSubjects.afterContentHash.isNotNull() &
            _database.operationRecords.status.equals('succeeded'),
      );
      if (decodedCursor != null) {
        query.where(
          _database.operationRecords.completedAtMicros.isSmallerThanValue(
                decodedCursor.orderedAtMicros,
              ) |
              (_database.operationRecords.completedAtMicros.equals(
                    decodedCursor.orderedAtMicros,
                  ) &
                  _database.operationRecords.operationId.isSmallerThanValue(
                    decodedCursor.operationId,
                  )),
        );
      }
      query
        ..orderBy([
          OrderingTerm.desc(_database.operationRecords.completedAtMicros),
          OrderingTerm.desc(_database.operationRecords.operationId),
        ])
        ..limit(limit + 1);
      final rows = await query.get();
      final hasMore = rows.length > limit;
      final pageRows = hasMore ? rows.take(limit).toList() : rows;
      final entries = pageRows
          .map((row) {
            final subject = row.readTable(_database.operationSubjects);
            final record = row.readTable(_database.operationRecords);
            return domain.PublishedRevisionSummary(
              reference: OperationSubjectReference(
                operationId: OperationId(record.operationId),
                subjectId: subject.subjectId,
              ),
              managedSkillId: ManagedSkillId(subject.managedSkillId),
              kind: _operationKind(record.kind),
              publishedAt: _utc(record.completedAtMicros),
              contentHash: subject.afterContentHash!,
            );
          })
          .toList(growable: false);
      return domain.PublishedHistoryPage(
        revisions: entries,
        nextCursor: hasMore
            ? _HistoryCursor(
                kind: _CursorKind.published,
                orderedAtMicros: pageRows.last
                    .readTable(_database.operationRecords)
                    .completedAtMicros,
                operationId: pageRows.last
                    .readTable(_database.operationRecords)
                    .operationId,
              ).encode()
            : null,
      );
    });
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

enum _CursorKind { operations, published }

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
