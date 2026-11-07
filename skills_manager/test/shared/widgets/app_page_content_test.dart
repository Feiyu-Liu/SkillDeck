import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/theme/app_theme.dart';
import 'package:skills_manager/shared/widgets/app_page_content.dart';

void main() {
  const contentKey = Key('page-content');

  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: AppPageContent(
            contentKey: contentKey,
            child: SizedBox(height: 40),
          ),
        ),
      ),
    );
  }

  Future<void> pumpSliverAtWidth(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const CupertinoApp(
        home: CupertinoPageScaffold(
          child: CustomScrollView(
            slivers: [
              AppPageSliverContent(
                sliver: SliverToBoxAdapter(
                  child: SizedBox(key: contentKey, height: 40),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('uses the shared maximum width on expanded layouts', (
    tester,
  ) async {
    await pumpAtWidth(tester, 1200);

    expect(
      tester.getSize(find.byKey(contentKey)).width,
      AppSizes.contentColumnWidth,
    );
  });

  testWidgets('keeps forty pixel insets on compact layouts', (tester) async {
    await pumpAtWidth(tester, 500);

    expect(
      tester.getSize(find.byKey(contentKey)).width,
      500 - AppSizes.pageHorizontalPadding * 2,
    );
  });

  testWidgets('uses the same width contract for sliver content', (
    tester,
  ) async {
    await pumpSliverAtWidth(tester, 1200);
    expect(
      tester.getSize(find.byKey(contentKey)).width,
      AppSizes.contentColumnWidth,
    );

    await pumpSliverAtWidth(tester, 500);
    expect(
      tester.getSize(find.byKey(contentKey)).width,
      500 - AppSizes.pageHorizontalPadding * 2,
    );
  });
}
