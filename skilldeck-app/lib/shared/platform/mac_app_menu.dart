import 'package:flutter/services.dart';

/// Receives the macOS App-menu commands that have no Flutter equivalent.
///
/// The App menu is owned by AppKit, not by the widget tree, so items such as
/// Settings cannot reach a route on their own. The native `AppDelegate` sends
/// them here and the App decides what they mean.
///
/// Only the macOS runner ever sends on this channel, so attaching on another
/// platform is inert rather than wrong.
final class MacAppMenu {
  MacAppMenu({MethodChannel channel = const MethodChannel(channelName)})
    : _channel = channel;

  static const channelName = 'skilldeck/app_menu';

  /// Sent when the user picks the App menu's Settings item or presses Cmd-,.
  static const openSettingsMethod = 'openSettings';

  final MethodChannel _channel;

  /// Starts routing App-menu commands to the given callbacks.
  void attach({required void Function() onOpenSettings}) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == openSettingsMethod) onOpenSettings();
      return null;
    });
  }

  /// Stops responding to App-menu commands.
  void detach() => _channel.setMethodCallHandler(null);
}
