import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skills_manager/app/app_router.dart';
import 'package:skills_manager/features/cloud/presentation/view_models/cloud_sign_in_view_model.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/settings/data/app_settings_store.dart';
import 'package:skills_manager/features/settings/models/app_settings.dart';
import 'package:skills_manager/shared/analytics/app_analytics.dart';
import 'package:skills_manager/shared/diagnostics/app_diagnostics.dart';

import '../../../support/fake_skill_browser_repository.dart';
import '../../../support/recording_app_analytics.dart';
import '../../../support/skills_manager_test_app.dart';

const _origin = 'https://cloud.example.test';
const _email = 'sign-in-only@example.test';
const _token = 'sign-in-only-token';

final _originValue = CloudServiceOrigin.parse(_origin);
final _signInButton = find.text('Sign in');
final _signOutButton = find.text('Sign out');

void main() {
  for (final (name, origin, isMacOS) in [
    ('without an origin', '', true),
    ('with an invalid origin', 'https://cloud.example.test/path', true),
    ('on a non-macOS platform', _origin, false),
  ]) {
    testWidgets('hides the Cloud section and builds no client $name', (
      tester,
    ) async {
      var clientBuilds = 0;
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          initialLocation: '/settings?section=cloud',
          overrides: [
            cloudIsMacOSProvider.overrideWithValue(isMacOS),
            cloudOriginDefineProvider.overrideWithValue(origin),
            cloudHttpClientProvider.overrideWith((ref) {
              clientBuilds++;
              return null;
            }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SkillDeck Cloud'), findsNothing);
      expect(find.byKey(const Key('settings-section-cloud')), findsNothing);
      expect(clientBuilds, 0);
    });
  }

  testWidgets('system sign-in stores credentials securely and signs out', (
    tester,
  ) async {
    final store = InMemoryCloudSessionStore();
    final analytics = RecordingAppAnalytics();
    final logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);
    final directory = Directory.systemTemp.createTempSync(
      'cloud-settings-test',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final settingsFile = File('${directory.path}/app-settings.json');
    final settingsStore = SharedPreferencesAppSettingsStore(
      preferences: _FileSettingsPreferences(settingsFile),
    );
    await settingsStore.write(const AppSettings());
    final originalSettings = settingsFile.readAsStringSync();
    final openedUrls = <Uri>[];
    var exchanges = 0;
    final completion = Completer<Uri?>();

    await _pumpSettings(
      tester,
      store,
      MockClient((request) async {
        expect(request.url.origin, _origin);
        switch (request.url.path) {
          case '/app/token':
            exchanges++;
            expect(request.bodyFields['client_id'], 'skilldeck-desktop');
            return _json({'access_token': _token, 'token_type': 'bearer'});
          case '/api/auth/get-session':
            if (!request.headers.containsKey('authorization')) {
              return http.Response('null', 200);
            }
            expect(request.headers['authorization'], 'Bearer $_token');
            return _json({
              'user': {'id': 'example-account', 'email': _email},
              'session': {'expiresAt': '2027-01-01T00:00:00Z'},
            });
          case '/api/auth/sign-out':
            expect(request.headers['authorization'], 'Bearer $_token');
            return _json({'success': true});
          default:
            fail('Unexpected Cloud request path');
        }
      }),
      settingsStore: settingsStore,
      overrides: [
        appAnalyticsProvider.overrideWithValue(analytics),
        appDiagnosticsProvider.overrideWithValue(
          AppDiagnostics.debug(writer: logs.add),
        ),
        cloudWebAuthenticatorProvider.overrideWithValue(
          _Authenticator((uri) {
            openedUrls.add(uri);
            return completion.future;
          }),
        ),
      ],
    );

    expect(find.byKey(const Key('settings-section-cloud')), findsOneWidget);
    await tester.tap(_signInButton);
    await tester.pump();
    expect(find.text('Continue in the sign-in window.'), findsOneWidget);
    expect(openedUrls, hasLength(1));
    await tester.tap(_signInButton);
    await tester.pump();
    expect(openedUrls, hasLength(1));
    completion.complete(_callback(openedUrls.single));
    await tester.pumpAndSettle();
    expect(exchanges, 1);
    expect(find.text(_email), findsOneWidget);
    expect((await store.read(_originValue))?.token, _token);

    final settingsAfterSignIn = settingsFile.readAsStringSync();
    expect(settingsAfterSignIn, originalSettings);
    final outputs = [
      ...logs,
      for (final event in analytics.events)
        jsonEncode({
          'category': event.category,
          'action': event.action,
          'name': event.name,
          'dimensions': event.dimensions(platform: 'macos', appVersion: 'test'),
        }),
      settingsAfterSignIn,
    ].join('\n');
    expect(outputs, isNot(contains(_email)));
    expect(outputs, isNot(contains(_token)));

    await tester.tap(_signOutButton);
    await tester.pump();
    expect(await store.read(_originValue), isNull);
    expect(find.text(_email), findsNothing);
    expect(_signInButton, findsOneWidget);
  });

  testWidgets(
    'leaving Settings keeps sign-in alive and returning shows its result',
    (tester) async {
      final store = InMemoryCloudSessionStore();
      final pending = Completer<Uri?>();
      Uri? started;
      await _pumpSettings(
        tester,
        store,
        MockClient(
          (request) async => request.url.path == '/app/token'
              ? _json({'access_token': _token, 'token_type': 'Bearer'})
              : _json({
                  'user': {'id': 'example-account', 'email': _email},
                  'session': {'expiresAt': '2027-01-01T00:00:00Z'},
                }),
        ),
        overrides: [
          cloudWebAuthenticatorProvider.overrideWithValue(
            _Authenticator((url) {
              started = url;
              return pending.future;
            }),
          ),
        ],
      );
      final container = ProviderScope.containerOf(
        tester.element(_signInButton),
      );
      await tester.tap(_signInButton);
      await tester.pump();
      container.read(skillsRouterProvider).go('/installed');
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        container.read(cloudSignInViewModelProvider).value?.phase,
        CloudSignInPhase.signingIn,
      );
      pending.complete(_callback(started!));
      await tester.pumpAndSettle();
      container.read(skillsRouterProvider).go('/settings?section=cloud');
      await tester.pumpAndSettle();
      expect(find.text(_email), findsOneWidget);
      expect((await store.read(_originValue))?.token, _token);
    },
  );

  for (final locale in ['en', 'zh']) {
    final chinese = locale == 'zh';
    final signInLabel = chinese ? '登录' : 'Sign in';
    final signedOut = chinese
        ? '登录后，可在你的多台 Mac 之间同步 Skill。'
        : 'Sign in to sync your Skills between your Macs.';
    for (final denied in [false, true]) {
      testWidgets('$locale cancellation denied=$denied has no error', (
        tester,
      ) async {
        var requests = 0;
        await _pumpSettings(
          tester,
          InMemoryCloudSessionStore(),
          MockClient((_) async {
            requests++;
            return _json({}, 200);
          }),
          locale: Locale(locale),
          overrides: [
            cloudWebAuthenticatorProvider.overrideWithValue(
              _Authenticator(
                (url) => denied ? _callback(url, error: 'access_denied') : null,
              ),
            ),
          ],
        );
        expect(find.text(signedOut), findsOneWidget);
        await tester.tap(find.text(signInLabel));
        await tester.pumpAndSettle();
        expect(find.text(signedOut), findsOneWidget);
        expect(find.text(signInLabel), findsOneWidget);
        expect(requests, 1);
      });
    }
    for (final (status, en, zh) in [
      (
        0,
        "Couldn't reach SkillDeck Cloud. Check your connection and try again.",
        '无法连接 SkillDeck Cloud，请检查网络后重试。',
      ),
      (
        429,
        'SkillDeck Cloud is busy right now. Try again in a minute.',
        'SkillDeck Cloud 暂时繁忙，请稍后重试。',
      ),
      (
        500,
        'SkillDeck Cloud is busy right now. Try again in a minute.',
        'SkillDeck Cloud 暂时繁忙，请稍后重试。',
      ),
      (400, "Sign-in didn't finish. Try again.", '登录没有完成，请重试。'),
    ]) {
      testWidgets('$locale maps $status and clears failure on retry', (
        tester,
      ) async {
        final retry = Completer<Uri?>();
        var attempts = 0;
        var failing = true;
        await _pumpSettings(
          tester,
          InMemoryCloudSessionStore(),
          MockClient((_) async {
            if (!failing) return _json({}, 200);
            if (status == 0) throw http.ClientException('offline');
            return _json({'error': 'invalid_grant'}, status);
          }),
          locale: Locale(locale),
          overrides: [
            cloudWebAuthenticatorProvider.overrideWithValue(
              _Authenticator((url) {
                expect(url.queryParameters['ui_locales'], locale);
                attempts++;
                return failing ? _callback(url) : retry.future;
              }),
            ),
          ],
        );
        await tester.tap(find.text(signInLabel));
        await tester.pumpAndSettle();
        expect(find.text(chinese ? zh : en), findsOneWidget);
        if (status != 400) expect(attempts, 0);
        failing = false;
        await tester.tap(find.text(signInLabel));
        await tester.pump();
        expect(find.text(chinese ? zh : en), findsNothing);
        expect(
          find.text(chinese ? '请在登录窗口中继续。' : 'Continue in the sign-in window.'),
          findsOneWidget,
        );
        retry.complete(null);
        await tester.pumpAndSettle();
      });
    }
  }

  testWidgets(
    'displays the cached account at offline launch and can sign out',
    (tester) async {
      final store = InMemoryCloudSessionStore();
      await store.write(
        StoredCloudSession(
          origin: _originValue,
          token: _token,
          account: CloudAccount(
            id: 'example-account',
            email: _email,
            sessionExpiresAt: DateTime.utc(2027),
          ),
        ),
      );
      await _pumpSettings(
        tester,
        store,
        MockClient((request) async {
          throw http.ClientException('offline fixture', request.url);
        }),
        locale: const Locale('zh'),
      );

      expect(find.text(_email), findsOneWidget);
      expect(find.text('当前离线，暂时无法检查登录状态。'), findsOneWidget);
      expect((await store.read(_originValue))?.token, _token);
      await tester.tap(find.text('退出登录'));
      await tester.pump();
      expect(await store.read(_originValue), isNull);
      expect(find.text(_email), findsNothing);
      expect(find.text('登录'), findsOneWidget);
    },
  );
}

Future<void> _pumpSettings(
  WidgetTester tester,
  CloudSessionStore store,
  MockClient client, {
  AppSettingsStore? settingsStore,
  List<Override> overrides = const [],
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    skillsManagerTestApp(
      browserRepository: FakeSkillBrowserRepository(),
      initialLocation: '/settings?section=cloud',
      locale: locale,
      appSettingsStore: settingsStore,
      overrides: [
        cloudSyncRuntimeProvider.overrideWithValue(null),
        cloudSyncStateProvider.overrideWith(
          (ref) => Stream.value(const CloudSyncState()),
        ),
        cloudIsMacOSProvider.overrideWithValue(true),
        cloudOriginDefineProvider.overrideWithValue(_origin),
        cloudSessionStoreProvider.overrideWithValue(store),
        cloudHttpClientProvider.overrideWithValue(client),
        cloudDeviceProvider.overrideWithValue(
          () async => CloudDevice(
            name: ' Studio Mac ${'🍎' * 64} ',
            platform: CloudDevicePlatform.macos,
          ),
        ),
        ...overrides,
      ],
    ),
  );
  await tester.pumpAndSettle();
}

final class _Authenticator implements CloudWebAuthenticator {
  _Authenticator(this.reply);
  final FutureOr<Uri?> Function(Uri) reply;
  @override
  Future<Uri?> authenticate(Uri url, {required String callbackScheme}) async =>
      reply(url);
}

Uri _callback(Uri url, {String? error}) =>
    Uri.parse('cc.skilldeck.signin:/callback').replace(
      queryParameters: {
        'state': url.queryParameters['state']!,
        if (error != null)
          'error': error
        else
          'code': 'test-authorization-code',
      },
    );

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

final class _FileSettingsPreferences implements SharedPreferencesAsync {
  _FileSettingsPreferences(this.file);

  final File file;

  @override
  Future<String?> getString(String key) async {
    expect(key, SharedPreferencesAppSettingsStore.preferenceKey);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  Future<void> setString(String key, String value) async {
    expect(key, SharedPreferencesAppSettingsStore.preferenceKey);
    file.writeAsStringSync(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
