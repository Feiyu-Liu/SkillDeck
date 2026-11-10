import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/platform/app_launch_mode.dart';

void main() {
  test('only the explicit background argument selects background mode', () {
    expect(AppLaunchMode.fromArguments([]), AppLaunchMode.interactive);
    expect(
      AppLaunchMode.fromArguments(['--skilldeck-other']),
      AppLaunchMode.interactive,
    );
    expect(
      AppLaunchMode.fromArguments(['--skilldeck-background=false']),
      AppLaunchMode.interactive,
    );
    expect(
      AppLaunchMode.fromArguments(['other', '--skilldeck-background']),
      AppLaunchMode.background,
    );
  });
  test(
    'background bootstrap never calls the opacity/show/focus seam',
    () async {
      final calls = <String>[];
      await revealBootstrapWindow(
        AppLaunchMode.background,
        showWindow: () async {
          calls.addAll(['opacity', 'show', 'focus']);
        },
      );
      expect(calls, isEmpty);
    },
  );
  test('interactive bootstrap awaits its window presentation', () async {
    final calls = <String>[];
    await revealBootstrapWindow(
      AppLaunchMode.interactive,
      showWindow: () async {
        await Future<void>.delayed(Duration.zero);
        calls.addAll(['opacity', 'show', 'focus']);
      },
    );
    expect(calls, ['opacity', 'show', 'focus']);
  });
}
