import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/app/dialog_page.dart';

void main() {
  testWidgets('uses the native Cupertino modal popup route', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      CupertinoApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final route = const DialogPage<void>(
      barrierDismissible: true,
      child: SizedBox.shrink(),
    ).createRoute(context);

    expect(route, isA<CupertinoModalPopupRoute<void>>());
    expect(
      (route as CupertinoModalPopupRoute<void>).transitionDuration,
      const Duration(milliseconds: 335),
    );
  });
}
