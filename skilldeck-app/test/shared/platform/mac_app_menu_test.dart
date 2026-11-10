import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/platform/mac_app_menu.dart';

const _channel = MethodChannel(MacAppMenu.channelName);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Delivers a command the way the native `AppDelegate` does.
  Future<void> emit(String method) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          _channel.codec.encodeMethodCall(MethodCall(method)),
          (_) {},
        );
  }

  test('the App menu Settings item reaches the App', () async {
    final menu = MacAppMenu();
    addTearDown(menu.detach);
    var opened = 0;
    menu.attach(onOpenSettings: () => opened++);

    await emit(MacAppMenu.openSettingsMethod);

    expect(opened, 1);
  });

  test('unknown App menu commands are ignored rather than mistaken', () async {
    final menu = MacAppMenu();
    addTearDown(menu.detach);
    var opened = 0;
    menu.attach(onOpenSettings: () => opened++);

    await emit('somethingElse');

    expect(opened, isZero);
  });

  test('detaching stops responding to the App menu', () async {
    final menu = MacAppMenu();
    var opened = 0;
    menu.attach(onOpenSettings: () => opened++);
    menu.detach();

    await emit(MacAppMenu.openSettingsMethod);

    expect(opened, isZero);
  });
}
