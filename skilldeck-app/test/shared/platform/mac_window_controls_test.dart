import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/platform/mac_window_controls.dart';

void main() {
  test(
    'still reaches the platform after a request that needs no work',
    () async {
      final applied = <bool>[];
      final controls = MacWindowControls(
        apply: (visible) async {
          applied.add(visible);
        },
      );

      await controls.setVisible(true);
      await controls.setVisible(true);
      await controls.setVisible(false);

      expect(applied, [true, false]);
    },
  );

  test('coalesces requests that arrive while a call is in flight', () async {
    final applied = <bool>[];
    final gate = Completer<void>();
    final controls = MacWindowControls(
      apply: (visible) async {
        applied.add(visible);
        if (applied.length == 1) await gate.future;
      },
    );

    final first = controls.setVisible(true);
    unawaited(controls.setVisible(false));
    unawaited(controls.setVisible(true));
    gate.complete();
    await first;

    expect(applied, [true], reason: 'the transient false must not be applied');
  });
}
