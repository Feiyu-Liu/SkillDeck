import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_configuration.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_gateway.dart';
import 'package:skills_manager/features/cloud/sync/cloud_sync_session.dart';
import 'package:skills_manager/features/cloud/presentation/cloud_settings.dart';
import 'package:skills_manager/l10n/l10n.dart';
import 'package:skills_manager/shared/notifications/app_notification.dart';
import 'package:skills_manager/shared/notifications/app_notification_controller.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

final class FakeGateway
    implements AppCloudGateway, AppCloudSyncGateway, AppCloudBackgroundGateway {
  int backgroundRestores = 0, foregrounds = 0;
  @override
  Stream<AppCloudSyncView> get syncUpdates => const Stream.empty();
  @override
  Future<bool> restoreOptedInBackground() async {
    backgroundRestores++;
    connect();
    return true;
  }

  @override
  void foreground() {
    foregrounds++;
  }

  int syncLoads = 0, syncRuns = 0, syncPauses = 0, syncEnables = 0;
  Completer<AppCloudSyncView>? deferredSync;
  AppCloudSyncView sync = const AppCloudSyncView(
    choices: [
      AppCloudSkillChoice(
        id: "local-one",
        name: "My reusable skill",
        kind: AppCloudChoiceKind.local,
      ),
      AppCloudSkillChoice(
        id: "private-local",
        name: "Local files",
        kind: AppCloudChoiceKind.local,
        supported: false,
      ),
      AppCloudSkillChoice(
        id: "remote-one",
        name: "Cloud reusable skill",
        kind: AppCloudChoiceKind.remote,
      ),
    ],
  );
  @override
  Future<AppCloudSyncView> syncOverview() async {
    syncLoads++;
    return sync;
  }

  @override
  Future<AppCloudSyncView> enableSyncChoice(AppCloudSkillChoice choice) async {
    syncEnables++;
    return sync = AppCloudSyncView(
      enabled: true,
      choices: sync.choices,
      selectedIds: {choice.id},
    );
  }

  @override
  Future<AppCloudSyncView> enableSyncChoices(
    List<AppCloudSkillChoice> choices,
  ) async {
    syncEnables++;
    return sync = AppCloudSyncView(
      enabled: true,
      choices: sync.choices,
      selectedIds: choices.map((choice) => choice.id).toSet(),
    );
  }

  @override
  Future<AppCloudSyncView> syncNow() async {
    syncRuns++;
    return deferredSync?.future ?? sync;
  }

  @override
  Future<AppCloudSyncView> stopSync() async {
    syncPauses++;
    return sync = AppCloudSyncView(
      enabled: false,
      choices: sync.choices,
      selectedIds: sync.selectedIds,
    );
  }

  @override
  String get deviceName => 'My Mac';
  @override
  CloudSession? currentSession;
  @override
  bool needsReconciliation = false;
  int signIns = 0, restores = 0, logouts = 0;
  Completer<void>? signInDelay;
  CloudErrorCode? failure;
  final revoked = <String>[];
  final rows = <Map<String, Object?>>[
    {
      'id': 'mine',
      'name': 'My Mac',
      'platform': 'macos',
      'createdAt': 1000,
      'lastSeenAt': 2000,
      'revokedAt': null,
    },
    {
      'id': 'other',
      'name': 'Office PC',
      'platform': 'windows',
      'createdAt': 1000,
      'lastSeenAt': 2000,
      'revokedAt': null,
    },
  ];
  void connect() {
    currentSession = const CloudSession(
      accountId: 'INTERNAL_ACCOUNT_NOT_UI',
      deviceId: 'mine',
      sessionId: 'INTERNAL_SESSION_NOT_UI',
    );
  }

  @override
  Future<CloudSession> signIn(CloudCancellation cancellation) async {
    signIns++;
    if (failure != null) throw CloudException(failure!);
    if (signInDelay case final delay?) {
      final stopped = Completer<void>();
      final unlisten = cancellation.listen(
        () => stopped.completeError(
          const CloudException(CloudErrorCode.cancelled),
        ),
      );
      try {
        await Future.any([delay.future, stopped.future]);
      } finally {
        unlisten();
      }
    }
    cancellation.throwIfCancelled();
    connect();
    return currentSession!;
  }

  @override
  Future<CloudSession?> restore(CloudCancellation cancellation) async {
    restores++;
    cancellation.throwIfCancelled();
    if (failure != null) throw CloudException(failure!);
    connect();
    return currentSession;
  }

  @override
  Future<List<CloudDevice>> devices() async =>
      rows.map(CloudDevice.fromJson).toList();
  @override
  Future<bool> revoke(String deviceId) async {
    revoked.add(deviceId);
    for (final row in rows) {
      if (row['id'] == deviceId) row['revokedAt'] = 3000;
    }
    if (deviceId == 'mine') currentSession = null;
    return true;
  }

  @override
  Future<void> logoutCredentials() async {
    logouts++;
    currentSession = null;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'Inter': 'Inter-Variable.ttf',
      'Space Grotesk': 'SpaceGrotesk-Variable.ttf',
      'JetBrains Mono': 'JetBrainsMono-Variable.ttf',
      'Noto Sans SC': 'NotoSansSC-Variable.ttf',
    }.entries) {
      final loader = FontLoader(entry.key)
        ..addFont(rootBundle.load('assets/fonts/${entry.value}'));
      await loader.load();
    }
  });
  late FakeGateway gateway;
  var factories = 0, startupProbes = 0;
  var hasStartupOptIn = false;
  Future<void> startupReady = Future.value();
  setUp(() {
    gateway = FakeGateway();
    factories = 0;
    startupProbes = 0;
    hasStartupOptIn = false;
    startupReady = Future.value();
  });
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    bool enabled = true,
    Uri? baseUri,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          cloudConfigurationProvider.overrideWithValue(
            CloudConfiguration(
              enabled: enabled,
              baseUri: baseUri ?? Uri.parse('https://cloud.example.invalid'),
            ),
          ),
          cloudWorkspaceReadyProvider.overrideWithValue(() => startupReady),
          cloudStartupProbeProvider.overrideWithValue((_) async {
            startupProbes++;
            return hasStartupOptIn;
          }),
          cloudGatewayFactoryProvider.overrideWithValue((_) async {
            factories++;
            return gateway;
          }),
        ],
        child: CupertinoApp(
          locale: locale,
          localizationsDelegates: appLocalizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: SkillsTheme.theme,
          // Match the real App's standalone/legacy Cupertino interoperability.
          // ignore: deprecated_member_use
          builder: (context, child) => CupertinoUiCompatibilityBridge(
            child: NeoButtonTheme(data: SkillsButtonTheme.neo, child: child!),
          ),
          home: CupertinoPageScaffold(
            child: Center(
              child: RepaintBoundary(
                key: const Key('cloud-capture'),
                child: ColoredBox(
                  color: AppColors.canvas,
                  child: SizedBox(
                    width: 820,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: const SingleChildScrollView(
                        child: CloudSettings(showSectionHeader: true),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(CloudSettings)),
    );
  }

  testWidgets(
    'default flag and missing/unsafe origin do not create services or read secure storage',
    (tester) async {
      expect(CloudConfiguration.fromBuild().enabled, isFalse);
      await pump(tester, enabled: false);
      expect(find.text('Cloud is unavailable in this build.'), findsOneWidget);
      expect(factories, 0);
      expect(gateway.signIns, 0);
      await pump(tester, baseUri: Uri.parse('http://untrusted.invalid'));
      expect(find.byKey(const Key('cloud-sign-in')), findsNothing);
      expect(factories, 0);
    },
  );
  test('background startup waits for ready Workspace and previous opt-in; default builds do no probe', () async {
    ProviderContainer create({
      bool enabled = true,
      required Future<void> ready,
    }) => ProviderContainer(
      overrides: [
        cloudConfigurationProvider.overrideWithValue(
          CloudConfiguration(
            enabled: enabled,
            baseUri: Uri.parse('https://cloud.example.invalid'),
          ),
        ),
        cloudWorkspaceReadyProvider.overrideWithValue(() => ready),
        cloudStartupProbeProvider.overrideWithValue((_) async {
          startupProbes++;
          return hasStartupOptIn;
        }),
        cloudGatewayFactoryProvider.overrideWithValue((_) async {
          factories++;
          return gateway;
        }),
      ],
    );
    var container = create(enabled: false, ready: Future.value());
    await container
        .read(cloudSettingsControllerProvider.notifier)
        .restoreOptedInBackground();
    expect(startupProbes, 0);
    expect(factories, 0);
    container.dispose();
    container = create(ready: Future.value());
    await container
        .read(cloudSettingsControllerProvider.notifier)
        .restoreOptedInBackground();
    expect(startupProbes, 1);
    expect(factories, 0);
    expect(gateway.backgroundRestores, 0);
    container.dispose();
    hasStartupOptIn = true;
    final ready = Completer<void>();
    container = create(ready: ready.future);
    final starting = container
        .read(cloudSettingsControllerProvider.notifier)
        .restoreOptedInBackground();
    await Future<void>.delayed(Duration.zero);
    expect(factories, 0);
    expect(gateway.backgroundRestores, 0);
    ready.complete();
    await starting;
    expect(factories, 1);
    expect(gateway.backgroundRestores, 1);
    expect(gateway.syncRuns, 0);
    container.read(cloudSettingsControllerProvider.notifier).foreground();
    expect(gateway.foregrounds, 1);
    expect(container.read(appNotificationControllerProvider), isNull);
    container.dispose();
  });
  testWidgets(
    'busy browser sign-in can be cancelled through the existing button',
    (tester) async {
      gateway.signInDelay = Completer<void>();
      final container = await pump(tester);
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Complete sign-in in your browser.'), findsOneWidget);
      expect(gateway.signIns, 1);
      await tester.tap(find.byKey(const Key('cloud-cancel')));
      await tester.pumpAndSettle();
      expect(container.read(cloudSettingsControllerProvider).busy, isFalse);
      expect(container.read(cloudSettingsControllerProvider).session, isNull);
      expect(
        container.read(appNotificationControllerProvider)?.notification.message,
        AppNotificationMessage.operationCancelled,
      );
    },
  );
  testWidgets(
    'failures and secure storage errors are short typed notifications, not inline diagnostics',
    (tester) async {
      gateway.failure = CloudErrorCode.secureStorage;
      final container = await pump(tester);
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pumpAndSettle();
      expect(
        container.read(appNotificationControllerProvider)?.notification.message,
        AppNotificationMessage.cloudStorageFailed,
      );
      expect(find.textContaining('PRIVATE_'), findsNothing);
      expect(find.text('This device is connected'), findsNothing);
      gateway.failure = CloudErrorCode.unavailable;
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pumpAndSettle();
      expect(
        container.read(appNotificationControllerProvider)?.notification.message,
        AppNotificationMessage.cloudFailed,
      );
    },
  );
  testWidgets(
    'connected devices can be revoked; logout only clears credentials',
    (tester) async {
      final container = await pump(tester);
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text('This device is connected'), findsOneWidget);
      expect(find.textContaining('INTERNAL_'), findsNothing);
      expect(
        find.text('Signing in does not enable sync or upload any Skills.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('cloud-revoke-other')));
      await tester.pumpAndSettle();
      expect(gateway.revoked, ['other']);
      expect(find.text('Access revoked'), findsOneWidget);
      expect(
        container.read(appNotificationControllerProvider)?.notification.message,
        AppNotificationMessage.cloudRevocationPending,
      );
      await tester.tap(find.byKey(const Key('cloud-sign-out')));
      await tester.pumpAndSettle();
      expect(gateway.logouts, 1);
      expect(find.byKey(const Key('cloud-sign-in')), findsOneWidget);
    },
  );
  testWidgets(
    'old session with lost local scope remains visible but requires reconciliation',
    (tester) async {
      gateway.needsReconciliation = true;
      final container = await pump(tester);
      await tester.tap(find.byKey(const Key('cloud-restore')));
      await tester.pumpAndSettle();
      expect(
        find.text('Local sync records need to be checked again.'),
        findsOneWidget,
      );
      expect(
        container.read(appNotificationControllerProvider)?.notification.message,
        AppNotificationMessage.cloudNeedsReconciliation,
      );
      expect(find.byType(CupertinoSwitch), findsNothing);
    },
  );
  testWidgets(
    'verified account explicitly chooses and confirms multiple Skills before manual sync or pause',
    (tester) async {
      await pump(tester);
      expect(gateway.syncLoads, 0);
      expect(find.byKey(const Key('cloud-load-sync')), findsNothing);
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pumpAndSettle();
      expect(gateway.syncLoads, 0);
      await tester.tap(find.byKey(const Key('cloud-load-sync')));
      await tester.pumpAndSettle();
      expect(gateway.syncLoads, 1);
      expect(gateway.syncEnables, 0);
      final local = find.byKey(const Key('cloud-sync-choice-local-local-one'));
      await tester.ensureVisible(local);
      await tester.tap(
        find.descendant(of: local, matching: find.text('Select')),
      );
      await tester.pumpAndSettle();
      // Selection is local UI state until one explicit batch confirmation.
      expect(gateway.syncEnables, 0);
      final remote = find.byKey(
        const Key('cloud-sync-choice-remote-remote-one'),
      );
      await tester.ensureVisible(remote);
      await tester.tap(
        find.descendant(of: remote, matching: find.text('Select')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('cloud-confirm-selection')),
      );
      await tester.tap(find.byKey(const Key('cloud-confirm-selection')));
      await tester.pumpAndSettle();
      expect(find.text('Enable sync for selected Skills?'), findsOneWidget);
      expect(gateway.syncEnables, 0);
      await tester.tap(find.text('Enable sync').last);
      await tester.pumpAndSettle();
      expect(gateway.syncEnables, 1);
      expect(gateway.syncRuns, 0);
      await tester.ensureVisible(find.byKey(const Key('cloud-sync-now')));
      await tester.tap(find.byKey(const Key('cloud-sync-now')));
      await tester.pumpAndSettle();
      expect(gateway.syncRuns, 1);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const Key('cloud-capture')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/cloud-visual/widget-sync-enabled-en.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.tap(find.byKey(const Key('cloud-stop-sync')));
      await tester.pumpAndSettle();
      expect(gateway.syncPauses, 1);
      expect(gateway.sync.selectedIds, {'local-one', 'remote-one'});
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pause cancels running sync and delayed completion cannot re-enable it',
    (tester) async {
      gateway.sync = const AppCloudSyncView(
        enabled: true,
        selectedIds: {'local-one'},
      );
      gateway.deferredSync = Completer<AppCloudSyncView>();
      final container = await pump(tester);
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-load-sync')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-sync-now')));
      await tester.pump();
      expect(container.read(cloudSettingsControllerProvider).busy, isTrue);
      await tester.tap(find.byKey(const Key('cloud-stop-sync')));
      await tester.pumpAndSettle();
      expect(gateway.syncPauses, 1);
      expect(
        container.read(cloudSettingsControllerProvider).sync!.enabled,
        isFalse,
      );
      gateway.deferredSync!.complete(
        const AppCloudSyncView(enabled: true, selectedIds: {'local-one'}),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(cloudSettingsControllerProvider).sync!.enabled,
        isFalse,
      );
      expect(container.read(cloudSettingsControllerProvider).busy, isFalse);
    },
  );
  testWidgets(
    'initial metadata conflicts explain that local data is preserved',
    (tester) async {
      gateway.sync = const AppCloudSyncView(
        enabled: true,
        pendingCount: 2,
        pendingReasons: {CloudPendingReason.metadataConflict},
      );
      await pump(tester);
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-load-sync')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Some notes, favorites or tag assignments differ. Your local values are kept.',
        ),
        findsOneWidget,
      );
      expect(gateway.syncRuns, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'background retry state stays visible without posting a notification',
    (tester) async {
      gateway.sync = const AppCloudSyncView(
        enabled: true,
        backgroundError: CloudErrorCode.unavailable,
      );
      final container = await pump(tester);
      await tester.tap(find.byKey(const Key('cloud-sign-in')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cloud-load-sync')));
      await tester.pumpAndSettle();
      expect(
        find.text('The last sync could not finish. It will retry later.'),
        findsOneWidget,
      );
      final previous = container.read(appNotificationControllerProvider);
      expect(
        previous?.notification.message,
        isNot(AppNotificationMessage.cloudFailed),
      );
    },
  );
  testWidgets('Chinese copy and widget-only connected visual evidence', (
    tester,
  ) async {
    await pump(tester);
    final initialBoundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('cloud-capture')),
    );
    await tester.runAsync(() async {
      final image = await initialBoundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/cloud-visual/widget-initial-en.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await pump(tester, locale: const Locale('zh'));
    expect(find.text('使用邮箱登录'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cloud-sign-in')));
    await tester.pumpAndSettle();
    expect(find.text('此设备已连接'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('cloud-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/cloud-visual/widget-connected-zh.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
