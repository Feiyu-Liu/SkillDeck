// Manual native acceptance against the local development Worker. Synthetic
// mailbox and an in-memory session store; no personal Workspace is opened.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/cloud_providers.dart';
import 'package:skills_manager/features/cloud/cloud_sync_providers.dart';
import 'package:skills_manager/features/cloud/data/cloud_sync_runtime.dart';
import 'package:skills_manager/features/cloud/presentation/view_models/cloud_sign_in_view_model.dart';
import 'package:window_manager/window_manager.dart';

import '../test/support/fake_skill_browser_repository.dart';
import '../test/support/skills_manager_test_app.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const unreachable = bool.fromEnvironment('SKILLDECK_NATIVE_UNREACHABLE');
  const serviceOrigin = String.fromEnvironment(
    'SKILLDECK_NATIVE_ORIGIN',
    defaultValue: 'http://127.0.0.1:8787',
  );
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  setUpAll(() async {
    binding.platformDispatcher.semanticsEnabledTestValue = false;
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(800, 600));
    await windowManager.setOpacity(1);
    await windowManager.show();
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  for (final locale in ['en', 'zh']) {
    final signInText = locale == 'zh' ? '登录' : 'Sign in';
    testWidgets(
      '$locale ${unreachable ? 'unreachable sign-in service shows failure before opening a window' : 'system email sign-in against staging'}',
      (tester) async {
        final store = InMemoryCloudSessionStore();
        await tester.pumpWidget(
          skillsManagerTestApp(
            browserRepository: FakeSkillBrowserRepository(),
            initialLocation: '/settings?section=cloud',
            locale: Locale(locale),
            overrides: [
              cloudIsMacOSProvider.overrideWithValue(true),
              cloudOriginDefineProvider.overrideWithValue(
                unreachable ? 'http://127.0.0.1:8786' : serviceOrigin,
              ),
              cloudSessionStoreProvider.overrideWithValue(store),
              cloudDeviceProvider.overrideWithValue(
                () async => CloudDevice(
                  name: 'Native acceptance Mac',
                  platform: CloudDevicePlatform.macos,
                ),
              ),
              cloudSyncRuntimeProvider.overrideWithValue(null),
              cloudSyncStateProvider.overrideWith(
                (ref) => Stream.value(const CloudSyncState()),
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.text(signInText)),
        );
        for (var attempt = 1; attempt <= 1; attempt++) {
          debugPrint('NATIVE_AUTH_ATTEMPT: $locale');
          await tester.tap(find.text(signInText));
          await tester.pump();
          while (container.read(cloudSignInViewModelProvider).value?.phase ==
              CloudSignInPhase.signingIn) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          await tester.pumpAndSettle();
          expect(
            container.read(cloudSignInViewModelProvider).value?.phase,
            unreachable ? CloudSignInPhase.failed : CloudSignInPhase.signedIn,
          );
        }
        if (!unreachable) {
          await tester.tap(find.text(locale == 'zh' ? '退出登录' : 'Sign out'));
          await tester.pump();
          while (container.read(cloudSignInViewModelProvider).value?.phase ==
              CloudSignInPhase.signingOut) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          await tester.pumpAndSettle();
          expect(
            container.read(cloudSignInViewModelProvider).value?.phase,
            CloudSignInPhase.signedOut,
          );
        }
        expect(
          await store.read(
            CloudServiceOrigin.parse(
              unreachable ? 'http://127.0.0.1:8786' : serviceOrigin,
            ),
          ),
          isNull,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      },
      semanticsEnabled: false,
      skip: !const bool.fromEnvironment('SKILLDECK_NATIVE_SIGN_IN'),
      timeout: const Timeout(Duration(minutes: 10)),
    );
  }
}
