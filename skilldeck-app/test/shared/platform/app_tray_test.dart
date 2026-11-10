import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/platform/app_tray.dart';
import 'package:tray_manager/tray_manager.dart';

const _windowChannel = MethodChannel('window_manager');

void main() {
  test('menu anchor stays above the bottom taskbar at 125 percent scaling', () {
    final position = trayMenuPosition(
      const Rect.fromLTWH(1850, 1145, 20, 20),
      const Rect.fromLTWH(0, 0, 1920, 1140),
    );
    expect(position.anchor, const Offset(1870, 1139));
    expect(position.placement, Placement.topEnd);
  });

  test(
    'menu anchor handles top and side taskbars and negative monitor origins',
    () {
      final top = trayMenuPosition(
        const Rect.fromLTWH(1850, 5, 20, 20),
        const Rect.fromLTWH(0, 48, 1920, 1152),
      );
      expect(top.anchor.dy, 49);
      expect(top.placement, Placement.bottomEnd);
      final left = trayMenuPosition(
        const Rect.fromLTWH(-1900, 550, 20, 20),
        const Rect.fromLTWH(-1860, 0, 1860, 1200),
      );
      expect(left.anchor.dx, -1859);
      expect(left.placement, Placement.topStart);
      final right = trayMenuPosition(
        const Rect.fromLTWH(1900, 550, 20, 20),
        const Rect.fromLTWH(0, 0, 1860, 1200),
      );
      expect(right.anchor.dx, 1859);
      expect(right.placement, Placement.topEnd);
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeTrayIcon icon;
  late _FakeMenu menu;
  late _FakeMenuItem show;
  late _FakeMenuItem quit;
  late List<MethodCall> windowCalls;
  late List<String> calls;
  late int quits;
  late AppTray tray;

  setUp(() {
    calls = [];
    windowCalls = [];
    quits = 0;
    icon = _FakeTrayIcon(calls);
    menu = _FakeMenu(calls);
    show = _FakeMenuItem(calls, 'show');
    quit = _FakeMenuItem(calls, 'quit');
    tray = AppTray.forTesting(
      onQuit: () async => quits++,
      openMenu: (_, _) => calls.add('open-menu'),
      createHandles: (showLabel, quitLabel) {
        calls.add('create:$showLabel:$quitLabel');
        return (
          icon: icon,
          image: _FakeImage(calls),
          menu: menu,
          showWindow: show,
          quit: quit,
        );
      },
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, (call) async {
          windowCalls.add(call);
          return call.method == 'isMinimized' ? false : null;
        });
  });
  tearDown(() async {
    await tray.detach();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_windowChannel, null);
  });

  Future<void> attach() => tray.attach(
    tooltip: 'SkillDeck',
    showWindowLabel: 'Show Main Window',
    quitLabel: 'Quit SkillDeck',
  );

  test('sets tooltip and native menu before showing the icon', () async {
    await attach();
    expect(tray.isAttached, isTrue);
    expect(calls, [
      'create:Show Main Window:Quit SkillDeck',
      'icon',
      'tooltip:SkillDeck',
      'item:show',
      'separator',
      'item:quit',
      'menu',
      'trigger:ContextMenuTrigger.none',
      'visible:true',
    ]);
  });

  test('left click and show menu item restore and focus the window', () async {
    await attach();
    icon.emit(const TrayIconClickedEvent(trayIconId: 1));
    await pumpEventQueue();
    expect(windowCalls.map((c) => c.method), ['isMinimized', 'show', 'focus']);
    windowCalls.clear();
    show.emit(const MenuItemClickedEvent(itemId: 2));
    await pumpEventQueue();
    expect(windowCalls.map((c) => c.method), ['isMinimized', 'show', 'focus']);
  });

  test('right click opens one positioned native menu after callback', () async {
    await attach();
    calls.clear();
    icon.emit(const TrayIconRightClickedEvent(trayIconId: 1));
    expect(calls, isEmpty);
    await pumpEventQueue();
    expect(calls, ['open-menu']);
    expect(windowCalls, isEmpty);
  });

  test('quit menu item invokes the shared quit callback', () async {
    await attach();
    quit.emit(const MenuItemClickedEvent(itemId: 3));
    await pumpEventQueue();
    expect(quits, 1);
    expect(windowCalls, isEmpty);
  });

  test(
    'detach frees native objects after the native callback returns',
    () async {
      await attach();
      calls.clear();
      final detached = tray.detach();
      expect(tray.isAttached, isFalse);
      expect(calls, isEmpty);
      quit.emit(const MenuItemClickedEvent(itemId: 3));
      icon.emit(const TrayIconClickedEvent(trayIconId: 1));
      await detached;
      expect(calls, [
        'close-menu',
        'no-menu',
        'dispose:icon',
        'dispose:menu',
        'dispose:show',
        'dispose:quit',
        'dispose:image',
      ]);
      expect(quits, 0);
      expect(windowCalls, isEmpty);
      expect(icon.listener, isNull);
      expect(show.listener, isNull);
      expect(quit.listener, isNull);
      calls.clear();
      await tray.detach();
      expect(calls, isEmpty);
    },
  );

  test('attaching twice creates a single icon', () async {
    await attach();
    await attach();
    expect(calls.where((call) => call.startsWith('create:')), hasLength(1));
  });

  test(
    'a failed registration frees partial resources and allows retry',
    () async {
      icon.canShow = false;
      await expectLater(attach(), throwsStateError);
      expect(tray.isAttached, isFalse);
      expect(calls, contains('dispose:icon'));
      expect(icon.listener, isNull);
      icon.canShow = true;
      await attach();
      expect(tray.isAttached, isTrue);
    },
  );
}

class _FakeTrayIcon implements TrayIcon {
  _FakeTrayIcon(this.calls);
  final List<String> calls;
  bool canShow = true;
  void Function(TrayIconEvent)? listener;
  void emit(TrayIconEvent event) => listener?.call(event);
  @override
  set icon(Image? value) => calls.add('icon');
  @override
  void setTooltip(String? value) => calls.add('tooltip:$value');
  @override
  void setContextMenu(Menu? value) =>
      calls.add(value == null ? 'no-menu' : 'menu');
  @override
  void setContextMenuTrigger(ContextMenuTrigger value) =>
      calls.add('trigger:$value');
  @override
  bool setVisible(bool value) {
    calls.add('visible:$value');
    return canShow;
  }

  @override
  int addListener(void Function(TrayIconEvent) callback) {
    listener = callback;
    return 1;
  }

  @override
  bool removeListener(int id) {
    listener = null;
    return true;
  }

  @override
  bool closeContextMenu() {
    calls.add('close-menu');
    return true;
  }

  @override
  void dispose() => calls.add('dispose:icon');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMenu implements Menu {
  _FakeMenu(this.calls);
  final List<String> calls;
  @override
  void addItem(MenuItem? item) =>
      calls.add('item:${(item as _FakeMenuItem).name}');
  @override
  void addSeparator() => calls.add('separator');
  @override
  void dispose() => calls.add('dispose:menu');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMenuItem implements MenuItem {
  _FakeMenuItem(this.calls, this.name);
  final List<String> calls;
  final String name;
  void Function(MenuEvent)? listener;
  void emit(MenuEvent event) => listener?.call(event);
  @override
  int addListener(void Function(MenuEvent) callback) {
    listener = callback;
    return 1;
  }

  @override
  bool removeListener(int id) {
    listener = null;
    return true;
  }

  @override
  void dispose() => calls.add('dispose:$name');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImage implements Image {
  _FakeImage(this.calls);
  final List<String> calls;
  @override
  void dispose() => calls.add('dispose:image');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
