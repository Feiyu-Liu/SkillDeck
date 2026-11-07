import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TranslationCredentialStore {
  Future<String?> read(String credentialId);

  Future<void> write(String credentialId, String value);

  Future<void> delete(String credentialId);
}

final class SecureTranslationCredentialStore
    implements TranslationCredentialStore {
  const SecureTranslationCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Developer ID builds have no Keychain Sharing entitlement.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  static const _prefix = 'agent_skills.translation.';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String credentialId) =>
      _storage.read(key: '$_prefix$credentialId');

  @override
  Future<void> write(String credentialId, String value) =>
      _storage.write(key: '$_prefix$credentialId', value: value);

  @override
  Future<void> delete(String credentialId) =>
      _storage.delete(key: '$_prefix$credentialId');
}
