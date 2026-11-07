import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/widgets/app_progress_bar.dart';

void main() {
  testWidgets('renders the progress fill at the supplied fraction', (
    tester,
  ) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(
          child: SizedBox(
            width: 200,
            height: 5,
            child: AppProgressBar(progress: 0.25),
          ),
        ),
      ),
    );

    final fill = find.byKey(const Key('app-progress-bar-fill'));
    await tester.pump(const Duration(milliseconds: 220));
    expect(tester.getSize(fill).width, closeTo(50, 0.1));
    expect(tester.getSize(fill).height, closeTo(5, 0.1));
  });
}
