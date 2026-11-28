// flutter test --no-pub -d macos --dart-define=SKILLDECK_SIGN_IN_CAPTURE=true
// integration_test/cloud_sign_in_capture_test.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/data/macos_web_authenticator.dart';
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/fake_skill_browser_repository.dart';
import '../test/support/skills_manager_test_app.dart';

final class _Authenticator implements CloudWebAuthenticator {
  _Authenticator(this.complete);
  final bool complete;
  int calls = 0;
  final pending = Completer<Uri?>();
  final nativeClosed = Completer<void>();
  @override
  Future<Uri?> authenticate(Uri url, {required String callbackScheme}) async {
    calls++;
    if (!complete &&
        const bool.fromEnvironment('SKILLDECK_CAPTURE_NATIVE_WINDOW')) {
      try {
        return await const MacosWebAuthenticator().authenticate(
          url,
          callbackScheme: callbackScheme,
        );
      } finally {
        nativeClosed.complete();
      }
    }
    return complete
        ? Uri.parse('cc.skilldeck.signin:/callback').replace(
            queryParameters: {
              'code': 'synthetic-code',
              'state': url.queryParameters['state']!,
            },
          )
        : pending.future;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  setUpAll(() async {
    // Capture-only: rapid root replacement can crash Flutter 3.50 native AX traversal.
    binding.platformDispatcher.semanticsEnabledTestValue = false;
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(800, 600));
    await windowManager.setOpacity(1);
    await windowManager.show();
    // AppKit can enable accessibility after showing the native window.
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  testWidgets('capture native App sign-in states with actual fonts', (
    tester,
  ) async {
    final output = Directory(
      const String.fromEnvironment('SKILLDECK_CAPTURE_DIRECTORY'),
    );
    await output.create(recursive: true);
    final origin = CloudServiceOrigin.parse(
      const bool.fromEnvironment('SKILLDECK_CAPTURE_NATIVE_WINDOW')
          ? 'http://127.0.0.1:8787'
          : 'https://cloud.example.test',
    );
    for (final locale in ['en', 'zh']) {
      for (final mode in [AppearanceMode.light, AppearanceMode.dark]) {
        for (final phase in [
          'signed-out',
          'signing-in-app-only',
          'failed-network',
          'failed-busy',
          'failed-other',
          'signed-in',
        ]) {
          final captureKey = GlobalKey();
          final store = InMemoryCloudSessionStore();
          if (phase == 'signed-in') {
            await store.write(
              StoredCloudSession(origin: origin, token: 'synthetic-session'),
            );
          }
          final auth = _Authenticator(phase != 'signing-in-app-only');
          final client = MockClient((request) async {
            if (phase == 'failed-network') {
              throw http.ClientException('offline');
            }
            if (phase == 'failed-busy') return http.Response('{}', 503);
            if (request.url.path == '/api/auth/get-session') {
              return http.Response(
                jsonEncode({
                  'user': {
                    'id': 'capture-account',
                    'email': 'review@example.test',
                  },
                  'session': {'expiresAt': '2027-12-01T00:00:00Z'},
                }),
                200,
              );
            }
            return http.Response('{}', phase == 'failed-busy' ? 503 : 400);
          });
          await tester.pumpWidget(
            KeyedSubtree(
              key: UniqueKey(),
              child: RepaintBoundary(
                key: captureKey,
                child: skillsManagerTestApp(
                  browserRepository: FakeSkillBrowserRepository(),
                  initialLocation: '/settings?section=cloud',
                  locale: Locale(locale),
                  overrides: [
                    initialAppearanceModeProvider.overrideWithValue(mode),
                    cloudIsMacOSProvider.overrideWithValue(true),
                    cloudOriginDefineProvider.overrideWithValue(
                      origin.toString(),
                    ),
                    cloudSessionStoreProvider.overrideWithValue(store),
                    cloudHttpClientProvider.overrideWithValue(client),
                    cloudWebAuthenticatorProvider.overrideWithValue(auth),
                    cloudDeviceProvider.overrideWithValue(
                      () async => CloudDevice(
                        name: 'Review Mac',
                        platform: CloudDevicePlatform.macos,
                      ),
                    ),
                    cloudSyncRuntimeProvider.overrideWithValue(null),
                    cloudSyncStateProvider.overrideWith(
                      (ref) => Stream.value(const CloudSyncState()),
                    ),
                  ],
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (phase.startsWith('failed-') || phase.startsWith('signing-in')) {
            await tester.tap(find.text(locale == 'en' ? 'Sign in' : '登录'));
            // The loading button intentionally animates continuously.
            await tester.pump(const Duration(milliseconds: 700));
            if (phase.startsWith('failed-')) await tester.pumpAndSettle();
          }
          if (phase == 'failed-network' || phase == 'failed-busy') {
            expect(auth.calls, 0);
          }
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File('${output.path}/$phase-$locale-${mode.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          if (phase == 'signing-in-app-only' &&
              const bool.fromEnvironment('SKILLDECK_CAPTURE_NATIVE_WINDOW')) {
            debugPrint('NATIVE_CAPTURE_READY: $locale-${mode.name}');
            while (!auth.nativeClosed.isCompleted) {
              await tester.pump(const Duration(milliseconds: 200));
            }
          }
          if (!auth.pending.isCompleted) auth.pending.complete(null);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          client.close();
        }
      }
    }
  }, skip: !const bool.fromEnvironment('SKILLDECK_SIGN_IN_CAPTURE'));
}
