import 'package:skills_workspace/src/platform/filesystem/windows_filesystem_primitives.dart';
import 'package:test/test.dart';

void main() {
  test('retries sharing and access locks with capped bounded backoff', () {
    for (final error in [5, 32]) {
      expect(
        windowsMoveRetryDelay(error, 0, Duration.zero),
        const Duration(milliseconds: 2),
      );
      expect(
        windowsMoveRetryDelay(error, 30, Duration.zero),
        const Duration(milliseconds: 100),
      );
      expect(
        windowsMoveRetryDelay(error, 30, const Duration(milliseconds: 1999)),
        const Duration(milliseconds: 1),
      );
      expect(
        windowsMoveRetryDelay(error, 0, const Duration(seconds: 2)),
        isNull,
      );
    }
  });
  test('does not retry permanent errors or success', () {
    for (final error in [0, 2, 3, 17, 183]) {
      expect(windowsMoveRetryDelay(error, 0, Duration.zero), isNull);
    }
  });
}
