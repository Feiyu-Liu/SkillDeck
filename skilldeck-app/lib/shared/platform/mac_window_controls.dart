import 'package:window_manager/window_manager.dart';

/// Controls the native macOS traffic lights without changing the title-bar
/// style used by SkillDeck's frameless shell.
///
/// Calls are coalesced and serialized because pointer enter/exit and sidebar
/// snap callbacks can arrive while the previous platform-channel call is
/// still in flight.
final class MacWindowControls {
  MacWindowControls({Future<void> Function(bool visible)? apply})
    : _apply = apply ?? _applyThroughWindowManager;

  /// window_manager exposes no standalone button-visibility call, so the
  /// title-bar style is re-applied with the desired visibility.
  static Future<void> _applyThroughWindowManager(bool visible) => windowManager
      .setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: visible);

  final Future<void> Function(bool visible) _apply;

  bool? _appliedVisibility;
  bool? _desiredVisibility;
  bool _draining = false;

  /// Requests whether the native close, minimize, and zoom buttons are shown.
  ///
  /// Redundant requests are cheap: they update the desired value and return
  /// without touching the platform. The drain guard is a plain flag rather
  /// than a cached future because a drain with no work to do completes
  /// synchronously, and a `??=` against such a future would latch onto an
  /// already-completed value and silently drop every later request.
  Future<void> setVisible(bool visible) async {
    _desiredVisibility = visible;
    if (_draining) return;
    _draining = true;
    try {
      while (_desiredVisibility != _appliedVisibility) {
        final next = _desiredVisibility!;
        await _apply(next);
        _appliedVisibility = next;
      }
    } finally {
      _draining = false;
    }
  }
}
