import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Shows the main window behind the frontmost App and asks for attention,
/// without taking keyboard focus: a Dock bounce on macOS.
///
/// The window may never have been revealed when the App was launched in the
/// background, so its opacity is restored too. Every step is best effort; an
/// approval must still be reachable from the Dock or tray if one fails.
Future<void> requestWindowAttention() async {
  try {
    await windowManager.setOpacity(1);
    await windowManager.show(inactive: true);
  } on Object {
    // No window plugin, as in tests; the request stays reachable regardless.
  }
  if (!Platform.isMacOS) return;
  try {
    await const MethodChannel('skilldeck/window_attention')
        .invokeMethod<void>('request');
  } on Object {
    // Older runners have no channel; the shown window is enough.
  }
}
