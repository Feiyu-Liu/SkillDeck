import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    // Flutter does not forward macOS launch arguments to Dart by default.
    let project = FlutterDartProject()
    project.dartEntrypointArguments = ProcessInfo.processInfo.arguments.filter {
      $0.hasPrefix("--skilldeck-")
    }
    let flutterViewController = FlutterViewController(project: project)
    let windowFrame = self.frame
    // AppKit paints this surface whenever Flutter has nothing to show: before
    // the first frame, during a live resize, and on restore. The stock value is
    // black, which read as a flash of black at every launch. Matching
    // AppColors.canvas keeps those moments the colour of the App itself.
    let canvas = NSColor(srgbRed: 0xEB / 255.0, green: 0xEB / 255.0, blue: 0xEC / 255.0, alpha: 1)
    self.backgroundColor = canvas
    flutterViewController.backgroundColor = canvas
    self.contentViewController = flutterViewController
    // Launch fully transparent so the empty window is not visible while `main`
    // opens stores and builds the first frame; Dart restores the opacity once
    // there is UI to see, and `AppDelegate` restores it regardless if Dart
    // never gets that far. The window stays *displayed* the whole time — hiding
    // it outright would stop AppKit from loading the content view, and the
    // Flutter engine would never start.
    self.alphaValue = 0
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // A command-line approval needs the user without taking their keyboard:
    // bounce the Dock icon rather than activating the App.
    FlutterMethodChannel(
      name: "skilldeck/window_attention",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "request" else {
        result(FlutterMethodNotImplemented)
        return
      }
      NSApp.requestUserAttention(.informationalRequest)
      result(nil)
    }

    super.awakeFromNib()
  }
}
