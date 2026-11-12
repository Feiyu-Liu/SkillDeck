import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/skills/presentation/widgets/repository_group_transition.dart';

void main() {
  for (final grid in [false, true]) {
    testWidgets('animates lazy ${grid ? 'grid' : 'list'} and reverses', (
      tester,
    ) async {
      var collapsed = false;
      var builds = 0;
      late StateSetter update;
      await tester.pumpWidget(
        CupertinoApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              final delegate = SliverChildBuilderDelegate((context, index) {
                builds++;
                return SizedBox(height: 50, child: Text('item $index'));
              }, childCount: 1000);
              return CustomScrollView(
                slivers: [
                  RepositoryGroupTransition(
                    collapsed: collapsed,
                    searchQuery: '',
                    sliver: grid
                        ? SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisExtent: 50,
                                ),
                            delegate: delegate,
                          )
                        : SliverList(delegate: delegate),
                  ),
                  const SliverToBoxAdapter(child: Text('following group')),
                ],
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(builds, lessThan(100));
      final scroll = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      final expandedExtent = scroll.maxScrollExtent;
      update(() => collapsed = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(scroll.maxScrollExtent, greaterThan(0));
      expect(scroll.maxScrollExtent, lessThan(expandedExtent));
      update(() => collapsed = false);
      await tester.pumpAndSettle();
      expect(scroll.maxScrollExtent, closeTo(expandedExtent, 1));
      update(() => collapsed = true);
      await tester.pumpAndSettle();
      expect(find.text('item 0'), findsNothing);
      expect(scroll.maxScrollExtent, 0);
      expect(tester.takeException(), isNull);
      // A variable-height list must measure rows crossed during a full slide.
      // Bound work to the three traversals above, not a full scan per frame.
      expect(builds, lessThan(grid ? 900 : 3100));
    });
  }

  testWidgets(
    'card trailing edge follows the shrinking group on both directions',
    (tester) async {
      var collapsed = false;
      late StateSetter update;
      await tester.pumpWidget(
        CupertinoApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return CustomScrollView(
                slivers: [
                  RepositoryGroupTransition(
                    collapsed: collapsed,
                    searchQuery: '',
                    sliver: SliverList.builder(
                      itemCount: 4,
                      itemBuilder: (context, index) => SizedBox(
                        key: ValueKey('row-$index'),
                        height: 60,
                        child: Text('row $index'),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(key: Key('following'), height: 50),
                  ),
                ],
              );
            },
          ),
        ),
      );
      final last = find.byKey(const ValueKey('row-3'));
      final following = find.byKey(const Key('following'));
      final originalBottom = tester.getBottomLeft(last).dy;
      update(() => collapsed = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(originalBottom - tester.getBottomLeft(last).dy, greaterThan(48));
      expect(
        tester.getBottomLeft(last).dy,
        closeTo(tester.getTopLeft(following).dy, 0.01),
      );
      update(() => collapsed = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        tester.getBottomLeft(last).dy,
        closeTo(tester.getTopLeft(following).dy, 0.01),
      );
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(last).dy, closeTo(originalBottom, 0.01));
    },
  );

  testWidgets('reduced motion folds immediately', (tester) async {
    var collapsed = false;
    late StateSetter update;
    await tester.pumpWidget(
      CupertinoApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return CustomScrollView(
                slivers: [
                  RepositoryGroupTransition(
                    collapsed: collapsed,
                    searchQuery: '',
                    sliver: const SliverToBoxAdapter(child: Text('member')),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    update(() => collapsed = true);
    await tester.pump();
    expect(find.text('member'), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
