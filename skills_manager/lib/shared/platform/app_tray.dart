import 'dart:async';
import 'dart:ui' show Offset, Rect;

import 'package:flutter/foundation.dart';
import 'package:nativeapi/nativeapi.dart' show DisplayManager;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// Native handles kept alive for the lifetime of the Windows tray icon.
@visibleForTesting
typedef AppTrayHandles = ({
  TrayIcon icon,
  Image image,
  Menu menu,
  MenuItem showWindow,
  MenuItem quit,
});

/// The Windows notification icon and its two-item native menu.
final class AppTray {
  AppTray({required this.onQuit})
    : _createHandles = _createNativeHandles,
      _openMenu = _openNativeMenu;

  @visibleForTesting
  AppTray.forTesting({
    required this.onQuit,
    required AppTrayHandles Function(String, String) createHandles,
    required void Function(TrayIcon, Menu) openMenu,
  }) : _createHandles = createHandles,
       _openMenu = openMenu;

  final AsyncCallback onQuit;
  final AppTrayHandles Function(String, String) _createHandles;
  final void Function(TrayIcon, Menu) _openMenu;
  static const iconAsset = 'assets/tray/app_icon.ico';
  AppTrayHandles? _handles;
  final _removeListeners = <VoidCallback>[];
  bool _attached = false;
  bool get isAttached => _attached;

  Future<void> attach({
    required String tooltip,
    required String showWindowLabel,
    required String quitLabel,
  }) async {
    if (_attached) return;
    final handles = _createHandles(showWindowLabel, quitLabel);
    _handles = handles;
    try {
      handles.icon.icon = handles.image;
      // Set the tooltip before NIM_ADD so Windows never captures an empty or
      // uninitialized InitialTooltip for this executable.
      handles.icon.setTooltip(tooltip);
      handles.menu
        ..addItem(handles.showWindow)
        ..addSeparator()
        ..addItem(handles.quit);
      handles.icon
        ..setContextMenu(handles.menu)
        ..setContextMenuTrigger(ContextMenuTrigger.none);
      final iconListener = handles.icon.addListener((event) {
        if (_attached && event is TrayIconClickedEvent) {
          unawaited(_showWindow());
        } else if (_attached && event is TrayIconRightClickedEvent) {
          // Leave the native click callback before entering its modal menu loop.
          unawaited(
            Future<void>(() {
              if (_attached) _openMenu(handles.icon, handles.menu);
            }),
          );
        }
      });
      _removeListeners.add(() => handles.icon.removeListener(iconListener));
      final showListener = handles.showWindow.addListener((event) {
        if (_attached && event is MenuItemClickedEvent) {
          unawaited(_showWindow());
        }
      });
      _removeListeners.add(
        () => handles.showWindow.removeListener(showListener),
      );
      final quitListener = handles.quit.addListener((event) {
        if (_attached && event is MenuItemClickedEvent) unawaited(onQuit());
      });
      _removeListeners.add(() => handles.quit.removeListener(quitListener));
      if (!handles.icon.setVisible(true)) {
        throw StateError('Unable to show the SkillDeck notification icon.');
      }
      _attached = true;
    } on Object {
      await detach();
      rethrow;
    }
  }

  Future<void> detach() async {
    _attached = false;
    final handles = _handles;
    _handles = null;
    if (handles == null) return;
    // Menu callbacks run inside a synchronous native call. Freeing its menu
    // there is unsafe; wait until that call has returned to the event loop.
    await Future<void>(() {
      for (final remove in _removeListeners) {
        remove();
      }
      _removeListeners.clear();
      handles.icon
        ..closeContextMenu()
        ..setContextMenu(null)
        ..dispose();
      handles.menu.dispose();
      handles.showWindow.dispose();
      handles.quit.dispose();
      handles.image.dispose();
    });
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  static void _openNativeMenu(TrayIcon icon, Menu menu) {
    final bounds = icon.getBounds(); // Physical pixels on Windows in 0.7.0.
    final displays = DisplayManager.instance.getAll();
    try {
      for (final display in displays) {
        final scale = display.scaleFactor;
        final physicalBounds = display.position * scale & display.size * scale;
        if (!physicalBounds.contains(bounds.center)) continue;
        final work = display.workArea;
        final physicalWork = Rect.fromLTWH(
          work.left * scale,
          work.top * scale,
          work.width * scale,
          work.height * scale,
        );
        final position = trayMenuPosition(bounds, physicalWork);
        final strategy = PositioningStrategy.absolute(position.anchor);
        if (strategy == null) return;
        try {
          menu.open(strategy, position.placement);
        } finally {
          strategy.dispose();
        }
        return;
      }
    } finally {
      for (final display in displays) {
        display.dispose();
      }
    }
  }

  static AppTrayHandles _createNativeHandles(
    String showLabel,
    String quitLabel,
  ) {
    TrayIcon? icon;
    Image? image;
    Menu? menu;
    MenuItem? showWindow;
    MenuItem? quit;
    try {
      icon = TrayIcon.create();
      image = ImageAsset.fromAsset(iconAsset);
      menu = Menu.create();
      showWindow = MenuItem.createWithLabelAndType(
        showLabel,
        MenuItemType.normal,
      );
      quit = MenuItem.createWithLabelAndType(quitLabel, MenuItemType.normal);
      if (icon == null ||
          image == null ||
          menu == null ||
          showWindow == null ||
          quit == null) {
        throw StateError('Unable to create the SkillDeck notification icon.');
      }
      return (
        icon: icon,
        image: image,
        menu: menu,
        showWindow: showWindow,
        quit: quit,
      );
    } on Object {
      icon?.dispose();
      menu?.dispose();
      showWindow?.dispose();
      quit?.dispose();
      image?.dispose();
      rethrow;
    }
  }
}

/// Positions the two-item tray menu inside the work area, not in the taskbar.
/// Both rectangles must be in physical pixels; monitor origins may be negative.
@visibleForTesting
({Offset anchor, Placement placement}) trayMenuPosition(Rect icon, Rect work) {
  final below = icon.center.dy <= work.top;
  final alignStart = icon.center.dx <= work.left;
  return (
    anchor: Offset(
      icon.right.clamp(work.left + 1, work.right - 1).toDouble(),
      (below ? icon.bottom : icon.top)
          .clamp(work.top + 1, work.bottom - 1)
          .toDouble(),
    ),
    placement: below
        ? (alignStart ? Placement.bottomStart : Placement.bottomEnd)
        : (alignStart ? Placement.topStart : Placement.topEnd),
  );
}
