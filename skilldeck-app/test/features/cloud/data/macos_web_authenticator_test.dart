import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_cloud/skills_cloud.dart';
import 'package:skills_manager/features/cloud/data/macos_web_authenticator.dart';

import 'package:http/testing.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('skilldeck/web_auth');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  test('native port passes the window arguments and returns callback or cancellation', () async {
    var cancel = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'authenticate');
      expect(call.arguments, {
        'url': 'https://cloud.example.test/app/sign-in',
        'callbackScheme': 'cc.skilldeck.signin',
      });
      return cancel
          ? null
          : 'cc.skilldeck.signin:/callback?code=test&state=test';
    });
    const port = MacosWebAuthenticator();
    final url = Uri.parse('https://cloud.example.test/app/sign-in');
    expect(
      await port.authenticate(url, callbackScheme: 'cc.skilldeck.signin'),
      Uri.parse('cc.skilldeck.signin:/callback?code=test&state=test'),
    );
    cancel = true;
    expect(
      await port.authenticate(url, callbackScheme: 'cc.skilldeck.signin'),
      isNull,
    );
  });
  for (final code in ['busy', 'unavailable']) {
    test(
      '$code becomes a generic sign-in failure without platform text',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(
            code: code,
            message: 'private callback token',
          ),
        );
        var requests = 0;
        final client = MockClient((_) async {
          requests++;
          return http.Response('', 200);
        });
        addTearDown(client.close);
        final signIn = CloudSignIn(
          client: client,
          origin: CloudServiceOrigin.parse('https://cloud.example.test'),
          store: InMemoryCloudSessionStore(),
        );
        final result = await signIn.signInWithBrowser(
          CloudDevice(name: 'Mac', platform: CloudDevicePlatform.macos),
          const MacosWebAuthenticator(),
        );
        expect((result as CloudSignInFailed).code, CloudFailureCode.protocol);
        expect(result.toString(), isNot(contains('private')));
        expect(requests, 1);
      },
    );
  }
}
