import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/shared/platform/window_lifecycle.dart';

const _channel = MethodChannel('window_manager');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  /// Delivers the native close signal the way the plugin does.
  Future<void> emitWindowClose() async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          _channel.codec.encodeMethodCall(
            const MethodCall('onEvent', {'eventName': 'close'}),
          ),
          (_) {},
        );
  }

  test('attaching intercepts the window close signal', () async {
    final lifecycle = BackgroundWindowLifecycle();
    addTearDown(lifecycle.detach);

    await lifecycle.attach();

    expect(lifecycle.isAttached, isTrue);
    expect(
      calls,
      contains(
        isA<MethodCall>()
            .having((c) => c.method, 'method', 'setPreventClose')
            .having((c) => c.arguments, 'arguments', {'isPreventClose': true}),
      ),
    );
  });

  test('closing the window hides it instead of ending the process', () async {
    final lifecycle = BackgroundWindowLifecycle();
    addTearDown(lifecycle.detach);
    await lifecycle.attach();
    calls.clear();

    await emitWindowClose();
    await Future<void>.delayed(Duration.zero);

    expect(calls.map((c) => c.method), contains('hide'));
    expect(calls.map((c) => c.method), isNot(contains('destroy')));
  });

  test('detaching restores the default close-quits behavior', () async {
    final lifecycle = BackgroundWindowLifecycle();
    await lifecycle.attach();
    calls.clear();

    await lifecycle.detach();
    await emitWindowClose();
    await Future<void>.delayed(Duration.zero);

    expect(lifecycle.isAttached, isFalse);
    expect(
      calls,
      contains(
        isA<MethodCall>()
            .having((c) => c.method, 'method', 'setPreventClose')
            .having((c) => c.arguments, 'arguments', {'isPreventClose': false}),
      ),
    );
    expect(calls.map((c) => c.method), isNot(contains('hide')));
  });

  test('attaching twice installs a single interception', () async {
    final lifecycle = BackgroundWindowLifecycle();
    addTearDown(lifecycle.detach);

    await lifecycle.attach();
    await lifecycle.attach();
    calls.clear();

    await emitWindowClose();
    await Future<void>.delayed(Duration.zero);

    expect(calls.where((c) => c.method == 'hide'), hasLength(1));
  });
}
