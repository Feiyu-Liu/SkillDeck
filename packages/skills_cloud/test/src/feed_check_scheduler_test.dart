import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:test/test.dart';

const _interval = Duration(minutes: 2);
const _tick = Duration(milliseconds: 1);
const _success = FeedCheckResult.success();
const _failure = FeedCheckResult.failure();

void main() {
  test('starts immediately and checks every two minutes while idle', () {
    fakeAsync((time) {
      final fixture = _Fixture(time);
      fixture.scheduler.start();
      fixture.scheduler.start();
      time.flushMicrotasks();
      expect(fixture.starts, [Duration.zero]);

      time.elapse(_interval - _tick);
      expect(fixture.starts, hasLength(1));
      time.elapse(_tick);
      time.elapse(_interval);
      expect(fixture.starts, [Duration.zero, _interval, _interval * 2]);
    });
  });

  test('launch, foreground, reconnect, and wake each request a check', () {
    fakeAsync((time) {
      final fixture = _Fixture(time);
      final scheduler = fixture.scheduler..start();
      time.flushMicrotasks();
      for (final trigger in [
        scheduler.onLaunch,
        scheduler.onForeground,
        scheduler.onReconnect,
        scheduler.onWake,
      ]) {
        time.elapse(const Duration(seconds: 1));
        trigger();
        expect(fixture.starts.last, time.elapsed);
        time.flushMicrotasks();
      }
      expect(fixture.starts, hasLength(5));
    });
  });

  test(
    'one check runs at a time and multiple triggers queue one follow-up',
    () {
      fakeAsync((time) {
        final fixture = _Fixture(time);
        final first = Completer<FeedCheckResult>();
        fixture.response = () => first.future;
        final scheduler = fixture.scheduler..start();
        scheduler.onForeground();
        scheduler.onReconnect();
        time.elapse(const Duration(minutes: 5));
        scheduler.onWake();
        expect(fixture.starts, [Duration.zero]);

        final second = Completer<FeedCheckResult>();
        fixture.response = () => second.future;
        first.complete(_success);
        time.flushMicrotasks();
        expect(fixture.starts, [Duration.zero, time.elapsed]);

        second.complete(_success);
        time.flushMicrotasks();
        time.elapse(_interval - _tick);
        expect(fixture.starts, hasLength(2));
        time.elapse(_tick);
        expect(fixture.starts, hasLength(3));
      });
    },
  );

  test('service delay survives prompt foreground and launch checks', () {
    fakeAsync((time) {
      const serviceDelay = Duration(minutes: 10);
      final fixture = _Fixture(time);
      fixture.response = () async =>
          const FeedCheckResult.success(retryAfter: serviceDelay);
      final scheduler = fixture.scheduler..start();
      time.flushMicrotasks();

      fixture.response = () async => _success;
      time.elapse(_interval);
      scheduler.onForeground();
      time.flushMicrotasks();
      time.elapse(_interval);
      scheduler.onLaunch();
      time.flushMicrotasks();
      expect(fixture.starts, [Duration.zero, _interval, _interval * 2]);

      time.elapse(serviceDelay - time.elapsed - _tick);
      expect(fixture.starts, hasLength(3));
      time.elapse(_tick);
      expect(fixture.starts.last, serviceDelay);
      time.elapse(_interval);
      expect(fixture.starts.last, serviceDelay + _interval);
      expect(fixture.starts, hasLength(5));
    });
  });

  test('a short service delay still waits two minutes', () {
    fakeAsync((time) {
      final fixture = _Fixture(time);
      fixture.response = () async =>
          const FeedCheckResult.success(retryAfter: Duration(seconds: 10));
      fixture.scheduler.start();
      time.elapse(_interval - _tick);
      expect(fixture.starts, hasLength(1));
      time.elapse(_tick);
      expect(fixture.starts.last, _interval);
    });
  });

  test(
    'failures use jittered exponential delays, cap, and reset on success',
    () {
      fakeAsync((time) {
        final jitter = [0.5, 0.0, 0.75, 0.9, 0.2, 0.5].iterator;
        final fixture = _Fixture(
          time,
          random: () {
            expect(jitter.moveNext(), isTrue);
            return jitter.current;
          },
        );
        fixture.response = () async => _failure;
        fixture.scheduler.start();
        time.flushMicrotasks();

        for (final delay in [
          const Duration(minutes: 3),
          const Duration(minutes: 4),
          const Duration(minutes: 14),
          const Duration(minutes: 28, seconds: 30),
        ]) {
          _expectNextCheck(fixture, time, delay);
        }

        fixture.response = () async => _success;
        _expectNextCheck(fixture, time, const Duration(minutes: 18));
        fixture.response = () async => _failure;
        _expectNextCheck(fixture, time, _interval);
        fixture.response = () async => _success;
        _expectNextCheck(fixture, time, const Duration(minutes: 3));
      });
    },
  );

  test('a failure delay replaces the backoff for the next check only', () {
    fakeAsync((time) {
      final fixture = _Fixture(time);
      fixture.response = () async =>
          const FeedCheckResult.failure(retryAfter: Duration(seconds: 10));
      fixture.scheduler.start();
      time.flushMicrotasks();

      fixture.response = () async => _failure;
      _expectNextCheck(fixture, time, const Duration(seconds: 10));
      // The delayed failure still counted, so the backoff has doubled once.
      _expectNextCheck(fixture, time, const Duration(minutes: 6));
    });
  });

  test('a thrown check failure uses backoff and allows later checks', () {
    fakeAsync((time) {
      final fixture = _Fixture(time);
      fixture.response = () => Future.error(TimeoutException('test timeout'));
      fixture.scheduler.start();
      time.flushMicrotasks();
      fixture.response = () async => _success;
      _expectNextCheck(fixture, time, const Duration(minutes: 3));
      _expectNextCheck(fixture, time, _interval);
    });
  });

  test('stop cancels the polling timer and ignores lifecycle triggers', () {
    fakeAsync((time) {
      final fixture = _Fixture(time);
      final scheduler = fixture.scheduler..start();
      time.flushMicrotasks();
      expect(time.nonPeriodicTimerCount, 1);
      scheduler.stop();
      scheduler.onForeground();
      time.elapse(_interval * 2);
      expect(fixture.starts, [Duration.zero]);
      expect(time.nonPeriodicTimerCount, 0);
    });
  });

  test('stop allows the current check to finish and clears its follow-up', () {
    fakeAsync((time) {
      final pending = Completer<FeedCheckResult>();
      final fixture = _Fixture(time);
      var finished = false;
      fixture.response = () async {
        final outcome = await pending.future;
        finished = true;
        return outcome;
      };
      final scheduler = fixture.scheduler..start();
      scheduler.onReconnect();
      scheduler.stop();
      pending.complete(_success);
      time.elapse(_interval * 2);
      expect(finished, isTrue);
      expect(fixture.starts, [Duration.zero]);
      expect(time.nonPeriodicTimerCount, 0);
    });
  });

  test('restart waits if a check from before stop is still running', () {
    fakeAsync((time) {
      final first = Completer<FeedCheckResult>();
      final fixture = _Fixture(time);
      fixture.response = () => first.future;
      final scheduler = fixture.scheduler..start();
      scheduler.stop();
      scheduler.start();
      time.elapse(_interval);
      expect(fixture.starts, [Duration.zero]);

      fixture.response = () async => _success;
      first.complete(_success);
      time.flushMicrotasks();
      expect(fixture.starts, [Duration.zero, _interval]);
    });
  });
}

void _expectNextCheck(_Fixture fixture, FakeAsync time, Duration delay) {
  final count = fixture.starts.length;
  time.elapse(delay - _tick);
  expect(fixture.starts, hasLength(count));
  time.elapse(_tick);
  expect(fixture.starts, hasLength(count + 1));
  expect(fixture.starts.last, time.elapsed);
}

final class _Fixture {
  _Fixture(FakeAsync time, {double Function()? random}) {
    scheduler = FeedCheckScheduler(
      check: () {
        starts.add(time.elapsed);
        return response();
      },
      elapsed: () => time.elapsed,
      createTimer: Timer.new,
      random: random ?? () => 0.5,
    );
  }

  final starts = <Duration>[];
  Future<FeedCheckResult> Function() response = () async => _success;
  late final FeedCheckScheduler scheduler;
}
