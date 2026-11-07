/// Only the explicit CLI launch argument suppresses bootstrap presentation.
enum AppLaunchMode {
  interactive,
  background;

  static AppLaunchMode fromArguments(List<String> arguments) =>
      arguments.contains('--skilldeck-background') ? background : interactive;
}

/// Keeps bootstrap window presentation behind one testable decision.
/// Dock and tray presentation deliberately do not pass through this gate.
Future<void> revealBootstrapWindow(
  AppLaunchMode mode, {
  required Future<void> Function() showWindow,
}) async {
  if (mode == AppLaunchMode.interactive) await showWindow();
}
