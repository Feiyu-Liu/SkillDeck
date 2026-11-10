import 'package:flutter/widgets.dart';
import 'package:scroll_animator/scroll_animator.dart';

/// Creates the scroll controller shared by top-level page scroll views.
///
/// Pointer scroll input is animated with Chromium's ease-in-out profile while
/// the surrounding [ScrollView] retains its inherited Cupertino physics for
/// touch dragging and boundary behavior.
abstract final class AppScrollControllers {
  static ScrollController create({String? debugLabel}) =>
      AnimatedScrollController(
        animationFactory: const ChromiumEaseInOut(),
        debugLabel: debugLabel,
      );
}
