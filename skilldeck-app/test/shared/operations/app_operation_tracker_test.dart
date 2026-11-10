import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/operations/app_operation_tracker.dart';

void main() {
  test(
    'tracks progress, deduplicates warnings, and forwards cancellation',
    () async {
      final states = StreamController<_Progress>();
      final result = Completer<int>();
      final cancelled = Completer<void>();
      final observed = <AppOperationState<_Progress, String>>[];
      final tracker = AppOperationTracker<_Progress, String>(
        onChanged: observed.add,
        warningsOf: (progress) => progress.warnings,
        warningKey: (warning) => warning,
      );

      final pending = tracker.run(
        current: const _Progress('planning', ['first']),
        states: states.stream,
        result: result.future,
        cancel: () async => cancelled.complete(),
      );
      states.add(const _Progress('applying', ['first', 'second']));
      await Future<void>.delayed(Duration.zero);

      expect(tracker.state.running, isTrue);
      expect(tracker.state.progress?.phase, 'applying');
      expect(tracker.state.warnings, ['first', 'second']);

      await tracker.cancel();
      expect(cancelled.isCompleted, isTrue);

      result.complete(7);
      expect(await pending, 7);
      expect(tracker.state.running, isFalse);
      expect(tracker.state.warnings, ['first', 'second']);

      await states.close();
      await tracker.dispose();
      expect(observed, isNotEmpty);
    },
  );

  test('merges terminal completion warnings into tracked state', () async {
    final tracker = AppOperationTracker<_Progress, String>(
      onChanged: (_) {},
      warningsOf: (progress) => progress.warnings,
      warningKey: (warning) => warning,
    );

    final completion = await tracker.runCompletion(
      current: const _Progress('applying', ['progress-only', 'shared']),
      states: const Stream.empty(),
      completed: Future.value(const _Completion(['shared', 'terminal-only'])),
      warningsOfCompletion: (value) => value.warnings,
      cancel: () async {},
    );

    expect(completion.warnings, ['shared', 'terminal-only']);
    expect(tracker.state.running, isFalse);
    expect(tracker.state.warnings, [
      'progress-only',
      'shared',
      'terminal-only',
    ]);
  });
}

final class _Progress {
  const _Progress(this.phase, this.warnings);

  final String phase;
  final List<String> warnings;
}

final class _Completion {
  const _Completion(this.warnings);

  final List<String> warnings;
}
