import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/widgets/app_cupertino_controls.dart';

void main() {
  testWidgets('animates dialog surface height when its content changes', (
    tester,
  ) async {
    final height = ValueNotifier(100.0);
    const contentKey = Key('dialog-content');
    addTearDown(height.dispose);

    await tester.pumpWidget(
      CupertinoApp(
        home: ValueListenableBuilder<double>(
          valueListenable: height,
          builder: (context, value, _) => AppCupertinoDialogSurface(
            width: 400,
            child: SizedBox(key: contentKey, height: value),
          ),
        ),
      ),
    );

    final animatedSize = find.byType(AnimatedSize);
    final content = find.byKey(contentKey);
    final centerY = tester.getCenter(animatedSize).dy;
    expect(tester.getSize(animatedSize).height, 100);
    expect(tester.getTopLeft(content).dy, tester.getTopLeft(animatedSize).dy);

    height.value = 220;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));

    final intermediateHeight = tester.getSize(animatedSize).height;
    expect(intermediateHeight, greaterThan(100));
    expect(intermediateHeight, lessThan(220));
    expect(tester.getTopLeft(content).dy, tester.getTopLeft(animatedSize).dy);
    expect(tester.getCenter(animatedSize).dy, centerY);

    await tester.pumpAndSettle();
    expect(tester.getSize(animatedSize).height, 220);
    expect(tester.getTopLeft(content).dy, tester.getTopLeft(animatedSize).dy);
    expect(tester.getCenter(animatedSize).dy, centerY);
  });
}
