import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _seedProvider = NotifierProvider<_SeedNotifier, int>(_SeedNotifier.new);

final _firstAsyncProvider = FutureProvider<int>(
  (ref) => ref.watch(_seedProvider),
);

final _secondAsyncProvider = FutureProvider<int>(
  (ref) async => (await ref.watch(_firstAsyncProvider.future)) * 2,
);

final class _SeedNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final class _TickerModeHarness extends ConsumerStatefulWidget {
  const _TickerModeHarness({super.key});

  @override
  ConsumerState<_TickerModeHarness> createState() => _TickerModeHarnessState();
}

final class _TickerModeHarnessState extends ConsumerState<_TickerModeHarness> {
  bool _enabled = true;

  void pauseDirtyAndResume() {
    setState(() => _enabled = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(_seedProvider.notifier).bump();
      setState(() => _enabled = true);
    });
  }

  @override
  Widget build(BuildContext context) => TickerMode(
    enabled: _enabled,
    child: Consumer(
      builder: (context, ref, child) {
        ref.watch(_secondAsyncProvider);
        return const SizedBox();
      },
    ),
  );
}

void main() {
  testWidgets(
    'resuming a dirty Riverpod subscription does not rebuild ProviderScope '
    'during build',
    (tester) async {
      final key = GlobalKey<_TickerModeHarnessState>();
      await tester.pumpWidget(
        ProviderScope(
          child: CupertinoApp(home: _TickerModeHarness(key: key)),
        ),
      );
      await tester.pumpAndSettle();

      key.currentState!.pauseDirtyAndResume();
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );
}
