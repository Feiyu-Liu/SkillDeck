import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_animator/scroll_animator.dart';
import 'package:skills_manager/shared/scrolling/app_scroll_controller.dart';

void main() {
  testWidgets('smooths mouse wheel deltas before reaching their target', (
    tester,
  ) async {
    final controller = AppScrollControllers.create();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: CustomScrollView(
            controller: controller,
            slivers: const [SliverToBoxAdapter(child: SizedBox(height: 2400))],
          ),
        ),
      ),
    );

    expect(controller, isA<AnimatedScrollController>());
    expect(controller.position, isA<AnimatedScrollPosition>());

    final mouse = TestPointer(1, ui.PointerDeviceKind.mouse);
    mouse.hover(tester.getCenter(find.byType(Viewport)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 240)));
    await tester.pump();

    expect(controller.position.isScrollingNotifier.value, isTrue);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 30));

    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(240));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(controller.offset, closeTo(240, 0.1));
  });
}
