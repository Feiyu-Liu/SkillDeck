import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:next_ui/next_ui.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_frame.dart';
import 'package:skills_manager/shared/widgets/app_collapsing_page_header.dart';
import 'package:skills_manager/shared/widgets/app_page_template.dart';

void main() {
  Future<void> pumpFrame(
    WidgetTester tester, {
    required ScrollController controller,
    required bool titleSelectable,
  }) => tester.pumpWidget(
    CupertinoApp(
      home: CupertinoPageScaffold(
        child: AppCollapsingPageFrame(
          controller: controller,
          breadcrumb: 'Workspace',
          breadcrumbIcon: CupertinoIcons.square_grid_2x2,
          title: 'frontend-design',
          titleKey: const Key('title'),
          titleSelectable: titleSelectable,
          child: CustomScrollView(
            controller: controller,
            slivers: const [SliverToBoxAdapter(child: SizedBox(height: 1200))],
          ),
        ),
      ),
    ),
  );

  testWidgets('selectable title copies the dragged text', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await pumpFrame(tester, controller: controller, titleSelectable: true);
    final title = find.byKey(const Key('title'));
    expect(
      find.ancestor(of: title, matching: find.byType(SelectableRegion)),
      findsOneWidget,
    );

    final gesture = await tester.startGesture(
      tester.getTopLeft(title) + const Offset(1, 10),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await gesture.moveTo(tester.getTopRight(title) + const Offset(-1, 10));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();

    expect(copied, 'frontend-design');
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('title stays inert unless selectable', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await pumpFrame(tester, controller: controller, titleSelectable: false);

    expect(find.byType(SelectableRegion), findsNothing);
  });

  testWidgets('collapses title actions between fixed command anchors', (
    tester,
  ) async {
    // This test is about the blur, so it pays for the shader.
    AppCollapsingPageFrame.blurEnabled = true;
    addTearDown(() => AppCollapsingPageFrame.blurEnabled = false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    const headerKey = Key('header');
    const leadingKey = Key('leading');
    const trailingKey = Key('trailing');
    const titleKey = Key('title');
    const titleActionKey = Key('title-action');
    const blurKey = Key('blur');

    await tester.pumpWidget(
      CupertinoApp(
        home: CupertinoPageScaffold(
          child: AppPageTemplate(
            controller: controller,
            headerKey: headerKey,
            titleKey: titleKey,
            blurKey: blurKey,
            breadcrumb: 'Workspace / Page',
            breadcrumbIcon: CupertinoIcons.square_grid_2x2,
            title: 'Page',
            commandLeading: const SizedBox(
              key: leadingKey,
              width: 80,
              height: AppSizes.controlHeight,
            ),
            commandTrailing: const SizedBox(
              key: trailingKey,
              width: 80,
              height: AppSizes.controlHeight,
            ),
            titleActions: const SizedBox(
              key: titleActionKey,
              width: 80,
              height: AppSizes.controlHeight,
            ),
            slivers: const [SliverToBoxAdapter(child: SizedBox(height: 1200))],
          ),
        ),
      ),
    );

    final headerTop = tester.getTopLeft(find.byKey(headerKey)).dy;
    final leadingPosition = tester.getTopLeft(find.byKey(leadingKey));
    final trailingPosition = tester.getTopLeft(find.byKey(trailingKey));
    final expandedTitleTop = tester.getTopLeft(find.byKey(titleKey)).dy;
    final expandedActionTop = tester.getTopLeft(find.byKey(titleActionKey)).dy;
    expect(
      tester.widget<Text>(find.byKey(titleKey)).style!.fontSize,
      AppCollapsingHeaderMetrics.expandedTitleFontSize,
    );

    expect(
      tester.getSize(find.byKey(headerKey)).width,
      AppSizes.contentColumnWidth,
    );
    expect(leadingPosition.dy - headerTop, AppInsets.pageHeader.top);
    expect(
      tester.getCenter(find.byKey(leadingKey)).dy,
      tester.getCenter(find.byKey(trailingKey)).dy,
    );
    expect(
      tester.getCenter(find.byKey(titleKey)).dy,
      tester.getCenter(find.byKey(titleActionKey)).dy,
    );
    expect(find.text('Workspace / Page'), findsOneWidget);
    expect(find.byKey(blurKey), findsOneWidget);
    expect(
      tester.widget<MyTopProgressiveBlur>(find.byKey(blurKey)).blurExtent,
      AppCollapsingHeaderMetrics.collapsedHeight +
          AppCollapsingPageFrame.blurFadeExtension,
    );
    expect(
      find.descendant(of: find.byKey(blurKey), matching: find.byKey(headerKey)),
      findsNothing,
    );

    controller.jumpTo(AppCollapsingHeaderMetrics.collapseDistance);
    await tester.pump();

    expect(tester.getTopLeft(find.byKey(leadingKey)), leadingPosition);
    expect(tester.getTopLeft(find.byKey(trailingKey)), trailingPosition);
    expect(
      tester.getTopLeft(find.byKey(titleKey)).dy,
      lessThan(expandedTitleTop),
    );
    expect(
      tester.getTopLeft(find.byKey(titleActionKey)).dy,
      lessThan(expandedActionTop),
    );
    expect(
      tester.getCenter(find.byKey(titleKey)).dy,
      tester.getCenter(find.byKey(titleActionKey)).dy,
    );
    expect(
      tester.getTopLeft(find.byKey(titleKey)).dx -
          tester.getTopRight(find.byKey(leadingKey)).dx,
      12,
    );
    expect(
      tester.getTopLeft(find.byKey(trailingKey)).dx -
          tester.getTopRight(find.byKey(titleActionKey)).dx,
      16,
    );
    expect(
      tester.getTopRight(find.byKey(titleKey)).dx,
      lessThanOrEqualTo(tester.getTopLeft(find.byKey(titleActionKey)).dx - 16),
    );
    expect(
      tester.widget<Text>(find.byKey(titleKey)).style!.fontSize,
      AppCollapsingHeaderMetrics.collapsedTitleFontSize,
    );
  });
}
