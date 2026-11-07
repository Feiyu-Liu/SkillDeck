import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// SkillDeck keeps running once its window is closed.
  ///
  /// Background update checks are pointless in a process that dies with its
  /// window, and macOS users expect the red close button to put an App away
  /// rather than to quit it. Cmd-Q and the Quit menu item still terminate.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Reveals the window even if Dart never asks.
  ///
  /// `MainFlutterWindow` launches at zero opacity so the bootstrap is not
  /// visible as an empty window, and Dart restores it after the first frame.
  /// This is the backstop for the case where that never happens: an unpainted
  /// window beats a process with no window at all.
  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // A CLI background launch must stay hidden even if Dart never starts.
    if ProcessInfo.processInfo.arguments.contains("--skilldeck-background") {
      mainFlutterWindow?.orderOut(nil)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
      guard let window = self?.mainFlutterWindow, window.alphaValue == 0 else { return }
      window.alphaValue = 1
    }
  }

  /// Brings the hidden window back when the Dock icon is clicked.
  ///
  /// The Dart side hides the window instead of closing it, which leaves it
  /// ordered out rather than merely deactivated, so AppKit cannot restore it
  /// on its own. Another auxiliary window may still be visible, so the
  /// `hasVisibleWindows` flag does not describe the main window's state.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    NSApp.unhide(nil)
    mainFlutterWindow?.alphaValue = 1 // Also reveal a never-shown background window.
    mainFlutterWindow?.makeKeyAndOrderFront(self)
    NSApp.activate(ignoringOtherApps: true)
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// Backs the standard Settings item in the App menu, and its Cmd-, shortcut.
  ///
  /// The stock Flutter template leaves that item with no action at all, which
  /// makes AppKit grey it out. It is wired to the First Responder rather than
  /// to this object directly so the item stays enabled through the delegate
  /// tail of the responder chain even while the window is hidden.
  ///
  /// Settings is a route inside the Flutter shell, not a separate native
  /// window, so the window is brought back first and the navigation itself is
  /// handed to Dart.
  @objc func showSettings(_ sender: Any?) {
    NSApp.unhide(nil)
    mainFlutterWindow?.alphaValue = 1 // Also reveal a never-shown background window.
    mainFlutterWindow?.makeKeyAndOrderFront(self)
    NSApp.activate(ignoringOtherApps: true)
    appMenuChannel?.invokeMethod(AppDelegate.openSettingsMethod, arguments: nil)
  }

  private static let appMenuChannelName = "skilldeck/app_menu"
  private static let openSettingsMethod = "openSettings"

  /// Resolved lazily: the channel needs the engine that `MainFlutterWindow`
  /// creates in `awakeFromNib`, which runs after this delegate exists.
  private var appMenuChannel: FlutterMethodChannel? {
    guard
      let controller = mainFlutterWindow?.contentViewController
        as? FlutterViewController
    else { return nil }
    return FlutterMethodChannel(
      name: AppDelegate.appMenuChannelName,
      binaryMessenger: controller.engine.binaryMessenger
    )
  }
}
