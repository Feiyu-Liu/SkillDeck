import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_resizable_sidebar.dart';

void main() {
  Widget buildSubject({
    ValueChanged<double>? onProgressChanged,
    ValueChanged<bool>? onCollapsedChanged,
    bool initiallyCollapsed = false,
  }) => CupertinoApp(
    home: AppResizableSidebar(
      onProgressChanged: onProgressChanged,
      onCollapsedChanged: onCollapsedChanged,
      initiallyCollapsed: initiallyCollapsed,
      sidebarBuilder: (context, width, progress) => SizedBox(
        key: const Key('sidebar-body'),
        width: width,
        child: Text('$progress'),
      ),
      child: const ColoredBox(
        key: Key('content-body'),
        color: CupertinoColors.white,
      ),
    ),
  );

  testWidgets('resizes continuously and snaps to the nearest sidebar state', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    expect(
      tester.getSize(find.byKey(const Key('sidebar-body'))).width,
      AppSizes.sidebarExpandedWidth,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('app-sidebar-resize-handle'))),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('sidebar-body'))).width,
      closeTo(AppSizes.sidebarExpandedWidth - 40, 0.1),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('sidebar-body'))).width,
      AppSizes.sidebarExpandedWidth,
    );

    final collapse = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('app-sidebar-resize-handle'))),
    );
    await collapse.moveBy(const Offset(-80, 0));
    await collapse.up();
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('sidebar-body'))).width,
      AppSizes.sidebarCollapsedWidth,
    );
  });

  testWidgets('handle overlays the content edge with a stable hit target', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject());
    final sidebar = find.byKey(const Key('sidebar-body'));
    final content = find.byKey(const Key('content-body'));
    final handle = find.byKey(const Key('app-sidebar-resize-handle'));

    expect(tester.getTopLeft(handle).dx, tester.getTopRight(sidebar).dx);
    expect(tester.getSize(handle).width, AppSizes.sidebarResizeHandleHitWidth);
    expect(tester.getTopLeft(content).dx, tester.getTopRight(sidebar).dx);

    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(-1000, 0));
    await tester.pump();
    expect(tester.getSize(sidebar).width, AppSizes.sidebarCollapsedWidth);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('foreground drag regions leave the resize handle uncovered', (
    tester,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        home: AppResizableSidebar(
          sidebarBuilder: (context, width, progress) => SizedBox(width: width),
          foregroundBuilder: (context, sidebarWidth, viewportWidth) => Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                width: sidebarWidth,
                height: AppSizes.dragRegionHeight,
                child: const SizedBox(key: Key('drag-region-left')),
              ),
              Positioned(
                left: sidebarWidth + AppSizes.sidebarResizeHandleHitWidth,
                top: 0,
                width:
                    viewportWidth -
                    sidebarWidth -
                    AppSizes.sidebarResizeHandleHitWidth,
                height: AppSizes.dragRegionHeight,
                child: const SizedBox(key: Key('drag-region-right')),
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );

    final handle = find.byKey(const Key('app-sidebar-resize-handle'));
    final rightRegion = find.byKey(const Key('drag-region-right'));
    expect(tester.getTopLeft(rightRegion).dx, tester.getTopRight(handle).dx);
  });

  testWidgets('reports collapse progress so the shell can track the rail', (
    tester,
  ) async {
    final reported = <double>[];
    await tester.pumpWidget(buildSubject(onProgressChanged: reported.add));
    expect(reported, isEmpty, reason: 'must not fire during build');

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('app-sidebar-resize-handle'))),
    );
    await gesture.moveBy(const Offset(-1000, 0));
    await tester.pump();
    expect(reported.last, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(reported.last, 0, reason: 'a long drag snaps to the rail');

    final expand = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('app-sidebar-resize-handle'))),
    );
    await expand.moveBy(const Offset(1000, 0));
    await expand.up();
    await tester.pumpAndSettle();
    expect(reported.last, 1);
  });

  testWidgets('starts collapsed when initiallyCollapsed is true', (
    tester,
  ) async {
    await tester.pumpWidget(buildSubject(initiallyCollapsed: true));
    expect(
      tester.getSize(find.byKey(const Key('sidebar-body'))).width,
      AppSizes.sidebarCollapsedWidth,
    );
  });

  testWidgets('reports a settled collapse change once per drag release', (
    tester,
  ) async {
    final reported = <bool>[];
    await tester.pumpWidget(buildSubject(onCollapsedChanged: reported.add));

    final collapse = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('app-sidebar-resize-handle'))),
    );
    await collapse.moveBy(const Offset(-40, 0));
    await tester.pump();
    expect(reported, isEmpty, reason: 'must not fire during an active drag');
    await collapse.moveBy(const Offset(-40, 0));
    await collapse.up();
    await tester.pumpAndSettle();
    expect(reported, [true]);

    final expand = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('app-sidebar-resize-handle'))),
    );
    await expand.moveBy(const Offset(1000, 0));
    await expand.up();
    await tester.pumpAndSettle();
    expect(reported, [true, false]);
  });
}
