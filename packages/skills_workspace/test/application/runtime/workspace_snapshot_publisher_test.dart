import 'dart:async';

import 'package:skills_workspace/src/application/ports/draft_change_hint_ports.dart';
import 'package:skills_workspace/src/application/ports/workspace_lifecycle_ports.dart';
import 'package:skills_workspace/src/application/runtime/workspace_snapshot_publisher.dart';
import 'package:skills_workspace/src/domain/identifiers.dart';
import 'package:skills_workspace/src/domain/public_models.dart';
import 'package:skills_workspace/src/domain/source_descriptor.dart';
import 'package:test/test.dart';

void main() {
  test('publishes initial and changed committed Snapshots in order', () async {
    final reader = _Reader();
    final publisher = WorkspaceSnapshotPublisher(reader: reader);
    final emitted = <RepositorySnapshot>[];
    final subscription = publisher.snapshots.listen(emitted.add);
    const integrity = WorkspaceIntegrityStatus.recovered;
    final initial = await publisher.readInitial(
      integrity: WorkspaceIntegrity(status: integrity),
    );
    await publisher.publishInitial(initial);
    reader.revision = 1;
    final refreshed = await publisher.reload();
    await Future<void>.delayed(Duration.zero);

    expect(publisher.current, refreshed);
    expect(emitted.map((value) => value.revision.value), [0, 1]);
    expect(refreshed.integrity.status, integrity);
    await subscription.cancel();
    await publisher.close();
  });

  test('does not emit a duplicate Snapshot for an unchanged refresh', () async {
    final reader = _Reader();
    final publisher = WorkspaceSnapshotPublisher(reader: reader);
    final emitted = <RepositorySnapshot>[];
    final subscription = publisher.snapshots.listen(emitted.add);
    final initial = await publisher.readInitial(
      integrity: WorkspaceIntegrity(),
    );
    await publisher.publishInitial(initial);
    await publisher.reload();
    await Future<void>.delayed(Duration.zero);

    expect(emitted, hasLength(1));
    await subscription.cancel();
    await publisher.close();
  });

  test(
    'publishes integrity changes without rereading committed state',
    () async {
      final initial = _snapshotWithDraft(0, 0);
      final reader = _SequenceReader(<RepositorySnapshot>[initial]);
      final publisher = WorkspaceSnapshotPublisher(reader: reader);
      final emitted = <RepositorySnapshot>[];
      final subscription = publisher.snapshots.listen(emitted.add);
      await publisher.publishInitial(
        await publisher.readInitial(integrity: WorkspaceIntegrity()),
      );

      publisher.publishIntegrity(
        WorkspaceIntegrity(
          skills: [
            ManagedSkillIntegrity(
              managedSkillId: initial.managedSkills.single.id,
              status: SkillIntegrityStatus.validating,
            ),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(reader.readCount, 1);
      expect(emitted, hasLength(2));
      expect(emitted.last.revision, initial.revision);
      expect(
        emitted.last.integrity.skills.single.status,
        SkillIntegrityStatus.validating,
      );
      await subscription.cancel();
      await publisher.close();
    },
  );

  test('fails closed before initial publication and after close', () async {
    final publisher = WorkspaceSnapshotPublisher(reader: _Reader());
    expect(() => publisher.current, throwsStateError);
    final initial = await publisher.readInitial(
      integrity: WorkspaceIntegrity(),
    );
    await publisher.publishInitial(initial);
    await expectLater(publisher.publishInitial(initial), throwsStateError);
    await publisher.close();
    await publisher.close();
    expect(() => publisher.current, throwsStateError);
    await expectLater(publisher.reload(), throwsStateError);
    expect(
      () => publisher.readInitial(integrity: WorkspaceIntegrity()),
      throwsStateError,
    );
  });

  test('coalesces burst hints into one authoritative reload', () async {
    final initial = _snapshotWithDraft(0, 0);
    final refreshed = _snapshotWithDraft(1, 0, dirty: true);
    final reader = _SequenceReader(<RepositorySnapshot>[initial, refreshed]);
    final hints = _Hints();
    final debounce = _ManualDebounceScheduler();
    final publisher = WorkspaceSnapshotPublisher(
      reader: reader,
      draftChangeHints: hints,
      debounceScheduler: debounce.schedule,
    );
    final first = await publisher.readInitial(integrity: WorkspaceIntegrity());
    await publisher.publishInitial(first);

    hints
      ..emit('/tmp/drafts/skill-0')
      ..emit('/tmp/drafts/skill-0')
      ..emit('/tmp/drafts/skill-0');

    expect(debounce.pendingCount, 1);
    debounce.fireNext();
    await reader.waitForReadCount(2);
    await _flushAsyncEvents();
    expect(reader.readCount, 2);
    expect(publisher.current, refreshed);
    await publisher.close();
  });

  test('a hint during a scan schedules one follow-up scan', () async {
    final initial = _snapshotWithDraft(0, 0);
    final firstRefresh = _snapshotWithDraft(1, 0, dirty: true);
    final secondRefresh = _snapshotWithDraft(2, 0);
    final reader = _BlockingSequenceReader(<RepositorySnapshot>[
      initial,
      firstRefresh,
      secondRefresh,
    ]);
    final hints = _Hints();
    final debounce = _ManualDebounceScheduler();
    final publisher = WorkspaceSnapshotPublisher(
      reader: reader,
      draftChangeHints: hints,
      debounceScheduler: debounce.schedule,
    );
    await publisher.publishInitial(
      await publisher.readInitial(integrity: WorkspaceIntegrity()),
    );

    reader.blockNextRead();
    hints.emit('/tmp/drafts/skill-0');
    debounce.fireNext();
    await reader.waitUntilBlocked();
    hints.emit('/tmp/drafts/skill-0');
    expect(debounce.pendingCount, 0);
    reader.releaseBlockedRead();
    await reader.waitForReadCount(2);
    await _flushAsyncEvents();

    expect(debounce.pendingCount, 1);
    debounce.fireNext();
    await reader.waitForReadCount(3);
    await _flushAsyncEvents();
    expect(publisher.current, secondRefresh);
    await publisher.close();
  });

  test('explicit reload synchronizes Draft additions and removals', () async {
    final initial = _snapshotWithDraft(0, 0);
    final changed = _snapshotWithDraft(1, 1);
    final reader = _SequenceReader(<RepositorySnapshot>[initial, changed]);
    final hints = _Hints();
    final publisher = WorkspaceSnapshotPublisher(
      reader: reader,
      draftChangeHints: hints,
    );
    await publisher.publishInitial(
      await publisher.readInitial(integrity: WorkspaceIntegrity()),
    );
    expect(hints.listenCount('/tmp/drafts/skill-0'), 1);

    await publisher.reload();

    expect(hints.cancelCount('/tmp/drafts/skill-0'), 1);
    expect(hints.listenCount('/tmp/drafts/skill-1'), 1);
    await publisher.close();
    expect(hints.cancelCount('/tmp/drafts/skill-1'), 1);
  });

  test(
    'watch termination rechecks state and resubscribes after success',
    () async {
      final initial = _snapshotWithDraft(0, 0);
      final reader = _SequenceReader(<RepositorySnapshot>[initial, initial]);
      final hints = _Hints();
      final debounce = _ManualDebounceScheduler();
      final publisher = WorkspaceSnapshotPublisher(
        reader: reader,
        draftChangeHints: hints,
        debounceScheduler: debounce.schedule,
      );
      await publisher.publishInitial(
        await publisher.readInitial(integrity: WorkspaceIntegrity()),
      );

      await hints.end('/tmp/drafts/skill-0');
      expect(debounce.pendingCount, 1);
      debounce.fireNext();
      await reader.waitForReadCount(2);
      await _flushAsyncEvents();

      expect(hints.listenCount('/tmp/drafts/skill-0'), 2);
      await publisher.close();
    },
  );

  test(
    'hint reload failure preserves current state and reports once',
    () async {
      final initial = _snapshotWithDraft(0, 0);
      final recovered = _snapshotWithDraft(1, 0, dirty: true);
      final reader = _SequenceReader(
        <RepositorySnapshot>[initial, recovered],
        failures: <Object>[StateError('scan failed')],
      );
      final hints = _Hints();
      final debounce = _ManualDebounceScheduler();
      final errors = <Object>[];
      final publisher = WorkspaceSnapshotPublisher(
        reader: reader,
        draftChangeHints: hints,
        debounceScheduler: debounce.schedule,
        onHintRefreshError: (error, _) => errors.add(error),
      );
      await publisher.publishInitial(
        await publisher.readInitial(integrity: WorkspaceIntegrity()),
      );

      hints.emit('/tmp/drafts/skill-0');
      debounce.fireNext();
      await reader.waitForReadCount(2);
      await _flushAsyncEvents();

      expect(errors, hasLength(1));
      expect(publisher.current, initial);
      expect(await publisher.reload(), recovered);
      await publisher.close();
    },
  );

  test('close cancels pending debounce and every Draft subscription', () async {
    final initial = RepositorySnapshot(
      revision: RepositoryRevision.initial(),
      managedSkills: <ManagedSkill>[_skill(0), _skill(1)],
    );
    final hints = _Hints();
    final debounce = _ManualDebounceScheduler();
    final reader = _SequenceReader(<RepositorySnapshot>[initial]);
    final publisher = WorkspaceSnapshotPublisher(
      reader: reader,
      draftChangeHints: hints,
      debounceScheduler: debounce.schedule,
    );
    await publisher.publishInitial(
      await publisher.readInitial(integrity: WorkspaceIntegrity()),
    );
    hints.emit('/tmp/drafts/skill-0');
    expect(debounce.pendingCount, 1);

    await publisher.close();

    expect(debounce.pendingCount, 0);
    expect(hints.cancelCount('/tmp/drafts/skill-0'), 1);
    expect(hints.cancelCount('/tmp/drafts/skill-1'), 1);
    expect(reader.readCount, 1);
  });
}

final class _Reader implements WorkspaceSnapshotReaderPort {
  int revision = 0;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async =>
      RepositorySnapshot(
        revision: RepositoryRevision(revision),
        integrity: integrity,
      );
}

final class _SequenceReader implements WorkspaceSnapshotReaderPort {
  _SequenceReader(this.snapshots, {List<Object> failures = const <Object>[]})
    : failures = List<Object>.of(failures);

  final List<RepositorySnapshot> snapshots;
  final List<Object> failures;
  final List<Completer<void>> _readWaiters = [];
  var readCount = 0;
  var _snapshotIndex = 0;

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async {
    readCount += 1;
    for (final waiter in _readWaiters.toList(growable: false)) {
      if (!waiter.isCompleted) waiter.complete();
    }
    if (readCount > 1 && failures.isNotEmpty) throw failures.removeAt(0);
    final snapshot =
        snapshots[_snapshotIndex < snapshots.length
            ? _snapshotIndex++
            : snapshots.length - 1];
    return snapshot;
  }

  Future<void> waitForReadCount(int count) {
    if (readCount >= count) return Future<void>.value();
    final completer = Completer<void>();
    _readWaiters.add(completer);
    return completer.future.then((_) => waitForReadCount(count));
  }
}

final class _BlockingSequenceReader implements WorkspaceSnapshotReaderPort {
  _BlockingSequenceReader(this.snapshots);

  final List<RepositorySnapshot> snapshots;
  final List<Completer<void>> _readWaiters = [];
  var readCount = 0;
  var _snapshotIndex = 0;
  Completer<void>? _blocked;
  Completer<void>? _blockedStarted;

  void blockNextRead() {
    _blocked = Completer<void>();
    _blockedStarted = Completer<void>();
  }

  Future<void> waitUntilBlocked() => _blockedStarted!.future;

  void releaseBlockedRead() => _blocked!.complete();

  @override
  Future<RepositorySnapshot> read({WorkspaceIntegrity? integrity}) async {
    readCount += 1;
    for (final waiter in _readWaiters.toList(growable: false)) {
      if (!waiter.isCompleted) waiter.complete();
    }
    final blocked = _blocked;
    if (blocked != null) {
      _blockedStarted!.complete();
      await blocked.future;
      _blocked = null;
    }
    return snapshots[_snapshotIndex < snapshots.length
        ? _snapshotIndex++
        : snapshots.length - 1];
  }

  Future<void> waitForReadCount(int count) {
    if (readCount >= count) return Future<void>.value();
    final completer = Completer<void>();
    _readWaiters.add(completer);
    return completer.future.then((_) => waitForReadCount(count));
  }
}

final class _Hints implements DraftChangeHintPort {
  final Map<String, _HintStream> _streams = {};

  @override
  Stream<DraftChangeHint> watchDraft(String draftPath) =>
      _streams.putIfAbsent(draftPath, _HintStream.new).newStream();

  void emit(String path) => _streams[path]!.emit();

  Future<void> end(String path) => _streams[path]!.endCurrentStream();

  int listenCount(String path) => _streams[path]?.listenCount ?? 0;

  int cancelCount(String path) => _streams[path]?.cancelCount ?? 0;
}

final class _HintStream {
  StreamController<DraftChangeHint>? _controller;
  var listenCount = 0;
  var cancelCount = 0;

  Stream<DraftChangeHint> newStream() {
    late final StreamController<DraftChangeHint> controller;
    controller = StreamController<DraftChangeHint>.broadcast(
      sync: true,
      onListen: () => listenCount += 1,
      onCancel: () => cancelCount += 1,
    );
    _controller = controller;
    return controller.stream;
  }

  void emit() => _controller!.add(const DraftChangeHint());

  Future<void> endCurrentStream() => _controller!.close();
}

final class _ManualDebounceScheduler {
  final List<_ManualDebounceHandle> _handles = [];

  DraftHintDebounceHandle schedule(
    Duration duration,
    void Function() callback,
  ) {
    final handle = _ManualDebounceHandle(callback);
    _handles.add(handle);
    return handle;
  }

  int get pendingCount =>
      _handles.where((handle) => !handle.cancelled && !handle.fired).length;

  void fireNext() {
    final handle = _handles.firstWhere(
      (candidate) => !candidate.cancelled && !candidate.fired,
    );
    handle.fire();
  }
}

final class _ManualDebounceHandle implements DraftHintDebounceHandle {
  _ManualDebounceHandle(this.callback);

  final void Function() callback;
  var cancelled = false;
  var fired = false;

  @override
  void cancel() => cancelled = true;

  void fire() {
    if (cancelled || fired) return;
    fired = true;
    callback();
  }
}

RepositorySnapshot _snapshotWithDraft(
  int revision,
  int skillIndex, {
  bool dirty = false,
}) => RepositorySnapshot(
  revision: RepositoryRevision(revision),
  managedSkills: <ManagedSkill>[_skill(skillIndex, dirty: dirty)],
);

ManagedSkill _skill(int index, {bool dirty = false}) => ManagedSkill(
  id: ManagedSkillId(
    '123e4567-e89b-42d3-a456-${(426614174000 + index).toString().padLeft(12, '0')}',
  ),
  slotKey: 'skill-$index',
  declaredName: 'skill-$index',
  displayName: 'Skill $index',
  description: 'Description $index',
  source: GitSourceDescriptor(locator: 'https://example.com/repo.git'),
  currentRevision: ManagedSkillRevisionSummary(
    contentHash:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    fileCount: 1,
    byteSize: 10,
    publishedAt: DateTime.utc(2026, 8, 20),
  ),
  draft: DraftSummary(
    purpose: DraftPurpose.customization,
    path: '/tmp/drafts/skill-$index',
    isDirty: dirty,
    updatedAt: DateTime.utc(2026, 8, 20),
  ),
);

Future<void> _flushAsyncEvents() async {
  await Future<void>.value();
  await Future<void>.value();
}
