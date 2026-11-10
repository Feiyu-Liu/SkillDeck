import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:skills_manager/features/translation/data/services/translation_credential_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  test(
    'uses the non-shared macOS Keychain for every credential operation',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'read' ? 'test-secret' : null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });

      const store = SecureTranslationCredentialStore();
      await store.write('id', 'test-secret');
      expect(await store.read('id'), 'test-secret');
      await store.delete('id');

      expect(calls.map((call) => call.method), ['write', 'read', 'delete']);
      for (final call in calls) {
        final arguments = call.arguments as Map<Object?, Object?>;
        final options = arguments['options'] as Map<Object?, Object?>;
        expect(options['usesDataProtectionKeychain'], 'false');
      }
    },
  );
}
