import 'dart:async';

import 'package:window_manager/window_manager.dart';

/// Keeps SkillDeck running after the user closes its window.
///
/// macOS treats the red close button as "put this App away", not as "quit it":
/// the process stays in the Dock and the menu bar until the user actually
/// quits. SkillDeck needs that because background update checks are pointless
/// in a process that dies with its window.
///
/// Closing the `NSWindow` would tear down the `FlutterViewController` with it,
/// so the close signal is intercepted and the window is merely hidden. The
/// native `AppDelegate` orders it back to the front when the Dock icon is
/// clicked, and Cmd-Q still terminates the App — `setPreventClose` guards the
/// window's close signal, not the application's terminate signal.
final class BackgroundWindowLifecycle with WindowListener {
  bool _attached = false;

  /// Whether close interception is currently installed.
  bool get isAttached => _attached;

  /// Starts intercepting the window's close signal.
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  /// Stops intercepting, restoring the default close-quits-the-App behavior.
  Future<void> detach() async {
    if (!_attached) return;
    _attached = false;
    windowManager.removeListener(this);
    await windowManager.setPreventClose(false);
  }

  @override
  void onWindowClose() {
    unawaited(windowManager.hide());
  }
}
