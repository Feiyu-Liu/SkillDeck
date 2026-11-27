import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:skills_cloud/skills_cloud.dart';

final class SecureCloudSessionStore implements CloudSessionStore {
  const SecureCloudSessionStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(
      // Developer ID builds have no Keychain Sharing entitlement.
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  static String _key(CloudServiceOrigin origin) =>
      'agent_skills.cloud.session.$origin';

  @override
  Future<StoredCloudSession?> read(CloudServiceOrigin origin) async {
    final value = await _storage.read(key: _key(origin));
    if (value == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?> || decoded['origin'] != '$origin') {
      return null;
    }
    final token = decoded['token'];
    if (token is! String || token.isEmpty) return null;
    return StoredCloudSession(
      origin: origin,
      token: token,
      account: _readAccount(decoded['account']),
    );
  }

  @override
  Future<void> write(StoredCloudSession session) {
    final account = session.account;
    return _storage.write(
      key: _key(session.origin),
      value: jsonEncode({
        'origin': session.origin.toString(),
        'token': session.token,
        if (account != null)
          'account': {
            'id': account.id,
            'email': account.email,
            'sessionExpiresAt': account.sessionExpiresAt.toIso8601String(),
          },
      }),
    );
  }

  @override
  Future<void> delete(CloudServiceOrigin origin) =>
      _storage.delete(key: _key(origin));

  static CloudAccount? _readAccount(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final id = value['id'];
    final email = value['email'];
    final expiresAt = value['sessionExpiresAt'];
    final expiry = expiresAt is String ? DateTime.tryParse(expiresAt) : null;
    if (id is! String || id.isEmpty || email is! String || expiry == null) {
      return null;
    }
    return CloudAccount(id: id, email: email, sessionExpiresAt: expiry);
  }
}
