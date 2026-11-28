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
  tearDownAll(binding.platformDispatcher.clearSemanticsEnabledTestValue);
  setUpAll(() async {
    binding.platformDispatcher.semanticsEnabledTestValue = false;
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(800, 600));
    await windowManager.setOpacity(1);
    await windowManager.show();
    await Future<void>.delayed(const Duration(seconds: 1));
  });
  testWidgets(
    unreachable
        ? 'unreachable sign-in service can be cancelled safely'
        : 'system cancel, page cancel, and local email sign-in',
    (tester) async {
      final store = InMemoryCloudSessionStore();
      await tester.pumpWidget(
        skillsManagerTestApp(
          browserRepository: FakeSkillBrowserRepository(),
          initialLocation: '/settings?section=cloud',
          overrides: [
            cloudIsMacOSProvider.overrideWithValue(true),
            cloudOriginDefineProvider.overrideWithValue(
              unreachable ? 'http://127.0.0.1:8786' : 'http://127.0.0.1:8787',
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
        tester.element(find.text('Sign in')),
      );
      for (var attempt = 1; attempt <= (unreachable ? 1 : 3); attempt++) {
        debugPrint('NATIVE_AUTH_ATTEMPT: $attempt');
        await tester.tap(find.text('Sign in'));
        await tester.pump();
        while (container.read(cloudSignInViewModelProvider).value?.phase ==
            CloudSignInPhase.signingIn) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        await tester.pumpAndSettle();
        expect(
          container.read(cloudSignInViewModelProvider).value?.phase,
          attempt < 3 ? CloudSignInPhase.signedOut : CloudSignInPhase.signedIn,
        );
      }
      if (!unreachable) {
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();
      }
      expect(
        await store.read(
          CloudServiceOrigin.parse(
            unreachable ? 'http://127.0.0.1:8786' : 'http://127.0.0.1:8787',
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
