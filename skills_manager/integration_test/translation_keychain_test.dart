import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:skills_manager/features/translation/data/services/translation_credential_store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS translation credentials survive a Keychain round trip', (
    tester,
  ) async {
    const store = SecureTranslationCredentialStore();
    final id = 'integration-${DateTime.now().microsecondsSinceEpoch}';
    const value = 'temporary-integration-secret';
    try {
      await store.write(id, value);
      expect(await store.read(id), value);
      await store.delete(id);
      expect(await store.read(id), isNull);
    } finally {
      await store.delete(id);
    }
  });
}
