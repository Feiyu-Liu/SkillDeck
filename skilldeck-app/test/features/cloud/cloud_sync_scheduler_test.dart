import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/sync/cloud_sync_scheduler.dart';

final class _Timer implements Timer {
  _Timer(this.delay, this.callback);
  final Duration delay;
  final void Function() callback;
  bool active = true;
  @override
  bool get isActive => active;
  @override
  int get tick => active ? 0 : 1;
  @override
  void cancel() => active = false;
  void fire() {
    if (!active) return;
    active = false;
    callback();
  }
}

void main() {
  test('period jitter, foreground debounce and overlapping manual calls share one run', () async {
    final timers = <_Timer>[];
    var runs = 0;
    final running = Completer<void>();
    final scheduler = AppCloudSyncScheduler(
      synchronize: () async {
        runs++;
        await running.future;
      },
      cancelAndDrain: () async {},
      random: () => 0,
      clock: () => DateTime.utc(2026, 11, 15),
      timer: (delay, callback) {
        final timer = _Timer(delay, callback);
        timers.add(timer);
        return timer;
      },
    );
    scheduler.start(immediate: false);
    expect(timers.last.delay, const Duration(minutes: 24));
    scheduler.foreground();
    final old = timers.last;
    scheduler.foreground();
    expect(old.isActive, isFalse);
    expect(timers.last.delay, const Duration(seconds: 1));
    final first = scheduler.runNow(), second = scheduler.runNow();
    expect(identical(first, second), isTrue);
    expect(runs, 1);
    running.complete();
    await first;
    expect(timers.last.delay, const Duration(minutes: 24));
    await scheduler.close();
    expect(timers.every((timer) => !timer.isActive), isTrue);
  });
  test('failure backoff is exponential through six hours and foreground does not bypass it', () async {
    final timers = <_Timer>[];
    final scheduler = AppCloudSyncScheduler(
      synchronize: () async {
        throw const CloudException(CloudErrorCode.unavailable);
      },
      cancelAndDrain: () async {},
      random: () => 1,
      timer: (delay, callback) {
        final timer = _Timer(delay, callback);
        timers.add(timer);
        return timer;
      },
    );
    scheduler.start(immediate: false);
    expect(timers.last.delay, const Duration(minutes: 36));
    for (var attempt = 0; attempt < 12; attempt++) {
      await expectLater(scheduler.runNow(), throwsA(isA<CloudException>()));
      final expected = attempt < 9 ? 1 << attempt : 360;
      expect(
        timers.last.delay,
        Duration(minutes: expected > 360 ? 360 : expected),
      );
      final count = timers.length;
      scheduler.foreground();
      expect(timers.length, count);
    }
    await scheduler.close();
  });
  test('pause drains old work, rejects interleaved restart and isolates observer failures', () async {
    final work = Completer<void>(), drain = Completer<void>();
    var runs = 0, cancellations = 0;
    final scheduler = AppCloudSyncScheduler(
      synchronize: () async {
        runs++;
        if (runs == 1) await work.future;
      },
      cancelAndDrain: () async {
        cancellations++;
        await drain.future;
      },
      onState: (_) {
        throw StateError('observer failure');
      },
      timer: (delay, callback) => _Timer(delay, callback),
    );
    scheduler.start(immediate: false);
    final run = scheduler.runNow();
    final paused = scheduler.pause();
    expect(() => scheduler.start(), throwsA(isA<CloudException>()));
    expect(() => scheduler.runNow(), throwsA(isA<CloudException>()));
    work.complete();
    drain.complete();
    await run;
    await paused;
    expect(scheduler.enabled, isFalse);
    expect(scheduler.state.phase, CloudSchedulePhase.paused);
    scheduler.start(immediate: false);
    await scheduler.runNow();
    expect(runs, 2);
    expect(scheduler.state.phase, CloudSchedulePhase.scheduled);
    await scheduler.close();
    expect(cancellations, 2);
  });
}
