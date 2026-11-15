import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:skills_cloud/skills_cloud.dart';

String _keyForOrigin(Uri origin) {
  if (origin.scheme != 'https' ||
      origin.host.isEmpty ||
      origin.userInfo.isNotEmpty ||
      origin.toString() != origin.origin) {
    throw const CloudException(CloudErrorCode.invalidConfiguration);
  }
  return 'agent_skills.cloud.session.${sha256.convert(utf8.encode(origin.origin))}.v1';
}

/// Dependency port used by adapter tests without accessing a user's Keychain.
abstract interface class CloudSecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

final class PlatformCloudSecureValues implements CloudSecureValueStore {
  const PlatformCloudSecureValues({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Stores one complete versioned credential exclusively in secure storage.
final class SecureCloudSessionStore implements SecureSessionStore {
  SecureCloudSessionStore({
    required this.serviceOrigin,
    CloudSecureValueStore? values,
  }) : _values = values ?? const PlatformCloudSecureValues(),
       _key = _keyForOrigin(serviceOrigin);
  final Uri serviceOrigin;
  final CloudSecureValueStore _values;
  final String _key;
  @override
  Future<SecureSessionRecord?> read() async {
    try {
      final value = await _values.read(_key);
      if (value == null) return null;
      final Object? decoded = jsonDecode(value);
      if (decoded is! Map<String, Object?>) {
        throw const CloudException(CloudErrorCode.secureStorage);
      }
      final record = SecureSessionRecord.fromSecureJson(decoded);
      if (record.serviceOrigin.origin != serviceOrigin.origin) {
        throw const CloudException(CloudErrorCode.secureStorage);
      }
      return record;
    } catch (_) {
      throw const CloudException(CloudErrorCode.secureStorage);
    }
  }

  @override
  Future<void> write(SecureSessionRecord record) async {
    if (record.serviceOrigin.origin != serviceOrigin.origin) {
      throw const CloudException(CloudErrorCode.secureStorage);
    }
    try {
      await _values.write(_key, jsonEncode(record.toSecureJson()));
    } catch (_) {
      throw const CloudException(CloudErrorCode.secureStorage);
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _values.delete(_key);
    } catch (_) {
      throw const CloudException(CloudErrorCode.secureStorage);
    }
  }

  @override
  String toString() => 'SecureCloudSessionStore([redacted])';
}
