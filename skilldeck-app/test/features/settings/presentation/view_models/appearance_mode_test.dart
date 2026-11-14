import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:skills_manager/features/settings/presentation/view_models/appearance_mode.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';

import '../../../../support/fake_skill_browser_repository.dart';
import '../../../../support/skills_manager_test_app.dart';

void main() {
  late SharedPreferencesAsyncPlatform? originalPlatform;
  late SharedPreferencesAsync preferences;
  late AppearanceModeStore store;

  setUpAll(() {
    originalPlatform = SharedPreferencesAsyncPlatform.instance;
  });
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    preferences = SharedPreferencesAsync();
    store = AppearanceModeStore(preferences: preferences);
  });
  tearDownAll(() {
    SharedPreferencesAsyncPlatform.instance = originalPlatform;
  });

  test('defaults to following the system and persists the choice', () async {
    expect(await store.read(), AppearanceMode.system);

    await store.write(AppearanceMode.dark);

    expect(await store.read(), AppearanceMode.dark);
  });

  test('invalid saved mode falls back to following the system', () async {
    await preferences.setString(AppearanceModeStore.preferenceKey, 'unknown');

    expect(await store.read(), AppearanceMode.system);
  });

  test('only the system mode follows the platform brightness', () {
    expect(AppearanceMode.system.resolve(Brightness.dark), Brightness.dark);
    expect(AppearanceMode.system.resolve(Brightness.light), Brightness.light);
    expect(AppearanceMode.light.resolve(Brightness.dark), Brightness.light);
    expect(AppearanceMode.dark.resolve(Brightness.light), Brightness.dark);
  });

  test('starts from the preloaded mode and saves new choices', () async {
    final container = ProviderContainer(
      overrides: [
        appearanceModeStoreProvider.overrideWithValue(store),
        initialAppearanceModeProvider.overrideWithValue(AppearanceMode.dark),
      ],
    );
    addTearDown(container.dispose);
    expect(container.read(appearanceModeProvider), AppearanceMode.dark);

    container
        .read(appearanceModeProvider.notifier)
        .select(AppearanceMode.light);
    await pumpEventQueue();

    expect(container.read(appearanceModeProvider), AppearanceMode.light);
    expect(await store.read(), AppearanceMode.light);
  });

  test('storage failures keep the in-memory selection usable', () async {
    store = AppearanceModeStore(preferences: _FailingPreferences());
    expect(await store.read(), AppearanceMode.system);
    final container = ProviderContainer(
      overrides: [appearanceModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    container.read(appearanceModeProvider.notifier).select(AppearanceMode.dark);
    await pumpEventQueue();

    expect(container.read(appearanceModeProvider), AppearanceMode.dark);
  });

  testWidgets('a fixed appearance overrides the system until reset', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      skillsManagerTestApp(
        browserRepository: FakeSkillBrowserRepository(),
        initialLocation: '/settings?section=appearance',
        appearanceModeStore: store,
      ),
    );
    await tester.pumpAndSettle();
    Color sidebar() =>
        tester.widget<Container>(find.byKey(const Key('app-sidebar'))).color!;
    expect(sidebar(), AppColors.canvas);

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(sidebar(), AppPalette.dark.canvas);
    expect(
      CupertinoTheme.brightnessOf(
        tester.element(find.byKey(const Key('app-sidebar'))),
      ),
      Brightness.dark,
    );
    expect(await store.read(), AppearanceMode.dark);

    // A fixed choice ignores the system switching appearance.
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(sidebar(), AppColors.canvas);

    await tester.tap(find.text('Follow System'));
    await tester.pumpAndSettle();
    expect(sidebar(), AppPalette.dark.canvas);
  });
}

final class _FailingPreferences extends SharedPreferencesAsync {
  @override
  Future<String?> getString(String key) async =>
      throw StateError('read failed');

  @override
  Future<void> setString(String key, String value) async =>
      throw StateError('write failed');
}
