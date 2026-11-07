import 'package:skills_workspace/skills_workspace.dart';
import 'package:test/test.dart';

void main() {
  test(
    'CancellationSource publishes one idempotent cancellation signal',
    () async {
      final source = CancellationSource();
      var notificationCount = 0;
      source.token.whenCancelled.then((_) => notificationCount += 1);

      expect(source.token.isCancelled, isFalse);

      await source.cancel();
      await source.cancel();

      expect(source.token.isCancelled, isTrue);
      expect(notificationCount, 1);
    },
  );

  test('CancellationToken.none never starts cancelled', () {
    final token = CancellationToken.none();

    expect(token.isCancelled, isFalse);
  });
}
