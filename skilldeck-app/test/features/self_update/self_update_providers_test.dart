import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/self_update/self_update_providers.dart';

void main() {
  test('native install request exits exactly once, not on download', () async {
    final platform = _FakeAutoUpdaterPlatform();
    var quits = 0;
    final quitCompleted = Completer<void>();
    final coordinator = AppUpdateCoordinator.forTesting(
      platform: platform,
      onQuitForUpdate: () async {
        quits++;
        await quitCompleted.future;
      },
    );
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    platform
      ..emit('update-available')
      ..emit('update-downloaded')
      ..emit('update-cancelled');
    await pumpEventQueue();
    expect(quits, 0);

    platform
      ..emit('before-quit-for-update')
      ..emit('before-quit-for-update');
    await pumpEventQueue();
    expect(quits, 1);
    quitCompleted.complete();
    await pumpEventQueue();

    platform.emit('before-quit-for-update');
    await pumpEventQueue();
    expect(quits, 1);
  });

  test('macOS leaves native update termination to Sparkle', () async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });
    platform.emit('before-quit-for-update');
    await pumpEventQueue();
    expect(coordinator.state, isA<AppUpdateDownloaded>());
  });

  test('disposed updater ignores an install request', () async {
    var quits = 0;
    final platform = _FakeAutoUpdaterPlatform();
    addTearDown(platform.close);
    final coordinator = AppUpdateCoordinator.forTesting(
      platform: platform,
      onQuitForUpdate: () async => quits++,
    );
    coordinator.dispose();
    coordinator.onUpdaterBeforeQuitForUpdate(null);
    expect(quits, 0);
  });

  test('cancelled checks return to idle and allow another check', () async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    await coordinator.initialize();
    await pumpEventQueue();
    platform.completeCheck = false;
    await coordinator.checkForUpdates();
    expect(coordinator.state, isA<AppUpdateChecking>());
    // A check that did not start from a prompt has nothing to keep visible.
    expect(coordinator.hasUpdatePrompt, isFalse);

    platform.emit('update-cancelled');
    await pumpEventQueue();
    expect(coordinator.state, isA<AppUpdateIdle>());
    expect(coordinator.hasUpdatePrompt, isFalse);

    final previousChecks = platform.checkCount;
    platform.completeCheck = true;
    await coordinator.checkForUpdates();
    await pumpEventQueue();
    expect(platform.checkCount, previousChecks + 1);
    expect(coordinator.state, isA<AppUpdateIdle>());
  });

  test('cancelling the native dialog keeps an available update', () async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    platform.emit('update-available');
    await pumpEventQueue();
    platform.emit('update-cancelled');
    await pumpEventQueue();

    expect(coordinator.state, isA<AppUpdateAvailable>());
    expect(coordinator.hasUpdatePrompt, isTrue);
  });

  test('ignores native errors from background checks', () async {
    final platform = _FakeAutoUpdaterPlatform()..emitErrorOnCheck = true;
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    await coordinator.initialize();
    await coordinator.checkForUpdates(inBackground: true);
    await Future<void>.delayed(Duration.zero);

    expect(platform.checkCount, 1);
    expect(coordinator.state, isA<AppUpdateIdle>());
    expect(coordinator.hasUpdatePrompt, isFalse);
  });

  test(
    'initialization leaves the startup check to the native scheduler',
    () async {
      final platform = _FakeAutoUpdaterPlatform();
      final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
      addTearDown(() async {
        coordinator.dispose();
        await platform.close();
      });

      await coordinator.initialize();
      await pumpEventQueue();

      // Starting the native updater lets its due scheduled check own the
      // session. A second check from here would be rejected by the native
      // updater while that session is in progress.
      expect(platform.checkCount, 0);
      expect(coordinator.state, isA<AppUpdateIdle>());

      platform
        ..emit('checking-for-update')
        ..emit('update-available')
        ..emit('update-finished');
      await pumpEventQueue();

      expect(platform.checkCount, 0);
      expect(coordinator.state, isA<AppUpdateAvailable>());
      expect(coordinator.hasUpdatePrompt, isTrue);

      // After the native cycle completes, a manual check still starts.
      await coordinator.checkForUpdates();
      await pumpEventQueue();

      expect(platform.checkCount, 1);
      expect(coordinator.state, isA<AppUpdateIdle>());
    },
  );

  test(
    'a check rejected by a native session in progress settles at once',
    () async {
      final platform = _FakeAutoUpdaterPlatform()
        ..checkStart = UpdateCheckStart.busy;
      final coordinator = AppUpdateCoordinator.forTesting(
        platform: platform,
        checkTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        coordinator.dispose();
        await platform.close();
      });

      await coordinator.initialize();
      await coordinator.checkForUpdates();

      expect(platform.checkCount, 1);
      expect(coordinator.state, isA<AppUpdateIdle>());

      // The timeout that used to stand in for the missing answer no longer
      // reports the rejected check as a failure.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(coordinator.state, isA<AppUpdateIdle>());
      expect(coordinator.hasUpdatePrompt, isFalse);

      // The native session's own events still reach the App.
      platform.emit('update-available');
      await pumpEventQueue();
      expect(coordinator.state, isA<AppUpdateAvailable>());

      platform.checkStart = UpdateCheckStart.started;
      await coordinator.checkForUpdates();
      await pumpEventQueue();
      expect(platform.checkCount, 2);
      expect(coordinator.state, isA<AppUpdateIdle>());
    },
  );

  test(
    'a check that focuses the update already shown keeps its prompt',
    () async {
      final platform = _FakeAutoUpdaterPlatform();
      final coordinator = AppUpdateCoordinator.forTesting(
        platform: platform,
        checkTimeout: const Duration(milliseconds: 10),
      );
      addTearDown(() async {
        coordinator.dispose();
        await platform.close();
      });

      await coordinator.initialize();
      platform.emit('update-available');
      await pumpEventQueue();

      platform.checkStart = UpdateCheckStart.resumed;
      await coordinator.checkForUpdates();

      expect(coordinator.state, isA<AppUpdateAvailable>());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(coordinator.state, isA<AppUpdateAvailable>());
      expect(coordinator.hasUpdatePrompt, isTrue);
    },
  );

  test('surfaces native errors from a foreground check', () async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    await coordinator.initialize();
    await Future<void>.delayed(Duration.zero);
    platform.emitErrorOnCheck = true;

    await coordinator.checkForUpdates();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state, isA<AppUpdateFailed>());
    expect(coordinator.hasUpdatePrompt, isTrue);
  });

  test('clears a synchronously failed request so it can be retried', () async {
    final platform = _FakeAutoUpdaterPlatform()..throwOnCheck = true;
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    await coordinator.initialize();
    await Future<void>.delayed(Duration.zero);
    platform.throwOnCheck = false;
    await coordinator.checkForUpdates();
    await Future<void>.delayed(Duration.zero);

    expect(coordinator.state, isA<AppUpdateIdle>());
  });

  test(
    'native update cycle completion clears a stuck checking state',
    () async {
      final platform = _FakeAutoUpdaterPlatform();
      final coordinator = AppUpdateCoordinator.forTesting(
        platform: platform,
        checkTimeout: const Duration(seconds: 1),
      );
      addTearDown(() async {
        coordinator.dispose();
        await platform.close();
      });

      await coordinator.initialize();
      await pumpEventQueue();
      platform.completeCheck = false;
      await coordinator.checkForUpdates();
      expect(coordinator.state, isA<AppUpdateChecking>());

      platform.emit('update-finished');
      await pumpEventQueue();

      expect(coordinator.state, isA<AppUpdateIdle>());
      expect(coordinator.hasUpdatePrompt, isFalse);
    },
  );

  test('foreground update cycle failures surface after completion', () async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    await coordinator.initialize();
    await pumpEventQueue();
    platform.completeCheck = false;
    await coordinator.checkForUpdates();
    expect(coordinator.state, isA<AppUpdateChecking>());

    platform.emit('update-finished', {'error': 'native failure'});
    await pumpEventQueue();

    expect(coordinator.state, isA<AppUpdateFailed>());
    expect(coordinator.hasUpdatePrompt, isTrue);
  });

  test('update cycle completion does not clear an available update', () async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    await coordinator.initialize();
    await pumpEventQueue();
    platform.completeCheck = false;
    await coordinator.checkForUpdates();
    expect(coordinator.state, isA<AppUpdateChecking>());

    platform.emit('update-available');
    await pumpEventQueue();
    platform.emit('update-finished');
    await pumpEventQueue();

    expect(coordinator.state, isA<AppUpdateAvailable>());
    expect(coordinator.hasUpdatePrompt, isTrue);
  });

  test(
    'background update cycle failures remain silent after completion',
    () async {
      final platform = _FakeAutoUpdaterPlatform();
      final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
      addTearDown(() async {
        coordinator.dispose();
        await platform.close();
      });

      await coordinator.initialize();
      await pumpEventQueue();
      platform.completeCheck = false;
      await coordinator.checkForUpdates(inBackground: true);
      expect(coordinator.state, isA<AppUpdateChecking>());

      platform.emit('update-finished', {'error': 'native failure'});
      await pumpEventQueue();

      expect(coordinator.state, isA<AppUpdateIdle>());
      expect(coordinator.hasUpdatePrompt, isFalse);
    },
  );

  test('foreground checks time out instead of staying busy forever', () async {
    final platform = _FakeAutoUpdaterPlatform();
    final coordinator = AppUpdateCoordinator.forTesting(
      platform: platform,
      checkTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(() async {
      coordinator.dispose();
      await platform.close();
    });

    await coordinator.initialize();
    await pumpEventQueue();
    platform.completeCheck = false;
    await coordinator.checkForUpdates();
    expect(coordinator.state, isA<AppUpdateChecking>());

    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(coordinator.state, isA<AppUpdateFailed>());
    expect(coordinator.hasUpdatePrompt, isTrue);
  });

  test(
    'a check started from a prompt keeps the prompt until it settles',
    () async {
      final platform = _FakeAutoUpdaterPlatform();
      final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
      addTearDown(() async {
        coordinator.dispose();
        await platform.close();
      });

      await coordinator.initialize();
      await pumpEventQueue();
      platform.emit('update-available');
      await pumpEventQueue();
      final notified = <bool>[];
      coordinator.addListener(() => notified.add(coordinator.hasUpdatePrompt));

      platform.completeCheck = false;
      await coordinator.checkForUpdates();

      expect(coordinator.state, isA<AppUpdateChecking>());
      expect(coordinator.hasUpdatePrompt, isTrue);
      // No listener ever observes the prompt missing on the way into the check.
      expect(notified, everyElement(isTrue));

      platform.emit('update-not-available');
      await pumpEventQueue();

      expect(coordinator.state, isA<AppUpdateIdle>());
      expect(coordinator.hasUpdatePrompt, isFalse);
    },
  );

  test(
    'cancelling a check started from a prompt restores the prompt',
    () async {
      final platform = _FakeAutoUpdaterPlatform();
      final coordinator = AppUpdateCoordinator.forTesting(platform: platform);
      addTearDown(() async {
        coordinator.dispose();
        await platform.close();
      });

      await coordinator.initialize();
      await pumpEventQueue();
      coordinator.onUpdaterUpdateDownloaded(
        const AppcastItem(displayVersionString: '1.2.0'),
      );
      platform.completeCheck = false;
      await coordinator.checkForUpdates();
      expect(coordinator.state, isA<AppUpdateChecking>());

      platform.emit('update-cancelled');
      await pumpEventQueue();

      expect(
        coordinator.state,
        isA<AppUpdateDownloaded>().having((s) => s.version, 'version', '1.2.0'),
      );
      expect(coordinator.hasUpdatePrompt, isTrue);
    },
  );
}

final class _FakeAutoUpdaterPlatform extends AutoUpdaterPlatform {
  final _events = StreamController<Map<Object?, Object?>>.broadcast();
  bool emitErrorOnCheck = false;
  bool throwOnCheck = false;
  bool completeCheck = true;
  UpdateCheckStart checkStart = UpdateCheckStart.started;
  int checkCount = 0;

  void emit(String type, [Map<Object?, Object?> data = const {}]) {
    _events.add({'type': type, ...data});
  }

  @override
  Stream<Map<Object?, Object?>> get sparkleEvents => _events.stream;

  @override
  Future<void> setFeedURL(String feedUrl) async {}

  @override
  Future<UpdateCheckStart> checkForUpdates({bool? inBackground}) async {
    checkCount++;
    if (throwOnCheck) throw StateError('test failure');
    if (checkStart != UpdateCheckStart.started || !completeCheck) {
      return checkStart;
    }
    if (emitErrorOnCheck) {
      _events.add(const {'type': 'error'});
    } else {
      _events.add(const {'type': 'update-not-available'});
    }
    return checkStart;
  }

  @override
  Future<void> setScheduledCheckInterval(int interval) async {}

  Future<void> close() => _events.close();
}
