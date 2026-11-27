import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
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
const _userCode = 'WXYZ-1234';
const _email = 'sign-in-only@example.test';
const _token = 'sign-in-only-token';
const _second = Duration(seconds: 1);

final _originValue = CloudServiceOrigin.parse(_origin);
final _verificationUrl = Uri.parse('$_origin/device?user_code=$_userCode');
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

  testWidgets(
    'logs in through the browser, retries rate limiting, then signs out',
    (tester) async {
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
      var polls = 0;

      await _pumpSettings(
        tester,
        store,
        MockClient((request) async {
          expect(request.url.origin, _origin);
          switch (request.url.path) {
            case '/api/auth/device/code':
              expect(request.bodyFields['client_id'], 'skilldeck-desktop');
              expect(request.bodyFields['device_platform'], 'macos');
              final name = request.bodyFields['device_name']!;
              expect(name.runes.length, 64);
              expect(name, startsWith('Studio Mac'));
              return _deviceCode();
            case '/api/auth/device/token':
              if (++polls == 1) return _json({'error': 'rate_limited'}, 429);
              return _json({'access_token': _token, 'token_type': 'bearer'});
            case '/api/auth/get-session':
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
          cloudBrowserLauncherProvider.overrideWithValue((uri) async {
            openedUrls.add(uri);
            return true;
          }),
        ],
      );

      expect(find.byKey(const Key('settings-section-cloud')), findsOneWidget);
      await tester.tap(_signInButton);
      await tester.pump();
      expect(find.textContaining(_userCode), findsOneWidget);
      expect(openedUrls, isEmpty);

      await tester.tap(find.text('Open browser'));
      await tester.pump();
      expect(openedUrls, [_verificationUrl]);
      await tester.pump(_second);
      expect(polls, 1);
      expect(find.textContaining(_userCode), findsOneWidget);
      await tester.pump(_second);
      expect(polls, 2);
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
            'dimensions': event.dimensions(
              platform: 'macos',
              appVersion: 'test',
            ),
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
    },
  );

  testWidgets('cancel stops polling and restores sign-in', (tester) async {
    final store = InMemoryCloudSessionStore();
    var polls = 0;
    await _pumpSettings(
      tester,
      store,
      MockClient((request) async {
        if (request.url.path.endsWith('/code')) return _deviceCode();
        polls++;
        return _json({'error': 'authorization_pending'}, 400);
      }),
    );
    await tester.tap(_signInButton);
    await tester.pump();
    await tester.pump(_second);
    expect(polls, 1);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(polls, 1);
    expect(_signInButton, findsOneWidget);
    expect(await store.read(_originValue), isNull);
  });

  for (final (error, message) in [
    ('access_denied', 'Sign-in was denied in the browser.'),
    ('expired_token', 'The verification code expired.'),
    ('invalid_client', 'Could not sign in.'),
  ]) {
    testWidgets('offers another sign-in attempt after $error', (tester) async {
      final store = InMemoryCloudSessionStore();
      await _pumpSettings(
        tester,
        store,
        MockClient((request) async {
          if (request.url.path.endsWith('/code')) return _deviceCode();
          return _json({'error': error}, 400);
        }),
      );
      await tester.tap(_signInButton);
      await tester.pump();
      await tester.pump(_second);

      expect(find.text(message), findsOneWidget);
      expect(await store.read(_originValue), isNull);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.textContaining(_userCode), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
    });
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

http.Response _deviceCode() => _json({
  'device_code': 'test-device-code',
  'user_code': _userCode,
  'verification_uri': '$_origin/device',
  'verification_uri_complete': _verificationUrl.toString(),
  'expires_in': 600,
  'interval': 1,
});

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
